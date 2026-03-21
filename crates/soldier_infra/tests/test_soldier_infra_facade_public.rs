//! External-surface smoke tests for `soldier_infra`.

use std::fs;
use std::path::PathBuf;

#[allow(deprecated, unused_imports)]
use soldier_infra::{
    ALL_PARAMS, AcknowledgedBootstrap, BarrierMetrics, BootstrapResult,
    BuildCreatedIntentRecordError, ConfigParam, CreatedIntentRecordInput, DeribitInstrument,
    DeribitInstrumentKind, DurableAppendResult, DurableWalGate, EXPECTED_PARAM_COUNT, FeeCache,
    FeeTierData, FullBootstrapConfig, FullBootstrapResult, GateConfig, InsertResult, IntentRecord,
    LedgerAppendError, LedgerMetrics, LedgerTransitionSink, MissingConfigError, RawThresholdConfig,
    RegistryError, RegistryMetrics, ReplayOutcome, SettlementPeriod, StorageConfig, TickSizeStep,
    TlsState, TradeIdRegistry, TradeRecord, WalBarrierConfig, WalLedger, WalWriterConfig,
    appendix_a_default, bootstrap_full, bootstrap_storage, build_created_intent_record,
    build_created_intent_record_from_input, build_gate_config_from_raw, durable_append,
    infra_bootstrapped, map_deribit_kind_to_input, param_name, reduce_only_from_lifecycle_intent,
    resolve_config_value, try_build_created_intent_record,
    try_build_created_intent_record_from_input,
};

#[test]
fn soldier_infra_facade_symbols_publicly_reachable() {
    assert_eq!(EXPECTED_PARAM_COUNT, ALL_PARAMS.len());
    assert!(!param_name(ALL_PARAMS[0]).is_empty());
    assert!(infra_bootstrapped());

    let gate_config = build_gate_config_from_raw(&RawThresholdConfig::default())
        .expect("default raw config should resolve via Appendix A defaults");
    assert!(gate_config.max_slippage_bps > 0.0);
}

#[test]
fn soldier_infra_root_stays_a_pure_facade() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let lib_rs = fs::read_to_string(manifest_dir.join("src/lib.rs")).expect("read src/lib.rs");
    let api_rs = fs::read_to_string(manifest_dir.join("src/api.rs")).expect("read src/api.rs");

    assert!(
        api_rs.contains("infra_bootstrapped"),
        "expected infra_bootstrapped to be re-exported from src/api.rs"
    );
    assert!(
        !lib_rs.contains("pub fn infra_bootstrapped"),
        "src/lib.rs should remain a pure facade root without direct public function definitions"
    );
}
