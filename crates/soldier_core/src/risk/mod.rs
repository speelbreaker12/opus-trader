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
    exposure_budget_reject_limit_missing_total, exposure_budget_reject_total,
};
pub use fees::{
    FeeCacheSnapshot, FeeEvaluation, FeeMetrics, FeeStaleness, FeeStalenessConfig,
    evaluate_fee_staleness, fee_staleness_hard_stale_total,
};
pub use instrument_state::InstrumentState;
pub use margin_gate::{
    MarginGateDecision, MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason,
    compute_margin_mode_hint, evaluate_margin_headroom_gate, margin_gate_reject_total,
};
pub use pending_exposure::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome, ReservationId,
    pending_exposure_reject_total,
};
pub use state::RiskState;
