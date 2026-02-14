//! OPEN runtime wiring for Slice 6 gate composition.

use crate::risk::{
    ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetResult, MarginGateInput,
    MarginGateMetrics, MarginGateMode, MarginGateResult, PendingExposureBook,
    PendingExposureMetrics, PendingExposureResult, PendingExposureTerminalOutcome, RiskState,
    evaluate_global_exposure_budget, evaluate_margin_headroom_gate,
};

use super::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    LiquidityGateInput, LiquidityGateMetrics, LiquidityGateResult, NetEdgeInput, NetEdgeMetrics,
    NetEdgeResult, PricerInput, PricerMetrics, PricerResult, build_gate_results,
    build_order_intent, compute_limit_price, evaluate_inventory_skew, evaluate_liquidity_gate,
    evaluate_net_edge,
};

const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str = "GLOBAL_EXPOSURE_BUDGET_REJECT";

/// OPEN runtime inputs assembled before chokepoint evaluation.
#[derive(Debug, Clone)]
pub struct OpenRuntimeInput {
    pub risk_state: RiskState,
    pub preflight_passed: bool,
    pub quantize_passed: bool,
    pub dispatch_consistency_passed: bool,
    pub fee_cache_passed: bool,
    pub wal_recorded: bool,
    pub current_delta: f64,
    pub delta_impact_est: f64,
    pub liquidity_input: LiquidityGateInput,
    pub net_edge_input: NetEdgeInput,
    pub inventory_skew_input: InventorySkewInput,
    pub pricer_input: PricerInput,
    pub exposure_budget_input: ExposureBudgetInput,
    pub margin_gate_input: MarginGateInput,
}

/// Runtime metrics aggregated by subsystem for OPEN wiring.
#[derive(Debug, Default)]
pub struct OpenRuntimeMetrics {
    pub pending_exposure: PendingExposureMetrics,
    pub global_exposure: ExposureBudgetMetrics,
    pub inventory_skew: InventorySkewMetrics,
    pub liquidity: LiquidityGateMetrics,
    pub net_edge: NetEdgeMetrics,
    pub pricer: PricerMetrics,
    pub margin_gate: MarginGateMetrics,
    pub reject_override_mismatch_total: u64,
}

/// OPEN runtime output surfaced to tests and callers.
#[derive(Debug, Clone)]
pub struct OpenRuntimeOutput {
    pub choke_result: ChokeResult,
    pub gate_results: GateResults,
    pub pending_reservation_id: Option<u64>,
    pub mode_hint: MarginGateMode,
    pub effective_risk_state: RiskState,
    pub adjusted_min_edge_usd: Option<f64>,
}

/// Build an OPEN intent decision by wiring runtime gates before chokepoint.
pub fn build_open_order_intent_runtime(
    input: &OpenRuntimeInput,
    pending_book: &mut PendingExposureBook,
    choke_metrics: &mut ChokeMetrics,
    runtime_metrics: &mut OpenRuntimeMetrics,
) -> OpenRuntimeOutput {
    let margin_gate_result =
        evaluate_margin_headroom_gate(&input.margin_gate_input, &mut runtime_metrics.margin_gate);
    let mode_hint = match margin_gate_result {
        MarginGateResult::Allowed { mode_hint, .. } => mode_hint,
        MarginGateResult::Rejected { mode_hint, .. } => mode_hint,
    };

    let mut effective_risk_state = input.risk_state;
    if matches!(margin_gate_result, MarginGateResult::Rejected { .. })
        && effective_risk_state == RiskState::Healthy
    {
        effective_risk_state = match mode_hint {
            MarginGateMode::Kill => RiskState::Kill,
            MarginGateMode::ReduceOnly | MarginGateMode::Active => RiskState::Degraded,
        };
    }

    let mut gate_results = build_gate_results(
        input.preflight_passed,
        input.quantize_passed,
        input.dispatch_consistency_passed,
        input.fee_cache_passed,
        true,
        true,
        true,
        input.wal_recorded,
        Some(input.liquidity_input.order_qty),
        None,
    );

    let mut pending_reservation_id = None;
    let mut max_dispatch_qty = Some(input.liquidity_input.order_qty);
    let mut adjusted_min_edge_usd = None;
    let mut liquidity_override_reason: Option<&'static str> = None;

    let pre_dispatch_gates_ready = effective_risk_state == RiskState::Healthy
        && input.preflight_passed
        && input.quantize_passed
        && input.dispatch_consistency_passed
        && input.fee_cache_passed;

    if pre_dispatch_gates_ready {
        match pending_book.reserve(
            input.current_delta,
            input.delta_impact_est,
            &mut runtime_metrics.pending_exposure,
        ) {
            PendingExposureResult::Reserved { reservation_id, .. } => {
                pending_reservation_id = Some(reservation_id);
            }
            PendingExposureResult::Rejected { .. } => {
                gate_results.liquidity_gate_passed = false;
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
                liquidity_override_reason = Some(REJECT_REASON_PENDING_EXPOSURE_OVERFILL);
            }
        }

        if liquidity_override_reason.is_none() {
            match evaluate_global_exposure_budget(
                &input.exposure_budget_input,
                &mut runtime_metrics.global_exposure,
            ) {
                ExposureBudgetResult::Allowed { .. } => {}
                ExposureBudgetResult::Rejected { .. } => {
                    gate_results.liquidity_gate_passed = false;
                    gate_results.net_edge_passed = false;
                    gate_results.pricer_passed = false;
                    liquidity_override_reason = Some(REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT);
                }
            }
        }

        if liquidity_override_reason.is_none() {
            gate_results.liquidity_gate_passed = match evaluate_liquidity_gate(
                &input.liquidity_input,
                &mut runtime_metrics.liquidity,
            ) {
                LiquidityGateResult::Allowed { allowed_qty, .. } => {
                    if let Some(qty) = allowed_qty {
                        max_dispatch_qty = Some(qty);
                    }
                    true
                }
                LiquidityGateResult::Rejected { allowed_qty, .. } => {
                    if let Some(qty) = allowed_qty {
                        max_dispatch_qty = Some(qty);
                    }
                    false
                }
            };

            if gate_results.liquidity_gate_passed {
                let first_net_edge =
                    evaluate_net_edge(&input.net_edge_input, &mut runtime_metrics.net_edge);
                let first_net_edge_usd = match first_net_edge {
                    NetEdgeResult::Allowed { net_edge_usd } => Some(net_edge_usd),
                    NetEdgeResult::Rejected { net_edge_usd, .. } => net_edge_usd,
                };
                gate_results.net_edge_passed =
                    matches!(first_net_edge, NetEdgeResult::Allowed { .. });

                let mut inventory_skew_input = input.inventory_skew_input.clone();
                if input.current_delta != 0.0 {
                    inventory_skew_input.current_delta = input.current_delta;
                }
                if let Some(min_edge_usd) = input.net_edge_input.min_edge_usd {
                    inventory_skew_input.min_edge_usd = min_edge_usd;
                }
                if let Some(net_edge_usd) = first_net_edge_usd {
                    inventory_skew_input.net_edge_usd = net_edge_usd;
                }

                match evaluate_inventory_skew(
                    &inventory_skew_input,
                    &mut runtime_metrics.inventory_skew,
                ) {
                    InventorySkewResult::Allowed {
                        adjusted_min_edge_usd: adjusted,
                        ..
                    } => {
                        adjusted_min_edge_usd = Some(adjusted);
                        let mut net_edge_recheck = input.net_edge_input.clone();
                        net_edge_recheck.min_edge_usd = Some(adjusted);
                        gate_results.net_edge_passed = matches!(
                            evaluate_net_edge(&net_edge_recheck, &mut runtime_metrics.net_edge),
                            NetEdgeResult::Allowed { .. }
                        );
                    }
                    InventorySkewResult::Rejected {
                        reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
                        ..
                    } => {
                        gate_results.net_edge_passed = false;
                        if effective_risk_state == RiskState::Healthy {
                            effective_risk_state = RiskState::Degraded;
                        }
                    }
                    InventorySkewResult::Rejected { .. } => {
                        gate_results.net_edge_passed = false;
                    }
                }

                if gate_results.net_edge_passed {
                    let mut pricer_input = input.pricer_input.clone();
                    if let Some(adjusted) = adjusted_min_edge_usd {
                        pricer_input.min_edge_usd = adjusted;
                    }
                    gate_results.pricer_passed = matches!(
                        compute_limit_price(&pricer_input, &mut runtime_metrics.pricer),
                        PricerResult::LimitPrice { .. }
                    );
                } else {
                    gate_results.pricer_passed = false;
                }
            } else {
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
            }
        }
    } else {
        gate_results.liquidity_gate_passed = false;
        gate_results.net_edge_passed = false;
        gate_results.pricer_passed = false;
    }

    gate_results.max_dispatch_qty = max_dispatch_qty;
    let mut choke_result = build_order_intent(
        ChokeIntentClass::Open,
        effective_risk_state,
        choke_metrics,
        &gate_results,
    );
    if let Some(override_reason) = liquidity_override_reason {
        choke_result = match choke_result {
            ChokeResult::Rejected {
                reason:
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::LiquidityGate,
                        ..
                    },
                gate_trace,
            } => ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: override_reason.to_string(),
                },
                gate_trace,
            },
            other => {
                runtime_metrics.reject_override_mismatch_total += 1;
                other
            }
        };
    }

    if matches!(choke_result, ChokeResult::Rejected { .. })
        && let Some(reservation_id) = pending_reservation_id.take()
    {
        let _ = pending_book.settle(
            reservation_id,
            PendingExposureTerminalOutcome::Rejected,
            &mut runtime_metrics.pending_exposure,
        );
    }

    OpenRuntimeOutput {
        choke_result,
        gate_results,
        pending_reservation_id,
        mode_hint,
        effective_risk_state,
        adjusted_min_edge_usd,
    }
}
