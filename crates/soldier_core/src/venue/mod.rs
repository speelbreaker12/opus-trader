//! Venue subsystem.
//!
//! Owns: instrument cache, venue capabilities, lifecycle classification
//! and expiry guarding, and instrument-kind derivation.
//!
//! **Public:** instrument cache + TTL breach, venue capabilities +
//! feature flags, lifecycle classification + expiry guard,
//! instrument-kind derivation.
//!
//! **Private:** `cache`, `capabilities`, `lifecycle`, `types`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public venue surface.

mod api;
mod cache;
mod capabilities;
mod lifecycle;
mod types;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use api::*;
