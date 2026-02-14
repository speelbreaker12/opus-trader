//! Tests for order-type preflight guard per CONTRACT.md §1.4.4.
//!
//! AT-013, AT-016, AT-017, AT-018, AT-019, AT-913, AT-914, AT-915, AT-916.

use soldier_core::execution::{
    OrderType, PostOnlyInput, PreflightInput, PreflightMetrics, PreflightReject, PreflightResult,
    Side, preflight_intent, preflight_reject_total, take_execution_metric_lines,
    with_intent_trace_ids,
};
use soldier_core::venue::InstrumentKind;

/// Helper: build a PreflightInput with defaults (limit order, no triggers, no linked).
fn limit_input(kind: InstrumentKind) -> PreflightInput<'static> {
    PreflightInput {
        instrument_kind: kind,
        order_type: OrderType::Limit,
        has_trigger: false,
        linked_order_type: None,
        linked_orders_allowed: false,
        post_only_input: None,
    }
}

// ─── Limit orders allowed ───────────────────────────────────────────────

#[test]
fn test_limit_order_option_allowed() {
    let input = limit_input(InstrumentKind::Option);
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
    assert_eq!(m.reject_total(), 0);
}

#[test]
fn test_limit_order_perpetual_allowed() {
    let input = limit_input(InstrumentKind::Perpetual);
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

#[test]
fn test_limit_order_linear_future_allowed() {
    let input = limit_input(InstrumentKind::LinearFuture);
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

#[test]
fn test_limit_order_inverse_future_allowed() {
    let input = limit_input(InstrumentKind::InverseFuture);
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

// ─── AT-016: Market order on options → reject ───────────────────────────

#[test]
fn test_at016_market_order_option_rejected() {
    let input = PreflightInput {
        order_type: OrderType::Market,
        ..limit_input(InstrumentKind::Option)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeMarketForbidden)
    );
}

// ─── AT-017: Market order on perpetual → reject ─────────────────────────

#[test]
fn test_at017_market_order_perpetual_rejected() {
    let input = PreflightInput {
        order_type: OrderType::Market,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeMarketForbidden)
    );
}

// ─── AT-913: Market order rejected with correct reason ──────────────────

#[test]
fn test_at913_market_order_reason_matches() {
    // Test across all instrument kinds
    let kinds = [
        InstrumentKind::Option,
        InstrumentKind::Perpetual,
        InstrumentKind::LinearFuture,
        InstrumentKind::InverseFuture,
    ];
    for kind in kinds {
        let input = PreflightInput {
            order_type: OrderType::Market,
            ..limit_input(kind)
        };
        let mut m = PreflightMetrics::new();
        match preflight_intent(&input, &mut m) {
            PreflightResult::Rejected(PreflightReject::OrderTypeMarketForbidden) => {}
            other => panic!("kind={kind:?}: expected MarketForbidden, got {other:?}"),
        }
    }
}

// ─── AT-018: Stop-market on options → reject ────────────────────────────

#[test]
fn test_at018_stop_market_option_rejected() {
    let input = PreflightInput {
        order_type: OrderType::StopMarket,
        ..limit_input(InstrumentKind::Option)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeStopForbidden)
    );
}

// ─── AT-019: Stop-market on perpetual → reject ──────────────────────────

#[test]
fn test_at019_stop_market_perpetual_rejected() {
    let input = PreflightInput {
        order_type: OrderType::StopMarket,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeStopForbidden)
    );
}

// ─── AT-914: Stop orders rejected with correct reason ───────────────────

#[test]
fn test_at914_stop_limit_rejected() {
    let input = PreflightInput {
        order_type: OrderType::StopLimit,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeStopForbidden)
    );
}

#[test]
fn test_at914_trigger_field_presence_rejected() {
    // Even with order_type=limit, if trigger fields are present → reject
    let input = PreflightInput {
        has_trigger: true,
        ..limit_input(InstrumentKind::Option)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeStopForbidden)
    );
}

#[test]
fn test_at914_stop_market_all_kinds() {
    let kinds = [
        InstrumentKind::Option,
        InstrumentKind::Perpetual,
        InstrumentKind::LinearFuture,
        InstrumentKind::InverseFuture,
    ];
    for kind in kinds {
        let input = PreflightInput {
            order_type: OrderType::StopMarket,
            ..limit_input(kind)
        };
        let mut m = PreflightMetrics::new();
        match preflight_intent(&input, &mut m) {
            PreflightResult::Rejected(PreflightReject::OrderTypeStopForbidden) => {}
            other => panic!("kind={kind:?}: expected StopForbidden, got {other:?}"),
        }
    }
}

// ─── AT-915: Linked orders rejected ─────────────────────────────────────

#[test]
fn test_at915_linked_order_rejected_default() {
    let input = PreflightInput {
        linked_order_type: Some("one_cancels_other"),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::LinkedOrderTypeForbidden)
    );
}

// ─── AT-004 / AT-013: Linked orders gating ──────────────────────────────

#[test]
fn test_at004_linked_order_option_always_rejected() {
    // Options: linked orders always forbidden, even if capability matrix allows.
    let input = PreflightInput {
        linked_order_type: Some("one_cancels_other"),
        linked_orders_allowed: true,
        ..limit_input(InstrumentKind::Option)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::LinkedOrderTypeForbidden)
    );
}

#[test]
fn test_linked_order_perp_both_flags_allowed() {
    // Futures/perps: allowed when evaluated capabilities permit.
    let input = PreflightInput {
        linked_order_type: Some("one_cancels_other"),
        linked_orders_allowed: true,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

#[test]
fn test_linked_order_perp_only_supported_rejected() {
    // Capabilities matrix denies linked orders -> reject (fail closed).
    let input = PreflightInput {
        linked_order_type: Some("one_cancels_other"),
        linked_orders_allowed: false,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::LinkedOrderTypeForbidden)
    );
}

#[test]
fn test_linked_order_perp_only_enabled_rejected() {
    // Any false outcome from capabilities matrix remains rejected.
    let input = PreflightInput {
        linked_order_type: Some("one_cancels_other"),
        linked_orders_allowed: false,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::LinkedOrderTypeForbidden)
    );
}

#[test]
fn test_linked_order_linear_future_both_flags_allowed() {
    let input = PreflightInput {
        linked_order_type: Some("oco"),
        linked_orders_allowed: true,
        ..limit_input(InstrumentKind::LinearFuture)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

// ─── No linked_order_type → no check ────────────────────────────────────

#[test]
fn test_no_linked_order_type_passes() {
    // linked_order_type is None → no linked-order check at all
    let input = PreflightInput {
        linked_order_type: None,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

// ─── AT-916: Post-only crossing rejected ───────────────────────────────

#[test]
fn test_at916_post_only_buy_crossing_rejected() {
    let input = PreflightInput {
        instrument_kind: InstrumentKind::Perpetual,
        post_only_input: Some(PostOnlyInput {
            post_only: true,
            side: Side::Buy,
            limit_price: 100.0,
            best_ask: Some(100.0),
            best_bid: None,
        }),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::PostOnlyWouldCross)
    );
}

#[test]
fn test_at916_post_only_non_crossing_allowed() {
    let input = PreflightInput {
        instrument_kind: InstrumentKind::Perpetual,
        post_only_input: Some(PostOnlyInput {
            post_only: true,
            side: Side::Buy,
            limit_price: 99.0,
            best_ask: Some(100.0),
            best_bid: None,
        }),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(preflight_intent(&input, &mut m), PreflightResult::Allowed);
}

#[test]
fn test_at916_post_only_sell_crossing_rejected() {
    let input = PreflightInput {
        instrument_kind: InstrumentKind::Perpetual,
        post_only_input: Some(PostOnlyInput {
            post_only: true,
            side: Side::Sell,
            limit_price: 100.0,
            best_ask: None,
            best_bid: Some(100.0),
        }),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::PostOnlyWouldCross)
    );
}

// ─── Metrics ────────────────────────────────────────────────────────────

#[test]
fn test_metrics_market_forbidden_counter() {
    let mut m = PreflightMetrics::new();
    let input = PreflightInput {
        order_type: OrderType::Market,
        ..limit_input(InstrumentKind::Option)
    };
    let _ = preflight_intent(&input, &mut m);
    let _ = preflight_intent(&input, &mut m);
    assert_eq!(m.market_forbidden_total(), 2);
    assert_eq!(m.reject_total(), 2);
}

#[test]
fn test_metrics_stop_forbidden_counter() {
    let mut m = PreflightMetrics::new();
    let input = PreflightInput {
        order_type: OrderType::StopMarket,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let _ = preflight_intent(&input, &mut m);
    assert_eq!(m.stop_forbidden_total(), 1);
}

#[test]
fn test_metrics_linked_forbidden_counter() {
    let mut m = PreflightMetrics::new();
    let input = PreflightInput {
        linked_order_type: Some("oco"),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let _ = preflight_intent(&input, &mut m);
    assert_eq!(m.linked_forbidden_total(), 1);
}

#[test]
fn test_metrics_post_only_cross_counter() {
    let mut m = PreflightMetrics::new();
    let input = PreflightInput {
        instrument_kind: InstrumentKind::Perpetual,
        post_only_input: Some(PostOnlyInput {
            post_only: true,
            side: Side::Buy,
            limit_price: 100.0,
            best_ask: Some(100.0),
            best_bid: None,
        }),
        ..limit_input(InstrumentKind::Perpetual)
    };
    let _ = preflight_intent(&input, &mut m);
    assert_eq!(m.post_only_would_cross_total(), 1);
}

#[test]
fn test_metrics_no_reject_on_allowed() {
    let mut m = PreflightMetrics::new();
    let input = limit_input(InstrumentKind::Perpetual);
    let _ = preflight_intent(&input, &mut m);
    assert_eq!(m.reject_total(), 0);
}

// ─── Priority: market checked before stop ───────────────────────────────

#[test]
fn test_market_checked_before_trigger() {
    // If both market and trigger are set, market rejection takes priority
    let input = PreflightInput {
        order_type: OrderType::Market,
        has_trigger: true,
        ..limit_input(InstrumentKind::Option)
    };
    let mut m = PreflightMetrics::new();
    assert_eq!(
        preflight_intent(&input, &mut m),
        PreflightResult::Rejected(PreflightReject::OrderTypeMarketForbidden)
    );
}

// ─── Deterministic rejection ────────────────────────────────────────────

#[test]
fn test_deterministic_same_input_same_result() {
    let input = PreflightInput {
        order_type: OrderType::StopLimit,
        ..limit_input(InstrumentKind::InverseFuture)
    };
    let mut m1 = PreflightMetrics::new();
    let mut m2 = PreflightMetrics::new();
    let r1 = preflight_intent(&input, &mut m1);
    let r2 = preflight_intent(&input, &mut m2);
    assert_eq!(r1, r2);
}

#[test]
fn test_preflight_emits_structured_reject_metric_line() {
    let intent_id = "intent-preflight-001";
    let run_id = "run-preflight-001";
    let _ = take_execution_metric_lines();

    let input = PreflightInput {
        order_type: OrderType::Market,
        ..limit_input(InstrumentKind::Perpetual)
    };
    let mut metrics = PreflightMetrics::new();

    let result =
        with_intent_trace_ids(intent_id, run_id, || preflight_intent(&input, &mut metrics));
    assert_eq!(
        result,
        PreflightResult::Rejected(PreflightReject::OrderTypeMarketForbidden)
    );

    let after = preflight_reject_total(PreflightReject::OrderTypeMarketForbidden);
    assert!(after >= 1, "counter must be non-zero after a reject");

    let lines = take_execution_metric_lines();
    let tagged_lines = lines
        .iter()
        .filter(|line| {
            line.starts_with("preflight_reject_total")
                && line.contains("reason=OrderTypeMarketForbidden")
                && line.contains(&format!("intent_id={intent_id}"))
                && line.contains(&format!("run_id={run_id}"))
        })
        .count();
    assert_eq!(
        tagged_lines, 1,
        "expected exactly one tagged preflight metric line, got {lines:?}"
    );
    assert!(
        lines
            .iter()
            .any(|line| line.starts_with("preflight_reject_total")),
        "expected structured preflight metric line, got {lines:?}"
    );
}
