//! Property-based tests for the Liquidity Gate (CONTRACT.md §1.3).
//!
//! Properties under test:
//! - CancelOnly intents always produce Allowed.
//! - Missing L2 (None) always rejects Open/Close/Hedge intents.
//! - Empty book always rejects Open/Close/Hedge intents.
//! - Never panics on any structurally valid input.
//! - Stale snapshot always rejects Open/Close/Hedge intents.

use super::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateDecision, LiquidityGateInput,
    LiquidityGateMetrics, LiquidityGateRejectReason, evaluate_liquidity_gate,
};
use proptest::prelude::*;

fn intent_class_strategy() -> impl Strategy<Value = GateIntentClass> {
    prop_oneof![
        Just(GateIntentClass::Open),
        Just(GateIntentClass::Close),
        Just(GateIntentClass::Hedge),
        Just(GateIntentClass::CancelOnly),
    ]
}

fn non_cancel_intent_class() -> impl Strategy<Value = GateIntentClass> {
    prop_oneof![
        Just(GateIntentClass::Open),
        Just(GateIntentClass::Close),
        Just(GateIntentClass::Hedge),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// CancelOnly intents always produce Allowed regardless of book state.
    #[test]
    fn cancel_only_always_allowed(
        has_book in proptest::bool::ANY,
        order_qty in (0.001_f64..1e4),
    ) {
        let l2_snapshot = if has_book {
            Some(L2BookSnapshot {
                asks: vec![L2Level { price: 100.0, qty: 10.0 }],
                bids: vec![],
                timestamp_ms: 1_000_000,
            })
        } else {
            None
        };
        let input = LiquidityGateInput {
            order_qty,
            is_buy: true,
            intent_class: GateIntentClass::CancelOnly,
            is_marketable: false,
            l2_snapshot,
            now_ms: 1_010_000,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps: 10.0,
        };
        let mut metrics = LiquidityGateMetrics::new();
        let result = evaluate_liquidity_gate(&input, &mut metrics);

        prop_assert!(
            matches!(result.decision, LiquidityGateDecision::Allowed),
            "CancelOnly should always be Allowed, got {:?}", result
        );
    }

    /// Missing L2 (None) always rejects non-CancelOnly intents.
    #[test]
    fn missing_l2_rejects_non_cancel(
        intent_class in non_cancel_intent_class(),
        order_qty in (0.001_f64..1e4),
        is_buy in proptest::bool::ANY,
    ) {
        let input = LiquidityGateInput {
            order_qty,
            is_buy,
            intent_class,
            is_marketable: true,
            l2_snapshot: None,
            now_ms: 1_010_000,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps: 10.0,
        };
        let mut metrics = LiquidityGateMetrics::new();
        let result = evaluate_liquidity_gate(&input, &mut metrics);

        prop_assert!(
            matches!(result.decision, LiquidityGateDecision::Rejected { reason: LiquidityGateRejectReason::LiquidityGateNoL2 }),
            "missing L2 should reject with LiquidityGateNoL2, got {:?}", result
        );
    }

    /// Empty book (asks empty for buy, bids empty for sell) rejects.
    #[test]
    fn empty_book_side_rejects(
        intent_class in non_cancel_intent_class(),
        order_qty in (0.001_f64..1e4),
        is_buy in proptest::bool::ANY,
    ) {
        // Give the opposite side levels but empty the relevant side
        let snapshot = if is_buy {
            L2BookSnapshot {
                asks: vec![],
                bids: vec![L2Level { price: 99.0, qty: 10.0 }],
                timestamp_ms: 1_005_000,
            }
        } else {
            L2BookSnapshot {
                asks: vec![L2Level { price: 101.0, qty: 10.0 }],
                bids: vec![],
                timestamp_ms: 1_005_000,
            }
        };
        let input = LiquidityGateInput {
            order_qty,
            is_buy,
            intent_class,
            is_marketable: true,
            l2_snapshot: Some(snapshot),
            now_ms: 1_010_000,
            l2_book_snapshot_max_age_ms: 10_000,
            max_slippage_bps: 100.0,
        };
        let mut metrics = LiquidityGateMetrics::new();
        let result = evaluate_liquidity_gate(&input, &mut metrics);

        prop_assert!(
            matches!(result.decision, LiquidityGateDecision::Rejected { reason: LiquidityGateRejectReason::LiquidityGateNoL2 }),
            "empty book side should reject with LiquidityGateNoL2, got {:?}", result
        );
    }

    /// Stale snapshot always rejects non-CancelOnly.
    #[test]
    fn stale_snapshot_rejects(
        intent_class in non_cancel_intent_class(),
        order_qty in (0.001_f64..1e4),
        is_buy in proptest::bool::ANY,
        staleness_ms in (6_000u64..100_000),
    ) {
        let now_ms = 1_010_000u64;
        let snapshot = L2BookSnapshot {
            asks: vec![L2Level { price: 100.0, qty: 10.0 }],
            bids: vec![L2Level { price: 99.0, qty: 10.0 }],
            timestamp_ms: now_ms.saturating_sub(staleness_ms),
        };
        let input = LiquidityGateInput {
            order_qty,
            is_buy,
            intent_class,
            is_marketable: true,
            l2_snapshot: Some(snapshot),
            now_ms,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps: 100.0,
        };
        let mut metrics = LiquidityGateMetrics::new();
        let result = evaluate_liquidity_gate(&input, &mut metrics);

        prop_assert!(
            matches!(result.decision, LiquidityGateDecision::Rejected { reason: LiquidityGateRejectReason::LiquidityGateNoL2 }),
            "stale snapshot ({}ms old) should reject with LiquidityGateNoL2, got {:?}",
            staleness_ms, result
        );
    }

    /// Never panics on structurally valid inputs with arbitrary book data.
    #[test]
    fn never_panics(
        intent_class in intent_class_strategy(),
        order_qty in prop::num::f64::ANY,
        is_buy in proptest::bool::ANY,
        has_book in proptest::bool::ANY,
        max_slippage_bps in prop::num::f64::ANY,
    ) {
        let l2_snapshot = if has_book {
            Some(L2BookSnapshot {
                asks: vec![L2Level { price: 100.0, qty: 10.0 }],
                bids: vec![L2Level { price: 99.0, qty: 10.0 }],
                timestamp_ms: 1_005_000,
            })
        } else {
            None
        };
        let input = LiquidityGateInput {
            order_qty,
            is_buy,
            intent_class,
            is_marketable: true,
            l2_snapshot,
            now_ms: 1_010_000,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps,
        };
        let mut metrics = LiquidityGateMetrics::new();
        // Must not panic — may return any valid result
        let _ = evaluate_liquidity_gate(&input, &mut metrics);
    }
}
