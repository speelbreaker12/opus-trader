//! Tests for InstrumentKind derivation and RiskState enum.
//!
//! Validates mapping from venue metadata to CONTRACT.md instrument_kind
//! (AT-333) and RiskState variants.
//!
//! **Dispatch causality**: Pipeline-level proof that unknown instrument kind
//! blocks dispatch lives in `test_intent_assembly.rs::test_assembly_unknown_kind_fails_closed`
//! and `test_assembled_pipeline_unknown_kind_rejects`.

use soldier_core::risk::RiskState;
use soldier_core::venue::{InstrumentKind, InstrumentKindInput, derive_instrument_kind};

// ─── InstrumentKind derivation ───────────────────────────────────────────

/// CONTRACT.md: option metadata → InstrumentKind::Option
#[test]
fn test_option_maps_to_option() {
    let input = InstrumentKindInput {
        is_option: true,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    assert_eq!(derive_instrument_kind(&input), Some(InstrumentKind::Option));
}

/// CONTRACT.md: BTC-PERPETUAL (BTC-settled perpetual) → Perpetual
#[test]
fn test_btc_perpetual_maps_to_perpetual() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: false, // settlement=BTC, quote=USD → not linear
    };
    assert_eq!(
        derive_instrument_kind(&input),
        Some(InstrumentKind::Perpetual)
    );
}

/// CONTRACT.md: "Linear Perpetuals (USDC-margined): treat as linear_future"
#[test]
fn test_usdc_margined_perpetual_maps_to_linear_future() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: true, // settlement=USDC, quote=USDC → linear
    };
    assert_eq!(
        derive_instrument_kind(&input),
        Some(InstrumentKind::LinearFuture)
    );
}

/// CONTRACT.md: BTC-settled dated future → InverseFuture
#[test]
fn test_btc_dated_future_maps_to_inverse_future() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: false,
        is_linear: false, // settlement=BTC, quote=USD → inverse
    };
    assert_eq!(
        derive_instrument_kind(&input),
        Some(InstrumentKind::InverseFuture)
    );
}

/// USDC-settled dated future → LinearFuture (same rule as USDC perps)
#[test]
fn test_usdc_dated_future_maps_to_linear_future() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: false,
        is_linear: true, // settlement=USDC, quote=USDC → linear
    };
    assert_eq!(
        derive_instrument_kind(&input),
        Some(InstrumentKind::LinearFuture)
    );
}

/// Combo instruments (option_combo, future_combo) → None (out of scope)
#[test]
fn test_combo_instruments_return_none() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    assert_eq!(derive_instrument_kind(&input), None);
}

/// Table-driven: all 4 InstrumentKind variants are derivable.
#[test]
fn test_all_instrument_kinds_derivable() {
    let cases = [
        (
            "option",
            InstrumentKindInput {
                is_option: true,
                is_future: false,
                is_perpetual: false,
                is_linear: false,
            },
            InstrumentKind::Option,
        ),
        (
            "linear_future",
            InstrumentKindInput {
                is_option: false,
                is_future: true,
                is_perpetual: false,
                is_linear: true,
            },
            InstrumentKind::LinearFuture,
        ),
        (
            "inverse_future",
            InstrumentKindInput {
                is_option: false,
                is_future: true,
                is_perpetual: false,
                is_linear: false,
            },
            InstrumentKind::InverseFuture,
        ),
        (
            "perpetual",
            InstrumentKindInput {
                is_option: false,
                is_future: true,
                is_perpetual: true,
                is_linear: false,
            },
            InstrumentKind::Perpetual,
        ),
    ];
    for (name, input, expected) in cases {
        assert_eq!(
            derive_instrument_kind(&input),
            Some(expected),
            "failed for {name}"
        );
    }
}

/// Linear takes priority over perpetual: USDC-margined perp → LinearFuture
#[test]
fn test_linear_priority_over_perpetual() {
    let input = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: true,
    };
    // CONTRACT.md: USDC-margined perpetual → linear_future, NOT perpetual
    assert_eq!(
        derive_instrument_kind(&input),
        Some(InstrumentKind::LinearFuture)
    );
}

/// Ambiguous input: both option and future flags set → None (contradictory, fail-closed)
#[test]
fn test_option_priority_over_future_when_both_set() {
    let input = InstrumentKindInput {
        is_option: true,
        is_future: true,
        is_perpetual: true,
        is_linear: true,
    };
    // Contradictory flags → None (fail-closed: unknown = reject)
    assert_eq!(derive_instrument_kind(&input), None);
}

// ─── GAP-002-1: get_instruments shape ────────────────────────────────────

/// GAP-002-1: Table-driven test covering realistic get_instruments payloads.
///
/// Each row simulates field extraction from a Deribit /public/get_instruments
/// response, proving the InstrumentKindInput abstraction layer correctly maps
/// venue-shaped data to InstrumentKind. This covers instruments that the
/// individual tests above do not: USDC-margined perpetual and ETH option
/// with realistic field derivation comments.
#[test]
fn test_get_instruments_realistic_payloads() {
    let cases = [
        // BTC-PERPETUAL: kind=future, settlement_period=perpetual, BTC-settled
        (
            "BTC-PERPETUAL",
            InstrumentKindInput {
                is_option: false, // kind="future"
                is_future: true,
                is_perpetual: true, // settlement_period="perpetual"
                is_linear: false,   // settlement_currency="BTC" != quote="USD"
            },
            Some(InstrumentKind::Perpetual),
        ),
        // BTCUSDC-PERP: kind=future, settlement_period=perpetual, USDC-settled
        (
            "BTCUSDC-PERP",
            InstrumentKindInput {
                is_option: false,
                is_future: true,
                is_perpetual: true,
                is_linear: true, // settlement_currency="USDC" == quote="USDC"
            },
            Some(InstrumentKind::LinearFuture),
        ),
        // ETH-28MAR25-3000-C: kind=option
        (
            "ETH-28MAR25-3000-C",
            InstrumentKindInput {
                is_option: true, // kind="option"
                is_future: false,
                is_perpetual: false,
                is_linear: false,
            },
            Some(InstrumentKind::Option),
        ),
        // BTC-28MAR25: kind=future, dated, BTC-settled → InverseFuture
        (
            "BTC-28MAR25",
            InstrumentKindInput {
                is_option: false,
                is_future: true,
                is_perpetual: false, // settlement_period="month"
                is_linear: false,    // settlement_currency="BTC" != quote="USD"
            },
            Some(InstrumentKind::InverseFuture),
        ),
        // BTC-FS-28MAR25_27JUN25: combo → None (out of scope)
        (
            "BTC-FS-28MAR25_27JUN25",
            InstrumentKindInput {
                is_option: false,
                is_future: false, // kind="future_combo" → not a simple future
                is_perpetual: false,
                is_linear: false,
            },
            None,
        ),
    ];
    for (name, input, expected) in cases {
        assert_eq!(
            derive_instrument_kind(&input),
            expected,
            "get_instruments mapping failed for {name}"
        );
    }
}

// ─── RiskState enum ──────────────────────────────────────────────────────

/// CONTRACT.md: RiskState includes Healthy, Degraded, Maintenance, Kill
#[test]
fn test_riskstate_has_all_variants() {
    let variants = [
        RiskState::Healthy,
        RiskState::Degraded,
        RiskState::Maintenance,
        RiskState::Kill,
    ];
    assert_eq!(variants.len(), 4);

    // Each variant is distinct
    for (i, a) in variants.iter().enumerate() {
        for (j, b) in variants.iter().enumerate() {
            if i == j {
                assert_eq!(a, b);
            } else {
                assert_ne!(a, b, "variants at {i} and {j} should differ");
            }
        }
    }
}

/// RiskState derives Copy + Clone + Eq + Hash (required for use as map keys)
#[test]
fn test_riskstate_derives() {
    let state = RiskState::Healthy;
    let cloned = state;
    assert_eq!(state, cloned);

    // Hash is derivable (used in HashMap/HashSet keys)
    use std::collections::HashSet;
    let mut set = HashSet::new();
    set.insert(RiskState::Healthy);
    set.insert(RiskState::Degraded);
    assert_eq!(set.len(), 2);
}
