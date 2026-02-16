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
//! - GI-001, GI-004, GI-009: pipeline (via evaluate_intent_pipeline)
//! - GI-002, GI-017, GI-020: module (direct module function)

mod common;

use soldier_core::execution::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateStep, IntentPipelineMetrics,
    RejectReasonCode, evaluate_intent_pipeline,
};
use soldier_core::idempotency::{IntentHashInput, compute_intent_hash};
use soldier_core::risk::RiskState;

// ─── GI-001: OPEN dispatch requires Active ────────────────────────────────

#[test]
fn gi_001_blocks_open_when_risk_degraded() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // ATTACK: Set risk_state to non-Healthy
    input.risk_state = RiskState::Degraded;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // 1. Must be Rejected with RiskStateNotHealthy
    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
        }
        other => panic!("GI-001 violation not blocked: {other:?}"),
    }

    // 2. Reject reason code from YAML frontmatter: MarginHeadroomRejectOpens
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens)
    );

    // 3. Chokepoint metrics confirm rejection
    assert_eq!(metrics.chokepoint.approved_total(), 0);
    assert_eq!(metrics.chokepoint.rejected_total(), 1);
}

#[test]
fn gi_001_blocks_open_when_risk_maintenance() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    input.risk_state = RiskState::Maintenance;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
        }
        other => panic!("GI-001 violation not blocked for Maintenance: {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens)
    );
}

#[test]
fn gi_001_blocks_open_when_risk_kill() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    input.risk_state = RiskState::Kill;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
        }
        other => panic!("GI-001 violation not blocked for Kill: {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens)
    );
}

#[test]
fn gi_001_allows_open_when_risk_healthy() {
    let input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Approved { gate_trace } => {
            assert!(!gate_trace.is_empty(), "Expected gate trace, got empty");
        }
        other => panic!("Baseline regression: {other:?}"),
    }
    assert_eq!(result.reject_reason_code, None);
}

// ─── GI-002: Intent classification fail-closed ────────────────────────────
//
// Test level: module
// Verify: Open intent_class applies risk_state gate; Close/CancelOnly does not.
// This proves classification affects gating behavior (fail-closed = Open = most restrictive).

#[test]
fn gi_002_open_class_applies_risk_state_gate() {
    let mut input = common::base_open_input();
    input.intent_class = ChokeIntentClass::Open;
    input.risk_state = RiskState::Degraded;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Open + Degraded → MUST be rejected (risk gate applied)
    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
        }
        other => panic!("GI-002: Open class did not apply risk gate: {other:?}"),
    }
}

#[test]
fn gi_002_close_class_skips_risk_state_gate() {
    let mut input = common::base_open_input();
    input.intent_class = ChokeIntentClass::Close;
    input.risk_state = RiskState::Degraded;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Close + Degraded → MUST NOT be rejected with RiskStateNotHealthy
    // (Close intents bypass the Open-only risk gate)
    assert!(
        result.reject_reason_code != Some(RejectReasonCode::MarginHeadroomRejectOpens),
        "GI-002: Close class incorrectly applied Open risk gate"
    );
}

#[test]
fn gi_002_cancel_only_always_approved() {
    let mut input = common::base_open_input();
    input.intent_class = ChokeIntentClass::CancelOnly;
    input.risk_state = RiskState::Kill;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace, &vec![GateStep::DispatchAuth]);
        }
        other => panic!("GI-002: CancelOnly should always be approved: {other:?}"),
    }
}

// ─── GI-004: WAL enqueue required for OPEN ────────────────────────────────

#[test]
fn gi_004_blocks_open_without_wal_recorded() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // ATTACK: WAL not recorded
    input.wal_recorded = false;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Must be Rejected
    match &result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::RecordedBeforeDispatch,
                        ..
                    }
                ),
                "GI-004: expected RecordedBeforeDispatch rejection, got {reason:?}"
            );
            assert!(gate_trace.contains(&GateStep::RecordedBeforeDispatch));
        }
        other => panic!("GI-004 violation not blocked: {other:?}"),
    }

    // Reject reason code from YAML frontmatter: RecordedBeforeDispatchFailed
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::RecordedBeforeDispatchFailed)
    );
}

#[test]
fn gi_004_allows_open_with_wal_recorded() {
    let input = common::base_open_input(); // wal_recorded = true
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Approved { gate_trace } => {
            assert!(gate_trace.contains(&GateStep::RecordedBeforeDispatch));
        }
        other => panic!("GI-004 baseline regression: {other:?}"),
    }
    assert_eq!(result.reject_reason_code, None);
}

// ─── GI-009: Critical input freshness gate ────────────────────────────────

#[test]
fn gi_009_blocks_open_when_fee_cache_missing() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // ATTACK: Fee cache timestamp missing → hard-stale
    input.fee_snapshot.fee_model_cached_at_ts_ms = None;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Must be Rejected at FeeCacheStaleness gate
    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::FeeCacheCheck,
                        ..
                    }
                ),
                "GI-009: expected FeeCacheStaleness rejection, got {reason:?}"
            );
        }
        other => panic!("GI-009 violation not blocked: {other:?}"),
    }

    // Reject reason code from YAML frontmatter: FeeCacheStale
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::FeeCacheStale)
    );
}

#[test]
fn gi_009_blocks_open_when_fee_cache_hard_stale() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // ATTACK: Fee cache extremely old (hard-stale)
    input.fee_snapshot.fee_model_cached_at_ts_ms = Some(1); // Very old
    input.fee_snapshot.now_ms = 10_000_000; // Way past hard threshold

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Rejected { .. } => {}
        other => panic!("GI-009: hard-stale fee cache should reject: {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::FeeCacheStale)
    );
}

#[test]
fn gi_009_allows_open_when_fee_cache_fresh() {
    let input = common::base_open_input(); // fee_model_cached_at_ts_ms = Some(1_000_000)
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match &result.decision {
        ChokeResult::Approved { .. } => {}
        other => panic!("GI-009 baseline regression: {other:?}"),
    }
    assert_eq!(result.reject_reason_code, None);
}

// ─── GI-017: Emergency close bypasses profitability gates ─────────────────
//
// Test level: module
// Verify: Close/Hedge intents bypass liquidity/net_edge/pricer gates even
// when those gates would fail for Open intents.

#[test]
fn gi_017_close_bypasses_liquidity_gate() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // Set up condition that would fail liquidity gate for Open
    input.liquidity = None; // Missing L2 → LiquidityGateNoL2 for Open

    // Change to Close intent
    input.intent_class = ChokeIntentClass::Close;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Close intent MUST NOT be rejected with liquidity gate codes
    assert!(
        result.reject_reason_code != Some(RejectReasonCode::LiquidityGateNoL2),
        "GI-017: Close intent was blocked by LiquidityGate"
    );
    assert!(
        result.reject_reason_code != Some(RejectReasonCode::ExpectedSlippageTooHigh),
        "GI-017: Close intent was blocked by slippage check"
    );
    assert!(
        result.reject_reason_code != Some(RejectReasonCode::InsufficientDepthWithinBudget),
        "GI-017: Close intent was blocked by depth check"
    );
}

#[test]
fn gi_017_close_bypasses_net_edge_gate() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // Set up condition that would fail net edge gate for Open
    input.net_edge = None; // Missing → NetEdgeInputMissing for Open

    // Change to Close intent
    input.intent_class = ChokeIntentClass::Close;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    assert!(
        result.reject_reason_code != Some(RejectReasonCode::NetEdgeTooLow),
        "GI-017: Close intent was blocked by NetEdge"
    );
    assert!(
        result.reject_reason_code != Some(RejectReasonCode::NetEdgeInputMissing),
        "GI-017: Close intent was blocked by missing NetEdge input"
    );
}

#[test]
fn gi_017_open_fails_without_liquidity() {
    let mut input = common::base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    // Same condition as Close test above, but for Open
    input.liquidity = None;
    input.intent_class = ChokeIntentClass::Open;

    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Open MUST be rejected (proves Close bypass is the differential)
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::LiquidityGateNoL2),
        "GI-017: Open intent SHOULD be blocked by missing LiquidityGate"
    );
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
