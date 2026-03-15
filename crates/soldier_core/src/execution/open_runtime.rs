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
#[allow(deprecated)] // PrecomputedWalGate is a migration shim (GAP-FE-004)
use super::build_order_intent::PrecomputedWalGate;
use super::build_order_intent::build_gate_results_from_dispatch_proof;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    RecordedBeforeDispatchGate, build_order_intent_with_optional_wal_gate,
};
use super::gate::{LiquidityGateInput, LiquidityGateMetrics, evaluate_liquidity_gate};
use super::gate_outcome::GateOutcome;
use super::gates::{NetEdgeInput, NetEdgeMetrics, NetEdgeResult, evaluate_net_edge};
use super::inventory_skew::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    evaluate_inventory_skew,
};
use super::pricer::{PricerInput, PricerMetrics, compute_limit_price};
use super::tlsm::Tlsm;

/// Machine-stable reject-detail tokens consumed by execution-engine mapping.
///
/// These are not user-facing messages. Keep them symbolic and deterministic so
/// `engine::map_open_runtime_reject_code` can map without brittle free-form text parsing.
pub(crate) const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
pub(crate) const REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED: &str =
    "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED";
pub(crate) const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str =
    "GLOBAL_EXPOSURE_BUDGET_REJECT";
pub(crate) const REJECT_REASON_INVENTORY_SKEW_DELTA_LIMIT_MISSING: &str =
    "INVENTORY_SKEW_DELTA_LIMIT_MISSING";

/// OPEN runtime inputs assembled before chokepoint evaluation.
///
/// Gates 1-6 are evaluated from `base_gates` via the shared evaluator.
/// Previous bool fields (`preflight_passed`, `quantize_passed`, etc.)
/// are no longer needed — the evaluator computes them from raw inputs.
#[derive(Debug, Clone)]
pub(crate) struct OpenRuntimeInput<'a> {
    /// Base gates input (gates 1-6). The shared evaluator computes
    /// preflight_passed, quantize_passed, dispatch_consistency,
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
pub(crate) struct OpenRuntimeOutput {
    pub choke_result: ChokeResult,
    pub gate_results: GateResults,
    pub pending_reservation_id: Option<ReservationId>,
    pub mode_hint: MarginGateMode,
    pub effective_risk_state: RiskState,
    pub adjusted_min_edge_usd: Option<f64>,
}

/// Build an OPEN intent decision by wiring runtime gates before chokepoint.
pub(crate) fn build_open_order_intent_runtime(
    input: &OpenRuntimeInput<'_>,
    pending_book: &PendingExposureBook,
    choke_metrics: &mut ChokeMetrics,
    runtime_metrics: &mut OpenRuntimeMetrics,
) -> OpenRuntimeOutput {
    #[allow(deprecated)] // Compatibility wrapper for tests still driving precomputed WAL input.
    let mut wal_gate = PrecomputedWalGate {
        recorded: input.wal_recorded,
    };
    build_open_order_intent_runtime_with_wal_gate(
        input,
        pending_book,
        Some(&mut wal_gate),
        choke_metrics,
        runtime_metrics,
    )
}

pub(crate) fn build_open_order_intent_runtime_with_wal_gate(
    input: &OpenRuntimeInput<'_>,
    pending_book: &PendingExposureBook,
    wal_gate: Option<&mut dyn RecordedBeforeDispatchGate>,
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

    let mut gate_results = build_gate_results_from_dispatch_proof(
        ChokeIntentClass::Open,
        legacy.preflight_passed,
        legacy.quantize_passed,
        input.base_gates.dispatch_consistency,
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
    let mut choke_override: Option<(GateStep, &'static str)> = None;

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
                choke_override = Some((
                    GateStep::LiquidityGate,
                    REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED,
                ));
            }
            PendingExposureResult::Rejected { .. } => {
                gate_results.liquidity_gate_passed = false;
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
                choke_override = Some((
                    GateStep::LiquidityGate,
                    REJECT_REASON_PENDING_EXPOSURE_OVERFILL,
                ));
            }
        }

        if choke_override.is_none() {
            match evaluate_global_exposure_budget(
                &input.exposure_budget_input,
                &mut runtime_metrics.global_exposure,
            ) {
                ExposureBudgetResult::Allowed { .. } => {}
                ExposureBudgetResult::Rejected { .. } => {
                    gate_results.liquidity_gate_passed = false;
                    gate_results.net_edge_passed = false;
                    gate_results.pricer_passed = false;
                    choke_override = Some((
                        GateStep::LiquidityGate,
                        REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT,
                    ));
                }
            }
        }

        if choke_override.is_none() {
            let liquidity_result =
                evaluate_liquidity_gate(&input.liquidity_input, &mut runtime_metrics.liquidity);
            let liquidity_outcome =
                GateOutcome::from_liquidity(GateStep::LiquidityGate, &liquidity_result);
            gate_results.liquidity_gate_passed = liquidity_outcome.is_allowed();
            // allowed_qty is extracted regardless of decision: on reject the gate
            // is still the authority on how much qty was fillable, and the value
            // is used for observability. Dispatch is gated by liquidity_gate_passed
            // downstream, so setting max_dispatch_qty on a rejection is harmless.
            if let Some(qty) = liquidity_result.metadata.allowed_qty {
                max_dispatch_qty = Some(qty);
            }

            if gate_results.liquidity_gate_passed {
                let first_net_edge =
                    evaluate_net_edge(&input.net_edge_input, &mut runtime_metrics.net_edge);
                let first_net_edge_outcome =
                    GateOutcome::from_net_edge(GateStep::NetEdgeGate, &first_net_edge);
                let first_net_edge_usd = match first_net_edge {
                    NetEdgeResult::Allowed { net_edge_usd } => Some(net_edge_usd),
                    NetEdgeResult::Rejected { net_edge_usd, .. } => net_edge_usd,
                };
                gate_results.net_edge_passed = first_net_edge_outcome.is_allowed();

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
                        let net_edge_recheck_result =
                            evaluate_net_edge(&net_edge_recheck, &mut runtime_metrics.net_edge);
                        let net_edge_recheck_outcome = GateOutcome::from_net_edge(
                            GateStep::NetEdgeGate,
                            &net_edge_recheck_result,
                        );
                        gate_results.net_edge_passed = net_edge_recheck_outcome.is_allowed();
                    }
                    InventorySkewResult::Rejected {
                        reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
                        ..
                    } => {
                        gate_results.net_edge_passed = false;
                        if effective_risk_state == RiskState::Healthy {
                            effective_risk_state = RiskState::Degraded;
                        }
                        choke_override = Some((
                            GateStep::NetEdgeGate,
                            REJECT_REASON_INVENTORY_SKEW_DELTA_LIMIT_MISSING,
                        ));
                    }
                    InventorySkewResult::Rejected {
                        adjusted_min_edge_usd: adjusted,
                        ..
                    } => {
                        // Propagate adjusted_min_edge_usd only when the initial
                        // net-edge check passed: in that case inventory-skew is
                        // the sole reason for rejection, so open_runtime_to_decision
                        // can map the step to InventorySkew instead of NetEdgeGate.
                        if first_net_edge_outcome.is_allowed() {
                            adjusted_min_edge_usd = adjusted;
                        }
                        gate_results.net_edge_passed = false;
                    }
                }

                if gate_results.net_edge_passed {
                    let mut pricer_input = input.pricer_input.clone();
                    if let Some(adjusted) = adjusted_min_edge_usd {
                        pricer_input.min_edge_usd = adjusted;
                    }
                    let pricer_result =
                        compute_limit_price(&pricer_input, &mut runtime_metrics.pricer);
                    let pricer_outcome = GateOutcome::from_pricer(GateStep::Pricer, &pricer_result);
                    gate_results.pricer_passed = pricer_outcome.is_allowed();
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
    let mut choke_result = build_order_intent_with_optional_wal_gate(
        ChokeIntentClass::Open,
        effective_risk_state,
        choke_metrics,
        &gate_results,
        wal_gate,
    );
    if let Some((override_gate, override_reason)) = choke_override {
        choke_result = match choke_result {
            ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected { gate, .. },
                gate_trace,
            } if gate == override_gate => ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: override_gate,
                    reason: override_reason.to_string(),
                },
                gate_trace: normalize_open_override_gate_trace(gate_trace, override_gate),
            },
            ChokeResult::Rejected {
                reason: ChokeRejectReason::RiskStateNotHealthy,
                gate_trace,
            } => ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: override_gate,
                    reason: override_reason.to_string(),
                },
                gate_trace: normalize_open_override_gate_trace(gate_trace, override_gate),
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

fn normalize_open_override_gate_trace(
    mut gate_trace: Vec<GateStep>,
    override_gate: GateStep,
) -> Vec<GateStep> {
    if gate_trace.last() == Some(&override_gate) {
        return gate_trace;
    }

    if let Some(prefix) = open_gate_trace_prefix_through(override_gate) {
        return prefix;
    }

    if !gate_trace.contains(&override_gate) {
        gate_trace.push(override_gate);
    }
    gate_trace
}

fn open_gate_trace_prefix_through(last_gate: GateStep) -> Option<Vec<GateStep>> {
    const OPEN_GATE_ORDER: [GateStep; 10] = [
        GateStep::DispatchAuth,
        GateStep::Preflight,
        GateStep::Quantize,
        GateStep::DispatchConsistency,
        GateStep::FeeCacheCheck,
        GateStep::ExpiryGuard,
        GateStep::LiquidityGate,
        GateStep::NetEdgeGate,
        GateStep::Pricer,
        GateStep::RecordedBeforeDispatch,
    ];

    let mut trace = Vec::with_capacity(OPEN_GATE_ORDER.len());
    for gate in OPEN_GATE_ORDER {
        trace.push(gate);
        if gate == last_gate {
            return Some(trace);
        }
    }
    None
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

#[cfg(test)]
#[path = "open_runtime_wiring_tests.rs"]
mod open_runtime_wiring_tests;
