//! Inventory Skew gate tests (S6.1).
//!
//! Contract targets:
//! - AT-030: bias=1.0 applies exactly max tick penalty (3 ticks default).
//! - AT-043/AT-922: missing delta_limit must fail-closed with explicit reason.
//! - AT-224 intent: near-limit risk-increasing OPEN may be rejected after skew tightening.

trait TestValueExt<T> {
    fn must(self) -> T;
}

impl<T> TestValueExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

use super::*;
use crate::execution::{begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids};

fn metrics_lock() -> std::sync::MutexGuard<'static, ()> {
    crate::execution::METRICS_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner())
}

#[test]
fn test_inventory_skew_rejects_risk_increasing_near_limit() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.5,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewReject,
            ..
        } => {}
        other => panic!("expected InventorySkewReject, got {other:?}"),
    }
    assert_eq!(metrics.reject_total(), 1);
}

#[test]
fn test_inventory_skew_tick_penalty_max_is_exactly_3_ticks_at_bias_1_0() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 100.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 4.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Allowed {
            bias_ticks,
            adjusted_limit_price,
            ..
        } => {
            assert_eq!(bias_ticks, 3, "expected exactly 3 ticks at bias=1.0");
            assert!(
                (adjusted_limit_price - 98.5).abs() < 1e-9,
                "buy limit should shift down by 3 ticks (1.5): got {adjusted_limit_price}"
            );
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
}

#[test]
fn test_inventory_skew_missing_delta_limit_fails_closed() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 10.0,
        pending_delta: 0.0,
        delta_limit: None,
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 10.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
            ..
        } => {}
        other => panic!("expected InventorySkewDeltaLimitMissing, got {other:?}"),
    }
    assert_eq!(metrics.reject_delta_limit_missing(), 1);
}

#[test]
fn test_inventory_skew_sell_risk_reducing_can_pass_after_min_edge_adjustment() {
    // AT-224 coverage: for long inventory, SELL is risk-reducing and may pass after
    // adjusted min-edge re-evaluation even when baseline min-edge would fail.
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Sell,
        min_edge_usd: 2.0,
        net_edge_usd: 1.6, // fails baseline 2.0 but should pass after skew loosening
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Allowed {
            adjusted_min_edge_usd,
            adjusted_limit_price,
            bias_ticks,
            ..
        } => {
            assert!(
                adjusted_min_edge_usd < input.min_edge_usd,
                "risk-reducing SELL should loosen min edge"
            );
            assert_eq!(bias_ticks, 3, "abs(0.9) with max=3 should ceil to 3 ticks");
            assert!(
                (adjusted_limit_price - 98.5).abs() < 1e-9,
                "risk-reducing SELL should shift limit toward touch by 3 ticks"
            );
        }
        other => panic!("expected Allowed for risk-reducing SELL, got {other:?}"),
    }

    assert_eq!(metrics.allowed_total(), 1);
}

#[test]
fn test_inventory_skew_tick_penalty_large_value_clamps_safely() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 100.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 1_000.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: u8::MAX,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Allowed { bias_ticks, .. } => {
            assert_eq!(bias_ticks, u8::MAX);
        }
        other => panic!("expected Allowed with large tick penalty max, got {other:?}"),
    }
}

#[test]
fn test_at281_risk_increasing_buy_tightens_min_edge_by_45_pct() {
    // AT-281: inventory_bias=0.9 for risk-increasing BUY tightens min_edge_usd.
    // Formula: adjusted = 2.0 * (1.0 + 0.5 * 0.9) = 2.0 * 1.45 = 2.9 (~45% increase).
    // net_edge(2.5) > baseline(2.0) but net_edge(2.5) < adjusted(2.9) — tightening is sole cause.
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.5,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    match out {
        InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewReject,
            inventory_bias,
            adjusted_min_edge_usd,
            ..
        } => {
            // Causality: net_edge(2.5) passes baseline(2.0) but fails adjusted(2.9)
            assert!(
                input.net_edge_usd > input.min_edge_usd,
                "net_edge must exceed baseline — proves tightening is sole cause"
            );
            let bias = inventory_bias.must();
            assert!(
                (bias - 0.9).abs() < 1e-9,
                "expected inventory_bias=0.9, got {bias}"
            );
            let adjusted = adjusted_min_edge_usd.must();
            assert!(
                (adjusted - 2.9).abs() < 1e-9,
                "expected adjusted_min_edge=2.9, got {adjusted}"
            );
            assert!(
                input.net_edge_usd < adjusted,
                "net_edge must be below adjusted — confirms rejection"
            );
        }
        other => panic!("expected InventorySkewReject, got {other:?}"),
    }
    assert_eq!(metrics.reject_total(), 1);
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `<` flipped to `<=` on net_edge < adjusted_min_edge check.
/// net_edge == adjusted_min_edge must ALLOW.
#[test]
fn test_inventory_skew_at_exact_adjusted_threshold_allowed() {
    let mut metrics = InventorySkewMetrics::new();
    // Zero inventory → bias=0 → adjusted_min_edge == min_edge == 2.0
    // net_edge=2.0 == adjusted_min_edge=2.0 → must ALLOW (< not <=)
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    assert!(
        matches!(out, InventorySkewResult::Allowed { .. }),
        "net_edge == adjusted_min_edge must ALLOW (< not <=), got {out:?}"
    );
}

/// Catches mutation: pending_delta ignored (only current_delta used).
/// Combined delta (current + pending) must determine inventory bias.
#[test]
fn test_inventory_skew_pending_delta_contribution() {
    let mut metrics = InventorySkewMetrics::new();
    // current_delta=50, pending_delta=40 → combined=90 → bias=0.9
    // This should tighten min_edge and potentially reject.
    let input_with_pending = InventorySkewInput {
        current_delta: 50.0,
        pending_delta: 40.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.5,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input_with_pending, &mut metrics);
    assert!(
        matches!(
            out,
            InventorySkewResult::Rejected {
                reason: InventorySkewRejectReason::InventorySkewReject,
                ..
            }
        ),
        "pending_delta must contribute to bias — combined=90 should reject, got {out:?}"
    );

    // Prove it's specifically the pending_delta that causes the rejection:
    // same test but pending=0 → combined=50 → bias=0.5 → adjusted=2.5 → net==adjusted → ALLOW
    let mut metrics2 = InventorySkewMetrics::new();
    let input_without_pending = InventorySkewInput {
        current_delta: 50.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.5,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out2 = evaluate_inventory_skew(&input_without_pending, &mut metrics2);
    assert!(
        matches!(out2, InventorySkewResult::Allowed { .. }),
        "without pending_delta, combined=50 should ALLOW, got {out2:?}"
    );
}

/// Catches mutation: NaN current_delta accepted silently.
#[test]
fn test_inventory_skew_nan_input_fails_closed() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: f64::NAN,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 10.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let out = evaluate_inventory_skew(&input, &mut metrics);
    assert!(
        matches!(out, InventorySkewResult::Rejected { .. }),
        "NaN current_delta must fail-closed to REJECT, got {out:?}"
    );
}

#[test]
fn test_static_counter_missing_delta_limit_reject_increments() {
    let _guard = metrics_lock();
    let before =
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing);
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: None,
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after =
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_static_counter_nan_reject_increments() {
    let _guard = metrics_lock();
    let before = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: f64::NAN,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_static_counter_edge_below_adjusted_reject_increments() {
    let _guard = metrics_lock();
    let before = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 0.5,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_inventory_skew_graybox_emits_reject_event_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before =
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing);
    let mut metrics = InventorySkewMetrics::new();
    let mut events = Vec::new();
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: None,
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let result = evaluate_inventory_skew_with_events(&input, &mut metrics, &mut events);

    assert!(matches!(
        result,
        InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
            inventory_bias: None,
            bias_ticks: None,
            adjusted_min_edge_usd: None,
            adjusted_limit_price: None,
        }
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(metrics.reject_delta_limit_missing(), 1);
    assert_eq!(
        events,
        vec![InventorySkewEvent::Reject {
            reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing
        }]
    );
    assert_eq!(
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing),
        before
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_inventory_skew_graybox_success_emits_no_events_or_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    let mut metrics = InventorySkewMetrics::new();
    let mut events = Vec::new();
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 2.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.5,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let result = evaluate_inventory_skew_with_events(&input, &mut metrics, &mut events);

    assert!(matches!(
        result,
        InventorySkewResult::Allowed {
            inventory_bias,
            bias_ticks,
            adjusted_min_edge_usd,
            adjusted_limit_price,
        } if inventory_bias == 0.0
            && bias_ticks == 0
            && (adjusted_min_edge_usd - 2.0).abs() < 1e-9
            && (adjusted_limit_price - 100.0).abs() < 1e-9
    ));
    assert_eq!(metrics.allowed_total(), 1);
    assert_eq!(events, vec![InventorySkewEvent::Allowed]);
    assert_eq!(
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject),
        before
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_inventory_skew_wrapper_emits_structured_reject_metric_line() {
    let _guard = begin_metrics_test();
    let before =
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing);
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: None,
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };

    let result = with_intent_trace_ids(
        "intent-inventory-skew-001",
        "run-inventory-skew-001",
        || evaluate_inventory_skew(&input, &mut metrics),
    );

    assert!(matches!(
        result,
        InventorySkewResult::Rejected {
            reason: InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
            inventory_bias: None,
            bias_ticks: None,
            adjusted_min_edge_usd: None,
            adjusted_limit_price: None,
        }
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(metrics.reject_delta_limit_missing(), 1);
    assert_eq!(
        inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewDeltaLimitMissing),
        before + 1
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with("inventory_skew_reject_total")
                && line.contains("intent_id=intent-inventory-skew-001")
                && line.contains("run_id=run-inventory-skew-001")
                && line.contains("reason=InventorySkewDeltaLimitMissing")
        }),
        "expected structured inventory skew metric line, got {lines:?}"
    );
}
