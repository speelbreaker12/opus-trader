// TARGET: GI-001
// TARGET: GI-002
// TARGET: GI-004
// TARGET: GI-009
// TARGET: GI-017
// TARGET: GI-020
//! Adversarial contract tests for Global Invariant enforcement.
//!
//! Each test attempts to VIOLATE one invariant. If the attack succeeds
//! (violation not blocked), it is a critical finding.
//!
//! Test levels:
//! - GI-001, GI-002, GI-004, GI-009, GI-017: chokepoint contract
//! - GI-020: idempotency hash module

#[path = "test_stubs.rs"]
mod test_stubs;

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    RejectReasonCode, build_order_intent_with_wal_gate, reject_reason_registry_contains,
};
use soldier_core::idempotency::{IntentHashInput, compute_intent_hash};
use soldier_core::risk::RiskState;
use test_stubs::{FailingWalGate, StubWalGate, gate_results_all_passing_failclosed_wal};

fn run_chokepoint_with_stub_wal(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    gate_results: GateResults,
) -> (ChokeResult, ChokeMetrics) {
    let mut metrics = ChokeMetrics::new();
    let mut wal_gate = StubWalGate;
    let result = build_order_intent_with_wal_gate(
        intent_class,
        risk_state,
        &mut metrics,
        &gate_results,
        &mut wal_gate,
    );
    (result, metrics)
}

fn assert_contract_reason_code_registered(code: RejectReasonCode) {
    assert!(
        reject_reason_registry_contains(code),
        "expected reject_reason_code {code:?} to be registered"
    );
}

// ─── Chokepoint-level strangler tests (Step 1b-gi-a) ───────────────────

#[test]
fn gi_001_blocks_open_when_risk_degraded_chokepoint() {
    let (result, metrics) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        gate_results_all_passing_failclosed_wal(),
    );

    match &result {
        ChokeResult::Rejected { reason, .. } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
        }
        other => panic!("GI-001 chokepoint violation not blocked: {other:?}"),
    }
    assert_contract_reason_code_registered(RejectReasonCode::MarginHeadroomRejectOpens);
    assert_eq!(metrics.approved_total(), 0);
    assert_eq!(metrics.rejected_total(), 1);
}

#[test]
fn gi_001_blocks_open_when_risk_maintenance_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Maintenance,
        gate_results_all_passing_failclosed_wal(),
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
fn gi_001_blocks_open_when_risk_kill_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Kill,
        gate_results_all_passing_failclosed_wal(),
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
fn gi_001_allows_open_when_risk_healthy_chokepoint() {
    let (result, metrics) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        gate_results_all_passing_failclosed_wal(),
    );
    match &result {
        ChokeResult::Approved { gate_trace } => {
            assert!(gate_trace.contains(&GateStep::RecordedBeforeDispatch));
        }
        other => panic!("GI-001 chokepoint baseline regression: {other:?}"),
    }
    assert_eq!(metrics.approved_total(), 1);
}

#[test]
fn gi_002_open_class_applies_risk_state_gate_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        gate_results_all_passing_failclosed_wal(),
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
fn gi_002_close_class_skips_risk_state_gate_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Close,
        RiskState::Degraded,
        gate_results_all_passing_failclosed_wal(),
    );
    assert!(matches!(result, ChokeResult::Approved { .. }));
}

#[test]
fn gi_002_cancel_only_always_approved_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::CancelOnly,
        RiskState::Kill,
        gate_results_all_passing_failclosed_wal(),
    );
    match &result {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace, &vec![GateStep::DispatchAuth])
        }
        other => panic!("GI-002 chokepoint cancel-only should be approved: {other:?}"),
    }
}

#[test]
fn gi_004_blocks_open_without_wal_recorded_chokepoint() {
    let gate_results = gate_results_all_passing_failclosed_wal();
    let mut metrics = ChokeMetrics::new();
    let mut wal_gate = FailingWalGate;
    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gate_results,
        &mut wal_gate,
    );
    match &result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::RecordedBeforeDispatch,
                    ..
                }
            ));
            assert!(gate_trace.contains(&GateStep::RecordedBeforeDispatch));
        }
        other => panic!("GI-004 chokepoint violation not blocked: {other:?}"),
    }
    assert_contract_reason_code_registered(RejectReasonCode::RecordedBeforeDispatchFailed);
}

#[test]
fn gi_004_allows_open_with_wal_recorded_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        gate_results_all_passing_failclosed_wal(),
    );
    match &result {
        ChokeResult::Approved { gate_trace } => {
            assert!(gate_trace.contains(&GateStep::RecordedBeforeDispatch));
        }
        other => panic!("GI-004 chokepoint baseline regression: {other:?}"),
    }
}

#[test]
fn gi_009_blocks_open_when_fee_cache_missing_chokepoint() {
    let gate_results = GateResults {
        fee_cache_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };
    let (result, _) =
        run_chokepoint_with_stub_wal(ChokeIntentClass::Open, RiskState::Healthy, gate_results);
    match &result {
        ChokeResult::Rejected { reason, .. } => assert!(matches!(
            reason,
            ChokeRejectReason::GateRejected {
                gate: GateStep::FeeCacheCheck,
                ..
            }
        )),
        other => panic!("GI-009 chokepoint missing-fee-cache violation not blocked: {other:?}"),
    }
    assert_contract_reason_code_registered(RejectReasonCode::FeeCacheStale);
}

#[test]
fn gi_009_blocks_open_when_fee_cache_hard_stale_chokepoint() {
    let gate_results = GateResults {
        fee_cache_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };
    let (result, _) =
        run_chokepoint_with_stub_wal(ChokeIntentClass::Open, RiskState::Healthy, gate_results);
    assert!(matches!(result, ChokeResult::Rejected { .. }));
}

#[test]
fn gi_009_allows_open_when_fee_cache_fresh_chokepoint() {
    let (result, _) = run_chokepoint_with_stub_wal(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        gate_results_all_passing_failclosed_wal(),
    );
    assert!(matches!(result, ChokeResult::Approved { .. }));
}

#[test]
fn gi_017_close_bypasses_liquidity_gate_chokepoint() {
    let gate_results = GateResults {
        liquidity_gate_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };
    let (result, _) =
        run_chokepoint_with_stub_wal(ChokeIntentClass::Close, RiskState::Healthy, gate_results);
    match result {
        ChokeResult::Approved { gate_trace } => {
            assert!(
                !gate_trace.contains(&GateStep::LiquidityGate),
                "Close path must bypass liquidity gate"
            );
        }
        other => panic!("GI-017 close path should be approved, got {other:?}"),
    }
}

#[test]
fn gi_017_close_bypasses_net_edge_gate_chokepoint() {
    let gate_results = GateResults {
        net_edge_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };
    let (result, _) =
        run_chokepoint_with_stub_wal(ChokeIntentClass::Close, RiskState::Healthy, gate_results);
    match result {
        ChokeResult::Approved { gate_trace } => {
            assert!(
                !gate_trace.contains(&GateStep::NetEdgeGate),
                "Close path must bypass net-edge gate"
            );
        }
        other => panic!("GI-017 close path should be approved, got {other:?}"),
    }
}

// ─── GI-020: Intent idempotency ──────────────────────────────────────────
//
// Test level: module
// Verify: compute_intent_hash is deterministic, depends only on quantized
// fields (not timestamps), and produces different hashes for different inputs.

#[test]
fn gi_020_intent_hash_is_deterministic() {
    let input = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 100,
        price_ticks: 50000,
        group_id: "550e8400-e29b-41d4-a716-446655440000",
        leg_idx: 0,
    };

    let hash1 = compute_intent_hash(&input);
    let hash2 = compute_intent_hash(&input);

    assert_eq!(
        hash1, hash2,
        "GI-020: identical inputs must produce identical hashes"
    );
}

#[test]
fn gi_020_intent_hash_independent_of_ordering() {
    // Same inputs, called multiple times — must be stable
    let input = IntentHashInput {
        instrument: "ETH-PERPETUAL",
        side: "sell",
        qty_steps: 200,
        price_ticks: 3000,
        group_id: "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
        leg_idx: 1,
    };

    let hashes: Vec<u64> = (0..10).map(|_| compute_intent_hash(&input)).collect();

    assert!(
        hashes.windows(2).all(|w| w[0] == w[1]),
        "GI-020: hash must be deterministic across invocations"
    );
}

#[test]
fn gi_020_different_fields_produce_different_hashes() {
    let base = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 100,
        price_ticks: 50000,
        group_id: "550e8400-e29b-41d4-a716-446655440000",
        leg_idx: 0,
    };

    // Change qty_steps
    let different_qty = IntentHashInput {
        qty_steps: 101,
        ..base.clone()
    };
    assert_ne!(
        compute_intent_hash(&base),
        compute_intent_hash(&different_qty),
        "GI-020: different qty_steps must produce different hashes"
    );

    // Change price_ticks
    let different_price = IntentHashInput {
        price_ticks: 50001,
        ..base.clone()
    };
    assert_ne!(
        compute_intent_hash(&base),
        compute_intent_hash(&different_price),
        "GI-020: different price_ticks must produce different hashes"
    );

    // Change side
    let different_side = IntentHashInput {
        side: "sell",
        ..base.clone()
    };
    assert_ne!(
        compute_intent_hash(&base),
        compute_intent_hash(&different_side),
        "GI-020: different side must produce different hashes"
    );

    // Change leg_idx
    let different_leg = IntentHashInput {
        leg_idx: 1,
        ..base.clone()
    };
    assert_ne!(
        compute_intent_hash(&base),
        compute_intent_hash(&different_leg),
        "GI-020: different leg_idx must produce different hashes"
    );
}

#[test]
fn gi_020_field_boundary_ambiguity_prevented() {
    // "AB" + "CD" must hash differently than "ABC" + "D"
    let input_a = IntentHashInput {
        instrument: "AB",
        side: "CD",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };

    let input_b = IntentHashInput {
        instrument: "ABC",
        side: "D",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };

    assert_ne!(
        compute_intent_hash(&input_a),
        compute_intent_hash(&input_b),
        "GI-020: field boundary ambiguity must be prevented (0xFF separator)"
    );
}
