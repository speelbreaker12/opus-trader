//! Tests for post-only crossing guard per CONTRACT.md §1.4.4 C.
//!
//! AT-916: post_only == true and limit price would cross → reject.

use soldier_core::execution::{
    PostOnlyInput, PostOnlyMetrics, PostOnlyResult, Side, check_post_only,
};

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
