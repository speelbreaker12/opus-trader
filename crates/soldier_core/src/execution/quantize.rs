//! Canonical quantization per CONTRACT.md §1.1.1.
//!
//! All idempotency keys and order payloads MUST use canonical,
//! exchange-valid rounded values. Quantization is deterministic
//! and rounds in the "safer" direction.
//!
//! - `qty_q = floor(raw_qty / amount_step) * amount_step` (never round up size)
//! - BUY: `limit_price_q = floor(raw_limit_price / tick_size) * tick_size`
//! - SELL: `limit_price_q = ceil(raw_limit_price / tick_size) * tick_size`
//! - If `qty_q < min_amount` → Reject(TooSmallAfterQuantization)

/// Order side — determines price rounding direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Side {
    Buy,
    Sell,
}

/// Instrument constraints required for quantization.
///
/// CONTRACT.md: these MUST come from fetched instrument metadata,
/// never hardcoded.
#[derive(Debug, Clone)]
pub struct QuantizeConstraints {
    /// Minimum price increment.
    pub tick_size: f64,
    /// Minimum quantity increment.
    pub amount_step: f64,
    /// Minimum order quantity.
    pub min_amount: f64,
}

/// Result of successful quantization.
///
/// Contains both the quantized float values and their integer
/// tick/step counts for deterministic idempotency hashing.
#[derive(Debug, Clone, PartialEq)]
pub struct QuantizedValues {
    /// Quantized quantity: `qty_steps * amount_step`.
    pub qty_q: f64,
    /// Integer number of amount steps: `floor(raw_qty / amount_step)`.
    pub qty_steps: i64,
    /// Quantized limit price: `price_ticks * tick_size`.
    pub limit_price_q: f64,
    /// Integer number of ticks (direction-dependent).
    pub price_ticks: i64,
}

/// Error returned when quantization fails.
#[derive(Debug, Clone, PartialEq)]
pub enum QuantizeError {
    /// CONTRACT.md AT-908: `qty_q < min_amount` after quantization.
    TooSmallAfterQuantization {
        /// The quantized quantity that was too small.
        qty_q: f64,
        /// The minimum required amount.
        min_amount: f64,
    },
    /// CONTRACT.md AT-926: instrument metadata missing or unparseable.
    InstrumentMetadataMissing {
        /// Which field is invalid.
        field: &'static str,
    },
    /// Raw input is non-finite and cannot be safely quantized.
    InvalidInput {
        /// Which field is invalid.
        field: &'static str,
    },
}

const BOUNDARY_EPS: f64 = 1e-9;
const BOUNDARY_STEP_FRACTION_CAP: f64 = 0.005;
const BOUNDARY_ULP_MULTIPLIER: f64 = 8.0;

fn boundary_tolerance(raw: f64, step: f64) -> f64 {
    // Correct one-step drift caused by floating-point division, but keep the
    // correction well below half a step so directional floor/ceil semantics hold.
    let step_abs = step.abs();
    let ulp_scaled = raw.abs().max(1.0) * f64::EPSILON * BOUNDARY_ULP_MULTIPLIER;
    let step_capped = step_abs * BOUNDARY_STEP_FRACTION_CAP;
    ulp_scaled.min(step_capped).max(step_abs * BOUNDARY_EPS)
}

fn quantize_ratio_to_i64(raw: f64, step: f64, round_up: bool) -> i64 {
    let ratio = raw / step;
    let mut steps = if round_up {
        ratio.ceil() as i64
    } else {
        ratio.floor() as i64
    };
    let tol = boundary_tolerance(raw, step);

    if round_up {
        if steps > i64::MIN {
            let prev = steps - 1;
            let prev_value = prev as f64 * step;
            if (raw - prev_value).abs() <= tol {
                steps = prev;
            }
        }
    } else if steps < i64::MAX {
        let next = steps + 1;
        let next_value = next as f64 * step;
        if (raw - next_value).abs() <= tol {
            steps = next;
        }
    }

    steps
}

/// Observability metrics for quantization (AT-908).
#[derive(Debug)]
pub struct QuantizeMetrics {
    /// `quantization_reject_too_small_total` counter.
    reject_too_small_total: u64,
}

impl QuantizeMetrics {
    /// Create a new metrics tracker with all counters at zero.
    pub fn new() -> Self {
        Self {
            reject_too_small_total: 0,
        }
    }

    /// Increment the too-small rejection counter.
    pub fn record_too_small_rejection(&mut self) {
        self.reject_too_small_total += 1;
    }

    /// Current value of `quantization_reject_too_small_total`.
    pub fn reject_too_small_total(&self) -> u64 {
        self.reject_too_small_total
    }
}

impl Default for QuantizeMetrics {
    fn default() -> Self {
        Self::new()
    }
}

/// Validate that quantization constraints are usable.
///
/// CONTRACT.md AT-926: missing/unparseable metadata → reject.
fn validate_constraints(constraints: &QuantizeConstraints) -> Result<(), QuantizeError> {
    if !constraints.tick_size.is_finite() || constraints.tick_size <= 0.0 {
        return Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" });
    }
    if !constraints.amount_step.is_finite() || constraints.amount_step <= 0.0 {
        return Err(QuantizeError::InstrumentMetadataMissing {
            field: "amount_step",
        });
    }
    if !constraints.min_amount.is_finite() || constraints.min_amount < 0.0 {
        return Err(QuantizeError::InstrumentMetadataMissing {
            field: "min_amount",
        });
    }
    Ok(())
}

/// Quantize raw order values per CONTRACT.md §1.1.1.
///
/// # Rules (deterministic)
/// - `qty_steps = floor(raw_qty / amount_step)`
/// - `qty_q = qty_steps * amount_step`
/// - BUY: `price_ticks = floor(raw_limit_price / tick_size)` (never pay extra)
/// - SELL: `price_ticks = ceil(raw_limit_price / tick_size)` (never sell cheaper)
/// - `limit_price_q = price_ticks * tick_size`
/// - If `qty_q < min_amount` → `Err(TooSmallAfterQuantization)`
pub fn quantize(
    raw_qty: f64,
    raw_limit_price: f64,
    side: Side,
    constraints: &QuantizeConstraints,
    metrics: &mut QuantizeMetrics,
) -> Result<QuantizedValues, QuantizeError> {
    validate_constraints(constraints)?;
    if !raw_qty.is_finite() {
        return Err(QuantizeError::InvalidInput { field: "raw_qty" });
    }
    if !raw_limit_price.is_finite() {
        return Err(QuantizeError::InvalidInput {
            field: "raw_limit_price",
        });
    }

    // Quantity: always round down (never round up size)
    let qty_steps = quantize_ratio_to_i64(raw_qty, constraints.amount_step, false);
    let qty_q = qty_steps as f64 * constraints.amount_step;

    // AT-908: reject if quantized quantity is below minimum
    if qty_q < constraints.min_amount {
        metrics.record_too_small_rejection();
        return Err(QuantizeError::TooSmallAfterQuantization {
            qty_q,
            min_amount: constraints.min_amount,
        });
    }

    // Price: direction-dependent rounding
    let price_ticks = match side {
        // BUY: round down (never pay extra)
        Side::Buy => quantize_ratio_to_i64(raw_limit_price, constraints.tick_size, false),
        // SELL: round up (never sell cheaper)
        Side::Sell => quantize_ratio_to_i64(raw_limit_price, constraints.tick_size, true),
    };
    let limit_price_q = price_ticks as f64 * constraints.tick_size;

    Ok(QuantizedValues {
        qty_q,
        qty_steps,
        limit_price_q,
        price_ticks,
    })
}
