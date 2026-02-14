//! Order-type preflight guard per CONTRACT.md §1.4.4.
//!
//! Centralizes all order-type validation BEFORE any API dispatch.
//! Violations are hard rejects — the engine never "tries anyway."
//!
//! AT-013, AT-016, AT-017, AT-018, AT-019, AT-913, AT-914, AT-915, AT-916.

use std::sync::atomic::{AtomicU64, Ordering};

use super::post_only_guard::{PostOnlyInput, PostOnlyMetrics, PostOnlyResult, check_post_only};
use crate::venue::InstrumentKind;

// ─── Rejection reasons ──────────────────────────────────────────────────

/// Deterministic rejection reason from the preflight guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreflightReject {
    /// `type == market` is forbidden for all instrument kinds.
    /// CONTRACT.md §1.4.4 A/B: "REJECT with Rejected(OrderTypeMarketForbidden)"
    OrderTypeMarketForbidden,

    /// `type in {stop_market, stop_limit}` or trigger fields present.
    /// CONTRACT.md §1.4.4 A/B: "REJECT with Rejected(OrderTypeStopForbidden)"
    OrderTypeStopForbidden,

    /// `linked_order_type` is non-null while linked orders are unsupported.
    /// CONTRACT.md §1.4.4 A/B: "REJECT with Rejected(LinkedOrderTypeForbidden)"
    LinkedOrderTypeForbidden,

    /// `post_only == true` while the limit price would cross the touch.
    /// CONTRACT.md §1.4.4 C: "REJECT with Rejected(PostOnlyWouldCross)"
    PostOnlyWouldCross,
}

// ─── Order type enum ────────────────────────────────────────────────────

/// Order type as submitted by the strategy intent.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OrderType {
    Limit,
    Market,
    StopMarket,
    StopLimit,
}

// ─── Preflight input ────────────────────────────────────────────────────

/// All fields needed by the preflight guard to make a decision.
#[derive(Debug, Clone)]
pub struct PreflightInput<'a> {
    /// The instrument kind (option, perpetual, etc.)
    pub instrument_kind: InstrumentKind,
    /// The order type requested.
    pub order_type: OrderType,
    /// Whether trigger fields are present (trigger price, trigger type, etc.)
    pub has_trigger: bool,
    /// The linked_order_type field, if set.
    pub linked_order_type: Option<&'a str>,
    /// Evaluated capabilities policy for linked orders.
    ///
    /// This MUST come from the capabilities matrix evaluation:
    /// `linked_orders_allowed = venue_capability && feature_flag`.
    pub linked_orders_allowed: bool,
    /// Optional post-only context used for crossing checks (AT-916).
    pub post_only_input: Option<PostOnlyInput>,
}

// ─── Preflight result ───────────────────────────────────────────────────

/// Result of the preflight check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PreflightResult {
    /// Intent passes preflight — proceed to dispatch.
    Allowed,
    /// Intent rejected — do NOT dispatch.
    Rejected(PreflightReject),
}

// ─── Metrics ────────────────────────────────────────────────────────────

/// Observability metrics for the preflight guard.
#[derive(Debug)]
pub struct PreflightMetrics {
    /// `preflight_reject_total{reason=market_forbidden}` counter.
    market_forbidden_total: u64,
    /// `preflight_reject_total{reason=stop_forbidden}` counter.
    stop_forbidden_total: u64,
    /// `preflight_reject_total{reason=linked_forbidden}` counter.
    linked_forbidden_total: u64,
    /// `preflight_reject_total{reason=post_only_would_cross}` counter.
    post_only_would_cross_total: u64,
}

impl PreflightMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            market_forbidden_total: 0,
            stop_forbidden_total: 0,
            linked_forbidden_total: 0,
            post_only_would_cross_total: 0,
        }
    }

    /// Record a rejection, incrementing the appropriate counter.
    pub fn record_reject(&mut self, reason: &PreflightReject) {
        match reason {
            PreflightReject::OrderTypeMarketForbidden => self.market_forbidden_total += 1,
            PreflightReject::OrderTypeStopForbidden => self.stop_forbidden_total += 1,
            PreflightReject::LinkedOrderTypeForbidden => self.linked_forbidden_total += 1,
            PreflightReject::PostOnlyWouldCross => self.post_only_would_cross_total += 1,
        }
    }

    /// Total rejections across all reasons.
    pub fn reject_total(&self) -> u64 {
        self.market_forbidden_total
            + self.stop_forbidden_total
            + self.linked_forbidden_total
            + self.post_only_would_cross_total
    }

    /// Counter for market-forbidden rejections.
    pub fn market_forbidden_total(&self) -> u64 {
        self.market_forbidden_total
    }

    /// Counter for stop-forbidden rejections.
    pub fn stop_forbidden_total(&self) -> u64 {
        self.stop_forbidden_total
    }

    /// Counter for linked-forbidden rejections.
    pub fn linked_forbidden_total(&self) -> u64 {
        self.linked_forbidden_total
    }

    /// Counter for post-only-crossing rejections.
    pub fn post_only_would_cross_total(&self) -> u64 {
        self.post_only_would_cross_total
    }
}

impl Default for PreflightMetrics {
    fn default() -> Self {
        Self::new()
    }
}

static PREFLIGHT_MARKET_FORBIDDEN_TOTAL: AtomicU64 = AtomicU64::new(0);
static PREFLIGHT_STOP_FORBIDDEN_TOTAL: AtomicU64 = AtomicU64::new(0);
static PREFLIGHT_LINKED_FORBIDDEN_TOTAL: AtomicU64 = AtomicU64::new(0);
static PREFLIGHT_POST_ONLY_WOULD_CROSS_TOTAL: AtomicU64 = AtomicU64::new(0);

pub fn preflight_reject_total(reason: PreflightReject) -> u64 {
    match reason {
        PreflightReject::OrderTypeMarketForbidden => {
            PREFLIGHT_MARKET_FORBIDDEN_TOTAL.load(Ordering::Relaxed)
        }
        PreflightReject::OrderTypeStopForbidden => {
            PREFLIGHT_STOP_FORBIDDEN_TOTAL.load(Ordering::Relaxed)
        }
        PreflightReject::LinkedOrderTypeForbidden => {
            PREFLIGHT_LINKED_FORBIDDEN_TOTAL.load(Ordering::Relaxed)
        }
        PreflightReject::PostOnlyWouldCross => {
            PREFLIGHT_POST_ONLY_WOULD_CROSS_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_preflight_reject(reason: PreflightReject) {
    match reason {
        PreflightReject::OrderTypeMarketForbidden => {
            PREFLIGHT_MARKET_FORBIDDEN_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        PreflightReject::OrderTypeStopForbidden => {
            PREFLIGHT_STOP_FORBIDDEN_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        PreflightReject::LinkedOrderTypeForbidden => {
            PREFLIGHT_LINKED_FORBIDDEN_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        PreflightReject::PostOnlyWouldCross => {
            PREFLIGHT_POST_ONLY_WOULD_CROSS_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line("preflight_reject_total", &tail);
}

// ─── Core preflight function ────────────────────────────────────────────

/// Run the order-type preflight guard per CONTRACT.md §1.4.4.
///
/// This is the single entrypoint that MUST be called before any API dispatch.
/// It checks order type, stop/trigger presence, and linked order gating.
///
/// Returns `Allowed` if the intent passes, or `Rejected(reason)` if it must
/// be blocked.
pub fn preflight_intent(
    input: &PreflightInput<'_>,
    metrics: &mut PreflightMetrics,
) -> PreflightResult {
    // Rule 1: Market orders forbidden for ALL instrument kinds.
    // CONTRACT.md §1.4.4 A: "If type == market → REJECT"
    // CONTRACT.md §1.4.4 B: "If type == market → REJECT"
    if input.order_type == OrderType::Market {
        let reason = PreflightReject::OrderTypeMarketForbidden;
        metrics.record_reject(&reason);
        bump_preflight_reject(reason);
        return PreflightResult::Rejected(reason);
    }

    // Rule 2: Stop orders forbidden for ALL instrument kinds.
    // CONTRACT.md §1.4.4 A: "Reject any type in {stop_market, stop_limit}
    //   or any presence of trigger / trigger_price"
    // CONTRACT.md §1.4.4 B: Same rule.
    if matches!(
        input.order_type,
        OrderType::StopMarket | OrderType::StopLimit
    ) || input.has_trigger
    {
        let reason = PreflightReject::OrderTypeStopForbidden;
        metrics.record_reject(&reason);
        bump_preflight_reject(reason);
        return PreflightResult::Rejected(reason);
    }

    // Rule 3: Linked/OCO orders forbidden unless capability matrix allows them.
    // CONTRACT.md §1.4.4 A: "Reject any non-null linked_order_type"
    // CONTRACT.md §1.4.4 B: "Reject ... unless linked_orders_supported == true
    //   AND ENABLE_LINKED_ORDERS_FOR_BOT == true"
    if input.linked_order_type.is_some() {
        let allowed = match input.instrument_kind {
            // Options: always forbidden (§1.4.4 A)
            InstrumentKind::Option => false,
            // Futures/Perps: allowed only when capabilities matrix says true.
            InstrumentKind::LinearFuture
            | InstrumentKind::InverseFuture
            | InstrumentKind::Perpetual => input.linked_orders_allowed,
        };
        if !allowed {
            let reason = PreflightReject::LinkedOrderTypeForbidden;
            metrics.record_reject(&reason);
            bump_preflight_reject(reason);
            return PreflightResult::Rejected(reason);
        }
    }

    // Rule 4: post_only orders must not cross the touch (AT-916).
    if let Some(post_only_input) = input.post_only_input.as_ref() {
        let mut post_only_metrics = PostOnlyMetrics::new();
        if matches!(
            check_post_only(post_only_input, &mut post_only_metrics),
            PostOnlyResult::Rejected
        ) {
            let reason = PreflightReject::PostOnlyWouldCross;
            metrics.record_reject(&reason);
            bump_preflight_reject(reason);
            return PreflightResult::Rejected(reason);
        }
    }

    PreflightResult::Allowed
}
