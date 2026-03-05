//! Execution engine: single public orchestration entrypoint.
//!
//! Upgrade 1B end-state:
//! - public callers construct engine-level domain inputs
//! - legacy wiring types stay crate-internal
//! - `ExecutionDecision` is authoritative output

use super::base_gates::BaseGatesInput;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateStep,
    RecordedBeforeDispatchGate,
};
use super::dispatch_map::DispatchConsistencyProof;
use super::gate::{GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput};
use super::gates::NetEdgeInput;
use super::inventory_skew::InventorySkewInput;
use super::open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, OpenRuntimeOutput, build_open_order_intent_runtime,
};
use super::pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, QuantizePipelineInput, evaluate_intent_pipeline,
};
use super::post_only_guard::PostOnlyInput;
use super::preflight::{OrderType, PreflightInput};
use super::pricer::PricerInput;
use super::quantize::{QuantizeConstraints, Side};
use super::reject_reason::{GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint};
use crate::risk::{
    ExposureBudgetInput, FeeCacheSnapshot, FeeStalenessConfig, MarginGateInput,
    PendingExposureBook, ReservationId, RiskState,
};
use crate::venue::{BotFeatureFlags, ExpiryGuardInput, InstrumentKind, VenueCapabilities};

const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
const REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED: &str =
    "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED";
const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str = "GLOBAL_EXPOSURE_BUDGET_REJECT";

#[derive(Debug, Clone)]
pub struct ExecutionBaseInput<'a> {
    pub risk_state: RiskState,
    pub preflight: ExecutionPreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizeExecutionInput,
    pub dispatch_consistency_passed: bool,
    pub fee_snapshot: FeeCacheSnapshot,
    pub fee_config: FeeStalenessConfig,
    pub expiry_guard: Option<ExpiryGuardInput>,
}

#[derive(Debug, Clone)]
pub struct ExecutionPreflightInput<'a> {
    pub instrument_kind: InstrumentKind,
    pub order_type: ExecutionOrderType,
    pub has_trigger: bool,
    pub linked_order_type: Option<&'a str>,
    pub linked_orders_allowed: bool,
    pub post_only: Option<ExecutionPostOnlyInput>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionOrderType {
    Limit,
    Market,
    StopMarket,
    StopLimit,
}

#[derive(Debug, Clone, Copy)]
pub struct ExecutionPostOnlyInput {
    pub post_only: bool,
    pub side: Side,
    pub limit_price: f64,
    pub best_ask: Option<f64>,
    pub best_bid: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub struct QuantizeExecutionInput {
    pub raw_qty: f64,
    pub raw_limit_price: f64,
    pub side: Side,
    pub tick_size: f64,
    pub amount_step: f64,
    pub min_amount: f64,
}

#[derive(Debug, Clone)]
pub struct OpenExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
    pub gate_reject_codes: GateRejectCodes,
    pub current_delta: f64,
    pub delta_impact_est: f64,
    pub liquidity: LiquidityExecutionInput,
    pub net_edge: NetEdgeExecutionInput,
    pub inventory_skew: InventorySkewExecutionInput,
    pub pricer: PricerExecutionInput,
    pub exposure_budget: ExposureBudgetInput,
    pub margin_gate: MarginGateInput,
    pub reservation_id: ReservationId,
    pub instrument_id: String,
}

#[derive(Debug, Clone)]
pub struct CloseExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct HedgeExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct CancelExecutionInput<'a> {
    pub base: ExecutionBaseInput<'a>,
}

#[derive(Debug, Clone)]
pub struct LiquidityExecutionInput {
    pub order_qty: f64,
    pub side: Side,
    pub is_marketable: bool,
    pub l2_snapshot: Option<ExecutionL2BookSnapshot>,
    pub now_ms: u64,
    pub l2_book_snapshot_max_age_ms: u64,
    pub max_slippage_bps: f64,
}

#[derive(Debug, Clone)]
pub struct ExecutionL2BookSnapshot {
    pub asks: Vec<ExecutionL2Level>,
    pub bids: Vec<ExecutionL2Level>,
    pub timestamp_ms: u64,
}

#[derive(Debug, Clone, Copy)]
pub struct ExecutionL2Level {
    pub price: f64,
    pub qty: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct NetEdgeExecutionInput {
    pub gross_edge_usd: Option<f64>,
    pub fee_usd: Option<f64>,
    pub expected_slippage_usd: Option<f64>,
    pub min_edge_usd: Option<f64>,
}

#[derive(Debug, Clone, Copy)]
pub struct InventorySkewExecutionInput {
    pub current_delta: f64,
    pub pending_delta: f64,
    pub delta_limit: Option<f64>,
    pub side: Side,
    pub min_edge_usd: f64,
    pub net_edge_usd: f64,
    pub limit_price: f64,
    pub tick_size: f64,
    pub inventory_skew_k: f64,
    pub inventory_skew_tick_penalty_max: u8,
}

#[derive(Debug, Clone, Copy)]
pub struct PricerExecutionInput {
    pub fair_price: f64,
    pub gross_edge_usd: f64,
    pub min_edge_usd: f64,
    pub fee_estimate_usd: f64,
    pub qty: f64,
    pub side: Side,
}

#[derive(Debug, Clone)]
#[allow(clippy::large_enum_variant)]
pub enum ExecutionInput<'a> {
    Open(OpenExecutionInput<'a>),
    Close(CloseExecutionInput<'a>),
    Hedge(HedgeExecutionInput<'a>),
    Cancel(CancelExecutionInput<'a>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ExecutionDecision {
    Approved(ApprovedExecution),
    Rejected(ExecutionRejection),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ApprovedExecution {
    pub effective_risk_state: RiskState,
    pub pending_reservation_id: Option<ReservationId>,
    pub adjusted_min_edge_usd: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExecutionRejection {
    pub code: RejectReasonCode,
    pub step: ExecutionStep,
    pub detail: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionStep {
    Runtime(RuntimeStep),
    Gate(GateStep),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeStep {
    BaseGates,
    PendingExposure,
    GlobalExposureBudget,
    InventorySkew,
    MarginGate,
    Assembly,
}

#[derive(Default)]
pub struct ExecutionRuntime<'a> {
    pub wal_gate: Option<&'a mut dyn RecordedBeforeDispatchGate>,
    pub pending_exposure_book: Option<&'a PendingExposureBook>,
}

impl<'a> ExecutionRuntime<'a> {
    pub fn new(
        wal_gate: Option<&'a mut dyn RecordedBeforeDispatchGate>,
        pending_exposure_book: Option<&'a PendingExposureBook>,
    ) -> Self {
        Self {
            wal_gate,
            pending_exposure_book,
        }
    }
}

pub struct ExecutionEngine;

impl ExecutionEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn decide<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        match input {
            ExecutionInput::Open(open) => self.decide_open(open, runtime),
            ExecutionInput::Close(close) => {
                self.decide_pipeline(&close.base, ChokeIntentClass::Close, runtime)
            }
            ExecutionInput::Hedge(hedge) => {
                self.decide_pipeline(&hedge.base, ChokeIntentClass::Hedge, runtime)
            }
            ExecutionInput::Cancel(cancel) => {
                self.decide_pipeline(&cancel.base, ChokeIntentClass::CancelOnly, runtime)
            }
        }
    }

    pub fn evaluate<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        self.decide(input, runtime)
    }

    fn decide_open<'input, 'runtime>(
        &self,
        input: &OpenExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        let Some(pending_book) = runtime.pending_exposure_book else {
            return missing_runtime_dependency_decision("pending_exposure_book");
        };

        let wal_recorded = runtime
            .wal_gate
            .as_deref_mut()
            .map(|gate| gate.record_before_dispatch().is_ok())
            .unwrap_or(false);

        let legacy_input = build_open_runtime_input(input, wal_recorded);
        let mut choke_metrics = ChokeMetrics::new();
        let mut runtime_metrics = OpenRuntimeMetrics::default();
        let output = build_open_order_intent_runtime(
            &legacy_input,
            pending_book,
            &mut choke_metrics,
            &mut runtime_metrics,
        );

        open_runtime_to_decision(input, &output)
    }

    fn decide_pipeline<'input, 'runtime>(
        &self,
        input: &ExecutionBaseInput<'input>,
        intent_class: ChokeIntentClass,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        let wal_recorded = pipeline_wal_recorded(intent_class, runtime);
        let legacy_input = build_pipeline_input(input, intent_class, wal_recorded);
        let mut metrics = IntentPipelineMetrics::new();
        let result = evaluate_intent_pipeline(&legacy_input, &mut metrics);
        pipeline_result_to_decision(
            result.decision,
            result.reject_reason_code,
            input.risk_state,
            &GateRejectCodes::default(),
        )
    }
}

impl Default for ExecutionEngine {
    fn default() -> Self {
        Self::new()
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

fn build_open_runtime_input<'a>(
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
            is_buy: matches!(input.liquidity.side, Side::Buy),
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
            qty: input.pricer.qty,
            side: input.pricer.side,
        },
        exposure_budget_input: input.exposure_budget.clone(),
        margin_gate_input: input.margin_gate.clone(),
        reservation_id: input.reservation_id.clone(),
        instrument_id: input.instrument_id.clone(),
    }
}

fn build_pipeline_input<'a>(
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

fn pipeline_wal_recorded(
    intent_class: ChokeIntentClass,
    runtime: &mut ExecutionRuntime<'_>,
) -> bool {
    match intent_class {
        ChokeIntentClass::Close | ChokeIntentClass::Hedge => {
            if let Some(gate) = runtime.wal_gate.as_deref_mut() {
                let _ = gate.record_before_dispatch();
            }
            true
        }
        ChokeIntentClass::CancelOnly => true,
        ChokeIntentClass::Open => false,
    }
}

fn pipeline_result_to_decision(
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

fn open_runtime_to_decision(
    input: &OpenExecutionInput<'_>,
    output: &OpenRuntimeOutput,
) -> ExecutionDecision {
    use ChokeResult::{Approved as ChokeApproved, Rejected as ChokeRejected};

    match &output.choke_result {
        ChokeRejected { reason, .. } => ExecutionDecision::Rejected(ExecutionRejection {
            code: map_open_runtime_reject_code(reason, &input.gate_reject_codes),
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

fn map_open_runtime_reject_code(
    reason: &ChokeRejectReason,
    gate_reject_codes: &GateRejectCodes,
) -> RejectReasonCode {
    // Invariant: these detail tags are machine constants emitted by
    // `open_runtime.rs` (not free-form text) and are parity-tested.
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

fn reject_reason_detail(reason: &ChokeRejectReason) -> String {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => "RiskState not Healthy".to_string(),
        ChokeRejectReason::GateRejected { reason, .. } => reason.clone(),
        ChokeRejectReason::AssemblyFailed => "Assembly failed".to_string(),
    }
}

#[cfg(test)]
#[path = "engine_decision_tests.rs"]
mod engine_parity_tests;
