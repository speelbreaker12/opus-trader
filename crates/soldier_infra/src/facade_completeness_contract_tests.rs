//! Compile-time proof that intended facade symbols are reachable via
//! `crate::{...}`.

#[allow(deprecated, unused_imports)]
use crate::{
    ALL_PARAMS, AcknowledgedBootstrap, BarrierMetrics, BootstrapResult,
    BuildCreatedIntentRecordError, ConfigParam, CreatedIntentRecordInput, DeribitInstrument,
    DeribitInstrumentKind, DurableAppendResult, DurableWalGate, EXPECTED_PARAM_COUNT, FeeCache,
    FeeTierData, FullBootstrapConfig, FullBootstrapResult, GateConfig, InsertResult, IntentRecord,
    LedgerAppendError, LedgerMetrics, LedgerTransitionSink, MissingConfigError, RawThresholdConfig,
    RegistryError, RegistryMetrics, ReplayOutcome, SettlementPeriod, StorageConfig, TickSizeStep,
    TlsState, TradeIdRegistry, TradeRecord, WalBarrierConfig, WalLedger, WalWriterConfig,
    appendix_a_default, bootstrap_full, bootstrap_storage, build_created_intent_record,
    build_created_intent_record_from_input, build_gate_config_from_raw, durable_append,
    map_deribit_kind_to_input, param_name, reduce_only_from_lifecycle_intent, resolve_config_value,
    try_build_created_intent_record, try_build_created_intent_record_from_input,
};

#[test]
fn facade_symbols_reachable_via_soldier_infra_facade() {
    assert_eq!(EXPECTED_PARAM_COUNT, ALL_PARAMS.len());
    assert!(!param_name(ALL_PARAMS[0]).is_empty());
}
