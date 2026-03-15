//! Public execution risk façade.
//!
//! This file intentionally enumerates the `soldier_core::risk` public surface.
//! Symbols not re-exported here remain implementation details.

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
