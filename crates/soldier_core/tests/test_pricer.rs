//! Tests for Fee-Aware IOC Limit Pricer per CONTRACT.md §1.4.
//!
//! AT-223: IOC limit guarantees min edge at limit price.

use soldier_core::execution::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, PricerSide, compute_limit_price,
};

/// Helper: build a pricer input.
fn input(
    fair: f64,
    gross: f64,
    min_edge: f64,
    fee: f64,
    qty: f64,
    side: PricerSide,
) -> PricerInput {
    PricerInput {
        fair_price: fair,
        gross_edge_usd: gross,
        min_edge_usd: min_edge,
        fee_estimate_usd: fee,
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
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, PricerSide::Buy);
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
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, PricerSide::Sell);
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
    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, PricerSide::Buy);
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

    let inp = input(100.0, 10.0, 2.0, 3.0, 1.0, PricerSide::Sell);
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
    let inp = input(100.0, 5.0, 2.0, 4.0, 1.0, PricerSide::Buy);
    let result = compute_limit_price(&inp, &mut m);

    match result {
        PricerResult::Rejected {
            reason,
            net_edge_usd,
        } => {
            assert_eq!(reason, PricerRejectReason::NetEdgeTooLow);
            assert!((net_edge_usd.unwrap() - 1.0).abs() < 1e-9);
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
    assert_eq!(m.reject_total(), 1);
}

#[test]
fn test_negative_net_edge_rejected() {
    let mut m = PricerMetrics::new();

    // gross=3, fee=5 → net=-2 < 0 → reject
    let inp = input(100.0, 3.0, 0.0, 5.0, 1.0, PricerSide::Buy);
    let result = compute_limit_price(&inp, &mut m);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            ..
        }
    ));
}

// ─── Invalid input ──────────────────────────────────────────────────────

#[test]
fn test_zero_qty_rejected() {
    let mut m = PricerMetrics::new();

    let inp = input(100.0, 10.0, 2.0, 3.0, 0.0, PricerSide::Buy);
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

    let inp = input(100.0, 10.0, 2.0, 3.0, -1.0, PricerSide::Buy);
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
    let inp = input(100.0, 20.0, 4.0, 6.0, 2.0, PricerSide::Buy);
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
    let inp = input(100.0, 10.0, 1.0, 1.0, 1.0, PricerSide::Buy);
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
