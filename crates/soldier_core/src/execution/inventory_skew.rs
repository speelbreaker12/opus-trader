//! Inventory Skew gate per CONTRACT.md §1.4.2.
//!
//! This gate biases pricing/edge requirements based on current inventory:
//! - risk-increasing side: tighten `min_edge_usd` and move limit price away
//! - risk-reducing side: loosen `min_edge_usd` and move limit price toward touch
//!
//! Missing `delta_limit` is fail-closed.

/// Side under evaluation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InventorySkewSide {
    Buy,
    Sell,
}

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
    pub side: InventorySkewSide,
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

    fn record_reject_delta_limit_missing(&mut self) {
        self.reject_total += 1;
        self.reject_delta_limit_missing += 1;
    }

    fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }
}

fn clamp_bias(v: f64) -> f64 {
    v.clamp(-1.0, 1.0)
}

/// Evaluate inventory skew adjustments and eligibility.
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

    // Risk-increasing side tightens thresholds; risk-reducing side can loosen them.
    let risk_increasing = match input.side {
        InventorySkewSide::Buy => inventory_bias > 0.0,
        InventorySkewSide::Sell => inventory_bias < 0.0,
    };

    let adjusted_min_edge_usd = if risk_increasing {
        input.min_edge_usd * (1.0 + input.inventory_skew_k * abs_bias)
    } else {
        (input.min_edge_usd * (1.0 - input.inventory_skew_k * abs_bias)).max(0.0)
    };

    let raw_ticks = (abs_bias * f64::from(input.inventory_skew_tick_penalty_max)).ceil();
    let clamped_ticks = raw_ticks.clamp(0.0, f64::from(u8::MAX));
    let bias_ticks = clamped_ticks as u8;
    let price_shift = f64::from(bias_ticks) * input.tick_size;
    let adjusted_limit_price = match (input.side, risk_increasing) {
        (InventorySkewSide::Buy, true) => input.limit_price - price_shift,
        (InventorySkewSide::Buy, false) => input.limit_price + price_shift,
        (InventorySkewSide::Sell, true) => input.limit_price + price_shift,
        (InventorySkewSide::Sell, false) => input.limit_price - price_shift,
    };

    // Fail-closed if price_shift or adjusted_limit_price overflowed to a non-finite value.
    if !price_shift.is_finite() || !adjusted_limit_price.is_finite() {
        metrics.record_reject();
        return InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewReject,
            inventory_bias: Some(inventory_bias),
            bias_ticks: Some(bias_ticks),
            adjusted_min_edge_usd: Some(adjusted_min_edge_usd),
            adjusted_limit_price: Some(adjusted_limit_price),
        };
    }

    if input.net_edge_usd < adjusted_min_edge_usd {
        metrics.record_reject();
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
