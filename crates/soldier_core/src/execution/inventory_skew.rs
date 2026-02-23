//! Inventory Skew gate per CONTRACT.md §1.4.2.
//!
//! This gate biases pricing/edge requirements based on current inventory:
//! - risk-increasing side: tighten `min_edge_usd` and move limit price away
//! - risk-reducing side: loosen `min_edge_usd` and move limit price toward touch
//!
//! Missing `delta_limit` is fail-closed.

use std::sync::atomic::{AtomicU64, Ordering};

use super::quantize::Side;

/// Inventory Skew input.
#[derive(Debug, Clone)]
pub struct InventorySkewInput {
    /// Current realized delta.
    pub current_delta: f64,
    /// Pending (reserved) delta from in-flight intents.
    pub pending_delta: f64,
    /// Absolute delta limit from policy/config. Missing => fail-closed.
    pub delta_limit: Option<f64>,
    /// Order side.
    pub side: Side,
    /// Baseline minimum edge (USD).
    pub min_edge_usd: f64,
    /// Net edge (USD) from upstream net-edge computation.
    pub net_edge_usd: f64,
    /// Candidate limit price prior to inventory skew adjustment.
    pub limit_price: f64,
    /// Tick size for price shifts.
    pub tick_size: f64,
    /// Multiplier for edge tightening/loosening (contract default 0.5).
    pub inventory_skew_k: f64,
    /// Maximum tick penalty (contract default 3).
    pub inventory_skew_tick_penalty_max: u8,
}

/// Rejection reasons for inventory skew.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InventorySkewRejectReason {
    /// Missing or invalid `delta_limit`.
    InventorySkewDeltaLimitMissing,
    /// Adjusted constraints still not satisfied.
    InventorySkewReject,
}

/// Inventory Skew evaluation result.
#[derive(Debug, Clone, PartialEq)]
pub enum InventorySkewResult {
    Allowed {
        inventory_bias: f64,
        bias_ticks: u8,
        adjusted_min_edge_usd: f64,
        adjusted_limit_price: f64,
    },
    Rejected {
        reason: InventorySkewRejectReason,
        inventory_bias: Option<f64>,
        bias_ticks: Option<u8>,
        adjusted_min_edge_usd: Option<f64>,
        adjusted_limit_price: Option<f64>,
    },
}

/// Observability counters for inventory skew decisions.
#[derive(Debug, Default)]
pub struct InventorySkewMetrics {
    reject_total: u64,
    reject_delta_limit_missing: u64,
    allowed_total: u64,
}

impl InventorySkewMetrics {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }

    pub fn reject_delta_limit_missing(&self) -> u64 {
        self.reject_delta_limit_missing
    }

    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }

    fn record_reject(&mut self) {
        self.reject_total += 1;
    }

    /// Record a delta-limit-missing rejection.
    /// Increments both `reject_total` (superset) and `reject_delta_limit_missing` (subset).
    fn record_reject_delta_limit_missing(&mut self) {
        self.reject_total += 1;
        self.reject_delta_limit_missing += 1;
    }

    fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }
}

static INVENTORY_SKEW_REJECT_DELTA_LIMIT_MISSING_TOTAL: AtomicU64 = AtomicU64::new(0);
static INVENTORY_SKEW_REJECT_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Process-lifetime rejection counter for inventory skew gate.
///
/// Use for production monitoring and multi-hour root cause analysis.
/// Compare with instance `InventorySkewMetrics` for tick-level debugging.
pub fn inventory_skew_reject_total(reason: InventorySkewRejectReason) -> u64 {
    match reason {
        InventorySkewRejectReason::InventorySkewDeltaLimitMissing => {
            INVENTORY_SKEW_REJECT_DELTA_LIMIT_MISSING_TOTAL.load(Ordering::Relaxed)
        }
        InventorySkewRejectReason::InventorySkewReject => {
            INVENTORY_SKEW_REJECT_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_inventory_skew_reject(reason: InventorySkewRejectReason) {
    match reason {
        InventorySkewRejectReason::InventorySkewDeltaLimitMissing => {
            INVENTORY_SKEW_REJECT_DELTA_LIMIT_MISSING_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        InventorySkewRejectReason::InventorySkewReject => {
            INVENTORY_SKEW_REJECT_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    super::emit_execution_metric_line(super::METRIC_INVENTORY_SKEW_REJECT, &tail);
    tracing::debug!("InventorySkewReject reason={:?}", reason);
}

/// Clamp inventory bias to [-1.0, 1.0].
///
/// This is intentional normalization, NOT a hard limit. When `combined_delta`
/// exceeds `delta_limit`, the bias saturates at ±1.0 (maximum penalty) but
/// does not reject the order outright. Hard position limits are enforced by
/// separate gates (pending exposure budget S6-008, global exposure budget S6-009).
fn clamp_bias(v: f64) -> f64 {
    v.clamp(-1.0, 1.0)
}

/// Evaluate inventory skew adjustments and eligibility.
///
/// This is a pure function — it operates on the snapshot values provided by the
/// caller. Freshness of `current_delta` and `pending_delta` is the caller's
/// responsibility; the runtime wiring (`build_open_order_intent_runtime`) reads
/// these from the pending exposure book under `&mut` exclusivity.
///
/// Contract mapping:
/// - AT-043/AT-922: missing `delta_limit` => reject fail-closed
/// - AT-030: `bias=1.0` + `max_ticks=3` => exactly 3 tick penalty
pub fn evaluate_inventory_skew(
    input: &InventorySkewInput,
    metrics: &mut InventorySkewMetrics,
) -> InventorySkewResult {
    let delta_limit = match input.delta_limit {
        Some(v) if v.is_finite() && v > 0.0 => v,
        _ => {
            metrics.record_reject_delta_limit_missing();
            bump_inventory_skew_reject(InventorySkewRejectReason::InventorySkewDeltaLimitMissing);
            return InventorySkewResult::Rejected {
                reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
                inventory_bias: None,
                bias_ticks: None,
                adjusted_min_edge_usd: None,
                adjusted_limit_price: None,
            };
        }
    };

    if !input.current_delta.is_finite()
        || !input.pending_delta.is_finite()
        || !input.min_edge_usd.is_finite()
        || !input.net_edge_usd.is_finite()
        || !input.limit_price.is_finite()
        || !input.tick_size.is_finite()
        || !input.inventory_skew_k.is_finite()
        || input.tick_size <= 0.0
        || input.min_edge_usd < 0.0
        || input.inventory_skew_k < 0.0
    {
        metrics.record_reject();
        bump_inventory_skew_reject(InventorySkewRejectReason::InventorySkewReject);
        return InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewReject,
            inventory_bias: None,
            bias_ticks: None,
            adjusted_min_edge_usd: None,
            adjusted_limit_price: None,
        };
    }

    let combined_delta = input.current_delta + input.pending_delta;
    let inventory_bias = clamp_bias(combined_delta / delta_limit);
    let abs_bias = inventory_bias.abs();

    let risk_increasing = match input.side {
        Side::Buy => inventory_bias > 0.0,
        Side::Sell => inventory_bias < 0.0,
    };

    let adjusted_min_edge_usd = if risk_increasing {
        input.min_edge_usd * (1.0 + input.inventory_skew_k * abs_bias)
    } else {
        (input.min_edge_usd * (1.0 - input.inventory_skew_k * abs_bias)).max(0.0)
    };

    let raw_ticks = (abs_bias * f64::from(input.inventory_skew_tick_penalty_max)).ceil();
    // SAFETY: abs_bias is clamped to [0.0, 1.0] and tick_penalty_max is u8 (max 255),
    // so raw_ticks is in [0.0, 255.0] — always fits in u8 without truncation.
    // Edge case: degenerate delta_limit (e.g., 1e-300) can produce NaN through
    // clamp_bias → NaN.abs() → (NaN * max).ceil() → NaN. Rust's saturating
    // float-to-int cast converts NaN to 0u8, yielding zero tick penalty (safe).
    let bias_ticks = raw_ticks as u8;
    let price_shift = f64::from(bias_ticks) * input.tick_size;
    let adjusted_limit_price = match (input.side, risk_increasing) {
        (Side::Buy, true) => input.limit_price - price_shift,
        (Side::Buy, false) => input.limit_price + price_shift,
        (Side::Sell, true) => input.limit_price + price_shift,
        (Side::Sell, false) => input.limit_price - price_shift,
    };

    if input.net_edge_usd < adjusted_min_edge_usd {
        metrics.record_reject();
        bump_inventory_skew_reject(InventorySkewRejectReason::InventorySkewReject);
        return InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewReject,
            inventory_bias: Some(inventory_bias),
            bias_ticks: Some(bias_ticks),
            adjusted_min_edge_usd: Some(adjusted_min_edge_usd),
            adjusted_limit_price: Some(adjusted_limit_price),
        };
    }

    metrics.record_allowed();
    InventorySkewResult::Allowed {
        inventory_bias,
        bias_ticks,
        adjusted_min_edge_usd,
        adjusted_limit_price,
    }
}
