//! Tests for post-only crossing guard per CONTRACT.md §1.4.4 C.
//!
//! AT-916: post_only == true and limit price would cross → reject.

use super::*;
use crate::execution::{begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids};

fn metrics_lock() -> std::sync::MutexGuard<'static, ()> {
    crate::execution::METRICS_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner())
}

/// Helper: build a post-only buy input.
fn post_only_buy(limit_price: f64, best_ask: Option<f64>) -> PostOnlyInput {
    PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price,
        best_ask,
        best_bid: None,
    }
}

/// Helper: build a post-only sell input.
fn post_only_sell(limit_price: f64, best_bid: Option<f64>) -> PostOnlyInput {
    PostOnlyInput {
        post_only: true,
        side: Side::Sell,
        limit_price,
        best_ask: None,
        best_bid,
    }
}

// ─── AT-916: Post-only crossing rejected ────────────────────────────────

#[test]
fn test_at916_buy_crosses_at_ask_rejected() {
    // Buy limit_price == best_ask → crosses (would take the ask)
    let input = post_only_buy(100.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
}

#[test]
fn test_at916_buy_above_ask_rejected() {
    // Buy limit_price > best_ask → crosses
    let input = post_only_buy(101.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
}

#[test]
fn test_at916_sell_crosses_at_bid_rejected() {
    // Sell limit_price == best_bid → crosses (would take the bid)
    let input = post_only_sell(100.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
}

#[test]
fn test_at916_sell_below_bid_rejected() {
    // Sell limit_price < best_bid → crosses
    let input = post_only_sell(99.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
}

// ─── Non-crossing allowed ───────────────────────────────────────────────

#[test]
fn test_buy_below_ask_allowed() {
    // Buy limit_price < best_ask → does not cross (rests on book)
    let input = post_only_buy(99.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

#[test]
fn test_sell_above_bid_allowed() {
    // Sell limit_price > best_bid → does not cross (rests on book)
    let input = post_only_sell(101.0, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

// ─── Empty book → allowed ───────────────────────────────────────────────

#[test]
fn test_buy_no_ask_allowed() {
    // No asks on book → cannot cross
    let input = post_only_buy(100.0, None);
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

#[test]
fn test_sell_no_bid_allowed() {
    // No bids on book → cannot cross
    let input = post_only_sell(100.0, None);
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

// ─── Not post_only → skip check ─────────────────────────────────────────

#[test]
fn test_not_post_only_always_allowed() {
    // post_only=false → no check, even if price would cross
    let input = PostOnlyInput {
        post_only: false,
        side: Side::Buy,
        limit_price: 200.0,
        best_ask: Some(100.0),
        best_bid: None,
    };
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
    assert_eq!(m.reject_total(), 0);
}

// ─── Metrics ────────────────────────────────────────────────────────────

#[test]
fn test_metrics_reject_counter_increments() {
    let mut m = PostOnlyMetrics::new();
    assert_eq!(m.reject_total(), 0);

    let input = post_only_buy(100.0, Some(100.0));
    let _ = check_post_only(&input, &mut m);
    assert_eq!(m.reject_total(), 1);

    let _ = check_post_only(&input, &mut m);
    assert_eq!(m.reject_total(), 2);
}

#[test]
fn test_metrics_no_increment_on_allowed() {
    let mut m = PostOnlyMetrics::new();
    let input = post_only_buy(99.0, Some(100.0));
    let _ = check_post_only(&input, &mut m);
    assert_eq!(m.reject_total(), 0);
}

// ─── Determinism ────────────────────────────────────────────────────────

#[test]
fn test_deterministic_result() {
    let input = post_only_sell(99.0, Some(100.0));
    let mut m1 = PostOnlyMetrics::new();
    let mut m2 = PostOnlyMetrics::new();
    let r1 = check_post_only(&input, &mut m1);
    let r2 = check_post_only(&input, &mut m2);
    assert_eq!(r1, r2);
}

// ─── Edge: tiny spread ──────────────────────────────────────────────────

#[test]
fn test_buy_just_below_ask_allowed() {
    // Price is 0.01 below ask → does not cross
    let input = post_only_buy(99.99, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

#[test]
fn test_sell_just_above_bid_allowed() {
    // Price is 0.01 above bid → does not cross
    let input = post_only_sell(100.01, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Allowed);
}

// ─── NaN/Inf fail-closed (Q3 retrofit) ─────────────────────────────────

/// NaN limit_price must be rejected (fail-closed).
/// IEEE 754: NaN >= ask returns false, so without the guard NaN would pass.
#[test]
fn test_post_only_nan_limit_price_rejected() {
    let input = post_only_buy(f64::NAN, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// NaN best_ask with finite limit_price must be rejected (fail-closed).
/// Catches guard-only-limit-price mutation (must also guard book prices).
#[test]
fn test_post_only_nan_best_ask_rejected() {
    let input = post_only_buy(99.0, Some(f64::NAN));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// NaN best_bid with finite limit_price must be rejected (fail-closed).
#[test]
fn test_post_only_nan_best_bid_rejected() {
    let input = post_only_sell(101.0, Some(f64::NAN));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// +Inf limit_price must be rejected (fail-closed).
/// Catches is_nan-only mutation (must use is_finite, not is_nan).
#[test]
fn test_post_only_inf_limit_price_rejected() {
    let input = post_only_buy(f64::INFINITY, Some(100.0));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// +Inf best_ask with finite limit_price must be rejected (fail-closed).
#[test]
fn test_post_only_inf_best_ask_rejected() {
    let input = post_only_buy(99.0, Some(f64::INFINITY));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// +Inf best_bid with finite limit_price must be rejected (fail-closed).
#[test]
fn test_post_only_inf_best_bid_rejected() {
    let input = post_only_sell(101.0, Some(f64::INFINITY));
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// NaN limit_price + empty book (None) must still be rejected.
/// Catches check-after-comparison mutation (guard must fire before book check).
#[test]
fn test_post_only_nan_limit_price_empty_book_rejected() {
    let input = post_only_buy(f64::NAN, None);
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

/// +Inf limit_price + empty book (None) must still be rejected.
#[test]
fn test_post_only_inf_limit_price_empty_book_rejected() {
    let input = post_only_sell(f64::INFINITY, None);
    let mut m = PostOnlyMetrics::new();
    assert_eq!(check_post_only(&input, &mut m), PostOnlyResult::Rejected);
    assert_eq!(m.reject_total(), 1);
}

#[test]
fn test_static_counter_cross_reject_increments() {
    let _guard = metrics_lock();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price: 100.0,
        best_ask: Some(99.0),
        best_bid: None,
    };
    let result = check_post_only(&input, &mut metrics);
    assert_eq!(result, PostOnlyResult::Rejected);
    let after = post_only_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_static_counter_nan_limit_fail_closed_reject_increments() {
    let _guard = metrics_lock();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price: f64::NAN,
        best_ask: Some(100.0),
        best_bid: None,
    };
    let result = check_post_only(&input, &mut metrics);
    assert_eq!(result, PostOnlyResult::Rejected);
    let after = post_only_reject_total();
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_static_counter_monotonic() {
    let _guard = metrics_lock();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Sell,
        limit_price: 100.0,
        best_ask: None,
        best_bid: Some(101.0),
    };
    let _ = check_post_only(&input, &mut metrics);
    let mid = post_only_reject_total();
    let _ = check_post_only(&input, &mut metrics);
    let after = post_only_reject_total();
    assert!(mid > before, "first call should increment");
    assert!(
        after > mid,
        "second call should increment further (monotonic)"
    );
}

#[test]
fn test_post_only_graybox_emits_reject_event_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let mut events = Vec::new();
    let input = post_only_buy(100.0, Some(100.0));

    let result = check_post_only_with_events(&input, &mut metrics, &mut events);

    assert_eq!(result, PostOnlyResult::Rejected);
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(events, vec![PostOnlyEvent::Reject]);
    assert_eq!(post_only_reject_total(), before);

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_post_only_graybox_invalid_limit_price_preserves_context_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let mut events = Vec::new();
    let input = post_only_buy(f64::NAN, Some(100.0));

    let result = check_post_only_with_events(&input, &mut metrics, &mut events);

    assert_eq!(result, PostOnlyResult::Rejected);
    assert_eq!(metrics.reject_total(), 1);
    assert!(matches!(
        events.as_slice(),
        [PostOnlyEvent::InvalidLimitPrice { limit_price }, PostOnlyEvent::Reject]
            if limit_price.is_nan()
    ));
    assert_eq!(post_only_reject_total(), before);

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_post_only_graybox_allowed_emits_no_events_or_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let mut events = Vec::new();
    let input = post_only_buy(99.0, Some(100.0));

    let result = check_post_only_with_events(&input, &mut metrics, &mut events);

    assert_eq!(result, PostOnlyResult::Allowed);
    assert_eq!(metrics.reject_total(), 0);
    assert!(
        events.is_empty(),
        "success path should not emit reject events"
    );
    assert_eq!(post_only_reject_total(), before);

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_post_only_wrapper_emits_structured_reject_metric_line() {
    let _guard = begin_metrics_test();
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = post_only_buy(100.0, Some(100.0));

    let result = with_intent_trace_ids("intent-post-only-001", "run-post-only-001", || {
        check_post_only(&input, &mut metrics)
    });

    assert_eq!(result, PostOnlyResult::Rejected);
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(post_only_reject_total(), before + 1);

    let lines = take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with("post_only_reject_total")
                && line.contains("intent_id=intent-post-only-001")
                && line.contains("run_id=run-post-only-001")
        }),
        "expected structured post-only metric line, got {lines:?}"
    );
}
