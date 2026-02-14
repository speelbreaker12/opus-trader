//! Risk assessment types.

pub mod expiry_guard;
pub mod fees;
pub mod state;

pub use expiry_guard::{
    ExpiryGuardInput, ExpiryGuardMetrics, ExpiryGuardResult, ExpiryIntentClass, ExpiryRejectReason,
    InstrumentLifecycleState, LifecycleErrorClass, TerminalLifecycleInput, TerminalLifecycleResult,
    evaluate_expiry_guard, handle_terminal_lifecycle_error,
};
pub use fees::{
    FeeCacheSnapshot, FeeEvaluation, FeeMetrics, FeeStaleness, FeeStalenessConfig,
    evaluate_fee_staleness,
};
pub use state::RiskState;
