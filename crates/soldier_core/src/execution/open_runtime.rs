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
use super::build_order_intent::build_gate_results_from_dispatch_proof;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
};
use super::dispatch_map::{DispatchConsistencyProof, IntentClass, MismatchMetrics};
use super::gate::{LiquidityGateInput, LiquidityGateMetrics, evaluate_liquidity_gate};
use super::gate_outcome::GateOutcome;
use super::gates::{NetEdgeInput, NetEdgeMetrics, NetEdgeResult, evaluate_net_edge};
use super::intent_assembly::{SizingParams, assemble_sizing};
use super::inventory_skew::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    evaluate_inventory_skew,
};
use super::orchestration_tail::run_orchestration_tail;
use super::pricer::{PricerInput, PricerMetrics, compute_limit_price};
use super::reject_reason::{GateRejectCodes, RejectReasonCode};
use super::tlsm::Tlsm;
use crate::venue::types::InstrumentKindInput;

/// Machine-stable reject-detail tokens consumed by execution-engine mapping.
///
/// These are not user-facing messages. Keep them symbolic and deterministic so
/// `engine::map_open_runtime_reject_code` can map without brittle free-form text parsing.
pub(crate) const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
pub(crate) const REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED: &str =
    "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED";
pub(crate) const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str =
    "GLOBAL_EXPOSURE_BUDGET_REJECT";

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
    pub gate_reject_codes: GateRejectCodes,
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
    let mut gate_reject_codes = GateRejectCodes {
        preflight: legacy.preflight_reject_code,
        quantize: legacy.quantize_reject_code,
        fee_cache: legacy.fee_cache_reject_code,
        expiry_guard: legacy.expiry_guard_reject_code,
        liquidity_gate: None,
        net_edge_gate: None,
        recorded_before_dispatch: if input.wal_recorded {
            None
        } else {
            Some(RejectReasonCode::RecordedBeforeDispatchFailed)
        },
        pricer: None,
    };

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
                gate_reject_codes.liquidity_gate =
                    Some(RejectReasonCode::PendingExposureBudgetExceeded);
                gate_reject_codes.net_edge_gate = Some(RejectReasonCode::GateCascadeSkip);
                gate_reject_codes.pricer = Some(RejectReasonCode::GateCascadeSkip);
                liquidity_override_reason =
                    Some(REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED);
            }
            PendingExposureResult::Rejected { .. } => {
                gate_results.liquidity_gate_passed = false;
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
                gate_reject_codes.liquidity_gate =
                    Some(RejectReasonCode::PendingExposureBudgetExceeded);
                gate_reject_codes.net_edge_gate = Some(RejectReasonCode::GateCascadeSkip);
                gate_reject_codes.pricer = Some(RejectReasonCode::GateCascadeSkip);
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
                    gate_reject_codes.liquidity_gate =
                        Some(RejectReasonCode::GlobalExposureBudgetExceeded);
                    gate_reject_codes.net_edge_gate = Some(RejectReasonCode::GateCascadeSkip);
                    gate_reject_codes.pricer = Some(RejectReasonCode::GateCascadeSkip);
                    liquidity_override_reason = Some(REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT);
                }
            }
        }

        if liquidity_override_reason.is_none() {
            let liquidity_result =
                evaluate_liquidity_gate(&input.liquidity_input, &mut runtime_metrics.liquidity);
            let liquidity_outcome =
                GateOutcome::from_liquidity(GateStep::LiquidityGate, &liquidity_result);
            let (liquidity_gate_passed, liquidity_gate_reject_code) = liquidity_outcome.to_legacy();
            gate_results.liquidity_gate_passed = liquidity_gate_passed;
            gate_reject_codes.liquidity_gate = liquidity_gate_reject_code;
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
                let first_net_edge_usd = match first_net_edge {
                    NetEdgeResult::Allowed { net_edge_usd } => Some(net_edge_usd),
                    NetEdgeResult::Rejected { net_edge_usd, .. } => net_edge_usd,
                };
                let first_net_edge_outcome =
                    GateOutcome::from_net_edge(GateStep::NetEdgeGate, &first_net_edge);
                let (net_edge_passed, net_edge_reject_code) = first_net_edge_outcome.to_legacy();
                gate_results.net_edge_passed = net_edge_passed;
                gate_reject_codes.net_edge_gate = net_edge_reject_code;

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
                        let rechecked_net_edge =
                            evaluate_net_edge(&net_edge_recheck, &mut runtime_metrics.net_edge);
                        let rechecked_net_edge_outcome =
                            GateOutcome::from_net_edge(GateStep::NetEdgeGate, &rechecked_net_edge);
                        let (rechecked_net_edge_passed, rechecked_net_edge_code) =
                            rechecked_net_edge_outcome.to_legacy();
                        gate_results.net_edge_passed = rechecked_net_edge_passed;
                        gate_reject_codes.net_edge_gate = rechecked_net_edge_code;
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
                    InventorySkewResult::Rejected {
                        adjusted_min_edge_usd: adjusted,
                        ..
                    } => {
                        // Only overwrite the reject code when the initial net-edge
                        // check passed: in that case the inventory-skew adjustment
                        // is the reason we are now rejecting, so NetEdgeTooLow is
                        // accurate.  If the initial check already failed (e.g.
                        // NetEdgeInputMissing), preserve that original code so
                        // map_open_rejection_step reports the real cause.
                        if net_edge_passed {
                            gate_reject_codes.net_edge_gate =
                                Some(RejectReasonCode::NetEdgeTooLow);
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
                    let (pricer_passed, pricer_reject_code) = pricer_outcome.to_legacy();
                    gate_results.pricer_passed = pricer_passed;
                    gate_reject_codes.pricer = pricer_reject_code;
                } else {
                    gate_results.pricer_passed = false;
                    gate_reject_codes.pricer = Some(RejectReasonCode::GateCascadeSkip);
                }
            } else {
                gate_results.net_edge_passed = false;
                gate_results.pricer_passed = false;
                gate_reject_codes.net_edge_gate = Some(RejectReasonCode::GateCascadeSkip);
                gate_reject_codes.pricer = Some(RejectReasonCode::GateCascadeSkip);
            }
        }
    } else {
        gate_results.liquidity_gate_passed = false;
        gate_results.net_edge_passed = false;
        gate_results.pricer_passed = false;
    }

    gate_results.max_dispatch_qty = max_dispatch_qty;
    let mut choke_result = run_orchestration_tail(
        ChokeIntentClass::Open,
        effective_risk_state,
        choke_metrics,
        &gate_results,
        &gate_reject_codes,
    )
    .decision;
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
        gate_reject_codes,
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

/// Build an OPEN intent with full assembly validation.
///
/// This combines `assemble_sizing()` (deriving `dispatch_consistency`
/// and optionally degrading risk state) with the OPEN runtime gate evaluation.
///
/// Use this entry point when raw venue metadata is available. It provides the
/// production callsite for `derive_instrument_kind`, `build_order_size`, and
/// `validate_and_dispatch` — ensuring the full assembly chain is exercised
/// before gate evaluation.
///
/// TODO(slice-2): Wire as production entry point for order submission.
///
/// Assembly failure is fail-closed: `dispatch_consistency` is set to
/// `failed()` and risk state is degraded.
#[allow(dead_code)]
pub(crate) fn build_open_intent_with_assembly(
    assembly_meta: &InstrumentKindInput,
    sizing_params: &SizingParams,
    input: &OpenRuntimeInput<'_>,
    pending_book: &PendingExposureBook,
    choke_metrics: &mut ChokeMetrics,
    runtime_metrics: &mut OpenRuntimeMetrics,
    mismatch_metrics: &mut MismatchMetrics,
) -> OpenRuntimeOutput {
    let mut adjusted_input = input.clone();

    match assemble_sizing(
        assembly_meta,
        sizing_params,
        IntentClass::Open,
        mismatch_metrics,
    ) {
        Ok(assembled) => {
            adjusted_input.base_gates.dispatch_consistency = assembled.dispatch_consistency;
            if assembled.risk_state_degraded
                && adjusted_input.base_gates.risk_state == RiskState::Healthy
            {
                adjusted_input.base_gates.risk_state = RiskState::Degraded;
            }
        }
        Err(e) => {
            tracing::warn!(
                ?e,
                "assembly failed — degrading dispatch_consistency to false"
            );
            adjusted_input.base_gates.dispatch_consistency = DispatchConsistencyProof::failed();
            if adjusted_input.base_gates.risk_state == RiskState::Healthy {
                adjusted_input.base_gates.risk_state = RiskState::Degraded;
            }
        }
    }

    build_open_order_intent_runtime(
        &adjusted_input,
        pending_book,
        choke_metrics,
        runtime_metrics,
    )
}

#[cfg(test)]
#[path = "open_runtime_wiring_tests.rs"]
mod open_runtime_wiring_tests;
