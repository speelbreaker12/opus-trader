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

#[test]
fn test_global_exposure_budget_allowed_returns_portfolio_delta() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 40.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 30.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 10.0,
        global_delta_limit_usd: Some(100.0),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Allowed {
            portfolio_delta_usd,
            combined_btc_delta_usd,
            combined_eth_delta_usd,
            combined_alts_delta_usd,
        } => {
            // combined_btc=50, combined_eth=30, combined_alts=0
            // variance = 50^2 + 30^2 + 2*0.8*50*30 = 2500 + 900 + 2400 = 5800
            // sqrt(5800) ≈ 76.16
            assert!(
                portfolio_delta_usd > 76.0 && portfolio_delta_usd < 77.0,
                "expected ~76.16, got {portfolio_delta_usd}"
            );
            assert!((combined_btc_delta_usd - 50.0).abs() < 1e-9);
            assert!((combined_eth_delta_usd - 30.0).abs() < 1e-9);
            assert!((combined_alts_delta_usd - 0.0).abs() < 1e-9);
        }
        other => panic!("expected Allowed with portfolio_delta_usd, got {other:?}"),
    }
    assert_eq!(metrics.allowed_total(), 1);
}

#[test]
fn test_global_exposure_budget_non_finite_portfolio_fails_closed() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: f64::MAX,
        pending_btc_delta_usd: f64::MAX,
        current_eth_delta_usd: f64::MAX,
        pending_eth_delta_usd: f64::MAX,
        current_alts_delta_usd: f64::MAX,
        pending_alts_delta_usd: f64::MAX,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: f64::MAX,
        global_delta_limit_usd: Some(f64::MAX),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            portfolio_delta_usd: Some(v),
            ..
        } => assert!(!v.is_finite()),
        other => panic!("expected fail-closed rejection on non-finite portfolio, got {other:?}"),
    }
    assert_eq!(metrics.reject_total(), 1);
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `>` flipped to `>=` on portfolio vs limit check.
/// Portfolio delta exactly at limit must be Allowed.
#[test]
fn test_global_exposure_budget_at_exact_limit_allowed() {
    let mut metrics = ExposureBudgetMetrics::new();
    // Use a single bucket so portfolio_delta == abs(combined_btc).
    // With only BTC, portfolio = sqrt(btc^2) = abs(btc).
    // current=90, candidate=10 → combined_btc=100, portfolio=100, limit=100.
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 90.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 10.0,
        global_delta_limit_usd: Some(100.0),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(
        matches!(out, ExposureBudgetResult::Allowed { .. }),
        "portfolio == limit must ALLOW (> not >=), got {out:?}"
    );
}

/// Catches mutation: correlation multiplier hardcoded to 1.0.
/// With two correlated buckets, portfolio_delta must be less than simple sum.
#[test]
fn test_global_exposure_budget_correlation_non_trivial() {
    let mut metrics = ExposureBudgetMetrics::new();
    // BTC=50, ETH=50, corr=0.8
    // variance = 50^2 + 50^2 + 2*0.8*50*50 = 2500+2500+4000 = 9000
    // portfolio = sqrt(9000) ≈ 94.87 (not 100 which would be simple sum)
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 50.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 50.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 0.0,
        global_delta_limit_usd: Some(100.0),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    match out {
        ExposureBudgetResult::Allowed {
            portfolio_delta_usd,
            ..
        } => {
            assert!(
                (portfolio_delta_usd - 94.868).abs() < 1.0,
                "expected ~94.87 (correlation-adjusted), got {portfolio_delta_usd}"
            );
            assert!(
                portfolio_delta_usd < 100.0,
                "correlation-adjusted portfolio must be < simple sum (100)"
            );
        }
        other => panic!("expected Allowed with correlation adjustment, got {other:?}"),
    }
}

/// Catches mutation: NaN limit accepted silently.
#[test]
fn test_global_exposure_budget_nan_limit_fails_closed() {
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 5.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: Some(f64::NAN),
    };

    let out = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(
        matches!(
            out,
            ExposureBudgetResult::Rejected {
                reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
                ..
            }
        ),
        "NaN limit must fail-closed to REJECT, got {out:?}"
    );
}
