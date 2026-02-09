//! Durable storage: WAL ledger, trade-ID registry.

pub mod ledger;

pub use ledger::{
    IntentRecord, LedgerAppendError, LedgerMetrics, ReplayOutcome, TlsState, WalLedger,
};
