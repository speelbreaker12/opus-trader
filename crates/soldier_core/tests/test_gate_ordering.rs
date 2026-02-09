//! Tests for single chokepoint gate ordering per CONTRACT.md CSP.5.2.
//!
//! AT-501: Gate ordering is deterministic — trace must match spec order.
//! AT-502: OPEN intents run all 8 gates.
//! AT-503: CLOSE/HEDGE skip liquidity/net-edge/pricer gates (5-7).
//! AT-504: CANCEL-only skips all gates after DispatchAuth.
//! AT-505: RiskState != Healthy blocks OPEN intents at gate 1.
//! AT-506: Each gate rejection stops evaluation (early-exit).

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    build_order_intent,
};
use soldier_core::risk::RiskState;

// ─── AT-501: Gate ordering is deterministic ──────────────────────────────

#[test]
fn test_at501_open_all_gates_pass_trace_order() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default(); // all pass

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(
                gate_trace,
                vec![
                    GateStep::DispatchAuth,
                    GateStep::Preflight,
                    GateStep::Quantize,
                    GateStep::FeeCacheCheck,
                    GateStep::LiquidityGate,
                    GateStep::NetEdgeGate,
                    GateStep::Pricer,
                    GateStep::RecordedBeforeDispatch,
                ],
                "OPEN intent gate trace must match spec ordering 1-8"
            );
        }
        other => panic!("expected Approved, got {other:?}"),
    }
    assert_eq!(m.approved_total(), 1);
}

// ─── AT-502: OPEN intents require all 8 gates ────────────────────────────

#[test]
fn test_at502_open_gate_count() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace.len(), 8, "OPEN must traverse all 8 gates");
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

// ─── AT-503: CLOSE/HEDGE skip gates 5-7 ──────────────────────────────────

#[test]
fn test_at503_close_skips_liquidity_edge_pricer() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Close, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(
                gate_trace,
                vec![
                    GateStep::DispatchAuth,
                    GateStep::Preflight,
                    GateStep::Quantize,
                    GateStep::FeeCacheCheck,
                    GateStep::RecordedBeforeDispatch,
                ],
                "CLOSE must skip LiquidityGate, NetEdgeGate, Pricer"
            );
            assert!(!gate_trace.contains(&GateStep::LiquidityGate));
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

#[test]
fn test_at503_hedge_skips_liquidity_edge_pricer() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Hedge, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert!(!gate_trace.contains(&GateStep::LiquidityGate));
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
            assert_eq!(gate_trace.len(), 5, "HEDGE must have 5 gates (skip 5-7)");
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

// ─── AT-504: CANCEL-only skips all gates after DispatchAuth ──────────────

#[test]
fn test_at504_cancel_only_dispatch_auth_only() {
    let mut m = ChokeMetrics::new();
    // Even with all gates failing, CANCEL should still approve
    let gates = GateResults {
        preflight_passed: false,
        quantize_passed: false,
        fee_cache_passed: false,
        liquidity_gate_passed: false,
        net_edge_passed: false,
        pricer_passed: false,
        wal_recorded: false,
    };

    let result = build_order_intent(
        ChokeIntentClass::CancelOnly,
        RiskState::Healthy,
        &mut m,
        &gates,
    );

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace, vec![GateStep::DispatchAuth]);
            assert_eq!(gate_trace.len(), 1);
        }
        other => panic!("expected Approved for CANCEL, got {other:?}"),
    }
    assert_eq!(m.approved_total(), 1);
}

#[test]
fn test_at504_cancel_approved_even_degraded() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    // CANCEL should pass even with Degraded risk state
    let result = build_order_intent(
        ChokeIntentClass::CancelOnly,
        RiskState::Degraded,
        &mut m,
        &gates,
    );

    assert!(matches!(result, ChokeResult::Approved { .. }));
}

// ─── AT-505: RiskState != Healthy blocks OPEN ────────────────────────────

#[test]
fn test_at505_open_degraded_rejected() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Degraded, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert_eq!(reason, ChokeRejectReason::RiskStateNotHealthy);
            assert_eq!(gate_trace, vec![GateStep::DispatchAuth]);
        }
        other => panic!("expected Rejected for OPEN+Degraded, got {other:?}"),
    }
    assert_eq!(m.rejected_total(), 1);
    assert_eq!(m.rejected_risk_state(), 1);
}

#[test]
fn test_at505_open_maintenance_rejected() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Maintenance,
        &mut m,
        &gates,
    );

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
}

#[test]
fn test_at505_open_kill_rejected() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Kill, &mut m, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
}

#[test]
fn test_at505_close_degraded_allowed() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    // CLOSE must pass even with Degraded (risk-reducing)
    let result = build_order_intent(ChokeIntentClass::Close, RiskState::Degraded, &mut m, &gates);

    assert!(matches!(result, ChokeResult::Approved { .. }));
}

#[test]
fn test_at505_hedge_degraded_allowed() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Hedge, RiskState::Degraded, &mut m, &gates);

    assert!(matches!(result, ChokeResult::Approved { .. }));
}

// ─── AT-506: Early-exit on gate failure ──────────────────────────────────

#[test]
fn test_at506_preflight_reject_stops_at_gate2() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        preflight_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Preflight,
                    ..
                }
            ));
            assert_eq!(
                gate_trace,
                vec![GateStep::DispatchAuth, GateStep::Preflight]
            );
        }
        other => panic!("expected Rejected at Preflight, got {other:?}"),
    }
}

#[test]
fn test_at506_quantize_reject_stops_at_gate3() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        quantize_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Quantize,
                    ..
                }
            ));
            assert_eq!(
                gate_trace,
                vec![
                    GateStep::DispatchAuth,
                    GateStep::Preflight,
                    GateStep::Quantize,
                ]
            );
        }
        other => panic!("expected Rejected at Quantize, got {other:?}"),
    }
}

#[test]
fn test_at506_fee_cache_reject_stops_at_gate4() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        fee_cache_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::FeeCacheCheck,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 4);
        }
        other => panic!("expected Rejected at FeeCacheCheck, got {other:?}"),
    }
}

#[test]
fn test_at506_liquidity_reject_stops_at_gate5() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        liquidity_gate_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 5);
        }
        other => panic!("expected Rejected at LiquidityGate, got {other:?}"),
    }
}

#[test]
fn test_at506_net_edge_reject_stops_at_gate6() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        net_edge_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::NetEdgeGate,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 6);
        }
        other => panic!("expected Rejected at NetEdgeGate, got {other:?}"),
    }
}

#[test]
fn test_at506_pricer_reject_stops_at_gate7() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        pricer_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Pricer,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 7);
        }
        other => panic!("expected Rejected at Pricer, got {other:?}"),
    }
}

#[test]
fn test_at506_wal_reject_stops_at_gate8() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        wal_recorded: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::RecordedBeforeDispatch,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 8);
        }
        other => panic!("expected Rejected at WAL, got {other:?}"),
    }
}

// ─── Metrics tracking ────────────────────────────────────────────────────

#[test]
fn test_metrics_approved_increments() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);
    build_order_intent(ChokeIntentClass::Close, RiskState::Healthy, &mut m, &gates);

    assert_eq!(m.approved_total(), 2);
    assert_eq!(m.rejected_total(), 0);
}

#[test]
fn test_metrics_rejected_increments() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        preflight_passed: false,
        ..GateResults::default()
    };

    build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    assert_eq!(m.rejected_total(), 1);
    assert_eq!(m.approved_total(), 0);
}

#[test]
fn test_metrics_risk_state_rejection_counted() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    build_order_intent(ChokeIntentClass::Open, RiskState::Degraded, &mut m, &gates);
    build_order_intent(ChokeIntentClass::Open, RiskState::Kill, &mut m, &gates);

    assert_eq!(m.rejected_risk_state(), 2);
    assert_eq!(m.rejected_total(), 2);
}

#[test]
fn test_metrics_default() {
    let m = ChokeMetrics::default();
    assert_eq!(m.approved_total(), 0);
    assert_eq!(m.rejected_total(), 0);
    assert_eq!(m.rejected_risk_state(), 0);
}

// ─── Close intent WAL rejection ─────────────────────────────────────────

#[test]
fn test_close_wal_failure_rejected() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        wal_recorded: false,
        ..GateResults::default()
    };

    // Even CLOSE intents must pass WAL gate
    let result = build_order_intent(ChokeIntentClass::Close, RiskState::Healthy, &mut m, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::RecordedBeforeDispatch,
                ..
            },
            ..
        }
    ));
}
