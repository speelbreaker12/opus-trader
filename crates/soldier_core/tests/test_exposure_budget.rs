//! Global exposure budget tests (S6.3).
//!
//! Contract targets:
//! - AT-226: correlation-aware portfolio budget can reject despite local pass.
//! - AT-911: reject reason for portfolio breach is GlobalExposureBudgetExceeded.
//! - AT-929: uses current + pending exposure (not current-only).

use soldier_core::risk::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetRejectReason,
    ExposureBudgetResult, evaluate_global_exposure_budget,
};

#[test]
fn test_global_exposure_budget_correlation_rejects() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 80.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 80.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 10.0,
        global_delta_limit_usd: Some(120.0),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected GlobalExposureBudgetExceeded, got {other:?}"),
    }
    assert_eq!(metrics.reject_total(), 1);
}

#[test]
fn test_global_exposure_budget_uses_current_plus_pending() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 60.0,
        pending_btc_delta_usd: 35.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 10.0,
        global_delta_limit_usd: Some(100.0),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected rejection using current+pending exposure, got {other:?}"),
    }
}

#[test]
fn test_global_exposure_budget_missing_limit_fails_closed() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 5.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Eth,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: None,
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected fail-closed rejection, got {other:?}"),
    }
    assert_eq!(metrics.reject_limit_missing_total(), 1);
}
