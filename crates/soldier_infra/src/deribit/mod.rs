//! Deribit venue adapter types.
//!
//! Owns: Deribit instrument metadata types/mapping and fee-tier cache types.
//!
//! **Public:** instrument metadata, instrument kind, fee cache/tier,
//! settlement period, tick-size steps, and kind-to-input mapping.
//!
//! **Private:** `account_summary`, `public`.
//!
//! **Tests:** integration tests under `tests/` covering Deribit adapter types.
//! Facade completeness covered by the crate-root
//! `facade_completeness_contract_tests.rs`.

mod account_summary;
mod public;

// Re-export key types for ergonomic imports.
pub use account_summary::{FeeCache, FeeTierData};
pub use public::{
    DeribitInstrument, DeribitInstrumentKind, SettlementPeriod, TickSizeStep,
    map_deribit_kind_to_input,
};
