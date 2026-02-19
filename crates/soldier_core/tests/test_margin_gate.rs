//! Margin headroom gate tests (S6.4).
//!
//! Contract targets:
//! - AT-227/AT-912: reject new OPEN at mm_util >= reject_opens with reason.
//! - AT-228/AT-207: mode hint enters ReduceOnly at mm_util >= reduceonly.
//! - AT-208: mode hint enters Kill at mm_util >= kill.

use soldier_core::risk::{
    MarginGateDecision, MarginGateInput, MarginGateMetrics, MarginGateMode, MarginGateRejectReason,
    compute_margin_mode_hint, evaluate_margin_headroom_gate,
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
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        } => {
            let mode = compute_margin_mode_hint(&reject_opens);
            assert_eq!(mode, MarginGateMode::Active);
        }
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
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        } => {
            let mode = compute_margin_mode_hint(&reduce_only);
            assert_eq!(mode, MarginGateMode::ReduceOnly);
        }
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
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        } => {
            let mode = compute_margin_mode_hint(&kill);
            assert_eq!(mode, MarginGateMode::Kill);
        }
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
        MarginGateDecision::Allowed { .. } => {
            let mode = compute_margin_mode_hint(&input);
            assert_eq!(mode, MarginGateMode::Active);
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
        MarginGateDecision::Rejected {
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
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: None,
        } => {
            assert_eq!(compute_margin_mode_hint(&zero_equity), MarginGateMode::Kill);
        }
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
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: None,
        } => {
            assert_eq!(
                compute_margin_mode_hint(&negative_equity),
                MarginGateMode::Kill
            );
        }
        other => panic!("expected fail-closed rejection for negative equity, got {other:?}"),
    }

    assert_eq!(metrics.reject_total(), 2);
    assert_eq!(metrics.allowed_total(), 0);
}

#[test]
fn test_margin_gate_tiny_positive_equity_uses_actual_ratio() {
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 1e-10,
        equity_usd: 1e-12,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };

    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    match out {
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: Some(mm_util),
        } => {
            assert!(
                mm_util > 1.0,
                "tiny positive equity must not be clamped to a larger denominator"
            );
            assert_eq!(compute_margin_mode_hint(&input), MarginGateMode::Kill);
        }
        other => panic!("expected tiny-equity rejection, got {other:?}"),
    }

    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(metrics.allowed_total(), 0);
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `>=` flipped to `>` on mm_util threshold check.
/// At exactly reject_opens threshold, mm_util == reject_opens must REJECT (>= not >).
#[test]
fn test_margin_at_exact_reject_opens_threshold_rejected() {
    let mut metrics = MarginGateMetrics::new();
    // mm_util = 70_000 / 100_000 = 0.70 == reject_opens threshold
    let input = MarginGateInput {
        maintenance_margin_usd: 70_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(
        matches!(out, MarginGateDecision::Rejected { .. }),
        "mm_util == reject_opens must REJECT (>= not >), got {out:?}"
    );
}

/// Catches mutation: one tick below threshold must ALLOW.
#[test]
fn test_margin_one_tick_below_reject_opens_allowed() {
    let mut metrics = MarginGateMetrics::new();
    // mm_util = 69_999 / 100_000 = 0.69999 < 0.70 threshold
    let input = MarginGateInput {
        maintenance_margin_usd: 69_999.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(
        matches!(out, MarginGateDecision::Allowed { .. }),
        "mm_util < reject_opens by 0.00001 must ALLOW, got {out:?}"
    );
}

/// Catches mutation: NaN equity accepted silently.
#[test]
fn test_margin_nan_equity_fails_closed() {
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 10_000.0,
        equity_usd: f64::NAN,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let out = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(
        matches!(out, MarginGateDecision::Rejected { .. }),
        "NaN equity must fail-closed to REJECT, got {out:?}"
    );
}

// ─── Dedicated compute_margin_mode_hint tests ─────────────────────────

/// Table-driven: Active below reduceonly, ReduceOnly at reduceonly, Kill at kill.
#[test]
fn test_compute_margin_mode_hint_thresholds() {
    let cases = vec![
        // (mm_usd, equity_usd, expected_mode, description)
        (
            10_000.0,
            100_000.0,
            MarginGateMode::Active,
            "10% util → Active",
        ),
        (
            84_999.0,
            100_000.0,
            MarginGateMode::Active,
            "just below reduceonly → Active",
        ),
        (
            85_000.0,
            100_000.0,
            MarginGateMode::ReduceOnly,
            "exact reduceonly → ReduceOnly",
        ),
        (
            90_000.0,
            100_000.0,
            MarginGateMode::ReduceOnly,
            "between reduceonly and kill → ReduceOnly",
        ),
        (
            95_000.0,
            100_000.0,
            MarginGateMode::Kill,
            "exact kill → Kill",
        ),
    ];

    for (mm_usd, equity_usd, expected, desc) in cases {
        let input = MarginGateInput {
            maintenance_margin_usd: mm_usd,
            equity_usd,
            mm_util_reject_opens: 0.70,
            mm_util_reduceonly: 0.85,
            mm_util_kill: 0.95,
        };
        let mode = compute_margin_mode_hint(&input);
        assert_eq!(mode, expected, "case: {desc}");
    }
}

/// Proves fail-closed behavior: invalid inputs → Kill.
#[test]
fn test_compute_margin_mode_hint_invalid_inputs_fail_closed_to_kill() {
    let cases = vec![
        (
            f64::NAN,
            100_000.0,
            0.70,
            0.85,
            0.95,
            "NaN maintenance margin",
        ),
        (10_000.0, f64::NAN, 0.70, 0.85, 0.95, "NaN equity"),
        (10_000.0, -1.0, 0.70, 0.85, 0.95, "negative equity"),
        (10_000.0, 0.0, 0.70, 0.85, 0.95, "zero equity"),
        (
            -1.0,
            100_000.0,
            0.70,
            0.85,
            0.95,
            "negative maintenance margin",
        ),
        (
            10_000.0,
            100_000.0,
            0.95,
            0.85,
            0.70,
            "invalid threshold ordering",
        ),
        (
            10_000.0,
            100_000.0,
            f64::NAN,
            0.85,
            0.95,
            "NaN reject_opens threshold",
        ),
    ];

    for (mm_usd, equity_usd, reject, reduce, kill, desc) in cases {
        let input = MarginGateInput {
            maintenance_margin_usd: mm_usd,
            equity_usd,
            mm_util_reject_opens: reject,
            mm_util_reduceonly: reduce,
            mm_util_kill: kill,
        };
        let mode = compute_margin_mode_hint(&input);
        assert_eq!(
            mode,
            MarginGateMode::Kill,
            "case: {desc} — must fail-closed to Kill"
        );
    }
}
