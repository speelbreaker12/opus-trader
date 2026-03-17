//! Tests for Fee-Aware IOC Limit Pricer per CONTRACT.md §1.4.
//!
//! AT-223: IOC limit guarantees min edge at limit price.

use super::*;
use crate::execution::{begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids};

fn metrics_lock() -> std::sync::MutexGuard<'static, ()> {
    crate::execution::METRICS_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner())
}

trait TestOptionExt<T> {
    fn must(self) -> T;
}

impl<T> TestOptionExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

/// Helper: build a pricer input.
fn input(fair: f64, gross: f64, min_edge: f64, fee: f64, qty: f64, side: Side) -> PricerInput {
    PricerInput {
        fair_price: fair,
        gross_edge_usd: gross,
        min_edge_usd: min_edge,
        fee_estimate_usd: fee,
        expected_slippage_usd: 0.0,
        qty,
        side,
    }
}

fn input_with_slippage(
    fair: f64,
    gross: f64,
    min_edge: f64,
    fee: f64,
    slippage: f64,
    qty: f64,
    side: Side,
) -> PricerInput {
    PricerInput {
        fair_price: fair,
        gross_edge_usd: gross,
        min_edge_usd: min_edge,
        fee_estimate_usd: fee,
        expected_slippage_usd: slippage,
        qty,
        side,
    }
}

// ─── AT-223: Limit price guarantees min edge ─────────────────────────────

#[test]
fn test_at223_buy_limit_clamped_to_min_edge() {
    let mut m = PricerMetrics::new();

    // fair=100, gross=10, min_edge=2, fee=3, qty=1
    // net_edge = 10-3 = 7
    // net_edge_per_unit = 7
    // fee_per_unit = 3
    // min_edge_per_unit = 2
    // max_price_for_min_edge (buy) = 100 - (2+3) = 95
    // proposed_limit (buy) = 100 - 0.5*7 = 96.5
    // clamp: min(96.5, 95) = 95
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            net_edge_usd,
        } => {
            assert!((limit_price - 95.0).abs() < 1e-9);
            assert!((max_price_for_min_edge - 95.0).abs() < 1e-9);
            assert!((net_edge_usd - 7.0).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
    assert_eq!(m.priced_total(), 1);
}

#[test]
fn test_at223_sell_limit_clamped_to_min_edge() {
    let mut m = PricerMetrics::new();

    // fair=100, gross=10, min_edge=2, fee=3, qty=1
    // max_price_for_min_edge (sell) = 100 + (2+3) = 105
    // proposed_limit (sell) = 100 + 0.5*7 = 103.5
    // clamp: max(103.5, 105) = 105
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, Side::Sell);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            ..
        } => {
            assert!((limit_price - 105.0).abs() < 1e-9);
            assert!((max_price_for_min_edge - 105.0).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

#[test]
fn test_at223_realized_edge_at_limit_ge_min_edge() {
    let mut m = PricerMetrics::new();

    // For a buy at limit_price:
    // realized_edge = (fair_price - limit_price) * qty - fee
    // Must be >= min_edge_usd
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            net_edge_usd: _,
            ..
        } => {
            let realized_edge = (inp.fair_price - limit_price) * inp.qty - inp.fee_estimate_usd;
            assert!(
                realized_edge >= inp.min_edge_usd - 1e-9,
                "realized_edge={realized_edge} must be >= min_edge={}",
                inp.min_edge_usd
            );
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

#[test]
fn test_at223_sell_realized_edge_at_limit_ge_min_edge() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, Side::Sell);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice { limit_price, .. } => {
            // For sell: realized_edge = (limit_price - fair_price) * qty - fee
            let realized_edge = (limit_price - inp.fair_price) * inp.qty - inp.fee_estimate_usd;
            assert!(
                realized_edge >= inp.min_edge_usd - 1e-9,
                "realized_edge={realized_edge} must be >= min_edge={}",
                inp.min_edge_usd
            );
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

// ─── Net edge too low → reject ──────────────────────────────────────────

#[test]
fn test_net_edge_too_low_rejected() {
    let mut m = PricerMetrics::new();

    // gross=5, fee=4, min_edge=2 → net=1 < 2 → reject
    let inp = input(100.0, 5.0, 2.0, 4.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::Rejected {
            reason,
            net_edge_usd,
        } => {
            assert_eq!(reason, PricerRejectReason::NetEdgeTooLow);
            assert!((net_edge_usd.must() - 1.0).abs() < 1e-9);
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
    assert_eq!(m.reject_total(), 1);
}

#[test]
fn test_negative_net_edge_rejected() {
    let mut m = PricerMetrics::new();

    // gross=3, fee=5 → net=-2 < 0 → reject
    let inp = input(100.0, 3.0, 0.0, 5.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            ..
        }
    ));
}

#[test]
fn test_contract_net_edge_subtracts_expected_slippage() {
    let mut m = PricerMetrics::new();
    let inp = input_with_slippage(100.0, 10.0, 2.0, 2.0, 3.0, 1.0, Side::Buy);

    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            net_edge_usd,
        } => {
            assert!((net_edge_usd - 5.0).abs() < 1e-9);
            assert!((max_price_for_min_edge - 93.0).abs() < 1e-9);
            assert!((limit_price - 93.0).abs() < 1e-9);
            let realized_edge = (inp.fair_price - limit_price) * inp.qty
                - inp.fee_estimate_usd
                - inp.expected_slippage_usd;
            assert!((realized_edge - inp.min_edge_usd).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

#[test]
fn test_contract_net_edge_subtracts_expected_slippage_for_sell() {
    let mut m = PricerMetrics::new();
    let inp = input_with_slippage(100.0, 10.0, 2.0, 2.0, 3.0, 1.0, Side::Sell);

    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            net_edge_usd,
        } => {
            assert!((net_edge_usd - 5.0).abs() < 1e-9);
            assert!((max_price_for_min_edge - 107.0).abs() < 1e-9);
            assert!((limit_price - 107.0).abs() < 1e-9);
            let realized_edge = (limit_price - inp.fair_price) * inp.qty
                - inp.fee_estimate_usd
                - inp.expected_slippage_usd;
            assert!((realized_edge - inp.min_edge_usd).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

#[test]
fn test_contract_net_edge_subtracts_expected_slippage_sell() {
    let mut m = PricerMetrics::new();
    let inp = input_with_slippage(100.0, 10.0, 2.0, 2.0, 3.0, 1.0, Side::Sell);

    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            net_edge_usd,
        } => {
            assert!((net_edge_usd - 5.0).abs() < 1e-9);
            assert!((max_price_for_min_edge - 107.0).abs() < 1e-9);
            assert!((limit_price - 107.0).abs() < 1e-9);
            let realized_edge = (limit_price - inp.fair_price) * inp.qty
                - inp.fee_estimate_usd
                - inp.expected_slippage_usd;
            assert!((realized_edge - inp.min_edge_usd).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

// ─── Invalid input ──────────────────────────────────────────────────────

#[test]
fn test_zero_qty_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, 2.0, 3.0, 0.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

#[test]
fn test_negative_qty_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, 2.0, 3.0, -1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

// ─── Multi-unit quantity ─────────────────────────────────────────────────

#[test]
fn test_multi_unit_buy() {
    let mut m = PricerMetrics::new();

    // fair=100, gross=20, min_edge=4, fee=6, qty=2
    // net = 20-6 = 14
    // net_per_unit = 7, fee_per_unit = 3, min_edge_per_unit = 2
    // max_price_buy = 100 - (2+3) = 95
    // proposed = 100 - 0.5*7 = 96.5
    // clamp: min(96.5, 95) = 95
    let inp = input(100.0, 20.0, 4.0, 6.0, 2.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice { limit_price, .. } => {
            assert!((limit_price - 95.0).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

// ─── Proposed limit within bound (no clamping needed) ────────────────────

#[test]
fn test_buy_proposed_within_bound_no_clamp() {
    let mut m = PricerMetrics::new();

    // fair=100, gross=10, min_edge=1, fee=1, qty=1
    // net = 9, net_per_unit = 9
    // max_price_buy = 100 - (1+1) = 98
    // proposed = 100 - 0.5*9 = 95.5
    // clamp: min(95.5, 98) = 95.5 (no clamp)
    let inp = input(100.0, 10.0, 1.0, 1.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::LimitPrice { limit_price, .. } => {
            assert!((limit_price - 95.5).abs() < 1e-9);
        }
        other => panic!("expected LimitPrice, got {other:?}"),
    }
}

// ─── Metrics ─────────────────────────────────────────────────────────────

#[test]
fn test_metrics_default() {
    let m = PricerMetrics::default();
    assert_eq!(m.reject_total(), 0);
    assert_eq!(m.priced_total(), 0);
}

#[test]
fn test_nan_fair_price_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(f64::NAN, 10.0, 2.0, 3.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

#[test]
fn test_negative_fee_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, 2.0, -0.1, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

#[test]
fn test_negative_min_edge_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, -1.0, 1.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

#[test]
fn test_infinite_gross_edge_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, f64::INFINITY, 2.0, 3.0, 1.0, Side::Sell);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

// ─── expected_slippage_usd boundary ──────────────────────────────────

#[test]
fn test_nan_expected_slippage_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input_with_slippage(100.0, 10.0, 2.0, 3.0, f64::NAN, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

#[test]
fn test_negative_expected_slippage_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input_with_slippage(100.0, 10.0, 2.0, 3.0, -0.1, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `<` flipped to `<=` on net_edge < min_edge check.
/// net_edge == min_edge must ALLOW (< not <=).
#[test]
fn test_pricer_at_exact_min_edge_boundary() {
    let mut m = PricerMetrics::new();
    // gross=8, fee=3 → net=5. min_edge=5 → net==min → should ALLOW.
    let inp = input(100.0, 8.0, 5.0, 3.0, 1.0, Side::Buy);
    let result = compute_limit_price(&inp, &mut m);
    assert!(
        matches!(result, PricerResult::LimitPrice { .. }),
        "net_edge == min_edge must ALLOW (< not <=), got {result:?}"
    );
}

#[test]
fn test_static_counter_invalid_input_reject_increments() {
    let _guard = metrics_lock();
    let before = pricer_reject_total(PricerRejectReason::InvalidInput);
    let mut metrics = PricerMetrics::new();
    let input = PricerInput {
        fair_price: f64::NAN,
        gross_edge_usd: 1.0,
        min_edge_usd: 0.5,
        fee_estimate_usd: 0.1,
        expected_slippage_usd: 0.0,
        qty: 1.0,
        side: Side::Buy,
    };
    let result = compute_limit_price(&input, &mut metrics);
    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));
    let after = pricer_reject_total(PricerRejectReason::InvalidInput);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_static_counter_net_edge_too_low_reject_increments() {
    let _guard = metrics_lock();
    let before = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    let mut metrics = PricerMetrics::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 0.5,
        min_edge_usd: 1.0,
        fee_estimate_usd: 0.1,
        expected_slippage_usd: 0.0,
        qty: 1.0,
        side: Side::Buy,
    };
    let result = compute_limit_price(&input, &mut metrics);
    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            ..
        }
    ));
    let after = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    assert!(
        after > before,
        "counter should increment: before={before}, after={after}"
    );
}

#[test]
fn test_pricer_graybox_emits_reject_event_without_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    let mut metrics = PricerMetrics::new();
    let mut events = Vec::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 0.5,
        min_edge_usd: 1.0,
        fee_estimate_usd: 0.1,
        expected_slippage_usd: 0.0,
        qty: 1.0,
        side: Side::Buy,
    };

    let result = compute_limit_price_with_events(&input, &mut metrics, &mut events);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            net_edge_usd: Some(net_edge_usd),
        } if (net_edge_usd - 0.4).abs() < 1e-9
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(
        events,
        vec![PricerEvent::Reject {
            reason: PricerRejectReason::NetEdgeTooLow
        }]
    );
    assert_eq!(
        pricer_reject_total(PricerRejectReason::NetEdgeTooLow),
        before
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_pricer_graybox_success_emits_no_events_or_global_side_effects() {
    let _guard = begin_metrics_test();
    let before = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    let mut metrics = PricerMetrics::new();
    let mut events = Vec::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 10.0,
        min_edge_usd: 2.0,
        fee_estimate_usd: 3.0,
        expected_slippage_usd: 0.0,
        qty: 1.0,
        side: Side::Buy,
    };

    let result = compute_limit_price_with_events(&input, &mut metrics, &mut events);

    assert!(matches!(
        result,
        PricerResult::LimitPrice {
            limit_price,
            max_price_for_min_edge,
            net_edge_usd,
        } if (limit_price - 95.0).abs() < 1e-9
            && (max_price_for_min_edge - 95.0).abs() < 1e-9
            && (net_edge_usd - 7.0).abs() < 1e-9
    ));
    assert_eq!(metrics.priced_total(), 1);
    assert!(
        events.is_empty(),
        "success path should not emit reject events"
    );
    assert_eq!(
        pricer_reject_total(PricerRejectReason::NetEdgeTooLow),
        before
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.is_empty(),
        "graybox path must not emit global metric lines: {lines:?}"
    );
}

#[test]
fn test_pricer_wrapper_emits_structured_reject_metric_line() {
    let _guard = begin_metrics_test();
    let before = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    let mut metrics = PricerMetrics::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 0.5,
        min_edge_usd: 1.0,
        fee_estimate_usd: 0.1,
        expected_slippage_usd: 0.0,
        qty: 1.0,
        side: Side::Buy,
    };

    let result = with_intent_trace_ids("intent-pricer-001", "run-pricer-001", || {
        compute_limit_price(&input, &mut metrics)
    });

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            net_edge_usd: Some(net_edge_usd),
        } if (net_edge_usd - 0.4).abs() < 1e-9
    ));
    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(
        pricer_reject_total(PricerRejectReason::NetEdgeTooLow),
        before + 1
    );

    let lines = take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with("pricer_reject_total")
                && line.contains("intent_id=intent-pricer-001")
                && line.contains("run_id=run-pricer-001")
                && line.contains("reason=NetEdgeTooLow")
        }),
        "expected structured pricer metric line, got {lines:?}"
    );
}
