//! Durable storage subsystem.
//!
//! Owns: WAL ledger append/replay and TLS state persistence,
//! and trade-ID registry.
//!
//! **Public:** WAL ledger, intent record, TLS state, trade-ID registry,
//! and associated config/metrics/error types.
//!
//! **Private:** `ledger`, `trade_id_registry`.
//!
//! **Tests:** unit tests alongside implementation files; integration tests
//! under `tests/` covering the public store surface.
//! Facade completeness covered by the crate-root
//! `facade_completeness_contract_tests.rs`.

mod ledger;
mod trade_id_registry;

pub use ledger::{
    IntentRecord, LedgerAppendError, LedgerMetrics, LedgerTransitionSink, ReplayOutcome, TlsState,
    WalLedger, WalWriterConfig,
};
pub use trade_id_registry::{
    InsertResult, RegistryError, RegistryMetrics, TradeIdRegistry, TradeRecord,
};
