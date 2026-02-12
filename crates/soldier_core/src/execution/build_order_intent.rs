//! Single chokepoint for order intent construction and gate ordering.
//!
//! CONTRACT.md CSP.5.2: All dispatch must route through `build_order_intent()`.
//!
//! **Gate ordering (deterministic):**
//! 1. Dispatch authorization (RiskState check)
//! 2. Preflight (order type validation)
//! 3. Quantize
//! 4. Dispatch consistency (AT-920 contracts/amount validation)
//! 5. Fee cache staleness check
//! 6. Liquidity Gate (book-walk slippage)
//! 7. Net Edge Gate (fee + slippage vs min_edge)
//! 8. Pricer (IOC limit price clamping)
//! 9. RecordedBeforeDispatch (WAL append)
//!
//! Only after all gates pass is an `OrderIntent` produced.

use super::gate::{
    GateIntentClass, LiquidityGateInput, LiquidityGateMetrics, LiquidityGateResult,
    evaluate_liquidity_gate,
};
use super::gates::{NetEdgeInput, NetEdgeMetrics, NetEdgeResult, evaluate_net_edge};
use super::inventory_skew::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    evaluate_inventory_skew,
};
use super::pricer::{PricerInput, PricerMetrics, PricerResult, compute_limit_price};
use crate::risk::{
    ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetResult, MarginGateInput,
    MarginGateMetrics, MarginGateMode, MarginGateResult, PendingExposureBook,
    PendingExposureMetrics, PendingExposureResult, PendingExposureTerminalOutcome, RiskState,
    evaluate_global_exposure_budget, evaluate_margin_headroom_gate,
};

// ─── Intent class ────────────────────────────────────────────────────────

/// Intent classification for dispatch authorization.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChokeIntentClass {
    /// Risk-increasing intent — requires all gates.
    Open,
    /// Risk-reducing order placement.
    Close,
    /// Hedge intent.
    Hedge,
    /// Cancel-only intent.
    CancelOnly,
}

// ─── Gate step ──────────────────────────────────────────────────────────

/// Named gate steps for ordering trace.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateStep {
    DispatchAuth,
    Preflight,
    Quantize,
    DispatchConsistency,
    FeeCacheCheck,
    LiquidityGate,
    NetEdgeGate,
    Pricer,
    RecordedBeforeDispatch,
}

// ─── Chokepoint result ──────────────────────────────────────────────────

/// Reject reason from the chokepoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChokeRejectReason {
    /// RiskState is not Healthy — OPEN blocked.
    RiskStateNotHealthy,
    /// A gate rejected the intent (gate name + reason string).
    GateRejected { gate: GateStep, reason: String },
}

/// Result of the chokepoint evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum ChokeResult {
    /// All gates passed — OrderIntent is ready for dispatch.
    Approved {
        /// Ordered list of gates that were executed.
        gate_trace: Vec<GateStep>,
    },
    /// Intent was rejected at a specific gate.
    Rejected {
        /// Rejection reason.
        reason: ChokeRejectReason,
        /// Gates executed before rejection (for audit).
        gate_trace: Vec<GateStep>,
    },
}

// ─── Metrics ─────────────────────────────────────────────────────────────

/// Observability metrics for the chokepoint.
#[derive(Debug)]
pub struct ChokeMetrics {
    /// Total intents approved.
    approved_total: u64,
    /// Total intents rejected.
    rejected_total: u64,
    /// Rejections due to risk state.
    rejected_risk_state: u64,
}

impl ChokeMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            approved_total: 0,
            rejected_total: 0,
            rejected_risk_state: 0,
        }
    }

    fn record_approved(&mut self) {
        self.approved_total += 1;
    }

    fn record_rejected(&mut self) {
        self.rejected_total += 1;
    }

    fn record_rejected_risk_state(&mut self) {
        self.rejected_risk_state += 1;
    }

    pub fn approved_total(&self) -> u64 {
        self.approved_total
    }

    pub fn rejected_total(&self) -> u64 {
        self.rejected_total
    }

    pub fn rejected_risk_state(&self) -> u64 {
        self.rejected_risk_state
    }
}

impl Default for ChokeMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Chokepoint evaluator ───────────────────────────────────────────────

/// Build an order intent through the single chokepoint.
///
/// This is the ONLY entry point for OrderIntent construction.
/// All gates run in deterministic order. OPEN intents require all gates;
/// CLOSE/HEDGE/CANCEL skip some gates but still flow through the chokepoint.
///
/// Returns `ChokeResult::Approved` with the gate trace if all pass,
/// or `ChokeResult::Rejected` with the failing gate.
pub fn build_order_intent(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
) -> ChokeResult {
    let mut trace = Vec::new();

    // Gate 1: Dispatch authorization (RiskState check)
    trace.push(GateStep::DispatchAuth);
    if intent_class == ChokeIntentClass::Open && risk_state != RiskState::Healthy {
        metrics.record_rejected();
        metrics.record_rejected_risk_state();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            gate_trace: trace,
        };
    }

    // CANCEL-only intents skip remaining gates
    if intent_class == ChokeIntentClass::CancelOnly {
        metrics.record_approved();
        return ChokeResult::Approved { gate_trace: trace };
    }

    // Gate 2: Preflight
    trace.push(GateStep::Preflight);
    if !gate_results.preflight_passed {
        metrics.record_rejected();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::Preflight,
                reason: "preflight rejected".to_string(),
            },
            gate_trace: trace,
        };
    }

    // Gate 3: Quantize
    trace.push(GateStep::Quantize);
    if !gate_results.quantize_passed {
        metrics.record_rejected();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::Quantize,
                reason: "quantize failed".to_string(),
            },
            gate_trace: trace,
        };
    }

    // Gate 4: Dispatch consistency (AT-920 contracts/amount validation)
    trace.push(GateStep::DispatchConsistency);
    if !gate_results.dispatch_consistency_passed {
        metrics.record_rejected();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::DispatchConsistency,
                reason: "dispatch consistency failed".to_string(),
            },
            gate_trace: trace,
        };
    }

    // Gate 5: Fee cache staleness
    trace.push(GateStep::FeeCacheCheck);
    if !gate_results.fee_cache_passed {
        metrics.record_rejected();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::FeeCacheCheck,
                reason: "fee cache stale".to_string(),
            },
            gate_trace: trace,
        };
    }

    // Gates 6-8 only for OPEN intents
    if intent_class == ChokeIntentClass::Open {
        // Gate 6: Liquidity Gate
        trace.push(GateStep::LiquidityGate);
        if !gate_results.liquidity_gate_passed {
            metrics.record_rejected();
            return ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: "liquidity gate rejected".to_string(),
                },
                gate_trace: trace,
            };
        }

        // Gate 7: Net Edge Gate
        trace.push(GateStep::NetEdgeGate);
        if !gate_results.net_edge_passed {
            metrics.record_rejected();
            return ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: GateStep::NetEdgeGate,
                    reason: "net edge too low".to_string(),
                },
                gate_trace: trace,
            };
        }

        // Gate 8: Pricer
        trace.push(GateStep::Pricer);
        if !gate_results.pricer_passed {
            metrics.record_rejected();
            return ChokeResult::Rejected {
                reason: ChokeRejectReason::GateRejected {
                    gate: GateStep::Pricer,
                    reason: "pricer rejected".to_string(),
                },
                gate_trace: trace,
            };
        }
    }

    // Gate 9: RecordedBeforeDispatch
    trace.push(GateStep::RecordedBeforeDispatch);
    if !gate_results.wal_recorded {
        metrics.record_rejected();
        return ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::RecordedBeforeDispatch,
                reason: "WAL append failed".to_string(),
            },
            gate_trace: trace,
        };
    }

    metrics.record_approved();
    ChokeResult::Approved { gate_trace: trace }
}

// ─── Gate results (pre-computed by caller) ──────────────────────────────

/// Pre-computed gate results passed to the chokepoint.
///
/// Each gate is evaluated independently before calling `build_order_intent`.
/// The chokepoint enforces ordering and early-exit semantics.
#[derive(Debug, Clone)]
pub struct GateResults {
    pub preflight_passed: bool,
    pub quantize_passed: bool,
    pub dispatch_consistency_passed: bool,
    pub fee_cache_passed: bool,
    pub liquidity_gate_passed: bool,
    pub net_edge_passed: bool,
    pub pricer_passed: bool,
    pub wal_recorded: bool,
}

impl Default for GateResults {
    fn default() -> Self {
        Self {
            preflight_passed: true,
            quantize_passed: true,
            dispatch_consistency_passed: true,
            fee_cache_passed: true,
            liquidity_gate_passed: true,
            net_edge_passed: true,
            pricer_passed: true,
            wal_recorded: true,
        }
    }
}

/// Runtime OPEN-input bundle used to wire Slice 6 gates into the chokepoint.
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

/// Runtime metrics for OPEN chokepoint wiring.
#[derive(Debug, Default)]
pub struct OpenRuntimeMetrics {
    pub pending_exposure: PendingExposureMetrics,
    pub global_exposure: ExposureBudgetMetrics,
    pub margin_gate: MarginGateMetrics,
    pub liquidity_gate: LiquidityGateMetrics,
    pub net_edge: NetEdgeMetrics,
    pub inventory_skew: InventorySkewMetrics,
    pub pricer: PricerMetrics,
}

/// Result of runtime OPEN chokepoint evaluation.
#[derive(Debug, Clone)]
pub struct OpenRuntimeResult {
    pub choke_result: ChokeResult,
    pub gate_results: GateResults,
    pub pending_reservation_id: Option<u64>,
    pub effective_risk_state: RiskState,
    pub mode_hint: MarginGateMode,
    pub adjusted_min_edge_usd: Option<f64>,
    pub adjusted_limit_price: Option<f64>,
}

/// Evaluate OPEN runtime gates (including Slice 6) and run the chokepoint.
///
/// Contract mapping:
/// - Pending exposure reserve occurs before dispatch and is released on local reject.
/// - Global budget, margin gate, and inventory skew are wired into OPEN eligibility.
/// - Inventory skew runs after net edge and before pricer; net edge is re-evaluated
///   with adjusted min-edge when skew modifies min-edge.
pub fn build_open_order_intent_runtime(
    input: &OpenRuntimeInput,
    pending_book: &mut PendingExposureBook,
    choke_metrics: &mut ChokeMetrics,
    runtime_metrics: &mut OpenRuntimeMetrics,
) -> OpenRuntimeResult {
    let margin_result =
        evaluate_margin_headroom_gate(&input.margin_gate_input, &mut runtime_metrics.margin_gate);
    let (mode_hint, mut effective_risk_state) = match margin_result {
        MarginGateResult::Allowed { mode_hint, .. } => (mode_hint, input.risk_state),
        MarginGateResult::Rejected { mode_hint, .. } => {
            let state = if mode_hint == MarginGateMode::Kill {
                RiskState::Kill
            } else {
                RiskState::Degraded
            };
            (mode_hint, state)
        }
    };

    let mut pending_reservation_id = None;
    let mut pending_passed = true;
    let mut global_budget_passed = true;
    let mut liquidity_gate_passed = true;
    let mut net_edge_passed = true;
    let mut pricer_passed = true;
    let mut pending_total_after_reserve = pending_book.pending_total();
    let mut adjusted_min_edge_usd = input.net_edge_input.min_edge_usd;
    let mut adjusted_limit_price = None;

    if effective_risk_state == RiskState::Healthy {
        match pending_book.reserve(
            input.current_delta,
            input.delta_impact_est,
            &mut runtime_metrics.pending_exposure,
        ) {
            PendingExposureResult::Reserved {
                reservation_id,
                pending_total,
            } => {
                pending_reservation_id = Some(reservation_id);
                pending_total_after_reserve = pending_total;
            }
            PendingExposureResult::Rejected { .. } => {
                pending_passed = false;
            }
        }

        if pending_passed {
            global_budget_passed = matches!(
                evaluate_global_exposure_budget(
                    &input.exposure_budget_input,
                    &mut runtime_metrics.global_exposure
                ),
                ExposureBudgetResult::Allowed { .. }
            );
        }

        if pending_passed && global_budget_passed {
            let mut liquidity_input = input.liquidity_input.clone();
            liquidity_input.intent_class = GateIntentClass::Open;
            liquidity_gate_passed = matches!(
                evaluate_liquidity_gate(&liquidity_input, &mut runtime_metrics.liquidity_gate),
                LiquidityGateResult::Allowed { .. }
            );
        }

        if pending_passed && global_budget_passed && liquidity_gate_passed {
            let mut net_edge_input = input.net_edge_input.clone();
            let base_net_edge =
                match evaluate_net_edge(&net_edge_input, &mut runtime_metrics.net_edge) {
                    NetEdgeResult::Allowed { net_edge_usd } => net_edge_usd,
                    NetEdgeResult::Rejected { .. } => {
                        net_edge_passed = false;
                        0.0
                    }
                };

            if net_edge_passed {
                let mut inventory_input = input.inventory_skew_input.clone();
                inventory_input.current_delta = input.current_delta;
                inventory_input.pending_delta = pending_total_after_reserve;
                inventory_input.net_edge_usd = base_net_edge;
                if let Some(min_edge) = input.net_edge_input.min_edge_usd {
                    inventory_input.min_edge_usd = min_edge;
                }

                match evaluate_inventory_skew(&inventory_input, &mut runtime_metrics.inventory_skew)
                {
                    InventorySkewResult::Allowed {
                        adjusted_min_edge_usd: adjusted_min_edge,
                        adjusted_limit_price: adjusted_limit,
                        ..
                    } => {
                        adjusted_min_edge_usd = Some(adjusted_min_edge);
                        adjusted_limit_price = Some(adjusted_limit);
                        if input.net_edge_input.min_edge_usd != Some(adjusted_min_edge) {
                            net_edge_input.min_edge_usd = Some(adjusted_min_edge);
                            net_edge_passed = matches!(
                                evaluate_net_edge(&net_edge_input, &mut runtime_metrics.net_edge),
                                NetEdgeResult::Allowed { .. }
                            );
                        }

                        if net_edge_passed {
                            let mut pricer_input = input.pricer_input.clone();
                            pricer_input.min_edge_usd = adjusted_min_edge;
                            pricer_passed = matches!(
                                compute_limit_price(&pricer_input, &mut runtime_metrics.pricer),
                                PricerResult::LimitPrice { .. }
                            );
                        }
                    }
                    InventorySkewResult::Rejected { reason, .. } => {
                        net_edge_passed = false;
                        if reason == InventorySkewRejectReason::InventorySkewDeltaLimitMissing {
                            effective_risk_state = RiskState::Degraded;
                        }
                    }
                }
            }
        }

        if !pending_passed || !global_budget_passed {
            net_edge_passed = false;
        }
    }

    let gate_results = GateResults {
        preflight_passed: input.preflight_passed,
        quantize_passed: input.quantize_passed,
        dispatch_consistency_passed: input.dispatch_consistency_passed,
        fee_cache_passed: input.fee_cache_passed,
        liquidity_gate_passed,
        net_edge_passed: pending_passed && global_budget_passed && net_edge_passed,
        pricer_passed,
        wal_recorded: input.wal_recorded,
    };

    let choke_result = build_order_intent(
        ChokeIntentClass::Open,
        effective_risk_state,
        choke_metrics,
        &gate_results,
    );

    if !matches!(choke_result, ChokeResult::Approved { .. })
        && let Some(reservation_id) = pending_reservation_id.take()
    {
        let _ = pending_book.settle(
            reservation_id,
            PendingExposureTerminalOutcome::Rejected,
            &mut runtime_metrics.pending_exposure,
        );
    }

    OpenRuntimeResult {
        choke_result,
        gate_results,
        pending_reservation_id,
        effective_risk_state,
        mode_hint,
        adjusted_min_edge_usd,
        adjusted_limit_price,
    }
}
