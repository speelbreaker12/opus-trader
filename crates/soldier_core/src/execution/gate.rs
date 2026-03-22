//! Pre-Trade Liquidity Gate per CONTRACT.md §1.3.
//!
//! **Purpose:** Prevent sweeping the book — reject OPEN intents whose
//! estimated slippage exceeds `max_slippage_bps`.
//!
//! **Algorithm (Deterministic):**
//! 1. Walk the L2 book on the correct side (asks for buy, bids for sell).
//! 2. Compute fillable depth within the slippage budget.
//! 3. OPEN intents fail-closed unless full `OrderQty` is fillable.
//! 4. CLOSE/HEDGE intents are clamped to fillable depth (risk-reducing only).
//! 5. Compute `slippage_bps = (WAP - BestPrice) / BestPrice * 10_000`.
//! 6. Reject if `slippage_bps > max_slippage_bps`.
//! 7. If rejected, log `LiquidityGateReject` with WAP + slippage_bps.
//!
//! **L2 staleness:** Missing/unparseable/stale L2 -> reject OPEN with
//! `LiquidityGateNoL2`. CANCEL-only intents are exempt.
//!
//! AT-222, AT-344, AT-909, AT-421.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::telemetry::EventSink;

// --- L2 Book -------------------------------------------------------------

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

// --- Intent classification ----------------------------------------------

/// Intent class for liquidity gate evaluation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateIntentClass {
    /// Risk-increasing -> requires L2 and slippage check.
    Open,
    /// Risk-reducing order placement -> requires L2 but exempt from some gates.
    Close,
    /// Risk-reducing hedge placement.
    Hedge,
    /// Cancel-only -> always allowed, no L2 needed.
    CancelOnly,
}

// --- Gate input ----------------------------------------------------------

/// Input to the Liquidity Gate evaluator.
#[derive(Debug, Clone)]
pub(crate) struct LiquidityGateInput {
    /// Order quantity to evaluate.
    pub order_qty: f64,
    /// Order side: true = buy, false = sell.
    pub is_buy: bool,
    /// Intent classification.
    pub intent_class: GateIntentClass,
    /// True for marketable/taker paths.
    ///
    /// Reserved for call-site diagnostics. The liquidity gate itself remains
    /// fail-closed and applies the same slippage/depth checks regardless of
    /// marketability to satisfy CONTRACT.md §1.3.
    pub is_marketable: bool,
    /// L2 book snapshot, if available.
    pub l2_snapshot: Option<L2BookSnapshot>,
    /// Current time (ms) for staleness check.
    pub now_ms: u64,
    /// Maximum age of L2 snapshot before it's considered stale (ms).
    pub l2_book_snapshot_max_age_ms: u64,
    /// Maximum allowed slippage in basis points (default: 10).
    pub max_slippage_bps: f64,
}

// --- Gate result ---------------------------------------------------------

/// Reject reason from the Liquidity Gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LiquidityGateRejectReason {
    /// L2 book is missing, unparseable, or stale.
    LiquidityGateNoL2,
    /// OPEN order cannot be fully filled within the configured slippage budget.
    InsufficientDepthWithinBudget,
    /// Estimated slippage exceeds max_slippage_bps.
    ExpectedSlippageTooHigh,
}

/// Operational data from the book walk — present on both allow and reject.
///
/// Named `Metadata` (not `Metrics`) to distinguish from `LiquidityGateMetrics`
/// which tracks counters. Always use explicit field syntax when constructing;
/// `Default` is not derived so the compiler enforces exhaustive field coverage
/// when new fields are added.
#[derive(Debug, Clone, PartialEq)]
pub struct LiquidityGateMetadata {
    /// Computed WAP (if book walk was performed).
    pub wap: Option<f64>,
    /// Computed slippage in bps (if book walk was performed).
    pub slippage_bps: Option<f64>,
    /// Total visible depth within the slippage budget.
    pub fillable_qty: Option<f64>,
    /// Maximum quantity allowed by the gate (for risk-reducing clamps).
    pub allowed_qty: Option<f64>,
}

/// Decision from the Liquidity Gate (allow or reject with reason).
#[derive(Debug, Clone, PartialEq)]
pub enum LiquidityGateDecision {
    /// Intent is allowed to proceed.
    Allowed,
    /// Intent is rejected.
    Rejected { reason: LiquidityGateRejectReason },
}

/// Result of the Liquidity Gate evaluation.
#[derive(Debug, Clone, PartialEq)]
pub struct LiquidityGateResult {
    /// Allow/reject decision.
    pub decision: LiquidityGateDecision,
    /// Operational data from the book walk.
    pub metadata: LiquidityGateMetadata,
}

/// Internal observability events for the liquidity gate.
/// Keep crate-private; callers still consume `LiquidityGateResult`.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum LiquidityGateEvent {
    Allowed,
    Reject { reason: LiquidityGateRejectReason },
    ExpectedSlippageSample,
}

struct ObservedLiquidityGateEvents<'a, 'b, E> {
    metrics: &'a mut LiquidityGateMetrics,
    inner: &'b mut E,
}

impl<E: EventSink<LiquidityGateEvent>> EventSink<LiquidityGateEvent>
    for ObservedLiquidityGateEvents<'_, '_, E>
{
    fn emit(&mut self, event: LiquidityGateEvent) {
        match &event {
            LiquidityGateEvent::Allowed => self.metrics.record_allowed(),
            LiquidityGateEvent::Reject { reason } => match reason {
                LiquidityGateRejectReason::LiquidityGateNoL2 => self.metrics.record_reject_no_l2(),
                LiquidityGateRejectReason::ExpectedSlippageTooHigh => {
                    self.metrics.record_reject_slippage()
                }
                LiquidityGateRejectReason::InsufficientDepthWithinBudget => {
                    self.metrics.record_reject_depth_shortfall()
                }
            },
            LiquidityGateEvent::ExpectedSlippageSample => {}
        }
        self.inner.emit(event);
    }
}

// --- Metrics -------------------------------------------------------------

/// Observability metrics for the Liquidity Gate.
#[derive(Debug)]
pub struct LiquidityGateMetrics {
    /// Rejections due to missing/stale L2.
    reject_no_l2: u64,
    /// Rejections due to slippage too high.
    reject_slippage: u64,
    /// Rejections due to insufficient in-budget depth for OPEN intents.
    reject_depth_shortfall: u64,
    /// Total evaluations that passed.
    allowed_total: u64,
}

impl LiquidityGateMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            reject_no_l2: 0,
            reject_slippage: 0,
            reject_depth_shortfall: 0,
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

    /// Record an insufficient-depth rejection.
    pub fn record_reject_depth_shortfall(&mut self) {
        self.reject_depth_shortfall += 1;
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

    /// Total insufficient-depth rejections.
    pub fn reject_depth_shortfall(&self) -> u64 {
        self.reject_depth_shortfall
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

static LIQUIDITY_GATE_REJECT_NO_L2_TOTAL: AtomicU64 = AtomicU64::new(0);
static LIQUIDITY_GATE_REJECT_EXPECTED_SLIPPAGE_TOTAL: AtomicU64 = AtomicU64::new(0);
static LIQUIDITY_GATE_REJECT_DEPTH_SHORTFALL_TOTAL: AtomicU64 = AtomicU64::new(0);
static EXPECTED_SLIPPAGE_BPS_SAMPLES: AtomicU64 = AtomicU64::new(0);

/// Process-lifetime rejection counter for liquidity gate.
///
/// Use for production monitoring and multi-hour root cause analysis.
/// Compare with instance `LiquidityGateMetrics` for tick-level debugging.
pub fn liquidity_gate_reject_total(reason: LiquidityGateRejectReason) -> u64 {
    match reason {
        LiquidityGateRejectReason::LiquidityGateNoL2 => {
            LIQUIDITY_GATE_REJECT_NO_L2_TOTAL.load(Ordering::Relaxed)
        }
        LiquidityGateRejectReason::ExpectedSlippageTooHigh => {
            LIQUIDITY_GATE_REJECT_EXPECTED_SLIPPAGE_TOTAL.load(Ordering::Relaxed)
        }
        LiquidityGateRejectReason::InsufficientDepthWithinBudget => {
            LIQUIDITY_GATE_REJECT_DEPTH_SHORTFALL_TOTAL.load(Ordering::Relaxed)
        }
    }
}

pub fn expected_slippage_bps_samples() -> u64 {
    EXPECTED_SLIPPAGE_BPS_SAMPLES.load(Ordering::Relaxed)
}

fn bump_liquidity_gate_reject(
    reason: LiquidityGateRejectReason,
    wap: Option<f64>,
    slippage_bps: Option<f64>,
) {
    #[cfg(test)]
    {
        crate::execution::with_metrics_update_lock(|| {
            bump_liquidity_gate_reject_inner(reason, wap, slippage_bps);
        })
    }

    #[cfg(not(test))]
    {
        bump_liquidity_gate_reject_inner(reason, wap, slippage_bps);
    }
}

fn bump_liquidity_gate_reject_inner(
    reason: LiquidityGateRejectReason,
    wap: Option<f64>,
    slippage_bps: Option<f64>,
) {
    match reason {
        LiquidityGateRejectReason::LiquidityGateNoL2 => {
            LIQUIDITY_GATE_REJECT_NO_L2_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        LiquidityGateRejectReason::ExpectedSlippageTooHigh => {
            LIQUIDITY_GATE_REJECT_EXPECTED_SLIPPAGE_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        LiquidityGateRejectReason::InsufficientDepthWithinBudget => {
            LIQUIDITY_GATE_REJECT_DEPTH_SHORTFALL_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line(super::METRIC_LIQUIDITY_GATE_REJECT, &tail);
    tracing::debug!(
        "LiquidityGateReject reason={:?} wap={:?} slippage_bps={:?}",
        reason,
        wap,
        slippage_bps
    );
}

fn record_expected_slippage_sample(slippage_bps: f64) {
    #[cfg(test)]
    {
        crate::execution::with_metrics_update_lock(|| {
            record_expected_slippage_sample_inner(slippage_bps);
        })
    }

    #[cfg(not(test))]
    {
        record_expected_slippage_sample_inner(slippage_bps);
    }
}

fn record_expected_slippage_sample_inner(slippage_bps: f64) {
    EXPECTED_SLIPPAGE_BPS_SAMPLES.fetch_add(1, Ordering::Relaxed);
    let tail = format!("value={slippage_bps}");
    super::emit_execution_metric_line(super::METRIC_EXPECTED_SLIPPAGE_BPS, &tail);
}

#[derive(Default)]
struct ProductionLiquidityGateEvents {
    saw_expected_slippage_sample: bool,
    reject_reason: Option<LiquidityGateRejectReason>,
}

impl EventSink<LiquidityGateEvent> for ProductionLiquidityGateEvents {
    fn emit(&mut self, event: LiquidityGateEvent) {
        match event {
            LiquidityGateEvent::Allowed => {}
            LiquidityGateEvent::Reject { reason } => {
                self.reject_reason = Some(reason);
            }
            LiquidityGateEvent::ExpectedSlippageSample => {
                self.saw_expected_slippage_sample = true;
            }
        }
    }
}

// --- Book walk -----------------------------------------------------------

/// Walk L2 book levels and compute WAP for the requested quantity.
///
/// Returns `(wap, filled_qty)`. If the book doesn't have enough depth
/// to fill the full quantity, returns the WAP for the available portion.
fn compute_wap(levels: &[L2Level], order_qty: f64) -> Option<(f64, f64)> {
    if levels.is_empty() || !order_qty.is_finite() || order_qty <= 0.0 {
        return None;
    }

    let mut remaining = order_qty;
    let mut cost = 0.0;
    let mut filled = 0.0;

    for level in levels {
        if !level.price.is_finite()
            || level.price <= 0.0
            || !level.qty.is_finite()
            || level.qty <= 0.0
        {
            return None;
        }
        if remaining <= 0.0 {
            break;
        }
        let take = remaining.min(level.qty);
        cost += take * level.price;
        filled += take;
        remaining -= take;
    }

    if filled <= 0.0 || !filled.is_finite() || !cost.is_finite() {
        return None;
    }

    Some((cost / filled, filled))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FillableDepthError {
    InvalidBook,
    NoDepthWithinBudget,
}

fn compute_fillable_depth(
    levels: &[L2Level],
    is_buy: bool,
    best_price: f64,
    max_slippage_bps: f64,
) -> Result<f64, FillableDepthError> {
    if levels.is_empty()
        || !best_price.is_finite()
        || best_price <= 0.0
        || !max_slippage_bps.is_finite()
        || max_slippage_bps < 0.0
    {
        return Err(FillableDepthError::InvalidBook);
    }

    let budget = max_slippage_bps / 10_000.0;
    let max_buy_price = best_price * (1.0 + budget);
    let min_sell_price = best_price * (1.0 - budget);
    if !budget.is_finite() || !max_buy_price.is_finite() || !min_sell_price.is_finite() {
        return Err(FillableDepthError::InvalidBook);
    }

    let price_limit = if is_buy {
        max_buy_price
    } else {
        min_sell_price
    };
    let mut fillable_qty = 0.0;
    let mut fillable_notional = 0.0;

    for level in levels {
        if !level.price.is_finite()
            || level.price <= 0.0
            || !level.qty.is_finite()
            || level.qty <= 0.0
        {
            return Err(FillableDepthError::InvalidBook);
        }

        let in_budget = if is_buy {
            level.price <= price_limit
        } else {
            level.price >= price_limit
        };

        if in_budget {
            fillable_qty += level.qty;
            fillable_notional += level.price * level.qty;
            if !fillable_qty.is_finite() || !fillable_notional.is_finite() {
                return Err(FillableDepthError::InvalidBook);
            }
            continue;
        }

        if fillable_qty <= 0.0 {
            break;
        }

        let numerator = if is_buy {
            price_limit * fillable_qty - fillable_notional
        } else {
            fillable_notional - price_limit * fillable_qty
        };
        let denominator = if is_buy {
            level.price - price_limit
        } else {
            price_limit - level.price
        };

        if !numerator.is_finite() || !denominator.is_finite() || denominator <= 0.0 {
            return Err(FillableDepthError::InvalidBook);
        }

        if numerator > 0.0 {
            let partial = (numerator / denominator).min(level.qty);
            if !partial.is_finite() || partial < 0.0 {
                return Err(FillableDepthError::InvalidBook);
            }
            if partial > 0.0 {
                fillable_qty += partial;
                fillable_notional += level.price * partial;
                if !fillable_qty.is_finite() || !fillable_notional.is_finite() {
                    return Err(FillableDepthError::InvalidBook);
                }
            }
        }

        break;
    }

    if fillable_qty <= 0.0 || !fillable_qty.is_finite() {
        return Err(FillableDepthError::NoDepthWithinBudget);
    }

    Ok(fillable_qty)
}

fn compute_reject_diagnostics(
    levels: &[L2Level],
    order_qty: f64,
    best_price: f64,
) -> (Option<f64>, Option<f64>) {
    let (wap, _filled) = match compute_wap(levels, order_qty) {
        Some(v) => v,
        None => return (None, None),
    };
    // Emit best-effort diagnostics even when depth is insufficient so reject
    // logs always carry actionable WAP/slippage context.
    let slippage_bps = ((wap - best_price) / best_price * 10_000.0).abs();
    if !slippage_bps.is_finite() {
        return (Some(wap), None);
    }
    (Some(wap), Some(slippage_bps))
}

fn reject_with_events<E: EventSink<LiquidityGateEvent>>(
    events: &mut E,
    reason: LiquidityGateRejectReason,
    wap: Option<f64>,
    slippage_bps: Option<f64>,
    fillable_qty: Option<f64>,
    allowed_qty: Option<f64>,
) -> LiquidityGateResult {
    events.emit(LiquidityGateEvent::Reject { reason });
    LiquidityGateResult {
        decision: LiquidityGateDecision::Rejected { reason },
        metadata: LiquidityGateMetadata {
            wap,
            slippage_bps,
            fillable_qty,
            allowed_qty,
        },
    }
}

// --- Gate evaluator ------------------------------------------------------

/// Evaluate an intent against the Liquidity Gate.
///
/// CONTRACT.md §1.3: "Before any order is sent, the Soldier must estimate
/// book impact for the requested size and reject trades that exceed max slippage."
///
/// CANCEL-only intents are always allowed (AT-421).
/// Missing/stale L2 rejects OPEN and CLOSE/HEDGE order placement (AT-344, AT-909, AT-421).
/// OPEN depth shortfall within the slippage budget rejects with
/// InsufficientDepthWithinBudget (AT-222).
pub(crate) fn evaluate_liquidity_gate_with_events<E: EventSink<LiquidityGateEvent>>(
    input: &LiquidityGateInput,
    metrics: &mut LiquidityGateMetrics,
    events: &mut E,
) -> LiquidityGateResult {
    let mut observed = ObservedLiquidityGateEvents {
        metrics,
        inner: events,
    };
    evaluate_liquidity_gate_inner(input, &mut observed)
}

fn evaluate_liquidity_gate_inner<E: EventSink<LiquidityGateEvent>>(
    input: &LiquidityGateInput,
    events: &mut E,
) -> LiquidityGateResult {
    // CANCEL-only intents are always allowed (AT-421)
    if input.intent_class == GateIntentClass::CancelOnly {
        events.emit(LiquidityGateEvent::Allowed);
        return LiquidityGateResult {
            decision: LiquidityGateDecision::Allowed,
            metadata: LiquidityGateMetadata {
                wap: None,
                slippage_bps: None,
                fillable_qty: None,
                allowed_qty: None,
            },
        };
    }

    // Invalid numerics are fail-closed.
    if !input.order_qty.is_finite()
        || input.order_qty <= 0.0
        || !input.max_slippage_bps.is_finite()
        || input.max_slippage_bps < 0.0
    {
        return reject_with_events(
            events,
            LiquidityGateRejectReason::ExpectedSlippageTooHigh,
            None,
            None,
            None,
            None,
        );
    }

    // Check L2 availability and staleness.
    let snapshot = match &input.l2_snapshot {
        None => {
            return reject_with_events(
                events,
                LiquidityGateRejectReason::LiquidityGateNoL2,
                None,
                None,
                None,
                None,
            );
        }
        Some(snap) => {
            // Reject future-dated snapshots and stale snapshots (fail-closed).
            if snap.timestamp_ms > input.now_ms
                || (input.now_ms - snap.timestamp_ms) > input.l2_book_snapshot_max_age_ms
            {
                return reject_with_events(
                    events,
                    LiquidityGateRejectReason::LiquidityGateNoL2,
                    None,
                    None,
                    None,
                    None,
                );
            }
            snap
        }
    };

    // Select correct side of book.
    let levels = if input.is_buy {
        &snapshot.asks
    } else {
        &snapshot.bids
    };

    if levels.is_empty() {
        return reject_with_events(
            events,
            LiquidityGateRejectReason::LiquidityGateNoL2,
            None,
            None,
            None,
            None,
        );
    }

    // Best price is the first level.
    let best_price = levels[0].price;
    if !best_price.is_finite() || best_price <= 0.0 {
        return reject_with_events(
            events,
            LiquidityGateRejectReason::LiquidityGateNoL2,
            None,
            None,
            None,
            None,
        );
    }

    let fillable_qty =
        match compute_fillable_depth(levels, input.is_buy, best_price, input.max_slippage_bps) {
            Ok(values) => values,
            Err(FillableDepthError::InvalidBook) => {
                return reject_with_events(
                    events,
                    LiquidityGateRejectReason::LiquidityGateNoL2,
                    None,
                    None,
                    None,
                    None,
                );
            }
            Err(FillableDepthError::NoDepthWithinBudget) => {
                let (wap, slippage_bps) =
                    compute_reject_diagnostics(levels, input.order_qty, best_price);
                if slippage_bps.is_some() {
                    events.emit(LiquidityGateEvent::ExpectedSlippageSample);
                }
                let reject_reason = match input.intent_class {
                    GateIntentClass::Open => {
                        LiquidityGateRejectReason::InsufficientDepthWithinBudget
                    }
                    GateIntentClass::Close | GateIntentClass::Hedge => {
                        LiquidityGateRejectReason::ExpectedSlippageTooHigh
                    }
                    GateIntentClass::CancelOnly => unreachable!("handled above"),
                };
                return reject_with_events(
                    events,
                    reject_reason,
                    wap,
                    slippage_bps,
                    Some(0.0),
                    None,
                );
            }
        };

    let allowed_qty = match input.intent_class {
        GateIntentClass::Open => {
            if fillable_qty + 1e-12 < input.order_qty {
                let (wap, slippage_bps) =
                    compute_reject_diagnostics(levels, input.order_qty, best_price);
                if slippage_bps.is_some() {
                    events.emit(LiquidityGateEvent::ExpectedSlippageSample);
                }
                return reject_with_events(
                    events,
                    LiquidityGateRejectReason::InsufficientDepthWithinBudget,
                    wap,
                    slippage_bps,
                    Some(fillable_qty),
                    Some(fillable_qty),
                );
            }
            input.order_qty
        }
        GateIntentClass::Close | GateIntentClass::Hedge => {
            let clamped = fillable_qty.min(input.order_qty);
            if clamped <= 0.0 || !clamped.is_finite() {
                return reject_with_events(
                    events,
                    LiquidityGateRejectReason::ExpectedSlippageTooHigh,
                    None,
                    None,
                    Some(fillable_qty),
                    Some(0.0),
                );
            }
            clamped
        }
        GateIntentClass::CancelOnly => unreachable!("handled above"),
    };

    // Compute WAP from the full book for the allowed quantity.
    let (wap, _filled) = match compute_wap(levels, allowed_qty) {
        Some(result) => result,
        None => {
            return reject_with_events(
                events,
                LiquidityGateRejectReason::LiquidityGateNoL2,
                None,
                None,
                None,
                None,
            );
        }
    };

    // Compute slippage: (WAP - BestPrice) / BestPrice * 10_000
    // For buys: WAP >= BestPrice (walking up asks)
    // For sells: BestPrice >= WAP (walking down bids)
    let slippage_bps = ((wap - best_price) / best_price * 10_000.0).abs();
    if !slippage_bps.is_finite() {
        return reject_with_events(
            events,
            LiquidityGateRejectReason::ExpectedSlippageTooHigh,
            Some(wap),
            None,
            Some(fillable_qty),
            Some(allowed_qty),
        );
    }
    events.emit(LiquidityGateEvent::ExpectedSlippageSample);

    // Reject if slippage exceeds max.
    if slippage_bps > input.max_slippage_bps {
        let reject_reason = if input.intent_class == GateIntentClass::Open {
            LiquidityGateRejectReason::InsufficientDepthWithinBudget
        } else {
            LiquidityGateRejectReason::ExpectedSlippageTooHigh
        };
        return reject_with_events(
            events,
            reject_reason,
            Some(wap),
            Some(slippage_bps),
            Some(fillable_qty),
            Some(allowed_qty),
        );
    }

    events.emit(LiquidityGateEvent::Allowed);
    LiquidityGateResult {
        decision: LiquidityGateDecision::Allowed,
        metadata: LiquidityGateMetadata {
            wap: Some(wap),
            slippage_bps: Some(slippage_bps),
            fillable_qty: Some(fillable_qty),
            allowed_qty: Some(allowed_qty),
        },
    }
}

pub(crate) fn evaluate_liquidity_gate(
    input: &LiquidityGateInput,
    metrics: &mut LiquidityGateMetrics,
) -> LiquidityGateResult {
    let mut events = ProductionLiquidityGateEvents::default();
    let result = evaluate_liquidity_gate_with_events(input, metrics, &mut events);

    if events.saw_expected_slippage_sample
        && let Some(slippage_bps) = result.metadata.slippage_bps
    {
        record_expected_slippage_sample(slippage_bps);
    }

    if let LiquidityGateDecision::Rejected { reason } = result.decision {
        debug_assert_eq!(events.reject_reason, Some(reason));
        bump_liquidity_gate_reject(reason, result.metadata.wap, result.metadata.slippage_bps);
    }

    result
}

#[cfg(test)]
#[path = "gate_tests.rs"]
mod gate_tests;

#[cfg(test)]
#[path = "gate_prop_liquidity_tests.rs"]
mod gate_prop_liquidity_tests;
