//! Tests for single chokepoint gate ordering per CONTRACT.md CSP.5.2.
//!
//! AT-501: Gate ordering is deterministic — trace must match spec order.
//! AT-502: OPEN intents run all 9 gates.
//! AT-503: CLOSE/HEDGE skip liquidity/net-edge/pricer gates (6-8).
//! AT-504: CANCEL-only skips all gates after DispatchAuth.
//! AT-505: RiskState != Healthy blocks OPEN intents at gate 1.
//! AT-506: Each gate rejection stops evaluation (early-exit).
//!
//! Gate ordering constraints (S6-004):
//! C1: All reject gates run before RecordedBeforeDispatch (persist).
//! C2: RecordedBeforeDispatch (WAL) is the last gate before dispatch.
//! C3: No side effects (approval) occur before all gates pass.

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults,
    GateSequenceResult, GateStep, build_order_intent, gate_sequence_total,
    take_execution_metric_lines, with_intent_trace_ids,
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
                    GateStep::DispatchConsistency,
                    GateStep::FeeCacheCheck,
                    GateStep::LiquidityGate,
                    GateStep::NetEdgeGate,
                    GateStep::Pricer,
                    GateStep::RecordedBeforeDispatch,
                ],
                "OPEN intent gate trace must match spec ordering 1-9"
            );
        }
        other => panic!("expected Approved, got {other:?}"),
    }
    assert_eq!(m.approved_total(), 1);
}

#[test]
fn test_gate_sequence_emits_structured_reject_metric_line() {
    let intent_id = "intent-gateseq-001";
    let run_id = "run-gateseq-001";
    let _ = take_execution_metric_lines();

    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();
    let result = with_intent_trace_ids(intent_id, run_id, || {
        build_order_intent(
            ChokeIntentClass::Open,
            RiskState::Degraded,
            &mut metrics,
            &gates,
        )
    });
    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));

    let after = gate_sequence_total(GateSequenceResult::Rejected);
    assert!(after >= 1, "counter must be non-zero after a reject");

    let lines = take_execution_metric_lines();
    let tagged_lines = lines
        .iter()
        .filter(|line| {
            line.starts_with("gate_sequence_total")
                && line.contains("result=rejected")
                && line.contains(&format!("intent_id={intent_id}"))
                && line.contains(&format!("run_id={run_id}"))
        })
        .count();
    assert_eq!(
        tagged_lines, 1,
        "expected exactly one tagged gate sequence metric line, got {lines:?}"
    );
    assert!(
        lines.iter().any(|line| line.starts_with("gate_sequence_total")),
        "expected gate sequence metric line, got {lines:?}"
    );
}

// ─── AT-502: OPEN intents require all 9 gates ────────────────────────────

#[test]
fn test_at502_open_gate_count() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace.len(), 9, "OPEN must traverse all 9 gates");
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

// ─── AT-503: CLOSE/HEDGE skip gates 6-8 ──────────────────────────────────

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
                    GateStep::DispatchConsistency,
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
            assert_eq!(gate_trace.len(), 6, "HEDGE must have 6 gates (skip 6-8)");
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
        dispatch_consistency_passed: false,
        fee_cache_passed: false,
        liquidity_gate_passed: false,
        net_edge_passed: false,
        pricer_passed: false,
        wal_recorded: false,
        requested_qty: None,
        max_dispatch_qty: None,
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
fn test_at506_dispatch_consistency_reject_stops_at_gate4() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        dispatch_consistency_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::DispatchConsistency,
                    ..
                }
            ));
            assert_eq!(gate_trace.len(), 4);
        }
        other => panic!("expected Rejected at DispatchConsistency, got {other:?}"),
    }
}

#[test]
fn test_at506_fee_cache_reject_stops_at_gate5() {
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
            assert_eq!(gate_trace.len(), 5);
        }
        other => panic!("expected Rejected at FeeCacheCheck, got {other:?}"),
    }
}

#[test]
fn test_at506_liquidity_reject_stops_at_gate6() {
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
            assert_eq!(gate_trace.len(), 6);
        }
        other => panic!("expected Rejected at LiquidityGate, got {other:?}"),
    }
}

#[test]
fn test_at506_net_edge_reject_stops_at_gate7() {
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
            assert_eq!(gate_trace.len(), 7);
        }
        other => panic!("expected Rejected at NetEdgeGate, got {other:?}"),
    }
}

#[test]
fn test_at506_pricer_reject_stops_at_gate8() {
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
            assert_eq!(gate_trace.len(), 8);
        }
        other => panic!("expected Rejected at Pricer, got {other:?}"),
    }
}

#[test]
fn test_at506_wal_reject_stops_at_gate9() {
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
            assert_eq!(gate_trace.len(), 9);
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

// ═══════════════════════════════════════════════════════════════════════════
// S6-004: Gate Ordering Constraints
// ═══════════════════════════════════════════════════════════════════════════

// ─── C1: All reject gates run before persist (RecordedBeforeDispatch) ────

#[test]
fn test_constraint_reject_gates_before_persist() {
    // For every gate that can reject, verify it appears BEFORE
    // RecordedBeforeDispatch in the trace.
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            let wal_pos = gate_trace
                .iter()
                .position(|g| *g == GateStep::RecordedBeforeDispatch)
                .expect("RecordedBeforeDispatch must be in trace");

            // Every reject-capable gate must come before WAL
            let reject_gates = [
                GateStep::DispatchAuth,
                GateStep::Preflight,
                GateStep::Quantize,
                GateStep::DispatchConsistency,
                GateStep::FeeCacheCheck,
                GateStep::LiquidityGate,
                GateStep::NetEdgeGate,
                GateStep::Pricer,
            ];

            for gate in &reject_gates {
                let pos = gate_trace
                    .iter()
                    .position(|g| g == gate)
                    .unwrap_or_else(|| panic!("{gate:?} must be in OPEN trace"));
                assert!(
                    pos < wal_pos,
                    "{gate:?} at position {pos} must come before RecordedBeforeDispatch at {wal_pos}"
                );
            }
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

// ─── C2: RecordedBeforeDispatch is always the LAST gate ──────────────────

#[test]
fn test_constraint_wal_is_last_gate_open() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(
                gate_trace.last(),
                Some(&GateStep::RecordedBeforeDispatch),
                "RecordedBeforeDispatch must be the last gate for OPEN"
            );
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

#[test]
fn test_constraint_wal_is_last_gate_close() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Close, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(
                gate_trace.last(),
                Some(&GateStep::RecordedBeforeDispatch),
                "RecordedBeforeDispatch must be the last gate for CLOSE"
            );
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

#[test]
fn test_constraint_wal_is_last_gate_hedge() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent(ChokeIntentClass::Hedge, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(
                gate_trace.last(),
                Some(&GateStep::RecordedBeforeDispatch),
                "RecordedBeforeDispatch must be the last gate for HEDGE"
            );
        }
        other => panic!("expected Approved, got {other:?}"),
    }
}

// ─── C3: No approval before all gates pass ───────────────────────────────

#[test]
fn test_constraint_no_approval_with_any_gate_failed() {
    // Exhaustively test: if ANY gate fails, result is Rejected (not Approved)
    let cases: Vec<(&str, GateResults)> = vec![
        (
            "preflight",
            GateResults {
                preflight_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "quantize",
            GateResults {
                quantize_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "dispatch_consistency",
            GateResults {
                dispatch_consistency_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "fee_cache",
            GateResults {
                fee_cache_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "liquidity",
            GateResults {
                liquidity_gate_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "net_edge",
            GateResults {
                net_edge_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "pricer",
            GateResults {
                pricer_passed: false,
                ..GateResults::default()
            },
        ),
        (
            "wal",
            GateResults {
                wal_recorded: false,
                ..GateResults::default()
            },
        ),
    ];

    for (name, gates) in &cases {
        let mut m = ChokeMetrics::new();
        let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, gates);

        assert!(
            matches!(result, ChokeResult::Rejected { .. }),
            "Gate '{name}' failed but got Approved — violates C3 constraint"
        );
    }
}

// ─── C3b: Approval only when ALL gates pass ──────────────────────────────

#[test]
fn test_constraint_approval_requires_all_gates_pass() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults::default(); // all true

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    assert!(
        matches!(result, ChokeResult::Approved { .. }),
        "All gates passed but result is not Approved"
    );
    assert_eq!(m.approved_total(), 1);
    assert_eq!(m.rejected_total(), 0);
}

// ─── C1b: Rejected trace never includes gates after the failing one ──────

#[test]
fn test_constraint_rejected_trace_stops_at_failure() {
    // When preflight fails, gates 3-9 must NOT appear in the trace
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        preflight_passed: false,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    match result {
        ChokeResult::Rejected { gate_trace, .. } => {
            let later_gates = [
                GateStep::Quantize,
                GateStep::DispatchConsistency,
                GateStep::FeeCacheCheck,
                GateStep::LiquidityGate,
                GateStep::NetEdgeGate,
                GateStep::Pricer,
                GateStep::RecordedBeforeDispatch,
            ];
            for gate in &later_gates {
                assert!(
                    !gate_trace.contains(gate),
                    "{gate:?} must NOT appear after Preflight rejection"
                );
            }
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
}

// ─── WAL must come after all validation gates (ordering proof) ───────────

#[test]
fn test_constraint_wal_after_all_validation_gates() {
    // Prove that for every intent class that reaches WAL,
    // all validation gates appear before it.
    for intent_class in [
        ChokeIntentClass::Open,
        ChokeIntentClass::Close,
        ChokeIntentClass::Hedge,
    ] {
        let mut m = ChokeMetrics::new();
        let gates = GateResults::default();

        let result = build_order_intent(intent_class, RiskState::Healthy, &mut m, &gates);

        match result {
            ChokeResult::Approved { gate_trace } => {
                let wal_pos = gate_trace
                    .iter()
                    .position(|g| *g == GateStep::RecordedBeforeDispatch)
                    .unwrap_or_else(|| panic!("WAL must be in trace for {intent_class:?}"));

                // WAL must be the last element
                assert_eq!(
                    wal_pos,
                    gate_trace.len() - 1,
                    "WAL must be last gate for {intent_class:?}, but was at position {wal_pos} of {}",
                    gate_trace.len()
                );
            }
            other => panic!("expected Approved for {intent_class:?}, got {other:?}"),
        }
    }
}

#[test]
fn test_dispatch_consistency_rejects_when_requested_qty_exceeds_clamp() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        requested_qty: Some(5.0),
        max_dispatch_qty: Some(2.0),
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::DispatchConsistency,
                ..
            },
            ..
        }
    ));
}

#[test]
fn test_dispatch_consistency_allows_when_requested_qty_within_clamp() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        requested_qty: Some(2.0),
        max_dispatch_qty: Some(2.0),
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);
    assert!(matches!(result, ChokeResult::Approved { .. }));
}

#[test]
fn test_dispatch_consistency_rejects_when_clamp_requested_qty_missing() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        requested_qty: None,
        max_dispatch_qty: Some(2.0),
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::DispatchConsistency,
                ..
            },
            ..
        }
    ));
}

#[test]
fn test_dispatch_consistency_rejects_when_clamp_max_dispatch_qty_missing() {
    let mut m = ChokeMetrics::new();
    let gates = GateResults {
        requested_qty: Some(2.0),
        max_dispatch_qty: None,
        ..GateResults::default()
    };

    let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::DispatchConsistency,
                ..
            },
            ..
        }
    ));
}
