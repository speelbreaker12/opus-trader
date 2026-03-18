//! External-surface smoke tests for `soldier_core::risk`.

#[allow(unused_imports)]
use soldier_core::risk::{
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
fn risk_facade_symbols_publicly_reachable() {
    let fee_eval = evaluate_fee_staleness(
        &FeeCacheSnapshot {
            fee_rate: 0.0005,
            fee_model_cached_at_ts_ms: Some(1_000),
            now_ms: 1_001,
        },
        &FeeStalenessConfig::default(),
    );
    assert_eq!(fee_eval.staleness, FeeStaleness::Fresh);

    let mut exposure_metrics = ExposureBudgetMetrics::default();
    let exposure = evaluate_global_exposure_budget(
        &ExposureBudgetInput {
            current_btc_delta_usd: 0.0,
            pending_btc_delta_usd: 0.0,
            current_eth_delta_usd: 0.0,
            pending_eth_delta_usd: 0.0,
            current_alts_delta_usd: 0.0,
            pending_alts_delta_usd: 0.0,
            candidate_bucket: ExposureBucket::Btc,
            candidate_delta_usd: 5.0,
            global_delta_limit_usd: Some(100.0),
        },
        &mut exposure_metrics,
    );
    assert!(matches!(exposure, ExposureBudgetResult::Allowed { .. }));

    let mut margin_metrics = MarginGateMetrics::default();
    let margin_input = MarginGateInput {
        maintenance_margin_usd: 10.0,
        equity_usd: 100.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
        now_ms: 1_000,
        mm_util_last_update_ts_ms: Some(1_000),
        mm_util_max_age_ms: 30_000,
    };
    let decision = evaluate_margin_headroom_gate(&margin_input, &mut margin_metrics);
    assert!(matches!(decision, MarginGateDecision::Allowed { .. }));
    assert_eq!(
        compute_margin_mode_hint(&margin_input),
        MarginGateMode::Active
    );
}
