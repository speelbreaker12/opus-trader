//! Risk assessment types and risk gate evaluation functions.
//!
//! This module provides the core risk assessment infrastructure for the trading system,
//! including exposure budgets, fee staleness checks, margin headroom gates, and pending
//! exposure tracking.
//!
//! Module exports are intentionally centralized for deterministic gate wiring.

pub mod exposure_budget;
pub mod fees;
pub mod instrument_state;
pub mod margin_gate;
pub mod pending_exposure;
pub mod state;

pub use exposure_budget::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetRejectReason,
    ExposureBudgetResult, evaluate_global_exposure_budget,
};
pub use fees::{
    FeeCacheSnapshot, FeeEvaluation, FeeMetrics, FeeStaleness, FeeStalenessConfig,
    evaluate_fee_staleness,
};
pub use instrument_state::InstrumentState;
pub use margin_gate::{
    MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason, MarginGateResult,
    evaluate_margin_headroom_gate,
};
pub use pending_exposure::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome,
};
pub use state::RiskState;
