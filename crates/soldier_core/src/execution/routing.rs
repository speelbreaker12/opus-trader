//! Internal execution routing between engine-facing inputs and the legacy
//! open/pipeline runtime modules.
//!
//! WAL gate dependency chain (debug search order):
//! 1. `wal_gate.rs`           — `RecordedBeforeDispatchGate` trait
//! 2. `build_order_intent.rs` — core chokepoint + deprecated `PrecomputedWalGate`
//! 3. `routing.rs`            — adapter dispatch (this file)
//! 4. `open_runtime.rs`       — `wal_recorded` compat field (ignored on adapter path)
//! 5. `pipeline.rs`           — shared pipeline evaluator wrapper
//!
//! Invariant: OPEN without a WAL gate adapter is always rejected (fail-closed).
//! Close/Hedge without a WAL gate adapter are allowed per CSP.3.2 and emit
//! `wal_nonblocking_allowed_total` with `source=no_gate_configured`.

use super::base_gates::BaseGatesInput;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateStep,
};
use super::dispatch_map::DispatchConsistencyProof;
use super::engine::{
    ApprovedExecution, ExecutionBaseInput, ExecutionDecision, ExecutionL2BookSnapshot,
    ExecutionOrderType, ExecutionRejection, ExecutionRuntime, ExecutionStep, OpenExecutionInput,
    RuntimeStep,
};
use super::gate::{GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput};
use super::gates::NetEdgeInput;
use super::inventory_skew::InventorySkewInput;
use super::open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, OpenRuntimeOutput,
    REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT, REJECT_REASON_INVENTORY_SKEW_DELTA_LIMIT_MISSING,
    REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED,
    REJECT_REASON_PENDING_EXPOSURE_OVERFILL, build_open_order_intent_runtime_with_wal_gate,
};
use super::pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, QuantizePipelineInput,
    evaluate_intent_pipeline_with_wal_gate,
};
use super::post_only_guard::PostOnlyInput;
use super::preflight::{OrderType, PreflightInput};
use super::pricer::PricerInput;
use super::quantize::QuantizeConstraints;
use super::reject_reason::{GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint};
use super::wal_gate::RecordedBeforeDispatchGate;
use crate::risk::RiskState;

pub(crate) fn route_open<'input, 'runtime>(
    input: &OpenExecutionInput<'input>,
    runtime: &mut ExecutionRuntime<'runtime>,
) -> ExecutionDecision {
    let Some(pending_book) = runtime.pending_exposure_book else {
        return missing_runtime_dependency_decision("pending_exposure_book");
    };

    let legacy_input = build_open_runtime_input(input, runtime.wal_gate.is_some());
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();
    let output = match runtime.wal_gate.as_mut() {
        Some(gate) => build_open_order_intent_runtime_with_wal_gate(
            &legacy_input,
            pending_book,
            Some(&mut **gate),
            &mut choke_metrics,
            &mut runtime_metrics,
        ),
        None => build_open_order_intent_runtime_with_wal_gate(
            &legacy_input,
            pending_book,
            None,
            &mut choke_metrics,
            &mut runtime_metrics,
        ),
    };

    open_runtime_to_decision(input, &output)
}

pub(crate) fn route_pipeline<'input, 'runtime>(
    input: &ExecutionBaseInput<'input>,
    intent_class: ChokeIntentClass,
    runtime: &mut ExecutionRuntime<'runtime>,
) -> ExecutionDecision {
    if intent_class == ChokeIntentClass::Open {
        return unexpected_open_pipeline_decision();
    }

    let no_gate_configured = matches!(
        intent_class,
        ChokeIntentClass::Close | ChokeIntentClass::Hedge
    ) && runtime.wal_gate.is_none();
    let legacy_input = build_pipeline_input(input, intent_class, runtime.wal_gate.is_some());
    let mut metrics = IntentPipelineMetrics::new();
    let result = match intent_class {
        ChokeIntentClass::Close | ChokeIntentClass::Hedge => match runtime.wal_gate.as_mut() {
            Some(gate) => evaluate_intent_pipeline_with_wal_gate(
                &legacy_input,
                &mut metrics,
                Some(&mut **gate),
            ),
            None => {
                let mut no_gate = NoGateConfiguredWalGate;
                evaluate_intent_pipeline_with_wal_gate(
                    &legacy_input,
                    &mut metrics,
                    Some(&mut no_gate),
                )
            }
        },
        ChokeIntentClass::CancelOnly => {
            evaluate_intent_pipeline_with_wal_gate(&legacy_input, &mut metrics, None)
        }
        ChokeIntentClass::Open => {
            tracing::error!("Open intent unexpectedly reached route_pipeline - failing closed");
            evaluate_intent_pipeline_with_wal_gate(&legacy_input, &mut metrics, None)
        }
    };

    if no_gate_configured && result.decision.is_approved() {
        super::build_order_intent::bump_wal_nonblocking_allowed_total();
        super::emit_execution_metric_line(
            super::METRIC_WAL_NONBLOCKING_ALLOWED_TOTAL,
            &format!("intent_class={intent_class:?} source=no_gate_configured"),
        );
        tracing::warn!(
            intent_class = ?intent_class,
            "WAL gate absent for non-OPEN intent - allowing per CSP.3.2 (no_gate_configured)"
        );
    }

    pipeline_result_to_decision(
        result.decision,
        result.reject_reason_code,
        input.risk_state,
        &GateRejectCodes::default(),
    )
}

pub(crate) fn build_open_runtime_input<'a>(
    input: &OpenExecutionInput<'a>,
    wal_recorded: bool,
) -> OpenRuntimeInput<'a> {
    OpenRuntimeInput {
        base_gates: build_base_gates_input(&input.base, ChokeIntentClass::Open),
        wal_recorded,
        current_delta: input.current_delta,
        delta_impact_est: input.delta_impact_est,
        liquidity_input: LiquidityGateInput {
            order_qty: input.liquidity.order_qty,
            is_buy: matches!(input.liquidity.side, super::quantize::Side::Buy),
            intent_class: GateIntentClass::Open,
            is_marketable: input.liquidity.is_marketable,
            l2_snapshot: input.liquidity.l2_snapshot.as_ref().map(map_l2_snapshot),
            now_ms: input.liquidity.now_ms,
            l2_book_snapshot_max_age_ms: input.liquidity.l2_book_snapshot_max_age_ms,
            max_slippage_bps: input.liquidity.max_slippage_bps,
        },
        net_edge_input: NetEdgeInput {
            gross_edge_usd: input.net_edge.gross_edge_usd,
            fee_usd: input.net_edge.fee_usd,
            expected_slippage_usd: input.net_edge.expected_slippage_usd,
            min_edge_usd: input.net_edge.min_edge_usd,
        },
        inventory_skew_input: InventorySkewInput {
            current_delta: input.inventory_skew.current_delta,
            pending_delta: input.inventory_skew.pending_delta,
            delta_limit: input.inventory_skew.delta_limit,
            side: input.inventory_skew.side,
            min_edge_usd: input.inventory_skew.min_edge_usd,
            net_edge_usd: input.inventory_skew.net_edge_usd,
            limit_price: input.inventory_skew.limit_price,
            tick_size: input.inventory_skew.tick_size,
            inventory_skew_k: input.inventory_skew.inventory_skew_k,
            inventory_skew_tick_penalty_max: input.inventory_skew.inventory_skew_tick_penalty_max,
        },
        pricer_input: PricerInput {
            fair_price: input.pricer.fair_price,
            gross_edge_usd: input.pricer.gross_edge_usd,
            min_edge_usd: input.pricer.min_edge_usd,
            fee_estimate_usd: input.pricer.fee_estimate_usd,
            expected_slippage_usd: input.pricer.expected_slippage_usd,
            qty: input.pricer.qty,
            side: input.pricer.side,
        },
        exposure_budget_input: input.exposure_budget.clone(),
        margin_gate_input: input.margin_gate.clone(),
        reservation_id: input.reservation_id.clone(),
        instrument_id: input.instrument_id.clone(),
    }
}

pub(crate) fn build_pipeline_input<'a>(
    input: &ExecutionBaseInput<'a>,
    intent_class: ChokeIntentClass,
    wal_recorded: bool,
) -> IntentPipelineInput<'a> {
    let (requested_qty, max_dispatch_qty) = if intent_class == ChokeIntentClass::CancelOnly {
        (None, None)
    } else {
        let qty = Some(input.quantize.raw_qty);
        (qty, qty)
    };

    IntentPipelineInput {
        intent_class,
        risk_state: input.risk_state,
        preflight: PreflightInput {
            instrument_kind: input.preflight.instrument_kind,
            order_type: map_order_type(input.preflight.order_type),
            has_trigger: input.preflight.has_trigger,
            linked_order_type: input.preflight.linked_order_type,
            linked_orders_allowed: input.preflight.linked_orders_allowed,
            post_only_input: input.preflight.post_only.map(|post| PostOnlyInput {
                post_only: post.post_only,
                side: post.side,
                limit_price: post.limit_price,
                best_ask: post.best_ask,
                best_bid: post.best_bid,
            }),
        },
        venue_capabilities: input.venue_capabilities.clone(),
        bot_feature_flags: input.bot_feature_flags.clone(),
        quantize: QuantizePipelineInput {
            raw_qty: input.quantize.raw_qty,
            raw_limit_price: input.quantize.raw_limit_price,
            side: input.quantize.side,
            constraints: QuantizeConstraints {
                tick_size: input.quantize.tick_size,
                amount_step: input.quantize.amount_step,
                min_amount: input.quantize.min_amount,
            },
        },
        dispatch_consistency: if input.dispatch_consistency_passed {
            DispatchConsistencyProof::no_contracts()
        } else {
            DispatchConsistencyProof::failed()
        },
        fee_snapshot: input.fee_snapshot.clone(),
        fee_config: input.fee_config.clone(),
        expiry_guard: input.expiry_guard,
        liquidity: None,
        net_edge: None,
        pricer: None,
        wal_recorded,
        requested_qty,
        max_dispatch_qty,
    }
}

pub(crate) fn pipeline_result_to_decision(
    result: ChokeResult,
    reject_code: Option<RejectReasonCode>,
    effective_risk_state: RiskState,
    gate_reject_codes: &GateRejectCodes,
) -> ExecutionDecision {
    use ChokeResult::{Approved as ChokeApproved, Rejected as ChokeRejected};

    match result {
        ChokeRejected { reason, .. } => {
            let code = reject_code
                .unwrap_or_else(|| reject_reason_from_chokepoint(&reason, gate_reject_codes));
            ExecutionDecision::Rejected(ExecutionRejection {
                code,
                step: map_pipeline_rejection_step(&reason),
                detail: reject_reason_detail(&reason),
            })
        }
        ChokeApproved { .. } => ExecutionDecision::Approved(ApprovedExecution {
            effective_risk_state,
            pending_reservation_id: None,
            adjusted_min_edge_usd: None,
        }),
    }
}

pub(crate) fn open_runtime_to_decision(
    input: &OpenExecutionInput<'_>,
    output: &OpenRuntimeOutput,
) -> ExecutionDecision {
    use ChokeResult::{Approved as ChokeApproved, Rejected as ChokeRejected};

    let gate_reject_codes = GateRejectCodes {
        preflight: output
            .gate_reject_codes
            .preflight
            .or(input.gate_reject_codes.preflight),
        quantize: output
            .gate_reject_codes
            .quantize
            .or(input.gate_reject_codes.quantize),
        fee_cache: output
            .gate_reject_codes
            .fee_cache
            .or(input.gate_reject_codes.fee_cache),
        expiry_guard: output
            .gate_reject_codes
            .expiry_guard
            .or(input.gate_reject_codes.expiry_guard),
        liquidity_gate: output
            .gate_reject_codes
            .liquidity_gate
            .or(input.gate_reject_codes.liquidity_gate),
        net_edge_gate: output
            .gate_reject_codes
            .net_edge_gate
            .or(input.gate_reject_codes.net_edge_gate),
        recorded_before_dispatch: output
            .gate_reject_codes
            .recorded_before_dispatch
            .or(input.gate_reject_codes.recorded_before_dispatch),
        pricer: output
            .gate_reject_codes
            .pricer
            .or(input.gate_reject_codes.pricer),
    };

    match &output.choke_result {
        ChokeRejected { reason, .. } => ExecutionDecision::Rejected(ExecutionRejection {
            code: map_open_runtime_reject_code(reason, &gate_reject_codes),
            step: map_open_rejection_step(input, output, reason),
            detail: reject_reason_detail(reason),
        }),
        ChokeApproved { .. } => ExecutionDecision::Approved(ApprovedExecution {
            effective_risk_state: output.effective_risk_state,
            pending_reservation_id: output.pending_reservation_id.clone(),
            adjusted_min_edge_usd: output.adjusted_min_edge_usd,
        }),
    }
}

fn map_order_type(order_type: ExecutionOrderType) -> OrderType {
    match order_type {
        ExecutionOrderType::Limit => OrderType::Limit,
        ExecutionOrderType::Market => OrderType::Market,
        ExecutionOrderType::StopMarket => OrderType::StopMarket,
        ExecutionOrderType::StopLimit => OrderType::StopLimit,
    }
}

fn build_base_gates_input<'a>(
    input: &ExecutionBaseInput<'a>,
    intent_class: ChokeIntentClass,
) -> BaseGatesInput<'a> {
    BaseGatesInput {
        intent_class,
        risk_state: input.risk_state,
        preflight: PreflightInput {
            instrument_kind: input.preflight.instrument_kind,
            order_type: map_order_type(input.preflight.order_type),
            has_trigger: input.preflight.has_trigger,
            linked_order_type: input.preflight.linked_order_type,
            linked_orders_allowed: input.preflight.linked_orders_allowed,
            post_only_input: input.preflight.post_only.map(|post| PostOnlyInput {
                post_only: post.post_only,
                side: post.side,
                limit_price: post.limit_price,
                best_ask: post.best_ask,
                best_bid: post.best_bid,
            }),
        },
        venue_capabilities: input.venue_capabilities.clone(),
        bot_feature_flags: input.bot_feature_flags.clone(),
        quantize: QuantizePipelineInput {
            raw_qty: input.quantize.raw_qty,
            raw_limit_price: input.quantize.raw_limit_price,
            side: input.quantize.side,
            constraints: QuantizeConstraints {
                tick_size: input.quantize.tick_size,
                amount_step: input.quantize.amount_step,
                min_amount: input.quantize.min_amount,
            },
        },
        dispatch_consistency: if input.dispatch_consistency_passed {
            DispatchConsistencyProof::no_contracts()
        } else {
            DispatchConsistencyProof::failed()
        },
        fee_snapshot: input.fee_snapshot.clone(),
        fee_config: input.fee_config.clone(),
        expiry_guard: input.expiry_guard,
    }
}

fn map_l2_snapshot(snapshot: &ExecutionL2BookSnapshot) -> L2BookSnapshot {
    L2BookSnapshot {
        asks: snapshot
            .asks
            .iter()
            .map(|level| L2Level {
                price: level.price,
                qty: level.qty,
            })
            .collect(),
        bids: snapshot
            .bids
            .iter()
            .map(|level| L2Level {
                price: level.price,
                qty: level.qty,
            })
            .collect(),
        timestamp_ms: snapshot.timestamp_ms,
    }
}

struct NoGateConfiguredWalGate;

impl RecordedBeforeDispatchGate for NoGateConfiguredWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        Ok(())
    }
}

fn map_open_runtime_reject_code(
    reason: &ChokeRejectReason,
    gate_reject_codes: &GateRejectCodes,
) -> RejectReasonCode {
    if let ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: detail,
    } = reason
    {
        return match detail.as_str() {
            REJECT_REASON_PENDING_EXPOSURE_OVERFILL
            | REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED => {
                RejectReasonCode::PendingExposureBudgetExceeded
            }
            REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT => {
                RejectReasonCode::GlobalExposureBudgetExceeded
            }
            _ => reject_reason_from_chokepoint(reason, gate_reject_codes),
        };
    }

    if let ChokeRejectReason::GateRejected {
        gate: GateStep::NetEdgeGate,
        reason: detail,
    } = reason
        && detail == REJECT_REASON_INVENTORY_SKEW_DELTA_LIMIT_MISSING
    {
        return RejectReasonCode::InventorySkewDeltaLimitMissing;
    }

    reject_reason_from_chokepoint(reason, gate_reject_codes)
}

fn map_pipeline_rejection_step(reason: &ChokeRejectReason) -> ExecutionStep {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => ExecutionStep::Gate(GateStep::DispatchAuth),
        ChokeRejectReason::GateRejected { gate, .. } => ExecutionStep::Gate(*gate),
        ChokeRejectReason::AssemblyFailed => ExecutionStep::Runtime(RuntimeStep::Assembly),
    }
}

fn map_open_rejection_step(
    input: &OpenExecutionInput<'_>,
    output: &OpenRuntimeOutput,
    reason: &ChokeRejectReason,
) -> ExecutionStep {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => {
            if input.base.risk_state == RiskState::Healthy
                && output.effective_risk_state != RiskState::Healthy
            {
                ExecutionStep::Runtime(RuntimeStep::MarginGate)
            } else {
                ExecutionStep::Gate(GateStep::DispatchAuth)
            }
        }
        ChokeRejectReason::AssemblyFailed => ExecutionStep::Runtime(RuntimeStep::Assembly),
        ChokeRejectReason::GateRejected { gate, reason } => {
            if matches!(
                gate,
                GateStep::Preflight
                    | GateStep::Quantize
                    | GateStep::DispatchConsistency
                    | GateStep::FeeCacheCheck
                    | GateStep::ExpiryGuard
            ) {
                return ExecutionStep::Runtime(RuntimeStep::BaseGates);
            }

            if *gate == GateStep::LiquidityGate {
                match reason.as_str() {
                    REJECT_REASON_PENDING_EXPOSURE_OVERFILL
                    | REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED => {
                        return ExecutionStep::Runtime(RuntimeStep::PendingExposure);
                    }
                    REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT => {
                        return ExecutionStep::Runtime(RuntimeStep::GlobalExposureBudget);
                    }
                    _ => {}
                }
            }

            if *gate == GateStep::NetEdgeGate
                && reason == REJECT_REASON_INVENTORY_SKEW_DELTA_LIMIT_MISSING
            {
                return ExecutionStep::Runtime(RuntimeStep::InventorySkew);
            }

            if *gate == GateStep::NetEdgeGate && output.adjusted_min_edge_usd.is_some() {
                return ExecutionStep::Runtime(RuntimeStep::InventorySkew);
            }

            ExecutionStep::Gate(*gate)
        }
    }
}

fn missing_runtime_dependency_decision(dependency: &'static str) -> ExecutionDecision {
    ExecutionDecision::Rejected(ExecutionRejection {
        code: RejectReasonCode::AssemblyFailed,
        step: ExecutionStep::Runtime(RuntimeStep::Assembly),
        detail: format!("missing runtime dependency: {dependency}"),
    })
}

fn unexpected_open_pipeline_decision() -> ExecutionDecision {
    ExecutionDecision::Rejected(ExecutionRejection {
        code: RejectReasonCode::RecordedBeforeDispatchFailed,
        step: ExecutionStep::Gate(GateStep::RecordedBeforeDispatch),
        detail: "Open intent unexpectedly reached non-OPEN pipeline path".to_string(),
    })
}

fn reject_reason_detail(reason: &ChokeRejectReason) -> String {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => "RiskState not Healthy".to_string(),
        ChokeRejectReason::GateRejected { reason, .. } => reason.clone(),
        ChokeRejectReason::AssemblyFailed => "Assembly failed".to_string(),
    }
}
