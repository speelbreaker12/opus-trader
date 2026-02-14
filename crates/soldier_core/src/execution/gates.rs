//! Net Edge Gate per CONTRACT.md §1.4.1.
//!
//! **Rule (Non-Negotiable):**
//! `net_edge_usd = gross_edge_usd - fee_usd - expected_slippage_usd`
//! Reject if `net_edge_usd < min_edge_usd` or any input is missing.
//!
//! This gate MUST run before any OrderIntent is eligible for dispatch.
//!
//! AT-015, AT-932.

use std::sync::atomic::{AtomicU64, Ordering};

// --- Gate input ----------------------------------------------------------

/// Input to the Net Edge Gate.
///
/// CONTRACT.md §1.4.1: All fields must be present. Missing/unparseable
/// -> Rejected(NetEdgeInputMissing).
#[derive(Debug, Clone)]
pub struct NetEdgeInput {
    /// Gross edge in USD (signal-derived expected profit before costs).
    pub gross_edge_usd: Option<f64>,
    /// Estimated fee in USD for this trade.
    pub fee_usd: Option<f64>,
    /// Expected slippage in USD (from Liquidity Gate WAP computation).
    pub expected_slippage_usd: Option<f64>,
    /// Minimum acceptable net edge in USD.
    pub min_edge_usd: Option<f64>,
}

// --- Gate result ---------------------------------------------------------

/// Reject reason from the Net Edge Gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetEdgeRejectReason {
    /// Net edge falls below min_edge_usd.
    NetEdgeTooLow,
    /// One or more inputs are missing/unparseable (fail-closed).
    NetEdgeInputMissing,
}

/// Result of the Net Edge Gate evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum NetEdgeResult {
    /// Intent is allowed — net edge is sufficient.
    Allowed {
        /// Computed net edge in USD.
        net_edge_usd: f64,
    },
    /// Intent is rejected.
    Rejected {
        /// Rejection reason.
        reason: NetEdgeRejectReason,
        /// Computed net edge in USD, if all inputs were available.
        net_edge_usd: Option<f64>,
    },
}

// --- Metrics -------------------------------------------------------------

/// Observability metrics for the Net Edge Gate.
#[derive(Debug)]
pub struct NetEdgeMetrics {
    /// Rejections due to net edge too low.
    reject_too_low: u64,
    /// Rejections due to missing inputs.
    reject_input_missing: u64,
    /// Total evaluations that passed.
    allowed_total: u64,
}

impl NetEdgeMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            reject_too_low: 0,
            reject_input_missing: 0,
            allowed_total: 0,
        }
    }

    /// Record a net-edge-too-low rejection.
    pub fn record_reject_too_low(&mut self) {
        self.reject_too_low += 1;
    }

    /// Record a missing-input rejection.
    pub fn record_reject_input_missing(&mut self) {
        self.reject_input_missing += 1;
    }

    /// Record an allowed evaluation.
    pub fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }

    /// Total too-low rejections.
    pub fn reject_too_low(&self) -> u64 {
        self.reject_too_low
    }

    /// Total missing-input rejections.
    pub fn reject_input_missing(&self) -> u64 {
        self.reject_input_missing
    }

    /// Total allowed evaluations.
    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }
}

impl Default for NetEdgeMetrics {
    fn default() -> Self {
        Self::new()
    }
}

static NET_EDGE_REJECT_TOO_LOW_TOTAL: AtomicU64 = AtomicU64::new(0);
static NET_EDGE_REJECT_INPUT_MISSING_TOTAL: AtomicU64 = AtomicU64::new(0);

pub fn net_edge_reject_total(reason: NetEdgeRejectReason) -> u64 {
    match reason {
        NetEdgeRejectReason::NetEdgeTooLow => NET_EDGE_REJECT_TOO_LOW_TOTAL.load(Ordering::Relaxed),
        NetEdgeRejectReason::NetEdgeInputMissing => {
            NET_EDGE_REJECT_INPUT_MISSING_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_net_edge_reject(reason: NetEdgeRejectReason, net_edge_usd: Option<f64>) {
    match reason {
        NetEdgeRejectReason::NetEdgeTooLow => {
            NET_EDGE_REJECT_TOO_LOW_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        NetEdgeRejectReason::NetEdgeInputMissing => {
            NET_EDGE_REJECT_INPUT_MISSING_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line("net_edge_reject_total", &tail);
    tracing::debug!(
        "NetEdgeReject reason={:?} net_edge_usd={:?}",
        reason,
        net_edge_usd
    );
}

fn reject_missing(metrics: &mut NetEdgeMetrics) -> NetEdgeResult {
    metrics.record_reject_input_missing();
    bump_net_edge_reject(NetEdgeRejectReason::NetEdgeInputMissing, None);
    NetEdgeResult::Rejected {
        reason: NetEdgeRejectReason::NetEdgeInputMissing,
        net_edge_usd: None,
    }
}

// --- Gate evaluator ------------------------------------------------------

/// Evaluate an intent against the Net Edge Gate.
///
/// CONTRACT.md §1.4.1:
/// - `net_edge_usd = gross_edge_usd - fee_usd - expected_slippage_usd`
/// - Missing inputs -> Rejected(NetEdgeInputMissing) (fail-closed).
/// - `net_edge_usd < min_edge_usd` -> Rejected(NetEdgeTooLow).
pub fn evaluate_net_edge(input: &NetEdgeInput, metrics: &mut NetEdgeMetrics) -> NetEdgeResult {
    // Fail-closed: reject if any input is missing (AT-932)
    let gross = match input.gross_edge_usd {
        Some(v) => v,
        None => return reject_missing(metrics),
    };

    let fee = match input.fee_usd {
        Some(v) => v,
        None => return reject_missing(metrics),
    };

    let slippage = match input.expected_slippage_usd {
        Some(v) => v,
        None => return reject_missing(metrics),
    };

    let min_edge = match input.min_edge_usd {
        Some(v) => v,
        None => return reject_missing(metrics),
    };

    // Fail-closed on non-finite inputs (NaN/inf).
    if !gross.is_finite() || !fee.is_finite() || !slippage.is_finite() || !min_edge.is_finite() {
        return reject_missing(metrics);
    }

    // Fail-closed on invalid negative costs/thresholds.
    if fee < 0.0 || slippage < 0.0 || min_edge < 0.0 {
        return reject_missing(metrics);
    }

    // Compute net edge.
    let net_edge_usd = gross - fee - slippage;

    if !net_edge_usd.is_finite() {
        return reject_missing(metrics);
    }

    // Reject if below minimum (AT-015).
    if net_edge_usd < min_edge {
        metrics.record_reject_too_low();
        bump_net_edge_reject(NetEdgeRejectReason::NetEdgeTooLow, Some(net_edge_usd));
        return NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeTooLow,
            net_edge_usd: Some(net_edge_usd),
        };
    }

    metrics.record_allowed();
    NetEdgeResult::Allowed { net_edge_usd }
}
