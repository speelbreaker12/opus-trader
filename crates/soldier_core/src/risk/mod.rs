//! Risk assessment types.
//! Module exports are intentionally centralized for deterministic gate wiring.

pub mod exposure_budget;
pub mod fees;
pub mod instrument_state;
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
pub use state::RiskState;
