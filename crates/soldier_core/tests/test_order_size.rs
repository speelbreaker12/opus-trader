//! Tests for OrderSize canonical sizing per CONTRACT.md §1.0.
//!
//! AT-277: dispatcher mapping validates option sizing and qty_usd unset.

use soldier_core::execution::{OrderSizeError, OrderSizeInput, build_order_size};
use soldier_core::venue::InstrumentKind;

// ─── AT-277: Contract worked examples ───────────────────────────────────

/// AT-277 example 1: option with qty_coin=0.3, index_price=100_000
/// → notional_usd=30_000, qty_usd unset
#[test]
fn test_at277_option_sizing() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.3,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();

    assert_eq!(size.qty_coin, Some(0.3));
    assert_eq!(size.qty_usd, None, "AT-277: option qty_usd MUST be unset");
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

/// AT-277 example 2: perpetual with qty_usd=30_000, index_price=100_000
/// → qty_coin=0.3, notional_usd=30_000
#[test]
fn test_at277_perpetual_sizing() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();

    assert_eq!(size.qty_usd, Some(30_000.0));
    assert!((size.qty_coin.unwrap() - 0.3).abs() < 1e-9);
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

// ─── Canonical sizing per instrument kind ───────────────────────────────

/// Option: canonical = qty_coin, qty_usd = None
#[test]
fn test_option_canonical_is_qty_coin() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.5,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.qty_coin, Some(1.5));
    assert_eq!(size.qty_usd, None);
    assert!((size.notional_usd - 75_000.0).abs() < 0.01);
}

/// LinearFuture: canonical = qty_coin, qty_usd = None
#[test]
fn test_linear_future_canonical_is_qty_coin() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::LinearFuture,
        canonical_qty: 2.0,
        index_price: 60_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.qty_coin, Some(2.0));
    assert_eq!(size.qty_usd, None);
    assert!((size.notional_usd - 120_000.0).abs() < 0.01);
}

/// Perpetual: canonical = qty_usd, derives qty_coin
#[test]
fn test_perpetual_canonical_is_qty_usd() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 50_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.qty_usd, Some(50_000.0));
    assert!((size.qty_coin.unwrap() - 0.5).abs() < 1e-9);
    assert!((size.notional_usd - 50_000.0).abs() < 0.01);
}

/// InverseFuture: canonical = qty_usd, derives qty_coin
#[test]
fn test_inverse_future_canonical_is_qty_usd() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::InverseFuture,
        canonical_qty: 10_000.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.qty_usd, Some(10_000.0));
    assert!((size.qty_coin.unwrap() - 0.2).abs() < 1e-9);
    assert!((size.notional_usd - 10_000.0).abs() < 0.01);
}

// ─── notional_usd invariant ─────────────────────────────────────────────

/// notional_usd always populated for all instrument kinds
#[test]
fn test_notional_usd_always_populated() {
    let kinds = [
        (InstrumentKind::Option, 0.5, 80_000.0, 40_000.0),
        (InstrumentKind::LinearFuture, 1.0, 70_000.0, 70_000.0),
        (InstrumentKind::Perpetual, 25_000.0, 100_000.0, 25_000.0),
        (InstrumentKind::InverseFuture, 15_000.0, 60_000.0, 15_000.0),
    ];
    for (kind, qty, price, expected_notional) in kinds {
        let input = OrderSizeInput {
            instrument_kind: kind,
            canonical_qty: qty,
            index_price: price,
            contract_multiplier: None,
        };
        let size = build_order_size(&input).unwrap();
        assert!(
            (size.notional_usd - expected_notional).abs() < 0.01,
            "notional_usd wrong for {kind:?}: got {} expected {expected_notional}",
            size.notional_usd
        );
    }
}

// ─── Contracts derivation ───────────────────────────────────────────────

/// Contracts derived from contract_multiplier for coin-sized instruments
#[test]
fn test_contracts_derived_for_option() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 3.0,
        index_price: 100_000.0,
        contract_multiplier: Some(1.0), // Deribit BTC option: 1 contract = 1 BTC
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.contracts, Some(3));
}

/// Contracts derived from contract_multiplier for USD-sized instruments
#[test]
fn test_contracts_derived_for_perpetual() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: Some(10.0), // Deribit BTC perp: 1 contract = $10
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.contracts, Some(3000));
}

/// No contract_multiplier → contracts = None
#[test]
fn test_no_multiplier_no_contracts() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.5,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).unwrap();
    assert_eq!(size.contracts, None);
}

// ─── Input validation (fail-closed) ─────────────────────────────────────

/// Zero index_price rejected
#[test]
fn test_zero_index_price_rejected() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: 0.0,
        contract_multiplier: None,
    };
    assert_eq!(
        build_order_size(&input),
        Err(OrderSizeError::InvalidIndexPrice(0.0))
    );
}

/// Negative index_price rejected
#[test]
fn test_negative_index_price_rejected() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 1000.0,
        index_price: -50_000.0,
        contract_multiplier: None,
    };
    assert_eq!(
        build_order_size(&input),
        Err(OrderSizeError::InvalidIndexPrice(-50_000.0))
    );
}

/// NaN index_price rejected
#[test]
fn test_nan_index_price_rejected() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: f64::NAN,
        contract_multiplier: None,
    };
    match build_order_size(&input) {
        Err(OrderSizeError::InvalidIndexPrice(_)) => {}
        other => panic!("expected InvalidIndexPrice, got {other:?}"),
    }
}

/// Zero canonical_qty rejected
#[test]
fn test_zero_canonical_qty_rejected() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    assert_eq!(
        build_order_size(&input),
        Err(OrderSizeError::InvalidCanonicalQty(0.0))
    );
}

/// Invalid contract_multiplier rejected
#[test]
fn test_invalid_contract_multiplier_rejected() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: 100_000.0,
        contract_multiplier: Some(0.0),
    };
    assert_eq!(
        build_order_size(&input),
        Err(OrderSizeError::InvalidContractMultiplier(0.0))
    );
}
