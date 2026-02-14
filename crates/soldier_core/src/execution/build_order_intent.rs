//! Single chokepoint for order intent construction and gate ordering.
//!
//! CONTRACT.md CSP.5.2: All dispatch must route through `build_order_intent()`.
//!
//! **Gate ordering (deterministic):**
//! 1. Dispatch authorization (RiskState check)
//! 2. Preflight (order type validation)
//! 3. Quantize
//! 4. Dispatch consistency (AT-920 contracts/amount + quantity clamp validation)
//! 5. Fee cache staleness check
//! 6. Liquidity Gate (book-walk slippage)
//! 7. Net Edge Gate (fee + slippage vs min_edge)
//! 8. Pricer (IOC limit price clamping)
//! 9. RecordedBeforeDispatch (WAL append)
//!
//! Only after all gates pass is an `OrderIntent` produced.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::risk::RiskState;

use super::reject_reason::{GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint};

const REJECT_REASON_PREFLIGHT: &str = "preflight rejected";
const REJECT_REASON_QUANTIZE: &str = "quantize failed";
const REJECT_REASON_DISPATCH_CONSISTENCY: &str = "dispatch consistency failed";
const REJECT_REASON_DISPATCH_CLAMP_EXCEEDED: &str = "requested qty exceeds liquidity clamp";
const REJECT_REASON_DISPATCH_CLAMP_INCOMPLETE: &str = "incomplete liquidity clamp metadata";
const REJECT_REASON_FEE_CACHE_STALE: &str = "fee cache stale";
const REJECT_REASON_LIQUIDITY_GATE: &str = "liquidity gate rejected";
const REJECT_REASON_NET_EDGE: &str = "net edge too low";
const REJECT_REASON_PRICER: &str = "pricer rejected";
const REJECT_REASON_WAL: &str = "WAL append failed";

// --- Intent class --------------------------------------------------------

/// Intent classification for dispatch authorization.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChokeIntentClass {
    /// Risk-increasing intent -> requires all gates.
    Open,
    /// Risk-reducing order placement.
    Close,
    /// Hedge intent.
    Hedge,
    /// Cancel-only intent.
    CancelOnly,
}

// --- Gate step -----------------------------------------------------------

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

/// Runtime adapter for the final RecordedBeforeDispatch gate.
///
/// Implementations perform the concrete WAL append attempt and return an
/// error when recording fails.
pub trait RecordedBeforeDispatchGate {
    fn record_before_dispatch(&mut self) -> Result<(), String>;
}

/// Evaluate the chokepoint with a runtime WAL gate adapter.
///
/// This helper prevents callsites from passing precomputed `wal_recorded`
/// values and instead derives gate 9 from the actual append attempt.
pub fn build_order_intent_with_wal_gate(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
    wal_gate: &mut dyn RecordedBeforeDispatchGate,
) -> ChokeResult {
    build_order_intent_internal(
        intent_class,
        risk_state,
        metrics,
        gate_results,
        Some(wal_gate),
    )
}

/// Evaluate the chokepoint with an optional runtime WAL gate adapter.
///
/// Missing adapter is fail-closed and treated as `wal_recorded = false`.
pub fn build_order_intent_with_optional_wal_gate(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
    wal_gate: Option<&mut dyn RecordedBeforeDispatchGate>,
) -> ChokeResult {
    match wal_gate {
        Some(gate) => {
            build_order_intent_internal(intent_class, risk_state, metrics, gate_results, Some(gate))
        }
        None => {
            let mut merged = gate_results.clone();
            merged.wal_recorded = false;
            build_order_intent_internal(intent_class, risk_state, metrics, &merged, None)
        }
    }
}

// --- Chokepoint result ---------------------------------------------------

/// Reject reason from the chokepoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChokeRejectReason {
    /// RiskState is not Healthy -> OPEN blocked.
    RiskStateNotHealthy,
    /// A gate rejected the intent (gate name + reason string).
    GateRejected { gate: GateStep, reason: String },
}

/// Result of the chokepoint evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum ChokeResult {
    /// All gates passed -> OrderIntent is ready for dispatch.
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

// --- Metrics -------------------------------------------------------------

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateSequenceResult {
    Allowed,
    Rejected,
}

static GATE_SEQUENCE_ALLOWED_TOTAL: AtomicU64 = AtomicU64::new(0);
static GATE_SEQUENCE_REJECTED_TOTAL: AtomicU64 = AtomicU64::new(0);

pub fn gate_sequence_total(result: GateSequenceResult) -> u64 {
    match result {
        GateSequenceResult::Allowed => GATE_SEQUENCE_ALLOWED_TOTAL.load(Ordering::Relaxed),
        GateSequenceResult::Rejected => GATE_SEQUENCE_REJECTED_TOTAL.load(Ordering::Relaxed),
    }
}

fn finish_approved(metrics: &mut ChokeMetrics, gate_trace: Vec<GateStep>) -> ChokeResult {
    metrics.record_approved();
    GATE_SEQUENCE_ALLOWED_TOTAL.fetch_add(1, Ordering::Relaxed);
    super::emit_execution_metric_line("gate_sequence_total", "result=allowed");
    ChokeResult::Approved { gate_trace }
}

fn finish_rejected(
    metrics: &mut ChokeMetrics,
    reason: ChokeRejectReason,
    gate_trace: Vec<GateStep>,
) -> ChokeResult {
    metrics.record_rejected();
    if reason == ChokeRejectReason::RiskStateNotHealthy {
        metrics.record_rejected_risk_state();
    }
    GATE_SEQUENCE_REJECTED_TOTAL.fetch_add(1, Ordering::Relaxed);
    super::emit_execution_metric_line("gate_sequence_total", "result=rejected");
    ChokeResult::Rejected { reason, gate_trace }
}

// --- Chokepoint evaluator ------------------------------------------------

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
    build_order_intent_internal(intent_class, risk_state, metrics, gate_results, None)
}

fn build_order_intent_internal(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
    wal_gate: Option<&mut dyn RecordedBeforeDispatchGate>,
) -> ChokeResult {
    let mut trace = Vec::new();

    // Gate 1: Dispatch authorization (RiskState check)
    trace.push(GateStep::DispatchAuth);
    if intent_class == ChokeIntentClass::Open && risk_state != RiskState::Healthy {
        return finish_rejected(metrics, ChokeRejectReason::RiskStateNotHealthy, trace);
    }

    // CANCEL-only intents skip remaining gates.
    if intent_class == ChokeIntentClass::CancelOnly {
        return finish_approved(metrics, trace);
    }

    // Gate 2: Preflight
    trace.push(GateStep::Preflight);
    if !gate_results.preflight_passed {
        return finish_rejected(
            metrics,
            ChokeRejectReason::GateRejected {
                gate: GateStep::Preflight,
                reason: REJECT_REASON_PREFLIGHT.to_string(),
            },
            trace,
        );
    }

    // Gate 3: Quantize
    trace.push(GateStep::Quantize);
    if !gate_results.quantize_passed {
        return finish_rejected(
            metrics,
            ChokeRejectReason::GateRejected {
                gate: GateStep::Quantize,
                reason: REJECT_REASON_QUANTIZE.to_string(),
            },
            trace,
        );
    }

    // Gate 4: Dispatch consistency (AT-920 contracts/amount validation)
    trace.push(GateStep::DispatchConsistency);
    if !gate_results.dispatch_consistency_passed {
        return finish_rejected(
            metrics,
            ChokeRejectReason::GateRejected {
                gate: GateStep::DispatchConsistency,
                reason: REJECT_REASON_DISPATCH_CONSISTENCY.to_string(),
            },
            trace,
        );
    }

    // Anti-bypass clamp check: when liquidity clamp metadata is provided,
    // dispatch qty must never exceed the gate-approved max.
    match (gate_results.requested_qty, gate_results.max_dispatch_qty) {
        (None, None) => {}
        (Some(requested_qty), Some(max_dispatch_qty)) => {
            let invalid_requested = !requested_qty.is_finite() || requested_qty <= 0.0;
            let invalid_max = !max_dispatch_qty.is_finite() || max_dispatch_qty <= 0.0;
            if invalid_requested || invalid_max || requested_qty > max_dispatch_qty + 1e-12 {
                return finish_rejected(
                    metrics,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::DispatchConsistency,
                        reason: REJECT_REASON_DISPATCH_CLAMP_EXCEEDED.to_string(),
                    },
                    trace,
                );
            }
        }
        _ => {
            return finish_rejected(
                metrics,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::DispatchConsistency,
                    reason: REJECT_REASON_DISPATCH_CLAMP_INCOMPLETE.to_string(),
                },
                trace,
            );
        }
    }

    // Gate 5: Fee cache staleness
    trace.push(GateStep::FeeCacheCheck);
    if !gate_results.fee_cache_passed {
        return finish_rejected(
            metrics,
            ChokeRejectReason::GateRejected {
                gate: GateStep::FeeCacheCheck,
                reason: REJECT_REASON_FEE_CACHE_STALE.to_string(),
            },
            trace,
        );
    }

    // Gates 6-8 only for OPEN intents.
    if intent_class == ChokeIntentClass::Open {
        // Gate 6: Liquidity Gate
        trace.push(GateStep::LiquidityGate);
        if !gate_results.liquidity_gate_passed {
            return finish_rejected(
                metrics,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: REJECT_REASON_LIQUIDITY_GATE.to_string(),
                },
                trace,
            );
        }

        // Gate 7: Net Edge Gate
        trace.push(GateStep::NetEdgeGate);
        if !gate_results.net_edge_passed {
            return finish_rejected(
                metrics,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::NetEdgeGate,
                    reason: REJECT_REASON_NET_EDGE.to_string(),
                },
                trace,
            );
        }

        // Gate 8: Pricer
        trace.push(GateStep::Pricer);
        if !gate_results.pricer_passed {
            return finish_rejected(
                metrics,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Pricer,
                    reason: REJECT_REASON_PRICER.to_string(),
                },
                trace,
            );
        }
    }

    // Gate 9: RecordedBeforeDispatch
    trace.push(GateStep::RecordedBeforeDispatch);
    let mut wal_error: Option<String> = None;
    let wal_recorded = match wal_gate {
        Some(gate) => match gate.record_before_dispatch() {
            Ok(()) => true,
            Err(reason) => {
                wal_error = Some(reason);
                false
            }
        },
        None => gate_results.wal_recorded,
    };
    if !wal_recorded {
        return finish_rejected(
            metrics,
            ChokeRejectReason::GateRejected {
                gate: GateStep::RecordedBeforeDispatch,
                reason: wal_error.unwrap_or_else(|| REJECT_REASON_WAL.to_string()),
            },
            trace,
        );
    }

    finish_approved(metrics, trace)
}

/// Build an order intent and attach a contract registry reject reason code.
pub fn build_order_intent_with_reject_reason_code(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
    gate_reject_codes: &GateRejectCodes,
) -> (ChokeResult, Option<RejectReasonCode>) {
    let result = build_order_intent(intent_class, risk_state, metrics, gate_results);
    let code = match &result {
        ChokeResult::Approved { .. } => None,
        ChokeResult::Rejected { reason, .. } => {
            Some(reject_reason_from_chokepoint(reason, gate_reject_codes))
        }
    };
    (result, code)
}

// --- Gate results (pre-computed by caller) ------------------------------

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
    /// Caller-provided requested dispatch quantity.
    pub requested_qty: Option<f64>,
    /// Caller-provided max allowed quantity from upstream liquidity clamp.
    pub max_dispatch_qty: Option<f64>,
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
            requested_qty: None,
            max_dispatch_qty: None,
        }
    }
}

/// Construct gate results inside the chokepoint module.
///
/// Keeping `GateResults` construction here preserves the single-boundary
/// invariant enforced by `test_dispatch_chokepoint`.
#[allow(clippy::too_many_arguments)]
pub fn build_gate_results(
    preflight_passed: bool,
    quantize_passed: bool,
    dispatch_consistency_passed: bool,
    fee_cache_passed: bool,
    liquidity_gate_passed: bool,
    net_edge_passed: bool,
    pricer_passed: bool,
    wal_recorded: bool,
    requested_qty: Option<f64>,
    max_dispatch_qty: Option<f64>,
) -> GateResults {
    GateResults {
        preflight_passed,
        quantize_passed,
        dispatch_consistency_passed,
        fee_cache_passed,
        liquidity_gate_passed,
        net_edge_passed,
        pricer_passed,
        wal_recorded,
        requested_qty,
        max_dispatch_qty,
    }
}
