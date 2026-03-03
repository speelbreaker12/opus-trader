use super::*;

fn sample_meta(semantics: AmountSemantics) -> InstrumentMeta {
    InstrumentMeta {
        instrument_id: "BTC-PERPETUAL".to_string(),
        instrument_family: InstrumentFamily::Perpetual,
        amount_semantics: semantics,
        tick_size: 0.5,
        amount_step: 0.001,
        min_amount: 0.001,
        contract_size_usd: Some(10.0),
    }
}

#[test]
fn normalize_coin_qty_with_coin_semantics() {
    let meta = sample_meta(AmountSemantics::Coin);
    let out = match normalize_order_size(&meta, OrderSizeInput::CoinQty(0.5), 100_000.0) {
        Ok(value) => value,
        Err(err) => panic!("coin semantics must accept CoinQty: {err:?}"),
    };

    assert_eq!(out.canonical_size_kind, CanonicalSizeKind::CoinQty);
    assert_eq!(out.qty_coin, Some(0.5));
    assert_eq!(out.qty_usd, Some(50_000.0));
    assert_eq!(out.notional_usd, 50_000.0);
}

#[test]
fn normalize_usd_qty_with_usd_semantics() {
    let meta = sample_meta(AmountSemantics::Usd);
    let out = match normalize_order_size(&meta, OrderSizeInput::UsdQty(30_000.0), 100_000.0) {
        Ok(value) => value,
        Err(err) => panic!("usd semantics must accept UsdQty: {err:?}"),
    };

    assert_eq!(out.canonical_size_kind, CanonicalSizeKind::UsdQty);
    assert_eq!(out.qty_usd, Some(30_000.0));
    assert_eq!(out.qty_coin, Some(0.3));
    assert_eq!(out.notional_usd, 30_000.0);
}

#[test]
fn rejects_amount_semantics_mismatch() {
    let meta = sample_meta(AmountSemantics::Coin);
    let err = normalize_order_size(&meta, OrderSizeInput::UsdQty(10_000.0), 100_000.0)
        .expect_err("coin semantics must reject UsdQty canonical input");

    assert!(matches!(
        err,
        DomainModelError::AmountSemanticsMismatch {
            expected: AmountSemantics::Coin,
            got: CanonicalSizeKind::UsdQty
        }
    ));
}

#[test]
fn contracts_require_contract_size_usd() {
    let mut meta = sample_meta(AmountSemantics::Usd);
    meta.contract_size_usd = None;
    let err = normalize_order_size(&meta, OrderSizeInput::Contracts(3), 100_000.0)
        .expect_err("contracts input requires contract_size_usd");
    assert!(matches!(err, DomainModelError::MissingContractSizeUsd));
}

#[test]
fn intent_id_roundtrip_u64() {
    let id = IntentId::from(42_u64);
    let raw: u64 = id.into();
    assert_eq!(raw, 42);
}
