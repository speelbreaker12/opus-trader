//! Soldier infrastructure crate.
//!
//! Owns: storage bootstrap, gate/config resolution, durable storage
//! (WAL ledger and trade-ID registry), Deribit adapter types, and
//! legacy WAL durability helpers.
//!
//! Primary public API lives in `api.rs`; crate root additionally
//! exposes `infra_bootstrapped()`.
//! All other child modules are intentionally private implementation details.

#![forbid(unsafe_code)]

mod api;
mod bootstrap;
mod config;
mod deribit;
mod store;
mod wal;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use api::*;

pub fn infra_bootstrapped() -> bool {
    soldier_core::crate_bootstrapped()
}
