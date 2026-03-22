//! Soldier infrastructure crate.
//!
//! Owns: storage bootstrap, gate/config resolution, durable storage
//! (WAL ledger and trade-ID registry), Deribit adapter types, and
//! legacy WAL durability helpers.
//!
//! **Public:** bootstrap + storage init, `infra_bootstrapped()`, gate/config
//! resolution, WAL ledger + trade-ID registry, Deribit adapter types,
//! legacy WAL durability helpers.
//!
//! **Private:** `bootstrap`, `config`, `deribit`, `store`, `wal`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public infra surface.

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
