//! Risk subsystem.
//!
//! Owns: fee staleness evaluation, margin headroom gating,
//! pending-exposure evaluation, global exposure budget evaluation,
//! instrument state, and `RiskState`.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation details.

mod api;
mod exposure_budget;
mod fees;
mod instrument_state;
mod margin_gate;
mod pending_exposure;
mod state;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use api::*;
