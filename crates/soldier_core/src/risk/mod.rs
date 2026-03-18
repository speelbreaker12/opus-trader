//! Risk assessment types and risk gate evaluation functions.
//!
//! This module provides the core risk assessment infrastructure for the trading system,
//! including exposure budgets, fee staleness checks, margin headroom gates, and pending
//! exposure tracking.
//!
//! Module exports are intentionally centralized for deterministic gate wiring.

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
