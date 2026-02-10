//! Tests for Net Edge Gate per CONTRACT.md §1.4.1.
//!
//! AT-015: net_edge_usd < min_edge_usd → reject, zero dispatch.
//! AT-932: Missing fee_usd or expected_slippage_usd → Rejected(NetEdgeInputMissing).

use soldier_core::execution::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};

/// Helper: build a complete net edge input.
fn full_input(gross: f64, fee: f64, slippage: f64, min_edge: f64) -> NetEdgeInput {
    NetEdgeInput {
        gross_edge_usd: Some(gross),
        fee_usd: Some(fee),
        expected_slippage_usd: Some(slippage),
        min_edge_usd: Some(min_edge),
    }
}

// ─── AT-015: Net edge too low → reject ──────────────────────────────────

#[test]
fn test_at015_net_edge_below_min_rejected() {
    let mut m = NetEdgeMetrics::new();

    // gross=10, fee=5, slippage=4 → net=1, min=2 → reject
    let input = full_input(10.0, 5.0, 4.0, 2.0);
    let result = evaluate_net_edge(&input, &mut m);

    match result {
        NetEdgeResult::Rejected {
            reason,
            net_edge_usd,
        } => {
            assert_eq!(reason, NetEdgeRejectReason::NetEdgeTooLow);
            assert!((net_edge_usd.unwrap() - 1.0).abs() < 1e-9);
        }
        other => panic!("expected Rejected(NetEdgeTooLow), got {other:?}"),
    }
    assert_eq!(m.reject_too_low(), 1);
}

#[test]
fn test_at015_zero_dispatch_on_rejection() {
    let mut m = NetEdgeMetrics::new();

    // Negative net edge
    let input = full_input(5.0, 3.0, 3.0, 1.0);
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeTooLow,
            ..
        }
    ));
    // Caller must NOT dispatch — rejection is the signal
}

#[test]
fn test_fees_exceed_gross_edge() {
    let mut m = NetEdgeMetrics::new();

    // gross=5, fee=3, slippage=3 → net=-1, min=0 → reject
    let input = full_input(5.0, 3.0, 3.0, 0.0);
    let result = evaluate_net_edge(&input, &mut m);

    match result {
        NetEdgeResult::Rejected {
            reason,
            net_edge_usd,
        } => {
            assert_eq!(reason, NetEdgeRejectReason::NetEdgeTooLow);
            assert!(net_edge_usd.unwrap() < 0.0);
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
}

// ─── Net edge sufficient → allowed ──────────────────────────────────────

#[test]
fn test_net_edge_above_min_allowed() {
    let mut m = NetEdgeMetrics::new();

    // gross=10, fee=2, slippage=1 → net=7, min=5 → allowed
    let input = full_input(10.0, 2.0, 1.0, 5.0);
    let result = evaluate_net_edge(&input, &mut m);

    match result {
        NetEdgeResult::Allowed { net_edge_usd } => {
            assert!((net_edge_usd - 7.0).abs() < 1e-9);
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
    assert_eq!(m.allowed_total(), 1);
}

#[test]
fn test_net_edge_exactly_at_min_allowed() {
    let mut m = NetEdgeMetrics::new();

    // gross=10, fee=3, slippage=2 → net=5, min=5 → allowed (not strictly less)
    let input = full_input(10.0, 3.0, 2.0, 5.0);
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(result, NetEdgeResult::Allowed { .. }));
}

#[test]
fn test_zero_costs_full_edge() {
    let mut m = NetEdgeMetrics::new();

    // No fees or slippage
    let input = full_input(10.0, 0.0, 0.0, 5.0);
    let result = evaluate_net_edge(&input, &mut m);

    match result {
        NetEdgeResult::Allowed { net_edge_usd } => {
            assert!((net_edge_usd - 10.0).abs() < 1e-9);
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
}

// ─── AT-932: Missing inputs → NetEdgeInputMissing ───────────────────────

#[test]
fn test_at932_missing_gross_edge() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: None,
        fee_usd: Some(2.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(5.0),
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            net_edge_usd: None,
        }
    ));
    assert_eq!(m.reject_input_missing(), 1);
}

#[test]
fn test_at932_missing_fee_usd() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: None,
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(5.0),
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_at932_missing_expected_slippage() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(2.0),
        expected_slippage_usd: None,
        min_edge_usd: Some(5.0),
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_at932_missing_min_edge() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(2.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: None,
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_at932_all_missing() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: None,
        fee_usd: None,
        expected_slippage_usd: None,
        min_edge_usd: None,
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_non_finite_gross_fails_closed() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(f64::NAN),
        fee_usd: Some(2.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(5.0),
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            net_edge_usd: None,
        }
    ));
}

#[test]
fn test_non_finite_min_edge_fails_closed() {
    let mut m = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(2.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(f64::INFINITY),
    };
    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            net_edge_usd: None,
        }
    ));
}

// ─── Net edge computation ───────────────────────────────────────────────

#[test]
fn test_net_edge_formula() {
    let mut m = NetEdgeMetrics::new();

    // net = gross - fee - slippage = 100 - 30 - 20 = 50
    let input = full_input(100.0, 30.0, 20.0, 10.0);
    let result = evaluate_net_edge(&input, &mut m);

    match result {
        NetEdgeResult::Allowed { net_edge_usd } => {
            assert!((net_edge_usd - 50.0).abs() < 1e-9);
        }
        other => panic!("expected Allowed, got {other:?}"),
    }
}

// ─── Metrics default ────────────────────────────────────────────────────

#[test]
fn test_metrics_default() {
    let m = NetEdgeMetrics::default();
    assert_eq!(m.reject_too_low(), 0);
    assert_eq!(m.reject_input_missing(), 0);
    assert_eq!(m.allowed_total(), 0);
}
