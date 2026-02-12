//! Tests for Pre-Trade Liquidity Gate per CONTRACT.md §1.3.
//!
//! AT-222: Slippage > max_slippage_bps → reject with ExpectedSlippageTooHigh.
//! AT-344: Missing/stale L2 → reject OPEN, no dispatch.
//! AT-909: Missing/stale L2 → Rejected(LiquidityGateNoL2).
//! AT-421: Cancel-only allowed even without L2; Close/Hedge rejected.

use soldier_core::execution::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateRejectReason, LiquidityGateResult, evaluate_liquidity_gate,
};

/// Helper: build a simple L2 book with given ask/bid levels.
fn book(asks: Vec<(f64, f64)>, bids: Vec<(f64, f64)>, ts: u64) -> L2BookSnapshot {
    L2BookSnapshot {
        asks: asks
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        bids: bids
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        timestamp_ms: ts,
    }
}

/// Helper: build a gate input with defaults.
fn gate_input(
    order_qty: f64,
    is_buy: bool,
    intent_class: GateIntentClass,
    l2: Option<L2BookSnapshot>,
) -> LiquidityGateInput {
    LiquidityGateInput {
        order_qty,
        is_buy,
        intent_class,
        is_marketable: true,
        l2_snapshot: l2,
        now_ms: 1000,
        l2_book_snapshot_max_age_ms: 500,
        max_slippage_bps: 10.0,
    }
}

// ─── AT-222: Slippage > max → reject ────────────────────────────────────

#[test]
fn test_at222_slippage_exceeds_max_rejected() {
    let mut m = LiquidityGateMetrics::new();

    // Asks: 100.0 x 1.0, 110.0 x 1.0 (10% spread between levels)
    // Buy 2.0: WAP = (100*1 + 110*1)/2 = 105
    // slippage_bps = (105-100)/100 * 10000 = 500 bps (way above 10)
    let snap = book(vec![(100.0, 1.0), (110.0, 1.0)], vec![], 900);
    let input = gate_input(2.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Rejected {
            reason,
            wap,
            slippage_bps,
            ..
        } => {
            assert_eq!(reason, LiquidityGateRejectReason::ExpectedSlippageTooHigh);
            assert!((wap.unwrap() - 105.0).abs() < 1e-9);
            assert!(slippage_bps.unwrap() > 10.0);
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
    assert_eq!(m.reject_slippage(), 1);
}

#[test]
fn test_at222_no_order_intent_on_rejection() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(100.0, 1.0), (200.0, 1.0)], vec![], 900);
    let input = gate_input(2.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    // Rejected — no OrderIntent should be emitted (caller responsibility)
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::ExpectedSlippageTooHigh,
            ..
        }
    ));
}

#[test]
fn test_at222_reject_log_includes_wap_and_slippage() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(100.0, 1.0), (110.0, 1.0)], vec![], 900);
    let input = gate_input(2.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Rejected {
            wap, slippage_bps, ..
        } => {
            // LiquidityGateReject log would include these values
            assert!(wap.is_some(), "WAP must be present for logging");
            assert!(
                slippage_bps.is_some(),
                "slippage_bps must be present for logging"
            );
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
}

// ─── Slippage within limit → allowed ─────────────────────────────────────

#[test]
fn test_slippage_within_limit_allowed() {
    let mut m = LiquidityGateMetrics::new();

    // Asks: 100.0 x 10.0 — all at same price, zero slippage
    let snap = book(vec![(100.0, 10.0)], vec![], 900);
    let input = gate_input(5.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Allowed {
            wap, slippage_bps, ..
        } => {
            assert!((wap.unwrap() - 100.0).abs() < 1e-9);
            assert!(slippage_bps.unwrap() < 1e-9); // zero slippage
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
    assert_eq!(m.allowed_total(), 1);
}

#[test]
fn test_slippage_at_boundary_allowed() {
    let mut m = LiquidityGateMetrics::new();

    // Asks: 10000.0 x 5.0, 10001.0 x 5.0
    // Buy 10: WAP = (10000*5 + 10001*5)/10 = 10000.5
    // slippage_bps = (10000.5 - 10000)/10000 * 10000 = 0.5 bps (below 10)
    let snap = book(vec![(10000.0, 5.0), (10001.0, 5.0)], vec![], 900);
    let input = gate_input(10.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(result, LiquidityGateResult::Allowed { .. }));
}

// ─── Sell side ──────────────────────────────────────────────────────────

#[test]
fn test_sell_walks_bids() {
    let mut m = LiquidityGateMetrics::new();

    // Bids: 100.0 x 1.0, 90.0 x 1.0 (descending)
    // Sell 2.0: WAP = (100*1 + 90*1)/2 = 95
    // slippage_bps = |95-100|/100 * 10000 = 500 bps
    let snap = book(vec![], vec![(100.0, 1.0), (90.0, 1.0)], 900);
    let input = gate_input(2.0, false, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Rejected {
            reason,
            wap,
            slippage_bps,
            ..
        } => {
            assert_eq!(reason, LiquidityGateRejectReason::ExpectedSlippageTooHigh);
            assert!((wap.unwrap() - 95.0).abs() < 1e-9);
            assert!(slippage_bps.unwrap() > 10.0);
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
}

// ─── AT-344 / AT-909: Missing/stale L2 → LiquidityGateNoL2 ─────────────

#[test]
fn test_at344_missing_l2_rejects_open() {
    let mut m = LiquidityGateMetrics::new();

    let input = gate_input(1.0, true, GateIntentClass::Open, None);

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
    assert_eq!(m.reject_no_l2(), 1);
}

#[test]
fn test_at909_missing_l2_reason_is_no_l2() {
    let mut m = LiquidityGateMetrics::new();

    let input = gate_input(1.0, true, GateIntentClass::Open, None);

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Rejected { reason, .. } => {
            assert_eq!(reason, LiquidityGateRejectReason::LiquidityGateNoL2);
        }
        other => panic!("expected Rejected(LiquidityGateNoL2), got {other:?}"),
    }
}

#[test]
fn test_at344_stale_l2_rejects_open() {
    let mut m = LiquidityGateMetrics::new();

    // Snapshot at ts=200, now=1000, max_age=500 → stale (age=800 > 500)
    let snap = book(vec![(100.0, 10.0)], vec![], 200);
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_stale_l2_fresh_enough_passes() {
    let mut m = LiquidityGateMetrics::new();

    // Snapshot at ts=600, now=1000, max_age=500 → fresh (age=400 < 500)
    let snap = book(vec![(100.0, 10.0)], vec![], 600);
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(result, LiquidityGateResult::Allowed { .. }));
}

#[test]
fn test_future_dated_l2_rejected_fail_closed() {
    let mut m = LiquidityGateMetrics::new();

    // Snapshot timestamp is in the future relative to now_ms.
    let snap = book(vec![(100.0, 10.0)], vec![], 1_500);
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

// ─── AT-421: Cancel allowed, Close/Hedge rejected ───────────────────────

#[test]
fn test_at421_cancel_only_allowed_without_l2() {
    let mut m = LiquidityGateMetrics::new();

    let input = gate_input(1.0, true, GateIntentClass::CancelOnly, None);

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(result, LiquidityGateResult::Allowed { .. }));
    assert_eq!(m.allowed_total(), 1);
}

#[test]
fn test_at421_close_rejected_without_l2() {
    let mut m = LiquidityGateMetrics::new();

    let input = gate_input(1.0, true, GateIntentClass::Close, None);

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_at421_cancel_allowed_with_stale_l2() {
    let mut m = LiquidityGateMetrics::new();

    // Stale snapshot
    let snap = book(vec![(100.0, 10.0)], vec![], 200);
    let input = gate_input(1.0, true, GateIntentClass::CancelOnly, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(result, LiquidityGateResult::Allowed { .. }));
}

// ─── Empty book side → NoL2 ─────────────────────────────────────────────

#[test]
fn test_empty_asks_for_buy_rejects() {
    let mut m = LiquidityGateMetrics::new();

    // Book has bids but no asks; buying requires asks
    let snap = book(vec![], vec![(100.0, 10.0)], 900);
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_empty_bids_for_sell_rejects() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(100.0, 10.0)], vec![], 900);
    let input = gate_input(1.0, false, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

// ─── Partial fill from thin book ─────────────────────────────────────────

#[test]
fn test_partial_fill_from_thin_book_evaluates_available() {
    let mut m = LiquidityGateMetrics::new();

    // Only 2.0 available but asking for 10.0 -> OPEN must fail-closed.
    let snap = book(vec![(100.0, 2.0)], vec![], 900);
    let input = gate_input(10.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::ExpectedSlippageTooHigh,
            ..
        }
    ));
}

// ─── Multi-level book walk ──────────────────────────────────────────────

#[test]
fn test_multi_level_wap_computation() {
    let mut m = LiquidityGateMetrics::new();

    // 3 ask levels: 100x5, 100.05x5, 100.10x5
    // Buy 15: WAP = (100*5 + 100.05*5 + 100.10*5)/15 = 100.05
    // slippage = (100.05 - 100)/100 * 10000 = 5 bps (below 10)
    let snap = book(
        vec![(100.0, 5.0), (100.05, 5.0), (100.10, 5.0)],
        vec![],
        900,
    );
    let input = gate_input(15.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Allowed {
            wap, slippage_bps, ..
        } => {
            assert!((wap.unwrap() - 100.05).abs() < 1e-6);
            assert!(slippage_bps.unwrap() < 10.0);
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
}

#[test]
fn test_open_wap_budget_allows_small_tail_beyond_level_cap() {
    let mut m = LiquidityGateMetrics::new();

    // Full-order WAP is within 10 bps despite a tiny tail at a far level.
    let snap = book(vec![(100.0, 10.0), (200.0, 0.01)], vec![], 900);
    let input = gate_input(10.01, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Allowed {
            allowed_qty,
            slippage_bps,
            ..
        } => {
            assert!((allowed_qty.unwrap() - 10.01).abs() < 1e-9);
            assert!(slippage_bps.unwrap() <= 10.0 + 1e-9);
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
}

#[test]
fn test_overflowed_slippage_budget_fails_closed() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(f64::MAX, 1.0)], vec![], 900);
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
    assert_eq!(m.reject_no_l2(), 1);
}

// ─── Metrics default ────────────────────────────────────────────────────

#[test]
fn test_metrics_default() {
    let m = LiquidityGateMetrics::default();
    assert_eq!(m.reject_no_l2(), 0);
    assert_eq!(m.reject_slippage(), 0);
    assert_eq!(m.allowed_total(), 0);
}

// ─── Close intent with valid L2 and low slippage ─────────────────────────

#[test]
fn test_close_allowed_with_valid_l2() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(100.0, 10.0)], vec![], 900);
    let input = gate_input(1.0, true, GateIntentClass::Close, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(result, LiquidityGateResult::Allowed { .. }));
}

#[test]
fn test_close_clamps_to_fillable_qty() {
    let mut m = LiquidityGateMetrics::new();

    // 2.0 units visible within budget, requested 10.0.
    let snap = book(vec![(100.0, 2.0)], vec![], 900);
    let input = gate_input(10.0, true, GateIntentClass::Close, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Allowed {
            fillable_qty,
            allowed_qty,
            ..
        } => {
            assert_eq!(fillable_qty, Some(2.0));
            assert_eq!(allowed_qty, Some(2.0));
        }
        other => panic!("expected Allowed for CLOSE clamp, got {other:?}"),
    }
}

#[test]
fn test_hedge_clamps_to_fillable_qty() {
    let mut m = LiquidityGateMetrics::new();

    let snap = book(vec![(100.0, 1.5)], vec![], 900);
    let input = gate_input(5.0, true, GateIntentClass::Hedge, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    match result {
        LiquidityGateResult::Allowed {
            fillable_qty,
            allowed_qty,
            ..
        } => {
            assert_eq!(fillable_qty, Some(1.5));
            assert_eq!(allowed_qty, Some(1.5));
        }
        other => panic!("expected Allowed for HEDGE clamp, got {other:?}"),
    }
}

#[test]
fn test_non_marketable_bypasses_depth_gate() {
    let mut m = LiquidityGateMetrics::new();

    // OPEN path with valid L2 bypasses depth-budget clamp when non-marketable.
    let mut input = gate_input(
        3.0,
        true,
        GateIntentClass::Open,
        Some(book(vec![(100.0, 1.0)], vec![], 900)),
    );
    input.is_marketable = false;

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Allowed {
            allowed_qty: Some(3.0),
            ..
        }
    ));
}

#[test]
fn test_non_marketable_open_without_l2_still_rejected_fail_closed() {
    let mut m = LiquidityGateMetrics::new();

    let mut input = gate_input(1.0, true, GateIntentClass::Open, None);
    input.is_marketable = false;

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_non_marketable_close_without_l2_still_rejected_fail_closed() {
    let mut m = LiquidityGateMetrics::new();

    let mut input = gate_input(1.0, true, GateIntentClass::Close, None);
    input.is_marketable = false;

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_non_marketable_hedge_with_stale_l2_still_rejected_fail_closed() {
    let mut m = LiquidityGateMetrics::new();

    let mut input = gate_input(
        1.0,
        true,
        GateIntentClass::Hedge,
        Some(book(vec![(100.0, 10.0)], vec![], 200)),
    );
    input.is_marketable = false;

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}

#[test]
fn test_non_marketable_open_with_stale_l2_still_rejected_fail_closed() {
    let mut m = LiquidityGateMetrics::new();

    let mut input = gate_input(
        1.0,
        true,
        GateIntentClass::Open,
        Some(book(vec![(100.0, 10.0)], vec![], 200)),
    );
    input.is_marketable = false;

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result,
        LiquidityGateResult::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2,
            ..
        }
    ));
}
