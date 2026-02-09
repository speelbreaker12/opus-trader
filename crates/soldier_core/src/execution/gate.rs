//! Pre-Trade Liquidity Gate per CONTRACT.md §1.3.
//!
//! **Purpose:** Prevent sweeping the book — reject OPEN intents whose
//! estimated slippage exceeds `max_slippage_bps`.
//!
//! **Algorithm (Deterministic):**
//! 1. Walk the L2 book on the correct side (asks for buy, bids for sell).
//! 2. Compute the Weighted Avg Price (WAP) for `OrderQty`.
//! 3. Compute `slippage_bps = (WAP - BestPrice) / BestPrice * 10_000`.
//! 4. Reject if `slippage_bps > max_slippage_bps`.
//! 5. If rejected, log `LiquidityGateReject` with WAP + slippage_bps.
//!
//! **L2 staleness:** Missing/unparseable/stale L2 → reject OPEN with
//! `LiquidityGateNoL2`. CANCEL-only intents are exempt.
//!
//! AT-222, AT-344, AT-909, AT-421.

// ─── L2 Book ─────────────────────────────────────────────────────────────

/// A single price level in the L2 order book.
#[derive(Debug, Clone, PartialEq)]
pub struct L2Level {
    /// Price at this level.
    pub price: f64,
    /// Quantity available at this level.
    pub qty: f64,
}

/// L2 book snapshot with freshness metadata.
#[derive(Debug, Clone)]
pub struct L2BookSnapshot {
    /// Ask levels (sorted ascending by price).
    pub asks: Vec<L2Level>,
    /// Bid levels (sorted descending by price).
    pub bids: Vec<L2Level>,
    /// Timestamp when this snapshot was captured (ms).
    pub timestamp_ms: u64,
}

// ─── Intent classification ──────────────────────────────────────────────

/// Intent class for liquidity gate evaluation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateIntentClass {
    /// Risk-increasing — requires L2 and slippage check.
    Open,
    /// Risk-reducing order placement — requires L2 but exempt from some gates.
    Close,
    /// Cancel-only — always allowed, no L2 needed.
    CancelOnly,
}

// ─── Gate input ─────────────────────────────────────────────────────────

/// Input to the Liquidity Gate evaluator.
#[derive(Debug, Clone)]
pub struct LiquidityGateInput {
    /// Order quantity to evaluate.
    pub order_qty: f64,
    /// Order side: true = buy, false = sell.
    pub is_buy: bool,
    /// Intent classification.
    pub intent_class: GateIntentClass,
    /// L2 book snapshot, if available.
    pub l2_snapshot: Option<L2BookSnapshot>,
    /// Current time (ms) for staleness check.
    pub now_ms: u64,
    /// Maximum age of L2 snapshot before it's considered stale (ms).
    pub l2_book_snapshot_max_age_ms: u64,
    /// Maximum allowed slippage in basis points (default: 10).
    pub max_slippage_bps: f64,
}

// ─── Gate result ─────────────────────────────────────────────────────────

/// Reject reason from the Liquidity Gate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LiquidityGateRejectReason {
    /// L2 book is missing, unparseable, or stale.
    LiquidityGateNoL2,
    /// Estimated slippage exceeds max_slippage_bps.
    ExpectedSlippageTooHigh,
}

/// Result of the Liquidity Gate evaluation.
#[derive(Debug, Clone, PartialEq)]
pub enum LiquidityGateResult {
    /// Intent is allowed to proceed.
    Allowed {
        /// Computed WAP (if book walk was performed).
        wap: Option<f64>,
        /// Computed slippage in bps (if book walk was performed).
        slippage_bps: Option<f64>,
    },
    /// Intent is rejected.
    Rejected {
        /// Rejection reason.
        reason: LiquidityGateRejectReason,
        /// Computed WAP (if available).
        wap: Option<f64>,
        /// Computed slippage in bps (if available).
        slippage_bps: Option<f64>,
    },
}

// ─── Metrics ─────────────────────────────────────────────────────────────

/// Observability metrics for the Liquidity Gate.
#[derive(Debug)]
pub struct LiquidityGateMetrics {
    /// Rejections due to missing/stale L2.
    reject_no_l2: u64,
    /// Rejections due to slippage too high.
    reject_slippage: u64,
    /// Total evaluations that passed.
    allowed_total: u64,
}

impl LiquidityGateMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            reject_no_l2: 0,
            reject_slippage: 0,
            allowed_total: 0,
        }
    }

    /// Record a no-L2 rejection.
    pub fn record_reject_no_l2(&mut self) {
        self.reject_no_l2 += 1;
    }

    /// Record a slippage rejection.
    pub fn record_reject_slippage(&mut self) {
        self.reject_slippage += 1;
    }

    /// Record an allowed evaluation.
    pub fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }

    /// Total no-L2 rejections.
    pub fn reject_no_l2(&self) -> u64 {
        self.reject_no_l2
    }

    /// Total slippage rejections.
    pub fn reject_slippage(&self) -> u64 {
        self.reject_slippage
    }

    /// Total allowed evaluations.
    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }
}

impl Default for LiquidityGateMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Book walk ──────────────────────────────────────────────────────────

/// Walk L2 book levels and compute WAP for the requested quantity.
///
/// Returns `(wap, filled_qty)`. If the book doesn't have enough depth
/// to fill the full quantity, returns the WAP for the available portion.
fn compute_wap(levels: &[L2Level], order_qty: f64) -> Option<(f64, f64)> {
    if levels.is_empty() || order_qty <= 0.0 {
        return None;
    }

    let mut remaining = order_qty;
    let mut cost = 0.0;
    let mut filled = 0.0;

    for level in levels {
        if remaining <= 0.0 {
            break;
        }
        let take = remaining.min(level.qty);
        cost += take * level.price;
        filled += take;
        remaining -= take;
    }

    if filled <= 0.0 {
        return None;
    }

    Some((cost / filled, filled))
}

// ─── Gate evaluator ─────────────────────────────────────────────────────

/// Evaluate an intent against the Liquidity Gate.
///
/// CONTRACT.md §1.3: "Before any order is sent, the Soldier must estimate
/// book impact for the requested size and reject trades that exceed max slippage."
///
/// CANCEL-only intents are always allowed (AT-421).
/// Missing/stale L2 rejects OPEN and CLOSE/HEDGE order placement (AT-344, AT-909, AT-421).
/// Slippage exceeding max_slippage_bps rejects with ExpectedSlippageTooHigh (AT-222).
pub fn evaluate_liquidity_gate(
    input: &LiquidityGateInput,
    metrics: &mut LiquidityGateMetrics,
) -> LiquidityGateResult {
    // CANCEL-only intents are always allowed (AT-421)
    if input.intent_class == GateIntentClass::CancelOnly {
        metrics.record_allowed();
        return LiquidityGateResult::Allowed {
            wap: None,
            slippage_bps: None,
        };
    }

    // Check L2 availability and staleness
    let snapshot = match &input.l2_snapshot {
        None => {
            metrics.record_reject_no_l2();
            return LiquidityGateResult::Rejected {
                reason: LiquidityGateRejectReason::LiquidityGateNoL2,
                wap: None,
                slippage_bps: None,
            };
        }
        Some(snap) => {
            // Check staleness
            if input.now_ms > snap.timestamp_ms
                && (input.now_ms - snap.timestamp_ms) > input.l2_book_snapshot_max_age_ms
            {
                metrics.record_reject_no_l2();
                return LiquidityGateResult::Rejected {
                    reason: LiquidityGateRejectReason::LiquidityGateNoL2,
                    wap: None,
                    slippage_bps: None,
                };
            }
            snap
        }
    };

    // Select correct side of book
    let levels = if input.is_buy {
        &snapshot.asks
    } else {
        &snapshot.bids
    };

    // Walk the book
    let (wap, _filled) = match compute_wap(levels, input.order_qty) {
        Some(result) => result,
        None => {
            // No levels on the relevant side — treat as no L2
            metrics.record_reject_no_l2();
            return LiquidityGateResult::Rejected {
                reason: LiquidityGateRejectReason::LiquidityGateNoL2,
                wap: None,
                slippage_bps: None,
            };
        }
    };

    // Best price is the first level
    let best_price = levels[0].price;

    // Compute slippage: (WAP - BestPrice) / BestPrice * 10_000
    // For buys: WAP >= BestPrice (walking up asks)
    // For sells: BestPrice >= WAP (walking down bids)
    let slippage_bps = if best_price > 0.0 {
        ((wap - best_price) / best_price * 10_000.0).abs()
    } else {
        0.0
    };

    // Reject if slippage exceeds max
    if slippage_bps > input.max_slippage_bps {
        metrics.record_reject_slippage();
        return LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::ExpectedSlippageTooHigh,
            wap: Some(wap),
            slippage_bps: Some(slippage_bps),
        };
    }

    metrics.record_allowed();
    LiquidityGateResult::Allowed {
        wap: Some(wap),
        slippage_bps: Some(slippage_bps),
    }
}
