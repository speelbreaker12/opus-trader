//! Post-only crossing guard per CONTRACT.md §1.4.4 C.
//!
//! If `post_only == true` and the limit price would cross the book,
//! Deribit rejects the order (F-06). Preflight must detect this
//! deterministically and reject before dispatch.
//!
//! AT-916.

use crate::execution::quantize::Side;
use std::sync::atomic::{AtomicU64, Ordering};

// ─── Static counters (Layer 1) ──────────────────────────────────────────

static POST_ONLY_CROSS_REJECT_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Read the static post-only rejection counter.
pub fn post_only_reject_total() -> u64 {
    POST_ONLY_CROSS_REJECT_TOTAL.load(Ordering::Relaxed)
}

fn bump_post_only_reject(reason: PostOnlyRejectReason) {
    POST_ONLY_CROSS_REJECT_TOTAL.fetch_add(1, Ordering::Relaxed);
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line(super::METRIC_POST_ONLY_REJECT, &tail);
    tracing::debug!("PostOnlyReject reason={:?}", reason);
}

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

/// Rejection reason for the post-only crossing guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PostOnlyRejectReason {
    /// Limit price would cross the touch.
    WouldCross,
    /// Non-finite limit price (NaN/Inf) — fail-closed.
    NonFinitePrice,
    /// Non-finite book price (NaN/Inf best_ask or best_bid) — fail-closed.
    NonFiniteBookPrice,
}

/// Result of the post-only crossing check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PostOnlyResult {
    /// Order is allowed (not post_only, or would not cross).
    Allowed,
    /// Order rejected — reason explains why.
    Rejected { reason: PostOnlyRejectReason },
}

// ─── Metrics ────────────────────────────────────────────────────────────

/// Observability metrics for the post-only crossing guard.
#[derive(Debug)]
pub struct PostOnlyMetrics {
    /// `post_only_reject_total` counter.
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

    /// Current value of `post_only_reject_total`.
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
///
/// NOTE: `limit_price`, `best_ask`, and `best_bid` are assumed to be
/// pre-quantized (tick-aligned) by the upstream quantizer, so f64
/// equality comparisons (`>=`, `<=`) are exact for crossing detection.
pub fn check_post_only(input: &PostOnlyInput, metrics: &mut PostOnlyMetrics) -> PostOnlyResult {
    // If not post_only, no check needed.
    if !input.post_only {
        return PostOnlyResult::Allowed;
    }

    // Fail-closed: reject non-finite limit_price (NaN, ±Inf).
    // IEEE 754: NaN comparisons always return false, so NaN >= ask would
    // silently pass the crossing check. is_finite() catches both NaN and Inf.
    if !input.limit_price.is_finite() {
        let reason = PostOnlyRejectReason::NonFinitePrice;
        tracing::warn!(
            limit_price = input.limit_price,
            "post_only: non-finite limit_price, rejecting (fail-closed)"
        );
        metrics.record_reject();
        bump_post_only_reject(reason);
        return PostOnlyResult::Rejected { reason };
    }

    let would_cross = match input.side {
        // A buy order crosses if its price >= the best ask (it would take liquidity).
        Side::Buy => match input.best_ask {
            Some(ask) => {
                if !ask.is_finite() {
                    let reason = PostOnlyRejectReason::NonFiniteBookPrice;
                    tracing::warn!(
                        best_ask = ask,
                        "post_only: non-finite best_ask, rejecting (fail-closed)"
                    );
                    metrics.record_reject();
                    bump_post_only_reject(reason);
                    return PostOnlyResult::Rejected { reason };
                }
                input.limit_price >= ask
            }
            None => false, // No asks → cannot cross
        },
        // A sell order crosses if its price <= the best bid (it would take liquidity).
        Side::Sell => match input.best_bid {
            Some(bid) => {
                if !bid.is_finite() {
                    let reason = PostOnlyRejectReason::NonFiniteBookPrice;
                    tracing::warn!(
                        best_bid = bid,
                        "post_only: non-finite best_bid, rejecting (fail-closed)"
                    );
                    metrics.record_reject();
                    bump_post_only_reject(reason);
                    return PostOnlyResult::Rejected { reason };
                }
                input.limit_price <= bid
            }
            None => false, // No bids → cannot cross
        },
    };

    if would_cross {
        let reason = PostOnlyRejectReason::WouldCross;
        metrics.record_reject();
        bump_post_only_reject(reason);
        PostOnlyResult::Rejected { reason }
    } else {
        PostOnlyResult::Allowed
    }
}
