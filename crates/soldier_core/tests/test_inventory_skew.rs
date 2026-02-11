//! Inventory Skew gate tests (S6.1).
//!
//! Contract targets:
//! - AT-030: bias=1.0 applies exactly max tick penalty (3 ticks default).
//! - AT-043/AT-922: missing delta_limit must fail-closed with explicit reason.
//! - AT-224 intent: near-limit risk-increasing OPEN may be rejected after skew tightening.

use soldier_core::execution::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    InventorySkewSide, evaluate_inventory_skew,
};

#[test]
fn test_inventory_skew_rejects_risk_increasing_near_limit() {
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: InventorySkewSide::Buy,
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
        side: InventorySkewSide::Buy,
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
        side: InventorySkewSide::Buy,
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
        side: InventorySkewSide::Sell,
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
        side: InventorySkewSide::Buy,
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
