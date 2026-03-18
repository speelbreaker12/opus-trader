//! Public Infra façade.
//!
//! This file intentionally enumerates the `soldier_infra` public surface.
//! Symbols not re-exported here remain implementation details.

pub use super::bootstrap::{
    AcknowledgedBootstrap, BootstrapResult, FullBootstrapConfig, FullBootstrapResult,
    StorageConfig, bootstrap_full, bootstrap_storage,
};
pub use super::config::{
    ALL_PARAMS, ConfigParam, EXPECTED_PARAM_COUNT, GateConfig, MissingConfigError,
    RawThresholdConfig, appendix_a_default, build_gate_config_from_raw, param_name,
    resolve_config_value,
};
pub use super::deribit::{
    DeribitInstrument, DeribitInstrumentKind, FeeCache, FeeTierData, SettlementPeriod,
    TickSizeStep, map_deribit_kind_to_input,
};
pub use super::store::{
    InsertResult, IntentRecord, LedgerAppendError, LedgerMetrics, LedgerTransitionSink,
    RegistryError, RegistryMetrics, ReplayOutcome, TlsState, TradeIdRegistry, TradeRecord,
    WalLedger, WalWriterConfig,
};
#[allow(deprecated)] // Keep legacy WAL symbols on the public facade during migration.
pub use super::wal::{
    BarrierMetrics, BuildCreatedIntentRecordError, CreatedIntentRecordInput, DurableAppendResult,
    DurableWalGate, WalBarrierConfig, build_created_intent_record,
    build_created_intent_record_from_input, durable_append, reduce_only_from_lifecycle_intent,
    try_build_created_intent_record, try_build_created_intent_record_from_input,
};
