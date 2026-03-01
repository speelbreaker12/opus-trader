//! Tests for process-lifetime static rejection counters in risk modules.
//!
//! Execution-module counter coverage moved to `src/execution/*_tests.rs`.

use soldier_core::risk::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetResult,
    ExposureBudgetStaticRejectReason, FeeCacheSnapshot, FeeStaleness, FeeStalenessConfig,
    MarginGateDecision, MarginGateInput, MarginGateMetrics, PendingExposureBook,
    PendingExposureMetrics, PendingExposureResult, ReservationId, evaluate_fee_staleness,
    evaluate_global_exposure_budget, evaluate_margin_headroom_gate, exposure_budget_reject_total,
    fee_staleness_hard_stale_total, margin_gate_reject_total, pending_exposure_reject_total,
};

#[test]
fn test_fee_staleness_hard_stale_missing_ts_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: None,
        now_ms: 1_000_000,
    };
    let config = FeeStalenessConfig::default();
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_fee_staleness_hard_stale_expired_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let config = FeeStalenessConfig::default();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: Some(0),
        now_ms: (config.fee_cache_hard_s + 1) * 1000 + 1,
    };
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_fee_staleness_nan_rate_fail_closed_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let snapshot = FeeCacheSnapshot {
        fee_rate: f64::NAN,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_000_000,
    };
    let config = FeeStalenessConfig::default();
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_margin_gate_invalid_input_reject_counter() {
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: f64::NAN,
        equity_usd: 1000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let result = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(matches!(result, MarginGateDecision::Rejected { .. }));
    let after = margin_gate_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_margin_gate_over_threshold_reject_counter() {
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 800.0,
        equity_usd: 1000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let result = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(matches!(result, MarginGateDecision::Rejected { .. }));
    let after = margin_gate_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_pending_exposure_unregistered_instrument_reject_counter() {
    let before = pending_exposure_reject_total();
    let book = PendingExposureBook::new(None);
    let mut metrics = PendingExposureMetrics::new();
    let rid = match ReservationId::new("test-1") {
        Some(value) => value,
        None => panic!("unexpected invalid ReservationId for test-1"),
    };
    let result = book.reserve(&rid, "UNKNOWN", 0.0, 1.0, &mut metrics);
    assert!(matches!(result, PendingExposureResult::Rejected { .. }));
    let after = pending_exposure_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_pending_exposure_budget_exceeded_reject_counter() {
    let before = pending_exposure_reject_total();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(10.0));
    let mut metrics = PendingExposureMetrics::new();
    let rid = match ReservationId::new("test-2") {
        Some(value) => value,
        None => panic!("unexpected invalid ReservationId for test-2"),
    };
    let result = book.reserve(&rid, "BTC", 0.0, 100.0, &mut metrics);
    assert!(matches!(result, PendingExposureResult::Rejected { .. }));
    let after = pending_exposure_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_exposure_budget_missing_limit_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 0.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: None,
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_exposure_budget_over_limit_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 1_000_000.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: Some(100.0),
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_exposure_budget_nan_input_fail_closed_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: f64::NAN,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: Some(100.0),
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}
