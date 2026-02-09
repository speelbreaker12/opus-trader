//! Post-only crossing guard per CONTRACT.md §1.4.4 C.
//!
//! If `post_only == true` and the limit price would cross the book,
//! Deribit rejects the order (F-06). Preflight must detect this
//! deterministically and reject before dispatch.
//!
//! AT-916.

use crate::execution::quantize::Side;

// ─── Input ──────────────────────────────────────────────────────────────

/// Input for the post-only crossing check.
#[derive(Debug, Clone)]
pub struct PostOnlyInput {
    /// Whether the order has `post_only == true`.
    pub post_only: bool,
    /// The order side (buy or sell).
    pub side: Side,
    /// The quantized limit price of the order.
    pub limit_price: f64,
    /// Best ask (lowest offer) from the order book. `None` if book is empty.
    pub best_ask: Option<f64>,
    /// Best bid (highest bid) from the order book. `None` if book is empty.
    pub best_bid: Option<f64>,
}

// ─── Result ─────────────────────────────────────────────────────────────

/// Result of the post-only crossing check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PostOnlyResult {
    /// Order is allowed (not post_only, or would not cross).
    Allowed,
    /// Order would cross the book — reject before dispatch.
    Rejected,
}

// ─── Metrics ────────────────────────────────────────────────────────────

/// Observability metrics for the post-only crossing guard.
#[derive(Debug)]
pub struct PostOnlyMetrics {
    /// `post_only_cross_reject_total` counter.
    reject_total: u64,
}

impl PostOnlyMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self { reject_total: 0 }
    }

    /// Increment the rejection counter.
    pub fn record_reject(&mut self) {
        self.reject_total += 1;
    }

    /// Current value of `post_only_cross_reject_total`.
    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }
}

impl Default for PostOnlyMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Core function ──────────────────────────────────────────────────────

/// Check whether a post-only order would cross the book.
///
/// CONTRACT.md §1.4.4 C:
/// - If `post_only == true` and order would cross the book → reject.
/// - A buy crosses if `limit_price >= best_ask`.
/// - A sell crosses if `limit_price <= best_bid`.
/// - If the relevant side of the book is empty (None), the order cannot
///   cross, so it is allowed.
pub fn check_post_only(input: &PostOnlyInput, metrics: &mut PostOnlyMetrics) -> PostOnlyResult {
    // If not post_only, no check needed.
    if !input.post_only {
        return PostOnlyResult::Allowed;
    }

    let would_cross = match input.side {
        // A buy order crosses if its price >= the best ask (it would take liquidity).
        Side::Buy => match input.best_ask {
            Some(ask) => input.limit_price >= ask,
            None => false, // No asks → cannot cross
        },
        // A sell order crosses if its price <= the best bid (it would take liquidity).
        Side::Sell => match input.best_bid {
            Some(bid) => input.limit_price <= bid,
            None => false, // No bids → cannot cross
        },
    };

    if would_cross {
        metrics.record_reject();
        PostOnlyResult::Rejected
    } else {
        PostOnlyResult::Allowed
    }
}
