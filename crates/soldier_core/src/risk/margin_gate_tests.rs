//! Margin headroom gate tests for event-seam + metrics parity (S6.4).
//!
//! AT targets: AT-227/AT-912/AT-228/AT-207/AT-208.

use super::*;
use crate::execution::{begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids};

fn margin_input() -> MarginGateInput {
    MarginGateInput {
        maintenance_margin_usd: 10_000.0,
        equity_usd: 100_000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
        now_ms: 1_000,
        mm_util_last_update_ts_ms: Some(1_000),
        mm_util_max_age_ms: 30_000,
    }
}

#[test]
fn test_margin_gate_graybox_reject_emits_event_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let mut events = Vec::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 80_000.0,
        ..margin_input()
    };

    let result = evaluate_margin_headroom_gate_with_events(&input, &mut metrics, &mut events);

    assert!(matches!(
        result,
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        }
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(
        events,
        vec![MarginGateEvent::Reject {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens
        }]
    );
    assert_eq!(margin_gate_reject_total(), before);

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_margin_gate_graybox_allow_emits_allowed_event_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let mut events = Vec::new();
    let input = margin_input();

    let result = evaluate_margin_headroom_gate_with_events(&input, &mut metrics, &mut events);

    assert_eq!(metrics.allowed_total(), 1);
    assert!(matches!(
        result,
        MarginGateDecision::Allowed { mm_util } if (mm_util - 0.1).abs() < f64::EPSILON
    ));
    assert_eq!(events, vec![MarginGateEvent::Allowed]);
    assert_eq!(margin_gate_reject_total(), before);

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_margin_gate_wrapper_emits_structured_reject_metric_line() {
    let _guard = begin_metrics_test();
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 80_000.0,
        ..margin_input()
    };

    let result = with_intent_trace_ids("intent-margin-gate-001", "run-margin-gate-001", || {
        evaluate_margin_headroom_gate(&input, &mut metrics)
    });

    assert!(matches!(
        result,
        MarginGateDecision::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            ..
        }
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(margin_gate_reject_total(), before + 1);

    let lines = take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with("margin_gate_reject_total")
                && line.contains("reason=MarginHeadroomRejectOpens")
                && line.contains("intent_id=intent-margin-gate-001")
                && line.contains("run_id=run-margin-gate-001")
        }),
        "expected structured reject metric line with reason, got {lines:?}"
    );
}
