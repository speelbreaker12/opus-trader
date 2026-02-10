//! Tests for canonical quantization per CONTRACT.md §1.1.1.
//!
//! AT-219: safe rounding direction (BUY down, SELL up).
//! AT-908: qty_q < min_amount → reject.
//! AT-926: missing/invalid instrument metadata → reject.

use soldier_core::execution::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, Side, quantize,
};

/// Standard test constraints (BTC-like instrument).
fn btc_constraints() -> QuantizeConstraints {
    QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    }
}

fn decimal_constraints() -> QuantizeConstraints {
    QuantizeConstraints {
        tick_size: 0.1,
        amount_step: 0.1,
        min_amount: 0.1,
    }
}

// ─── Quantity quantization ─────────────────────────────────────────────

/// qty_q = floor(raw_qty / amount_step) * amount_step
#[test]
fn test_qty_rounds_down() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.35, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 3);
    assert!((result.qty_q - 0.3).abs() < 1e-9, "0.35 rounds down to 0.3");
}

/// Exact multiple → no rounding needed
#[test]
fn test_qty_exact_multiple() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.5, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 5);
    assert!((result.qty_q - 0.5).abs() < 1e-9);
}

/// qty_steps is the integer count for hashing
#[test]
fn test_qty_steps_integer() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.99, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 19);
    assert!((result.qty_q - 1.9).abs() < 1e-9);
}

/// Decimal boundary: 0.3/0.1 should quantize to exactly 3 steps, not 2.
#[test]
fn test_qty_decimal_boundary_is_stable() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.3, 50_000.0, Side::Buy, &decimal_constraints(), &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 3);
    assert!((result.qty_q - 0.3).abs() < 1e-9);
}

// ─── AT-219: Price rounding direction ──────────────────────────────────

/// BUY: price rounds DOWN (never pay extra)
#[test]
fn test_buy_price_rounds_down() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 50_000.7, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
    // 50_000.7 / 0.5 = 100_001.4, floor = 100_001
    assert_eq!(result.price_ticks, 100_001);
    assert!(
        (result.limit_price_q - 50_000.5).abs() < 1e-9,
        "BUY rounds down"
    );
    assert!(
        result.limit_price_q <= 50_000.7,
        "BUY price must never increase"
    );
}

/// SELL: price rounds UP (never sell cheaper)
#[test]
fn test_sell_price_rounds_up() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 50_000.3, Side::Sell, &btc_constraints(), &mut metrics).unwrap();
    // 50_000.3 / 0.5 = 100_000.6, ceil = 100_001
    assert_eq!(result.price_ticks, 100_001);
    assert!(
        (result.limit_price_q - 50_000.5).abs() < 1e-9,
        "SELL rounds up"
    );
    assert!(
        result.limit_price_q >= 50_000.3,
        "SELL price must never decrease"
    );
}

/// BUY: exact tick → no rounding
#[test]
fn test_buy_price_exact_tick() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 100_000);
    assert!((result.limit_price_q - 50_000.0).abs() < 1e-9);
}

/// SELL: exact tick → no rounding
#[test]
fn test_sell_price_exact_tick() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 50_000.0, Side::Sell, &btc_constraints(), &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 100_000);
    assert!((result.limit_price_q - 50_000.0).abs() < 1e-9);
}

/// Decimal boundary: 100.3/0.1 should stay on tick for BUY.
#[test]
fn test_buy_price_decimal_boundary_is_stable() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 100.3, Side::Buy, &decimal_constraints(), &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1003);
    assert!((result.limit_price_q - 100.3).abs() < 1e-9);
}

/// Decimal boundary: 100.3/0.1 should stay on tick for SELL.
#[test]
fn test_sell_price_decimal_boundary_is_stable() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(1.0, 100.3, Side::Sell, &decimal_constraints(), &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1003);
    assert!((result.limit_price_q - 100.3).abs() < 1e-9);
}

/// AT-219: BUY price never increases
#[test]
fn test_at219_buy_never_increases() {
    let mut metrics = QuantizeMetrics::new();
    let prices = [99_999.1, 50_000.3, 50_000.9, 12_345.67];
    for raw_price in prices {
        let result = quantize(1.0, raw_price, Side::Buy, &btc_constraints(), &mut metrics).unwrap();
        assert!(
            result.limit_price_q <= raw_price,
            "BUY price {raw_price} → {} must not increase",
            result.limit_price_q
        );
    }
}

/// AT-219: SELL price never decreases
#[test]
fn test_at219_sell_never_decreases() {
    let mut metrics = QuantizeMetrics::new();
    let prices = [99_999.1, 50_000.3, 50_000.9, 12_345.67];
    for raw_price in prices {
        let result =
            quantize(1.0, raw_price, Side::Sell, &btc_constraints(), &mut metrics).unwrap();
        assert!(
            result.limit_price_q >= raw_price,
            "SELL price {raw_price} → {} must not decrease",
            result.limit_price_q
        );
    }
}

// ─── AT-908: Too small after quantization ──────────────────────────────

/// AT-908: qty_q < min_amount → TooSmallAfterQuantization
#[test]
fn test_at908_too_small_rejected() {
    let mut metrics = QuantizeMetrics::new();
    // raw_qty=0.05, amount_step=0.1 → qty_steps=0, qty_q=0.0 < min_amount=0.1
    let result = quantize(0.05, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics);
    match result {
        Err(QuantizeError::TooSmallAfterQuantization { qty_q, min_amount }) => {
            assert!((qty_q - 0.0).abs() < 1e-9);
            assert!((min_amount - 0.1).abs() < 1e-9);
        }
        other => panic!("expected TooSmallAfterQuantization, got {other:?}"),
    }
}

/// AT-908: rejection increments counter
#[test]
fn test_at908_counter_increments() {
    let mut metrics = QuantizeMetrics::new();
    assert_eq!(metrics.reject_too_small_total(), 0);

    let _ = quantize(0.05, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics);
    assert_eq!(metrics.reject_too_small_total(), 1);

    let _ = quantize(0.01, 50_000.0, Side::Sell, &btc_constraints(), &mut metrics);
    assert_eq!(metrics.reject_too_small_total(), 2);
}

/// AT-908: exactly min_amount → passes
#[test]
fn test_at908_exactly_min_amount_passes() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.1, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics);
    assert!(result.is_ok(), "exactly min_amount should pass");
    assert_eq!(metrics.reject_too_small_total(), 0);
}

/// AT-908: dispatch count 0 on rejection (no QuantizedValues returned)
#[test]
fn test_at908_no_output_on_rejection() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.05, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics);
    assert!(result.is_err());
}

// ─── AT-926: Missing instrument metadata ───────────────────────────────

/// AT-926: zero tick_size → InstrumentMetadataMissing
#[test]
fn test_at926_zero_tick_size() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.0,
        amount_step: 0.1,
        min_amount: 0.1,
    };
    let result = quantize(1.0, 50_000.0, Side::Buy, &constraints, &mut metrics);
    assert_eq!(
        result,
        Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" })
    );
}

/// AT-926: NaN amount_step → InstrumentMetadataMissing
#[test]
fn test_at926_nan_amount_step() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: f64::NAN,
        min_amount: 0.1,
    };
    let result = quantize(1.0, 50_000.0, Side::Buy, &constraints, &mut metrics);
    assert_eq!(
        result,
        Err(QuantizeError::InstrumentMetadataMissing {
            field: "amount_step"
        })
    );
}

/// AT-926: negative min_amount → InstrumentMetadataMissing
#[test]
fn test_at926_negative_min_amount() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: -1.0,
    };
    let result = quantize(1.0, 50_000.0, Side::Buy, &constraints, &mut metrics);
    assert_eq!(
        result,
        Err(QuantizeError::InstrumentMetadataMissing {
            field: "min_amount"
        })
    );
}

/// AT-926: infinity tick_size → InstrumentMetadataMissing
#[test]
fn test_at926_infinity_tick_size() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: f64::INFINITY,
        amount_step: 0.1,
        min_amount: 0.1,
    };
    let result = quantize(1.0, 50_000.0, Side::Buy, &constraints, &mut metrics);
    assert_eq!(
        result,
        Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" })
    );
}

/// Non-finite raw qty must fail-closed before quantization.
#[test]
fn test_non_finite_raw_qty_rejected() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(f64::NAN, 50_000.0, Side::Buy, &btc_constraints(), &mut metrics);
    assert_eq!(result, Err(QuantizeError::InvalidInput { field: "raw_qty" }));
}

/// Non-finite raw limit price must fail-closed before quantization.
#[test]
fn test_non_finite_raw_limit_price_rejected() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(
        1.0,
        f64::INFINITY,
        Side::Buy,
        &btc_constraints(),
        &mut metrics,
    );
    assert_eq!(
        result,
        Err(QuantizeError::InvalidInput {
            field: "raw_limit_price"
        })
    );
}

// ─── Deterministic round-trip ──────────────────────────────────────────

/// Quantization is deterministic: same inputs → same outputs
#[test]
fn test_deterministic_quantization() {
    let constraints = btc_constraints();
    let mut m1 = QuantizeMetrics::new();
    let mut m2 = QuantizeMetrics::new();

    let r1 = quantize(0.35, 50_000.7, Side::Buy, &constraints, &mut m1).unwrap();
    let r2 = quantize(0.35, 50_000.7, Side::Buy, &constraints, &mut m2).unwrap();

    assert_eq!(r1.qty_steps, r2.qty_steps);
    assert_eq!(r1.price_ticks, r2.price_ticks);
    assert!((r1.qty_q - r2.qty_q).abs() < 1e-15);
    assert!((r1.limit_price_q - r2.limit_price_q).abs() < 1e-15);
}

/// Integer tick/step values are suitable for hashing
#[test]
fn test_integer_values_for_hashing() {
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(2.75, 65_432.1, Side::Sell, &btc_constraints(), &mut metrics).unwrap();
    // These are i64 values — guaranteed deterministic for hashing
    let _qty_steps: i64 = result.qty_steps;
    let _price_ticks: i64 = result.price_ticks;
    assert!(result.qty_steps > 0);
    assert!(result.price_ticks > 0);
}

/// Large ratios must preserve floor semantics for quantity (never round up size).
#[test]
fn test_large_ratio_qty_still_floors() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1.0,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let raw_qty = 1_000_000_000_000.75;
    let result = quantize(raw_qty, 100.0, Side::Buy, &constraints, &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 1_000_000_000_000);
    assert_eq!(result.qty_q, 1_000_000_000_000.0);
    assert!(result.qty_q <= raw_qty);
}

/// Large ratios must preserve BUY floor semantics for price.
#[test]
fn test_large_ratio_buy_price_still_floors() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1.0,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let raw_price = 1_000_000_000_000.75;
    let result = quantize(1.0, raw_price, Side::Buy, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1_000_000_000_000);
    assert_eq!(result.limit_price_q, 1_000_000_000_000.0);
    assert!(result.limit_price_q <= raw_price);
}

/// Large ratios must preserve SELL ceil semantics for price.
#[test]
fn test_large_ratio_sell_price_still_ceils() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1.0,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let raw_price = 1_000_000_000_000.25;
    let result = quantize(1.0, raw_price, Side::Sell, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1_000_000_000_001);
    assert_eq!(result.limit_price_q, 1_000_000_000_001.0);
    assert!(result.limit_price_q >= raw_price);
}

/// Large decimal boundaries should still snap to exact quantity steps.
#[test]
fn test_large_decimal_boundary_qty_stays_on_step() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1.0,
        amount_step: 0.1,
        min_amount: 0.0,
    };
    let raw_qty = 100_000_000.3;
    let result = quantize(raw_qty, 100.0, Side::Buy, &constraints, &mut metrics).unwrap();
    assert_eq!(result.qty_steps, 1_000_000_003);
    assert!((result.qty_q - raw_qty).abs() < 1e-6);
}

/// Large decimal boundaries should still snap to exact BUY price ticks.
#[test]
fn test_large_decimal_boundary_buy_price_stays_on_tick() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.1,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let raw_price = 100_000_000.3;
    let result = quantize(1.0, raw_price, Side::Buy, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1_000_000_003);
    assert!((result.limit_price_q - raw_price).abs() < 1e-6);
}

/// Large decimal boundaries should still snap to exact SELL price ticks.
#[test]
fn test_large_decimal_boundary_sell_price_stays_on_tick() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.1,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let raw_price = 100_000_000.3;
    let result = quantize(1.0, raw_price, Side::Sell, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, 1_000_000_003);
    assert!((result.limit_price_q - raw_price).abs() < 1e-6);
}

/// Extreme ratios must not let BUY snapping round price up by one tick.
#[test]
fn test_extreme_ratio_buy_never_rounds_up_via_snap() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1e-9,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let n_ticks: i64 = 80_000_000_000_000;
    let raw_price = (n_ticks as f64 + 0.9) * constraints.tick_size;
    let result = quantize(1.0, raw_price, Side::Buy, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, n_ticks);
    assert!(result.limit_price_q <= raw_price);
}

/// Extreme ratios must not let SELL snapping round price down by one tick.
#[test]
fn test_extreme_ratio_sell_never_rounds_down_via_snap() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 1e-9,
        amount_step: 1.0,
        min_amount: 0.0,
    };
    let n_ticks: i64 = 80_000_000_000_000;
    let raw_price = (n_ticks as f64 + 0.1) * constraints.tick_size;
    let result = quantize(1.0, raw_price, Side::Sell, &constraints, &mut metrics).unwrap();
    assert_eq!(result.price_ticks, n_ticks + 1);
    assert!(result.limit_price_q >= raw_price);
}

// ─── Edge cases ────────────────────────────────────────────────────────

/// min_amount=0 with zero qty_q should pass (0 >= 0)
#[test]
fn test_zero_min_amount_allows_zero_qty() {
    let mut metrics = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.0,
    };
    // raw_qty=0.05 → qty_steps=0, qty_q=0.0 >= min_amount=0.0 → OK
    let result = quantize(0.05, 50_000.0, Side::Buy, &constraints, &mut metrics);
    assert!(result.is_ok());
}
