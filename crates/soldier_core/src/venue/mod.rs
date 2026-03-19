//! Venue subsystem.
//!
//! Owns: instrument cache, venue capabilities, lifecycle classification
//! and expiry guarding, and instrument-kind derivation.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation details.

mod api;
mod cache;
mod capabilities;
mod lifecycle;
mod types;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use api::*;
