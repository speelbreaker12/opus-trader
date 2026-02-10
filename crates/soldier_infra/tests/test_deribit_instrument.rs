//! Integration tests for Deribit instrument struct deserialization.
//!
//! Validates that `DeribitInstrument` correctly deserializes from
//! `/public/get_instruments` response payloads (CONTRACT.md AT-333).

use soldier_infra::deribit::{DeribitInstrument, DeribitInstrumentKind, SettlementPeriod};

/// BTC perpetual — the most common Deribit instrument.
const BTC_PERPETUAL_JSON: &str = r#"
{
    "instrument_name": "BTC-PERPETUAL",
    "kind": "future",
    "is_active": true,
    "settlement_period": "perpetual",
    "settlement_currency": "BTC",
    "quote_currency": "USD",
    "base_currency": "BTC",
    "tick_size": 0.5,
    "min_trade_amount": 10.0,
    "contract_size": 10.0,
    "creation_timestamp": 1534167754000,
    "is_perpetual": true
}
"#;

/// ETH option with expiration and tick_size_steps.
const ETH_OPTION_JSON: &str = r#"
{
    "instrument_name": "ETH-28MAR25-3000-C",
    "kind": "option",
    "is_active": true,
    "settlement_period": "month",
    "settlement_currency": "ETH",
    "quote_currency": "ETH",
    "base_currency": "ETH",
    "tick_size": 0.0005,
    "min_trade_amount": 1.0,
    "amount_step": 1.0,
    "contract_size": 1.0,
    "expiration_timestamp": 1743148800000,
    "creation_timestamp": 1700000000000,
    "tick_size_steps": [
        {"above_price": 0.01, "tick_size": 0.001},
        {"above_price": 0.1, "tick_size": 0.005}
    ]
}
"#;

/// Future combo (spread instrument).
const FUTURE_COMBO_JSON: &str = r#"
{
    "instrument_name": "BTC-FS-28MAR25_27JUN25",
    "kind": "future_combo",
    "is_active": true,
    "settlement_period": "quarter",
    "settlement_currency": "BTC",
    "quote_currency": "USD",
    "base_currency": "BTC",
    "tick_size": 0.5,
    "min_trade_amount": 10.0,
    "contract_size": 10.0,
    "creation_timestamp": 1700000000000,
    "expiration_timestamp": 1750896000000
}
"#;

/// AT-333: Deribit perpetual deserializes with all CONTRACT.md fields.
#[test]
fn test_btc_perpetual_deserializes() {
    let instr: DeribitInstrument =
        serde_json::from_str(BTC_PERPETUAL_JSON).expect("BTC-PERPETUAL should deserialize");

    assert_eq!(instr.instrument_name, "BTC-PERPETUAL");
    assert_eq!(instr.kind, DeribitInstrumentKind::Future);
    assert!(instr.is_active);
    assert_eq!(instr.settlement_period, SettlementPeriod::Perpetual);
    assert_eq!(instr.settlement_currency, "BTC");
    assert_eq!(instr.quote_currency, "USD");
    assert_eq!(instr.base_currency, "BTC");
}

/// AT-333: tick_size, min_trade_amount, contract_size (contract_multiplier) present.
#[test]
fn test_contract_required_fields_present() {
    let instr: DeribitInstrument =
        serde_json::from_str(BTC_PERPETUAL_JSON).expect("BTC-PERPETUAL should deserialize");

    // CONTRACT.md: tick_size
    assert!((instr.tick_size - 0.5).abs() < f64::EPSILON);
    // CONTRACT.md: min_amount
    assert!((instr.min_trade_amount - 10.0).abs() < f64::EPSILON);
    // CONTRACT.md: contract_multiplier
    assert!((instr.contract_size - 10.0).abs() < f64::EPSILON);
    assert!((instr.contract_multiplier() - 10.0).abs() < f64::EPSILON);
}

/// AT-333: amount_step defaults to None when absent from venue response.
/// Downstream sizing code (S1-004) must handle None with fail-closed logic.
#[test]
fn test_amount_step_none_when_absent() {
    let instr: DeribitInstrument =
        serde_json::from_str(BTC_PERPETUAL_JSON).expect("BTC-PERPETUAL should deserialize");

    assert!(instr.amount_step.is_none());
}

/// AT-333: amount_step is Some when explicitly provided by venue.
#[test]
fn test_amount_step_some_when_present() {
    let instr: DeribitInstrument =
        serde_json::from_str(ETH_OPTION_JSON).expect("ETH option should deserialize");

    assert_eq!(instr.amount_step, Some(1.0));
}

/// AT-333: option kind deserializes correctly.
#[test]
fn test_option_kind() {
    let instr: DeribitInstrument =
        serde_json::from_str(ETH_OPTION_JSON).expect("ETH option should deserialize");

    assert_eq!(instr.kind, DeribitInstrumentKind::Option);
    assert_eq!(instr.settlement_period, SettlementPeriod::Month);
    assert!(instr.expiration_timestamp.is_some());
}

/// AT-333: tick_size_steps deserialize when present.
#[test]
fn test_tick_size_steps() {
    let instr: DeribitInstrument =
        serde_json::from_str(ETH_OPTION_JSON).expect("ETH option should deserialize");

    assert_eq!(instr.tick_size_steps.len(), 2);
    assert!((instr.tick_size_steps[0].above_price - 0.01).abs() < f64::EPSILON);
    assert!((instr.tick_size_steps[0].tick_size - 0.001).abs() < f64::EPSILON);
    assert!((instr.tick_size_steps[1].above_price - 0.1).abs() < f64::EPSILON);
    assert!((instr.tick_size_steps[1].tick_size - 0.005).abs() < f64::EPSILON);
}

/// tick_size_steps defaults to empty vec when absent.
#[test]
fn test_tick_size_steps_default_empty() {
    let instr: DeribitInstrument =
        serde_json::from_str(BTC_PERPETUAL_JSON).expect("BTC-PERPETUAL should deserialize");

    assert!(instr.tick_size_steps.is_empty());
}

/// future_combo kind and quarter settlement period.
#[test]
fn test_future_combo_kind() {
    let instr: DeribitInstrument =
        serde_json::from_str(FUTURE_COMBO_JSON).expect("future combo should deserialize");

    assert_eq!(instr.kind, DeribitInstrumentKind::FutureCombo);
    assert_eq!(instr.settlement_period, SettlementPeriod::Quarter);
}

/// Perpetual instruments have no expiration_timestamp.
#[test]
fn test_perpetual_no_expiration() {
    let instr: DeribitInstrument =
        serde_json::from_str(BTC_PERPETUAL_JSON).expect("BTC-PERPETUAL should deserialize");

    assert!(instr.expiration_timestamp.is_none());
    assert_eq!(instr.is_perpetual, Some(true));
}

/// Pub re-export: types are accessible from soldier_infra::deribit.
#[test]
fn test_pub_reexport() {
    // This test compiles iff the re-exports are correct.
    let _kind: DeribitInstrumentKind = DeribitInstrumentKind::Future;
    let _period: SettlementPeriod = SettlementPeriod::Perpetual;
}
