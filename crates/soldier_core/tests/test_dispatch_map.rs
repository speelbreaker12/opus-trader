//! Tests for dispatcher amount mapping per CONTRACT.md Dispatcher Rules.
//!
//! AT-277: dispatcher mapping validates option sizing and amount field.

use soldier_core::execution::{
    CONTRACTS_AMOUNT_MATCH_TOLERANCE, DispatchMapError, IntentClass, MismatchMetrics, OrderSize,
    OrderSizeInput, build_order_size, map_to_dispatch, validate_and_dispatch,
};
use soldier_core::risk::RiskState;
use soldier_core::venue::InstrumentKind;

// ─── Amount field selection ─────────────────────────────────────────────

/// Option → amount = qty_coin
#[test]
fn test_option_amount_is_qty_coin() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.3,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open).unwrap();
    assert!(
        (req.amount - 0.3).abs() < 1e-9,
        "option amount should be qty_coin=0.3"
    );
}

/// LinearFuture → amount = qty_coin
#[test]
fn test_linear_future_amount_is_qty_coin() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::LinearFuture,
        canonical_qty: 2.0,
        index_price: 60_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::LinearFuture, IntentClass::Open).unwrap();
    assert!(
        (req.amount - 2.0).abs() < 1e-9,
        "linear_future amount should be qty_coin=2.0"
    );
}

/// Perpetual → amount = qty_usd
#[test]
fn test_perpetual_amount_is_qty_usd() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Perpetual, IntentClass::Open).unwrap();
    assert!(
        (req.amount - 30_000.0).abs() < 0.01,
        "perpetual amount should be qty_usd=30_000"
    );
}

/// InverseFuture → amount = qty_usd
#[test]
fn test_inverse_future_amount_is_qty_usd() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::InverseFuture,
        canonical_qty: 10_000.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::InverseFuture, IntentClass::Open).unwrap();
    assert!(
        (req.amount - 10_000.0).abs() < 0.01,
        "inverse_future amount should be qty_usd=10_000"
    );
}

// ─── Exactly one amount field ───────────────────────────────────────────

/// Option: qty_usd is unset in OrderSize, so only qty_coin is used
#[test]
fn test_option_only_one_amount_field() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    // Verify OrderSize has the right structure
    assert!(size.qty_coin.is_some(), "option must have qty_coin");
    assert!(size.qty_usd.is_none(), "option must NOT have qty_usd");

    // Dispatch succeeds using qty_coin
    let req = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open).unwrap();
    assert!(req.amount > 0.0);
}

/// Coin-sized instrument with missing qty_coin → error
#[test]
fn test_missing_qty_coin_error() {
    // Manually construct an OrderSize without qty_coin
    let size = OrderSize {
        contracts: None,
        qty_coin: None,
        qty_usd: Some(10_000.0),
        notional_usd: 10_000.0,
    };

    let result = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open);
    assert_eq!(result, Err(DispatchMapError::MissingQtyCoin));
}

/// USD-sized instrument with missing qty_usd → error
#[test]
fn test_missing_qty_usd_error() {
    // Manually construct an OrderSize without qty_usd
    let size = OrderSize {
        contracts: None,
        qty_coin: Some(0.3),
        qty_usd: None,
        notional_usd: 30_000.0,
    };

    let result = map_to_dispatch(&size, InstrumentKind::Perpetual, IntentClass::Open);
    assert_eq!(result, Err(DispatchMapError::MissingQtyUsd));
}

/// `map_to_dispatch` is fail-closed when contracts are populated.
/// Callers must use validate_and_dispatch so AT-920 mismatch checks run.
#[test]
fn test_map_to_dispatch_rejects_contracts_without_validation() {
    let size = OrderSize {
        contracts: Some(3),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let result = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open);
    assert_eq!(result, Err(DispatchMapError::ContractsRequireValidation));
}

// ─── reduce_only mapping ────────────────────────────────────────────────

/// OPEN → reduce_only = false
#[test]
fn test_open_intent_not_reduce_only() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 1.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open).unwrap();
    assert!(!req.reduce_only, "OPEN should not be reduce_only");
}

/// CLOSE → reduce_only = true
#[test]
fn test_close_intent_is_reduce_only() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 10_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Perpetual, IntentClass::Close).unwrap();
    assert!(req.reduce_only, "CLOSE should be reduce_only");
}

/// HEDGE → reduce_only = true
#[test]
fn test_hedge_intent_is_reduce_only() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 5_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Perpetual, IntentClass::Hedge).unwrap();
    assert!(req.reduce_only, "HEDGE should be reduce_only");
}

/// CANCEL → reduce_only = true
#[test]
fn test_cancel_intent_is_reduce_only() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.5,
        index_price: 80_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Cancel).unwrap();
    assert!(req.reduce_only, "CANCEL should be reduce_only");
}

/// Table-driven: all IntentClass → reduce_only mapping
#[test]
fn test_intent_class_reduce_only_table() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 10_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let cases = [
        (IntentClass::Open, false),
        (IntentClass::Close, true),
        (IntentClass::Hedge, true),
        (IntentClass::Cancel, true),
    ];
    for (intent, expected_reduce_only) in cases {
        let req = map_to_dispatch(&size, InstrumentKind::Perpetual, intent).unwrap();
        assert_eq!(
            req.reduce_only, expected_reduce_only,
            "reduce_only wrong for {intent:?}"
        );
    }
}

// ─── AT-277 full round-trip ─────────────────────────────────────────────

/// AT-277: option qty_coin=0.3 → dispatch amount=0.3
#[test]
fn test_at277_option_dispatch_roundtrip() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 0.3,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Option, IntentClass::Open).unwrap();
    assert!((req.amount - 0.3).abs() < 1e-9, "option amount=0.3 (coin)");
    assert!(!req.reduce_only);
    assert_eq!(size.qty_usd, None, "AT-277: option qty_usd unset");
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

/// AT-277: perpetual qty_usd=30_000 → dispatch amount=30_000
#[test]
fn test_at277_perpetual_dispatch_roundtrip() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Perpetual,
        canonical_qty: 30_000.0,
        index_price: 100_000.0,
        contract_multiplier: None,
    })
    .unwrap();

    let req = map_to_dispatch(&size, InstrumentKind::Perpetual, IntentClass::Open).unwrap();
    assert!(
        (req.amount - 30_000.0).abs() < 0.01,
        "perp amount=30_000 (USD)"
    );
    assert!(!req.reduce_only);
    assert!((size.qty_coin.unwrap() - 0.3).abs() < 1e-9);
    assert!((size.notional_usd - 30_000.0).abs() < 0.01);
}

// ─── AT-920: contracts/amount mismatch rejection ─────────────────────

/// AT-920: consistent contracts/amount → dispatch succeeds, RiskState::Healthy
#[test]
fn test_at920_consistent_contracts_passes() {
    let size = build_order_size(&OrderSizeInput {
        instrument_kind: InstrumentKind::Option,
        canonical_qty: 3.0,
        index_price: 100_000.0,
        contract_multiplier: Some(1.0),
    })
    .unwrap();

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    let validated = result.unwrap();
    assert!((validated.request.amount - 3.0).abs() < 1e-9);
    assert_eq!(validated.risk_state, RiskState::Healthy);
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);
}

/// AT-920: mismatched contracts/amount → rejected with ContractsAmountMismatch
#[test]
fn test_at920_mismatch_rejected() {
    // contracts=10, multiplier=1.0 → implied=10.0, but canonical=3.0
    // delta = |10 - 3| / 3 = 2.33 >> tolerance
    let size = OrderSize {
        contracts: Some(10),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    match result {
        Err(DispatchMapError::ContractsAmountMismatch { delta }) => {
            assert!(delta > CONTRACTS_AMOUNT_MATCH_TOLERANCE);
        }
        other => panic!("expected ContractsAmountMismatch, got {other:?}"),
    }
}

/// AT-920: mismatch rejection increments counter
#[test]
fn test_at920_mismatch_increments_counter() {
    let size = OrderSize {
        contracts: Some(100),
        qty_coin: Some(1.0),
        qty_usd: None,
        notional_usd: 100_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);

    let _ = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    assert_eq!(metrics.reject_unit_mismatch_total(), 1);

    // Second rejection increments again
    let _ = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    assert_eq!(metrics.reject_unit_mismatch_total(), 2);
}

/// AT-920: no contracts → skip check, dispatch succeeds
#[test]
fn test_at920_no_contracts_skips_check() {
    let size = OrderSize {
        contracts: None,
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    assert!(result.is_ok());
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);
}

/// AT-920: contracts present but no contract_multiplier → fail closed
#[test]
fn test_at920_no_multiplier_rejected_fail_closed() {
    let size = OrderSize {
        contracts: Some(3),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        None,
        &mut metrics,
    );
    assert_eq!(result, Err(DispatchMapError::ContractsRequireValidation));
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);
}

/// AT-920: denominator uses max(abs(amount), 1e-9) for very small canonical amounts.
#[test]
fn test_at920_epsilon_denominator_allows_small_amount_within_tolerance() {
    // contracts=0, multiplier=0 => implied=0
    // canonical=1e-12 => delta = 1e-12 / max(1e-12,1e-9) = 0.001 (exact tolerance)
    // Equality is allowed; only > tolerance rejects.
    let size = OrderSize {
        contracts: Some(0),
        qty_coin: Some(1e-12),
        qty_usd: None,
        notional_usd: 1e-7,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(0.0),
        &mut metrics,
    );
    assert!(result.is_ok(), "delta at tolerance boundary should pass");
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);
}

/// AT-920: non-finite multiplier must fail closed and reject dispatch.
#[test]
fn test_at920_non_finite_multiplier_rejected() {
    let size = OrderSize {
        contracts: Some(3),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(f64::NAN),
        &mut metrics,
    );
    match result {
        Err(DispatchMapError::ContractsAmountMismatch { delta }) => {
            assert!(
                !delta.is_finite(),
                "non-finite multiplier should produce non-finite mismatch delta"
            );
        }
        other => panic!("expected ContractsAmountMismatch, got {other:?}"),
    }
    assert_eq!(metrics.reject_unit_mismatch_total(), 1);
}

/// AT-920: perpetual mismatch (USD-sized) rejected
#[test]
fn test_at920_perpetual_mismatch_rejected() {
    // contracts=100, multiplier=10.0 → implied=1000 USD, but canonical=30_000 USD
    let size = OrderSize {
        contracts: Some(100),
        qty_coin: Some(0.3),
        qty_usd: Some(30_000.0),
        notional_usd: 30_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Perpetual,
        IntentClass::Open,
        Some(10.0),
        &mut metrics,
    );
    match result {
        Err(DispatchMapError::ContractsAmountMismatch { delta }) => {
            assert!(delta > CONTRACTS_AMOUNT_MATCH_TOLERANCE);
        }
        other => panic!("expected ContractsAmountMismatch, got {other:?}"),
    }
    assert_eq!(metrics.reject_unit_mismatch_total(), 1);
}

/// AT-920: mismatch within tolerance → passes
#[test]
fn test_at920_within_tolerance_passes() {
    // contracts=3, multiplier=1.0 → implied=3.0
    // canonical=3.0 → delta=0.0 (within tolerance)
    let size = OrderSize {
        contracts: Some(3),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    assert!(result.is_ok());
    assert_eq!(metrics.reject_unit_mismatch_total(), 0);
}

/// AT-920: mismatch delta is included in error for deterministic error propagation
#[test]
fn test_at920_delta_in_error() {
    // contracts=5, multiplier=1.0 → implied=5.0, canonical=3.0
    // delta = |5.0 - 3.0| / 3.0 = 0.6667
    let size = OrderSize {
        contracts: Some(5),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    match result {
        Err(DispatchMapError::ContractsAmountMismatch { delta }) => {
            assert!(
                (delta - 2.0 / 3.0).abs() < 1e-9,
                "delta should be ~0.6667, got {delta}"
            );
        }
        other => panic!("expected ContractsAmountMismatch, got {other:?}"),
    }
}

/// AT-920: tolerance constant is 0.001
#[test]
fn test_at920_tolerance_constant() {
    assert!(
        (CONTRACTS_AMOUNT_MATCH_TOLERANCE - 0.001).abs() < 1e-12,
        "tolerance must be 0.001 per CONTRACT.md"
    );
}

/// AT-920: dispatch count 0 on mismatch (no DispatchRequest created)
#[test]
fn test_at920_no_dispatch_on_mismatch() {
    let size = OrderSize {
        contracts: Some(10),
        qty_coin: Some(3.0),
        qty_usd: None,
        notional_usd: 300_000.0,
    };

    let mut metrics = MismatchMetrics::new();
    let result = validate_and_dispatch(
        &size,
        InstrumentKind::Option,
        IntentClass::Open,
        Some(1.0),
        &mut metrics,
    );
    assert!(result.is_err(), "mismatch must prevent dispatch");
}
