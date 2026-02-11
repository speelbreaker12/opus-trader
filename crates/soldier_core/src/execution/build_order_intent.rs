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

use crate::risk::RiskState;

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

    pub fn record_approved(&mut self) {
        self.approved_total += 1;
    }

    pub fn record_rejected(&mut self) {
        self.rejected_total += 1;
    }

    pub fn record_rejected_risk_state(&mut self) {
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
