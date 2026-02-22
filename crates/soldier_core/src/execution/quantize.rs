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

use std::sync::atomic::{AtomicU64, Ordering};

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
// Keep correction well below half-step to preserve directional guarantees:
// qty/BUY must never round up and SELL must never round down.
const BOUNDARY_STEP_FRACTION_CAP: f64 = 0.005;
const BOUNDARY_ULP_MULTIPLIER: f64 = 8.0;

fn boundary_tolerance(raw: f64, step: f64) -> f64 {
    // Correct one-step drift caused by floating-point division while fail-closing:
    // if drift exceeds this window, we keep strict floor/ceil behavior instead of
    // widening snap tolerance and risking direction violations.
    let step_abs = step.abs();
    let ulp_scaled = raw.abs().max(1.0) * f64::EPSILON * BOUNDARY_ULP_MULTIPLIER;
    let step_capped = step_abs * BOUNDARY_STEP_FRACTION_CAP;
    ulp_scaled.min(step_capped).max(step_abs * BOUNDARY_EPS)
}

fn quantize_ratio_to_i64(raw: f64, step: f64, round_up: bool) -> Result<i64, QuantizeError> {
    let ratio = raw / step;
    // Guard: NaN, ±Infinity from division
    if !ratio.is_finite() {
        return Err(QuantizeError::InvalidInput { field: "ratio" });
    }
    // Guard: i64 overflow before cast
    if ratio.abs() > (i64::MAX as f64) {
        return Err(QuantizeError::InvalidInput {
            field: "ratio_overflow",
        });
    }
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
            if (raw - prev_value).abs() < tol {
                steps = prev;
            }
        }
    } else if steps < i64::MAX {
        let next = steps + 1;
        let next_value = next as f64 * step;
        if (raw - next_value).abs() < tol {
            steps = next;
        }
    }

    Ok(steps)
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

// ─── Static counters (Layer 1) ──────────────────────────────────────────

static QUANTIZE_REJECT_TOO_SMALL_TOTAL: AtomicU64 = AtomicU64::new(0);
static QUANTIZE_REJECT_METADATA_MISSING_TOTAL: AtomicU64 = AtomicU64::new(0);
static QUANTIZE_REJECT_INVALID_INPUT_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Read the static quantize rejection counter for a given error variant.
pub fn quantize_reject_total(error: &QuantizeError) -> u64 {
    match error {
        QuantizeError::TooSmallAfterQuantization { .. } => {
            QUANTIZE_REJECT_TOO_SMALL_TOTAL.load(Ordering::Relaxed)
        }
        QuantizeError::InstrumentMetadataMissing { .. } => {
            QUANTIZE_REJECT_METADATA_MISSING_TOTAL.load(Ordering::Relaxed)
        }
        QuantizeError::InvalidInput { .. } => {
            QUANTIZE_REJECT_INVALID_INPUT_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_quantize_reject(error: &QuantizeError) {
    match error {
        QuantizeError::TooSmallAfterQuantization { .. } => {
            QUANTIZE_REJECT_TOO_SMALL_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        QuantizeError::InstrumentMetadataMissing { .. } => {
            QUANTIZE_REJECT_METADATA_MISSING_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        QuantizeError::InvalidInput { .. } => {
            QUANTIZE_REJECT_INVALID_INPUT_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("error={error:?}");
    super::emit_execution_metric_line(super::METRIC_QUANTIZE_REJECT, &tail);
    tracing::debug!("QuantizeReject error={:?}", error);
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
    if let Err(e) = validate_constraints(constraints) {
        bump_quantize_reject(&e);
        return Err(e);
    }
    if !raw_qty.is_finite() {
        let e = QuantizeError::InvalidInput { field: "raw_qty" };
        bump_quantize_reject(&e);
        return Err(e);
    }
    if !raw_limit_price.is_finite() {
        let e = QuantizeError::InvalidInput {
            field: "raw_limit_price",
        };
        bump_quantize_reject(&e);
        return Err(e);
    }
    if raw_qty < 0.0 {
        let e = QuantizeError::InvalidInput { field: "raw_qty" };
        bump_quantize_reject(&e);
        return Err(e);
    }

    // Quantity: always round down (never round up size)
    let qty_steps = match quantize_ratio_to_i64(raw_qty, constraints.amount_step, false) {
        Ok(v) => v,
        Err(e) => {
            bump_quantize_reject(&e);
            return Err(e);
        }
    };
    let qty_q = qty_steps as f64 * constraints.amount_step;

    // AT-908: reject if quantized quantity is below minimum
    if qty_q < constraints.min_amount {
        metrics.record_too_small_rejection();
        let e = QuantizeError::TooSmallAfterQuantization {
            qty_q,
            min_amount: constraints.min_amount,
        };
        bump_quantize_reject(&e);
        return Err(e);
    }

    // Price: direction-dependent rounding
    let price_ticks = match side {
        // BUY: round down (never pay extra)
        Side::Buy => quantize_ratio_to_i64(raw_limit_price, constraints.tick_size, false),
        // SELL: round up (never sell cheaper)
        Side::Sell => quantize_ratio_to_i64(raw_limit_price, constraints.tick_size, true),
    }
    .inspect_err(|e| {
        bump_quantize_reject(e);
    })?;
    let limit_price_q = price_ticks as f64 * constraints.tick_size;

    Ok(QuantizedValues {
        qty_q,
        qty_steps,
        limit_price_q,
        price_ticks,
    })
}
