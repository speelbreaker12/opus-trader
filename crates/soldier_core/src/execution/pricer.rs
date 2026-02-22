//! Fee-Aware IOC Limit Pricer per CONTRACT.md §1.4.
//!
//! **Rule:**
//! - `net_edge = gross_edge - fees`
//! - If `net_edge < min_edge` -> reject.
//! - `net_edge_per_unit = net_edge / qty`
//! - `fee_per_unit = fee_estimate_usd / qty`
//! - `min_edge_per_unit = min_edge_usd / qty`
//! - `max_price_for_min_edge`:
//!   - BUY: `fair_price - (min_edge_per_unit + fee_per_unit)`
//!   - SELL: `fair_price + (min_edge_per_unit + fee_per_unit)`
//! - `proposed_limit = fair_price +/- 0.5 * net_edge_per_unit`
//! - Final limit clamped to guarantee min edge at limit price.
//!
//! AT-223.

use super::quantize::Side;
use std::sync::atomic::{AtomicU64, Ordering};

// --- Pricer input --------------------------------------------------------

/// Input to the IOC limit pricer.
#[derive(Debug, Clone)]
pub struct PricerInput {
    /// Fair price from the signal/model.
    pub fair_price: f64,
    /// Gross edge in USD (signal-derived expected profit before costs).
    pub gross_edge_usd: f64,
    /// Minimum acceptable net edge in USD.
    pub min_edge_usd: f64,
    /// Estimated fee in USD for this trade.
    pub fee_estimate_usd: f64,
    /// Order quantity.
    pub qty: f64,
    /// Order side.
    pub side: Side,
}

// --- Pricer result -------------------------------------------------------

/// Reject reason from the pricer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PricerRejectReason {
    /// Net edge after fees is below min_edge_usd.
    NetEdgeTooLow,
    /// Invalid input (non-finite numerics, qty <= 0, etc).
    InvalidInput,
}

/// Result of the pricer evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum PricerResult {
    /// Limit price computed successfully.
    LimitPrice {
        /// Final clamped limit price for IOC order.
        limit_price: f64,
        /// The max_price_for_min_edge bound used for clamping.
        max_price_for_min_edge: f64,
        /// Computed net edge in USD.
        net_edge_usd: f64,
    },
    /// Intent rejected — cannot achieve min edge.
    Rejected {
        /// Rejection reason.
        reason: PricerRejectReason,
        /// Net edge if computable.
        net_edge_usd: Option<f64>,
    },
}

// --- Metrics -------------------------------------------------------------

/// Observability metrics for the pricer.
#[derive(Debug)]
pub struct PricerMetrics {
    /// Rejections due to net edge too low.
    reject_total: u64,
    /// Total successful pricings.
    priced_total: u64,
}

impl PricerMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            reject_total: 0,
            priced_total: 0,
        }
    }

    /// Record a rejection.
    pub fn record_reject(&mut self) {
        self.reject_total += 1;
    }

    /// Record a successful pricing.
    pub fn record_priced(&mut self) {
        self.priced_total += 1;
    }

    /// Total rejections.
    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }

    /// Total successful pricings.
    pub fn priced_total(&self) -> u64 {
        self.priced_total
    }
}

impl Default for PricerMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Static counters (Layer 1) ──────────────────────────────────────────

static PRICER_REJECT_NET_EDGE_TOO_LOW_TOTAL: AtomicU64 = AtomicU64::new(0);
static PRICER_REJECT_INVALID_INPUT_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Read the static rejection counter for a given `PricerRejectReason`.
pub fn pricer_reject_total(reason: PricerRejectReason) -> u64 {
    match reason {
        PricerRejectReason::NetEdgeTooLow => {
            PRICER_REJECT_NET_EDGE_TOO_LOW_TOTAL.load(Ordering::Relaxed)
        }
        PricerRejectReason::InvalidInput => {
            PRICER_REJECT_INVALID_INPUT_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_pricer_reject(reason: PricerRejectReason, net_edge: Option<f64>) {
    match reason {
        PricerRejectReason::NetEdgeTooLow => {
            PRICER_REJECT_NET_EDGE_TOO_LOW_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        PricerRejectReason::InvalidInput => {
            PRICER_REJECT_INVALID_INPUT_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line(super::METRIC_PRICER_REJECT, &tail);
    tracing::debug!("PricerReject reason={:?} net_edge={:?}", reason, net_edge);
}

fn reject_invalid(metrics: &mut PricerMetrics) -> PricerResult {
    metrics.record_reject();
    bump_pricer_reject(PricerRejectReason::InvalidInput, None);
    PricerResult::Rejected {
        reason: PricerRejectReason::InvalidInput,
        net_edge_usd: None,
    }
}

// --- Pricer evaluator ----------------------------------------------------

/// Compute IOC limit price with fee-aware min-edge clamping.
///
/// CONTRACT.md §1.4: "No Market Orders" — always produce a limit price
/// that guarantees min_edge_usd at the limit.
pub fn compute_limit_price(input: &PricerInput, metrics: &mut PricerMetrics) -> PricerResult {
    // Standalone fail-closed input validation.
    if !input.fair_price.is_finite()
        || input.fair_price <= 0.0
        || !input.gross_edge_usd.is_finite()
        || !input.min_edge_usd.is_finite()
        || input.min_edge_usd < 0.0
        || !input.fee_estimate_usd.is_finite()
        || input.fee_estimate_usd < 0.0
        || !input.qty.is_finite()
        || input.qty <= 0.0
    {
        return reject_invalid(metrics);
    }

    // net_edge = gross_edge - fees
    let net_edge = input.gross_edge_usd - input.fee_estimate_usd;
    if !net_edge.is_finite() {
        return reject_invalid(metrics);
    }

    // Reject if net_edge < min_edge
    if net_edge < input.min_edge_usd {
        metrics.record_reject();
        bump_pricer_reject(PricerRejectReason::NetEdgeTooLow, Some(net_edge));
        return PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            net_edge_usd: Some(net_edge),
        };
    }

    // Per-unit calculations
    let net_edge_per_unit = net_edge / input.qty;
    let fee_per_unit = input.fee_estimate_usd / input.qty;
    let min_edge_per_unit = input.min_edge_usd / input.qty;
    if !net_edge_per_unit.is_finite() || !fee_per_unit.is_finite() || !min_edge_per_unit.is_finite()
    {
        return reject_invalid(metrics);
    }

    // max_price_for_min_edge (guarantees min edge at fill)
    let max_price_for_min_edge = match input.side {
        Side::Buy => input.fair_price - (min_edge_per_unit + fee_per_unit),
        Side::Sell => input.fair_price + (min_edge_per_unit + fee_per_unit),
    };

    // proposed_limit from fill aggressiveness
    let proposed_limit = match input.side {
        Side::Buy => input.fair_price - 0.5 * net_edge_per_unit,
        Side::Sell => input.fair_price + 0.5 * net_edge_per_unit,
    };

    if !max_price_for_min_edge.is_finite() || !proposed_limit.is_finite() {
        return reject_invalid(metrics);
    }

    // Clamp to guarantee min edge
    let limit_price = match input.side {
        Side::Buy => proposed_limit.min(max_price_for_min_edge),
        Side::Sell => proposed_limit.max(max_price_for_min_edge),
    };

    if !limit_price.is_finite() || limit_price <= 0.0 {
        return reject_invalid(metrics);
    }

    metrics.record_priced();
    PricerResult::LimitPrice {
        limit_price,
        max_price_for_min_edge,
        net_edge_usd: net_edge,
    }
}
