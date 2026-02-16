//! Property-based tests for the quantization module (CONTRACT.md §1.1.1).
//!
//! Properties under test:
//! - Quantized qty is always a multiple of amount_step.
//! - Quantized price is always a multiple of tick_size.
//! - BUY prices round DOWN (never pay extra).
//! - SELL prices round UP (never sell cheaper).
//! - Quantize is idempotent: quantize(quantize(x)) == quantize(x).
//! - Never panics on valid positive constraints.

use proptest::prelude::*;
use soldier_core::execution::{QuantizeConstraints, QuantizeMetrics, Side, quantize};

/// Generate strictly positive f64 values suitable for constraints.
fn positive_f64() -> impl Strategy<Value = f64> {
    // Use range that avoids subnormals and extreme values
    1e-8_f64..1e6
}

/// Generate a raw quantity (positive, finite).
fn raw_qty_strategy() -> impl Strategy<Value = f64> {
    1e-6_f64..1e6
}

/// Generate a raw limit price (positive, finite).
fn raw_price_strategy() -> impl Strategy<Value = f64> {
    1e-4_f64..1e8
}

/// Generate valid quantize constraints.
fn constraints_strategy() -> impl Strategy<Value = QuantizeConstraints> {
    (positive_f64(), positive_f64(), positive_f64()).prop_map(
        |(tick_size, amount_step, min_amount)| QuantizeConstraints {
            tick_size,
            amount_step,
            min_amount,
        },
    )
}

fn side_strategy() -> impl Strategy<Value = Side> {
    prop_oneof![Just(Side::Buy), Just(Side::Sell)]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// Quantized qty is always a non-negative integer multiple of amount_step.
    #[test]
    fn qty_is_multiple_of_amount_step(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        side in side_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut metrics = QuantizeMetrics::new();
        if let Ok(result) = quantize(raw_qty, raw_price, side, &constraints, &mut metrics) {
            // qty_q == qty_steps * amount_step
            let expected = result.qty_steps as f64 * constraints.amount_step;
            let diff = (result.qty_q - expected).abs();
            prop_assert!(
                diff < 1e-10,
                "qty_q={} != qty_steps({}) * amount_step({}), diff={}",
                result.qty_q, result.qty_steps, constraints.amount_step, diff
            );
            prop_assert!(result.qty_steps >= 0, "qty_steps must be non-negative");
        }
    }

    /// Quantized price is always an integer multiple of tick_size.
    #[test]
    fn price_is_multiple_of_tick_size(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        side in side_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut metrics = QuantizeMetrics::new();
        if let Ok(result) = quantize(raw_qty, raw_price, side, &constraints, &mut metrics) {
            let expected = result.price_ticks as f64 * constraints.tick_size;
            let diff = (result.limit_price_q - expected).abs();
            prop_assert!(
                diff < 1e-10,
                "limit_price_q={} != price_ticks({}) * tick_size({}), diff={}",
                result.limit_price_q, result.price_ticks, constraints.tick_size, diff
            );
        }
    }

    /// BUY prices round DOWN: quantized price <= raw price.
    #[test]
    fn buy_price_rounds_down(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut metrics = QuantizeMetrics::new();
        if let Ok(result) = quantize(raw_qty, raw_price, Side::Buy, &constraints, &mut metrics) {
            // Allow tiny floating-point tolerance
            let tolerance = constraints.tick_size * 0.01;
            prop_assert!(
                result.limit_price_q <= raw_price + tolerance,
                "BUY limit_price_q={} > raw_price={} (tolerance={})",
                result.limit_price_q, raw_price, tolerance
            );
        }
    }

    /// SELL prices round UP: quantized price >= raw price.
    #[test]
    fn sell_price_rounds_up(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut metrics = QuantizeMetrics::new();
        if let Ok(result) = quantize(raw_qty, raw_price, Side::Sell, &constraints, &mut metrics) {
            let tolerance = constraints.tick_size * 0.01;
            prop_assert!(
                result.limit_price_q >= raw_price - tolerance,
                "SELL limit_price_q={} < raw_price={} (tolerance={})",
                result.limit_price_q, raw_price, tolerance
            );
        }
    }

    /// Quantize is idempotent: quantize(quantize(x)) == quantize(x).
    #[test]
    fn quantize_is_idempotent(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        side in side_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut m1 = QuantizeMetrics::new();
        let mut m2 = QuantizeMetrics::new();
        if let Ok(first) = quantize(raw_qty, raw_price, side, &constraints, &mut m1)
            && let Ok(second) = quantize(first.qty_q, first.limit_price_q, side, &constraints, &mut m2)
        {
            prop_assert_eq!(
                first.qty_steps, second.qty_steps,
                "qty_steps not idempotent: first={}, second={}",
                first.qty_steps, second.qty_steps
            );
            prop_assert_eq!(
                first.price_ticks, second.price_ticks,
                "price_ticks not idempotent: first={}, second={}",
                first.price_ticks, second.price_ticks
            );
        }
    }

    /// Quantity always rounds DOWN (never rounds up size).
    #[test]
    fn qty_rounds_down(
        raw_qty in raw_qty_strategy(),
        raw_price in raw_price_strategy(),
        side in side_strategy(),
        constraints in constraints_strategy(),
    ) {
        let mut metrics = QuantizeMetrics::new();
        if let Ok(result) = quantize(raw_qty, raw_price, side, &constraints, &mut metrics) {
            let tolerance = constraints.amount_step * 0.01;
            prop_assert!(
                result.qty_q <= raw_qty + tolerance,
                "qty_q={} > raw_qty={} (tolerance={})",
                result.qty_q, raw_qty, tolerance
            );
        }
    }

    /// Quantization never panics on valid positive constraints.
    #[test]
    fn never_panics_on_valid_input(
        raw_qty in prop::num::f64::ANY,
        raw_price in prop::num::f64::ANY,
        side in side_strategy(),
        tick_size in positive_f64(),
        amount_step in positive_f64(),
        min_amount in positive_f64(),
    ) {
        let constraints = QuantizeConstraints { tick_size, amount_step, min_amount };
        let mut metrics = QuantizeMetrics::new();
        // Should return Ok or Err, never panic
        let _ = quantize(raw_qty, raw_price, side, &constraints, &mut metrics);
    }
}
