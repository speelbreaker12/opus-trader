//! Durable storage: WAL ledger, trade-ID registry.

pub mod ledger;
pub mod trade_id_registry;

pub use ledger::{
    IntentRecord, LedgerAppendError, LedgerMetrics, LedgerTransitionSink, ReplayOutcome, TlsState,
    WalLedger,
};
pub use trade_id_registry::{
    InsertResult, RegistryError, RegistryMetrics, TradeIdRegistry, TradeRecord,
};
