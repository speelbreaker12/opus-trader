//! Compile-time proof that intended facade symbols are reachable via
//! `crate::risk::{...}`.

#[allow(unused_imports)]
use crate::risk::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetRejectReason,
    ExposureBudgetResult, ExposureBudgetStaticRejectReason, FeeCacheSnapshot, FeeEvaluation,
    FeeMetrics, FeeStaleness, FeeStalenessConfig, InstrumentState, MarginGateDecision,
    MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason,
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome, ReservationId, RiskState,
    compute_margin_mode_hint, evaluate_fee_staleness, evaluate_global_exposure_budget,
    evaluate_margin_headroom_gate, exposure_budget_reject_total, fee_staleness_hard_stale_total,
    margin_gate_reject_total, pending_exposure_reject_total,
};

#[test]
fn facade_symbols_reachable_via_risk_facade() {
    let evaluation = evaluate_fee_staleness(
        &FeeCacheSnapshot {
            fee_rate: 0.0005,
            fee_model_cached_at_ts_ms: Some(1_000),
            now_ms: 1_001,
        },
        &FeeStalenessConfig::default(),
    );

    assert_eq!(evaluation.staleness, FeeStaleness::Fresh);
    assert_eq!(evaluation.risk_state, RiskState::Healthy);
}
