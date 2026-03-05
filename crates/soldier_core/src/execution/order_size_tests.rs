use super::*;
use crate::venue::InstrumentKind;

trait TestResultExt<T> {
    fn must(self) -> T;
}

impl<T, E: std::fmt::Debug> TestResultExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

impl<T> TestResultExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

// AT-277: Contract worked examples

#[test]
fn test_at277_option_sizing() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.3,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();

    assert_eq!(size.qty_coin, Some(0.3));
    assert_eq!(size.qty_usd, None, "AT-277: option qty_usd MUST be unset");
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

#[test]
fn test_at277_perpetual_sizing() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();

    assert_eq!(size.qty_usd, Some(30_000.0));
    assert!((size.qty_coin.must() - 0.3).abs() < 1e-9);
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

// Canonical sizing per instrument kind

#[test]
fn test_option_canonical_is_qty_coin() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.5,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.qty_coin, Some(1.5));
    assert_eq!(size.qty_usd, None);
    assert!((size.notional_usd - 75_000.0).abs() < 0.01);
}

#[test]
fn test_linear_future_canonical_is_qty_coin() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::LinearFuture,
        canonical_qty: 2.0,
        index_price: 60_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.qty_coin, Some(2.0));
    assert_eq!(size.qty_usd, None);
    assert!((size.notional_usd - 120_000.0).abs() < 0.01);
}

#[test]
fn test_perpetual_canonical_is_qty_usd() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 50_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.qty_usd, Some(50_000.0));
    assert!((size.qty_coin.must() - 0.5).abs() < 1e-9);
    assert!((size.notional_usd - 50_000.0).abs() < 0.01);
}

#[test]
fn test_inverse_future_canonical_is_qty_usd() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::InverseFuture,
        canonical_qty: 10_000.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.qty_usd, Some(10_000.0));
    assert!((size.qty_coin.must() - 0.2).abs() < 1e-9);
    assert!((size.notional_usd - 10_000.0).abs() < 0.01);
}

#[test]
fn test_instrument_kind_metadata_changes_sizing_outcome() {
    let option_input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let perp_input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };

    let option_size = build_order_size(&option_input).must();
    let perp_size = build_order_size(&perp_input).must();

    assert!(option_size.qty_coin.is_some(), "option must have qty_coin");
    assert!(
        option_size.qty_usd.is_none(),
        "option must not have qty_usd"
    );
    assert!(perp_size.qty_usd.is_some(), "perpetual must have qty_usd");
    assert_ne!(
        option_size.notional_usd, perp_size.notional_usd,
        "different instrument_kind must produce different notional_usd"
    );
}

// notional_usd invariant

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
        let size = build_order_size(&input).must();
        assert!(
            (size.notional_usd - expected_notional).abs() < 0.01,
            "notional_usd wrong for {kind:?}: got {} expected {expected_notional}",
            size.notional_usd
        );
    }
}

// Contracts derivation

#[test]
fn test_contracts_derived_for_option() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 3.0,
        index_price: 100_000.0,
        contract_multiplier: Some(1.0),
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.contracts, Some(3));
}

#[test]
fn test_contracts_derived_for_perpetual() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: Some(10.0),
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.contracts, Some(3000));
}

#[test]
fn test_no_multiplier_no_contracts() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.5,
        index_price: 100_000.0,
        contract_multiplier: None,
    };
    let size = build_order_size(&input).must();
    assert_eq!(size.contracts, None);
}

// Input validation

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

// Output validation

#[test]
fn test_order_size_nan_notional_returns_err() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: f64::MAX,
        index_price: f64::MAX,
        contract_multiplier: None,
    };
    let result = build_order_size(&input);
    assert!(result.is_err(), "NaN/Inf notional must be rejected");
    assert!(
        matches!(result, Err(OrderSizeError::InvalidNotional(_))),
        "expected InvalidNotional, got {result:?}"
    );
}

#[test]
fn test_order_size_overflow_contracts_returns_err() {
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1e30,
        index_price: 50000.0,
        contract_multiplier: Some(1e-20),
    };
    let result = build_order_size(&input);
    assert!(result.is_err(), "i64 overflow must be rejected");
    assert!(
        matches!(result, Err(OrderSizeError::ContractsOverflow { .. })),
        "expected ContractsOverflow, got {result:?}"
    );
}

// TODO-13: contracts > 2^53 must be rejected before i64→f64 conversion (precision loss guard)

#[test]
fn test_contracts_exceeds_f64_precision_limit_rejected_option() {
    // Use 2^53 + 2, the next representable f64 above 2^53.
    // Note: (1i64 << 53) + 1 rounds DOWN to 2^53 in IEEE 754 (odd integers
    // above 2^53 are not representable); +2 is the first representable value
    // strictly greater than 2^53, ensuring the precision guard fires.
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: (1i64 << 53) as f64 + 2.0, // first f64 strictly > 2^53
        index_price: 50_000.0,
        contract_multiplier: Some(1.0),
    };
    let result = build_order_size(&input);
    assert!(
        matches!(result, Err(OrderSizeError::ContractsPrecisionLoss { .. })),
        "contracts exceeding 2^53 must return ContractsPrecisionLoss, got {result:?}"
    );
}

#[test]
fn test_contracts_exceeds_f64_precision_limit_rejected_perpetual() {
    // Same guard must fire for the Perpetual/InverseFuture arm.
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: (1i64 << 53) as f64 + 2.0, // first f64 strictly > 2^53
        index_price: 50_000.0,
        contract_multiplier: Some(1.0),
    };
    let result = build_order_size(&input);
    assert!(
        matches!(result, Err(OrderSizeError::ContractsPrecisionLoss { .. })),
        "contracts exceeding 2^53 must return ContractsPrecisionLoss (perpetual), got {result:?}"
    );
}

#[test]
fn test_contracts_exceeds_f64_precision_limit_rejected_inverse_future() {
    // InverseFuture shares the Perpetual code path; explicit coverage documents the invariant.
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::InverseFuture,
        canonical_qty: (1i64 << 53) as f64 + 2.0, // first f64 strictly > 2^53
        index_price: 50_000.0,
        contract_multiplier: Some(1.0),
    };
    let result = build_order_size(&input);
    assert!(
        matches!(result, Err(OrderSizeError::ContractsPrecisionLoss { .. })),
        "InverseFuture arm must also reject contracts exceeding 2^53, got {result:?}"
    );
}

#[test]
fn test_contracts_at_f64_precision_limit_accepted() {
    // 2^53 exactly is representable in f64 without loss; must not be rejected.
    let contracts_value = 1i64 << 53;
    let input = OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: contracts_value as f64,
        index_price: 50_000.0,
        contract_multiplier: Some(1.0),
    };
    let result = build_order_size(&input);
    assert!(
        result.is_ok(),
        "contracts == 2^53 must be accepted (boundary is exclusive), got {result:?}"
    );
    assert_eq!(result.unwrap().contracts, Some(contracts_value));
}
