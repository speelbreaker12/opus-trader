//! Public risk facade.
//!
//! This file defines the intended public surface for `soldier_core::risk`.
//! Symbols not re-exported here remain implementation details.
//!
//! **Public:** `RiskState`, fee evaluation, margin gate, pending exposure,
//! exposure budget, `InstrumentState`.
//!
//! **Private:** `fees`, `margin_gate`, `pending_exposure`, `exposure_budget`,
//! `state`, `instrument_state`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public risk surface.

pub use super::exposure_budget::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetRejectReason,
    ExposureBudgetResult, ExposureBudgetStaticRejectReason, evaluate_global_exposure_budget,
    exposure_budget_reject_total,
};
pub use super::fees::{
    FeeCacheSnapshot, FeeEvaluation, FeeMetrics, FeeStaleness, FeeStalenessConfig,
    evaluate_fee_staleness, fee_staleness_hard_stale_total,
};
pub use super::instrument_state::InstrumentState;
pub use super::margin_gate::{
    MarginGateDecision, MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason,
    compute_margin_mode_hint, evaluate_margin_headroom_gate, margin_gate_reject_total,
};
pub use super::pending_exposure::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome, ReservationId,
    pending_exposure_reject_total,
};
pub use super::state::RiskState;
