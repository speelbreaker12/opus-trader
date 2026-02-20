//! OPEN runtime wiring for Slice 6 gate composition.
//!
//! Gates 1-6 are evaluated via the shared `evaluate_base_gates()` to
//! eliminate dual-orchestration drift risk with `pipeline.rs` (Q1).

use crate::risk::{
    ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetResult, MarginGateDecision,
    MarginGateInput, MarginGateMetrics, MarginGateMode, PendingExposureBook,
    PendingExposureMetrics, PendingExposureResult, PendingExposureTerminalOutcome, ReservationId,
    RiskState, compute_margin_mode_hint, evaluate_global_exposure_budget,
    evaluate_margin_headroom_gate,
};

use super::base_gates::{BaseGatesInput, BaseGatesLegacy, BaseGatesMetrics, evaluate_base_gates};
#[allow(deprecated)] // TODO: migrate to build_order_intent_with_wal_gate()
use super::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    LiquidityGateDecision, LiquidityGateInput, LiquidityGateMetrics, NetEdgeInput, NetEdgeMetrics,
    NetEdgeResult, PricerInput, PricerMetrics, PricerResult, Tlsm, build_gate_results,
    build_order_intent, compute_limit_price, evaluate_inventory_skew, evaluate_liquidity_gate,
    evaluate_net_edge,
};

const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
const REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED: &str =
    "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED";
const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str = "GLOBAL_EXPOSURE_BUDGET_REJECT";

/// OPEN runtime inputs assembled before chokepoint evaluation.
///
/// Gates 1-6 are evaluated from `base_gates` via the shared evaluator.
/// Previous bool fields (`preflight_passed`, `quantize_passed`, etc.)
/// are no longer needed — the evaluator computes them from raw inputs.
#[derive(Debug, Clone)]
pub struct OpenRuntimeInput<'a> {
    /// Base gates input (gates 1-6). The shared evaluator computes
    /// preflight_passed, quantize_passed, dispatch_consistency_passed,
    /// fee_cache_passed, and expiry_guard_passed from these inputs.
    pub base_gates: BaseGatesInput<'a>,
    pub wal_recorded: bool,
    pub current_delta: f64,
    pub delta_impact_est: f64,
    pub liquidity_input: LiquidityGateInput,
    pub net_edge_input: NetEdgeInput,
    pub inventory_skew_input: InventorySkewInput,
    pub pricer_input: PricerInput,
    pub exposure_budget_input: ExposureBudgetInput,
    pub margin_gate_input: MarginGateInput,
    /// Caller-provided idempotency key for pending exposure reservation.
    /// Typically derived from intent_hash: `ReservationId::new(format!("pe-{}", intent.intent_hash))`.
    /// ReservationIds are globally unique across instruments — the reservation book uses a
    /// reverse lookup to route settlements to the correct instrument.
    pub reservation_id: ReservationId,
    /// Instrument for per-instrument pending exposure isolation (PX-2, §1.4.2.1).
    pub instrument_id: String,
}

/// Runtime metrics aggregated by subsystem for OPEN wiring.
#[derive(Debug, Default)]
pub struct OpenRuntimeMetrics {
    pub base_gates: BaseGatesMetrics,
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
    pub pending_reservation_id: Option<ReservationId>,
    pub mode_hint: MarginGateMode,
    pub effective_risk_state: RiskState,
    pub adjusted_min_edge_usd: Option<f64>,
}

/// Build an OPEN intent decision by wiring runtime gates before chokepoint.
pub fn build_open_order_intent_runtime(
    input: &OpenRuntimeInput<'_>,
    pending_book: &PendingExposureBook,
    choke_metrics: &mut ChokeMetrics,
    runtime_metrics: &mut OpenRuntimeMetrics,
) -> OpenRuntimeOutput {
    // ── Gates 1-6: shared base gate evaluator ───────────────────────────
    let base_result = evaluate_base_gates(&input.base_gates, &mut runtime_metrics.base_gates);

    let legacy = match &base_result {
        Ok(proof) => BaseGatesLegacy::from(proof),
        Err(rejection) => BaseGatesLegacy::from(rejection),
    };

    let margin_decision =
        evaluate_margin_headroom_gate(&input.margin_gate_input, &mut runtime_metrics.margin_gate);
    let mode_hint = compute_margin_mode_hint(&input.margin_gate_input);

    let mut effective_risk_state = input.base_gates.risk_state;
    if matches!(margin_decision, MarginGateDecision::Rejected { .. })
        && effective_risk_state == RiskState::Healthy
    {
        effective_risk_state = match mode_hint {
            MarginGateMode::Kill => RiskState::Kill,
            MarginGateMode::ReduceOnly | MarginGateMode::Active => RiskState::Degraded,
        };
    }

    let mut gate_results = build_gate_results(
        legacy.preflight_passed,
        legacy.quantize_passed,
        legacy.dispatch_consistency_passed,
        legacy.fee_cache_passed,
        legacy.expiry_guard_passed,
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
        && legacy.preflight_passed
        && legacy.quantize_passed
        && legacy.dispatch_consistency_passed
        && legacy.fee_cache_passed
        && legacy.expiry_guard_passed;

    if pre_dispatch_gates_ready {
        match pending_book.reserve(
            &input.reservation_id,
            &input.instrument_id,
            input.current_delta,
            input.delta_impact_est,
            &mut runtime_metrics.pending_exposure,
        ) {
            PendingExposureResult::Reserved {
                reservation_id: rid,
                ..
            } => {
                pending_reservation_id = Some(rid);
            }
            PendingExposureResult::Rejected {
                reason: crate::risk::PendingExposureRejectReason::InstrumentNotRegistered,
                ..
            } => {
                gate_results.liquidity_gate_passed = false;
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
                liquidity_override_reason =
                    Some(REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED);
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
            let liquidity_result =
                evaluate_liquidity_gate(&input.liquidity_input, &mut runtime_metrics.liquidity);
            gate_results.liquidity_gate_passed =
                matches!(liquidity_result.decision, LiquidityGateDecision::Allowed);
            if let Some(qty) = liquidity_result.metadata.allowed_qty {
                max_dispatch_qty = Some(qty);
            }

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
                // Always override with the authoritative current_delta from the runtime input,
                // including when zero (a legitimate flat position, not a sentinel).
                inventory_skew_input.current_delta = input.current_delta;
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
    // TODO: migrate to build_order_intent_with_wal_gate() to prevent WAL bypass.
    #[allow(deprecated)]
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
        && let Some(ref reservation_id) = pending_reservation_id
    {
        let released = pending_book.settle(
            reservation_id,
            &input.instrument_id,
            PendingExposureTerminalOutcome::Rejected,
            &mut runtime_metrics.pending_exposure,
        );
        if !released {
            tracing::error!(
                %reservation_id,
                "pre-dispatch reservation settle failed — TLSM/book desync"
            );
        }
        pending_reservation_id = None;
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

/// Complete lifecycle: settle pending exposure on TLSM terminal state (S6-008).
///
/// # Safety / concurrency
///
/// This function requires `&mut Tlsm` and `&PendingExposureBook` (interior
/// mutability via RefCell). Callers sharing these across threads must use
/// `Mutex` or equivalent synchronisation.
///
/// Settlement is intentionally **one-shot**: `take_pending_reservation_on_terminal()`
/// consumes the reservation ID, so repeated calls after the first terminal event
/// are safe no-ops. This prevents double-settlement on duplicate WS events.
pub fn settle_pending_on_tlsm_terminal(
    tlsm: &mut Tlsm,
    pending_book: &PendingExposureBook,
    metrics: &mut PendingExposureMetrics,
) {
    if let Some((reservation_id, instrument_id)) = tlsm.take_pending_reservation_on_terminal() {
        let outcome = match tlsm.state() {
            crate::execution::TlsmState::Filled => PendingExposureTerminalOutcome::Filled,
            crate::execution::TlsmState::Cancelled | crate::execution::TlsmState::Failed => {
                PendingExposureTerminalOutcome::Rejected
            }
            // Defensive: take_pending_reservation_on_terminal() only returns Some on terminal
            // states. If this arm fires, a TLSM contract violation occurred. Treat as failure
            // (fail-closed) rather than panicking in production.
            _ => {
                tracing::error!(
                    state = ?tlsm.state(),
                    %reservation_id, %instrument_id,
                    "take_pending_reservation_on_terminal returned Some for non-terminal state"
                );
                PendingExposureTerminalOutcome::Rejected
            }
        };
        let released = pending_book.settle(&reservation_id, &instrument_id, outcome, metrics);
        if !released {
            tracing::error!(
                %reservation_id, %instrument_id,
                ?outcome,
                "pending exposure settlement failed — reservation not found in book (TLSM/book desync)"
            );
        }
    }
}
