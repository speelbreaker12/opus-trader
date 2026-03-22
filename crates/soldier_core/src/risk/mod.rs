//! Risk subsystem.
//!
//! Owns: fee staleness evaluation, margin headroom gating,
//! pending-exposure evaluation, global exposure budget evaluation,
//! instrument state, and `RiskState`.
//!
//! **Public:** `RiskState`, fee evaluation, margin gate, pending exposure,
//! exposure budget, `InstrumentState`.
//!
//! **Private:** `exposure_budget`, `fees`, `instrument_state`,
//! `margin_gate`, `pending_exposure`, `state`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public risk surface.

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
