//! Margin headroom gate tests (S6.4).
//!
//! Contract targets:
//! - AT-227/AT-912: reject new OPEN at mm_util >= reject_opens with reason.
//! - AT-228/AT-207: mode hint enters ReduceOnly at mm_util >= reduceonly.
//! - AT-208: mode hint enters Kill at mm_util >= kill.

use soldier_core::risk::{
    MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason, MarginGateResult,
    evaluate_margin_headroom_gate,
};

#[test]
fn test_margin_gate_thresholds_block_reduceonly_kill() {
    let mut metrics = MarginGateMetrics::new();

    // 72% utilization: reject opens, mode may remain Active.
    let reject_opens = MarginGateInput {
        maintenance_margin_usd: 72_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&reject_opens, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mode_hint,
            ..
        } => assert_eq!(mode_hint, MarginGateMode::Active),
        other => panic!("expected reject-opens result, got {other:?}"),
    }

    // 90% utilization: reject opens and force ReduceOnly.
    let reduce_only = MarginGateInput {
        maintenance_margin_usd: 90_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&reduce_only, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mode_hint,
            ..
        } => assert_eq!(mode_hint, MarginGateMode::ReduceOnly),
        other => panic!("expected reduce-only result, got {other:?}"),
    }

    // 96% utilization: reject opens and force Kill.
    let kill = MarginGateInput {
        maintenance_margin_usd: 96_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&kill, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mode_hint,
            ..
        } => assert_eq!(mode_hint, MarginGateMode::Kill),
        other => panic!("expected kill result, got {other:?}"),
    }
}

#[test]
fn test_margin_gate_allows_opens_below_threshold() {
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 10_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };

    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    match out {
        MarginGateResult::Allowed { mode_hint, .. } => {
            assert_eq!(mode_hint, MarginGateMode::Active);
        }
        other => panic!("expected Allowed below reject threshold, got {other:?}"),
    }
}

#[test]
fn test_margin_gate_invalid_inputs_fail_closed() {
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: f64::NAN,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };

    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        } => {}
        other => panic!("expected fail-closed rejection, got {other:?}"),
    }
    assert_eq!(metrics.reject_total(), 1);
}

#[test]
fn test_margin_gate_non_positive_equity_fails_closed() {
    let mut metrics = MarginGateMetrics::new();

    let zero_equity = MarginGateInput {
        maintenance_margin_usd: 0.0,
        equity_usd: 0.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&zero_equity, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: None,
            mode_hint: MarginGateMode::Kill,
        } => {}
        other => panic!("expected fail-closed rejection for zero equity, got {other:?}"),
    }

    let negative_equity = MarginGateInput {
        maintenance_margin_usd: 1.0,
        equity_usd: -10.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&negative_equity, &mut metrics);
    match out {
        MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: None,
            mode_hint: MarginGateMode::Kill,
        } => {}
        other => panic!("expected fail-closed rejection for negative equity, got {other:?}"),
    }

    assert_eq!(metrics.reject_total(), 2);
    assert_eq!(metrics.allowed_total(), 0);
}
