//! Integration tests for execution pipeline orchestration.

mod common;

use soldier_core::execution::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateStep, IntentPipelineMetrics,
    LiquidityGateInput, OrderType, PostOnlyInput, RejectReasonCode, Side, evaluate_intent_pipeline,
};
use soldier_core::risk::RiskState;
use soldier_core::venue::{BotFeatureFlags, InstrumentKind, VenueCapabilities};

use common::base_open_input;

#[test]
fn test_pipeline_open_happy_path_approved() {
    let input = base_open_input();
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace.last(), Some(&GateStep::RecordedBeforeDispatch));
            assert!(gate_trace.contains(&GateStep::LiquidityGate));
            assert!(gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected Approved, got {other:?}"),
    }
    assert_eq!(result.reject_reason_code, None);
}

#[test]
fn test_pipeline_open_missing_l2_rejected_at_liquidity_gate() {
    let mut input = base_open_input();
    input.liquidity = Some(LiquidityGateInput {
        l2_snapshot: None,
        ..input.liquidity.take().expect("base input has liquidity")
    });
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    ..
                }
            ));
            assert!(gate_trace.contains(&GateStep::LiquidityGate));
        }
        other => panic!("expected Rejected at LiquidityGate, got {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::LiquidityGateNoL2)
    );
}

#[test]
fn test_pipeline_open_market_order_maps_preflight_reject_reason() {
    let mut input = base_open_input();
    input.preflight.order_type = OrderType::Market;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Preflight,
                    ..
                }
            ));
            assert!(gate_trace.contains(&GateStep::Preflight));
        }
        other => panic!("expected Rejected at Preflight, got {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::OrderTypeMarketForbidden)
    );
}

#[test]
fn test_pipeline_post_only_cross_rejected_at_preflight() {
    let mut input = base_open_input();
    input.preflight.instrument_kind = InstrumentKind::Perpetual;
    input.preflight.post_only_input = Some(PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price: 100.0,
        best_ask: Some(100.0),
        best_bid: None,
    });
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Preflight,
                    ..
                }
            ));
            assert_eq!(gate_trace.last(), Some(&GateStep::Preflight));
        }
        other => panic!("expected Rejected at Preflight, got {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::PostOnlyWouldCross)
    );
}

#[test]
fn test_pipeline_capabilities_matrix_overrides_preflight_linked_flag() {
    let mut input = base_open_input();
    input.preflight.instrument_kind = InstrumentKind::Perpetual;
    input.preflight.linked_order_type = Some("oco");
    // Caller-provided value should be ignored in favor of evaluated capabilities.
    input.preflight.linked_orders_allowed = true;
    input.venue_capabilities = VenueCapabilities {
        linked_orders_supported: false,
    };
    input.bot_feature_flags = BotFeatureFlags {
        enable_linked_orders: false,
    };
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::Preflight,
                    ..
                }
            ));
            assert_eq!(gate_trace.last(), Some(&GateStep::Preflight));
        }
        other => panic!("expected Rejected at Preflight, got {other:?}"),
    }
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::LinkedOrderTypeForbidden)
    );
}

#[test]
fn test_pipeline_cancel_only_skips_preflight_and_quantize_side_effects() {
    let mut input = base_open_input();
    input.intent_class = ChokeIntentClass::CancelOnly;
    input.preflight.order_type = OrderType::Market;
    input.quantize.raw_qty = 0.0;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Approved { gate_trace } => {
            assert_eq!(gate_trace, vec![GateStep::DispatchAuth]);
        }
        other => panic!("expected Approved cancel-only decision, got {other:?}"),
    }

    assert_eq!(result.reject_reason_code, None);
    assert_eq!(metrics.preflight.reject_total(), 0);
    assert_eq!(metrics.quantize.reject_too_small_total(), 0);
}

#[test]
fn test_pipeline_open_degraded_skips_preflight_side_effects() {
    let mut input = base_open_input();
    input.risk_state = RiskState::Degraded;
    input.preflight.order_type = OrderType::Market;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
            assert_eq!(gate_trace, vec![GateStep::DispatchAuth]);
        }
        other => panic!("expected DispatchAuth rejection, got {other:?}"),
    }

    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens)
    );
    assert_eq!(metrics.preflight.reject_total(), 0);
}

/// AT-104 causality — pipeline level.
/// Companion to test_instrument_cache_ttl.rs::test_stale_cache_blocks_opens (proves stale→Degraded).
/// This test proves: Degraded → OPEN dispatch=0, CLOSE/HEDGE/CANCEL dispatch=1.
/// Together they prove the full AT-104 chain: stale_cache → Degraded → OPEN blocked.
#[test]
fn test_at104_degraded_blocks_open_at_chokepoint() {
    // Degraded is what InstrumentCache::risk_state_for_at() returns when metadata is stale.
    // The cache-to-Degraded path is proven in test_instrument_cache_ttl.rs.
    let degraded = RiskState::Degraded;

    // Part 1: OPEN + Degraded → rejected at DispatchAuth (dispatch=0)
    let mut open_input = base_open_input();
    open_input.risk_state = degraded;
    let mut m1 = IntentPipelineMetrics::new();
    let r1 = evaluate_intent_pipeline(&open_input, &mut m1);
    assert!(
        matches!(r1.decision, ChokeResult::Rejected { .. }),
        "OPEN must be rejected at DispatchAuth when RiskState is Degraded"
    );
    assert_eq!(
        m1.chokepoint.approved_total(),
        0,
        "OPEN dispatch count must be 0 when stale"
    );

    // Part 2: CLOSE + Degraded → approved (dispatch=1)
    // CLOSE skips the risk-state rejection at DispatchAuth (only OPEN is gated on Healthy).
    // Gates 7-9 (Liquidity, NetEdge, Pricer) are skipped for CLOSE; gates 1-6 + 10 pass.
    let mut close_input = base_open_input();
    close_input.risk_state = degraded;
    close_input.intent_class = ChokeIntentClass::Close;
    let mut m2 = IntentPipelineMetrics::new();
    let r2 = evaluate_intent_pipeline(&close_input, &mut m2);
    assert!(
        matches!(r2.decision, ChokeResult::Approved { .. }),
        "CLOSE must NOT be blocked by Degraded risk state (risk-reducing intent)"
    );
    assert_eq!(
        m2.chokepoint.approved_total(),
        1,
        "CLOSE dispatch count must be 1 when Degraded"
    );

    // Part 3: HEDGE + Degraded → approved (dispatch=1)
    // Hedge is risk-reducing; only OPEN is blocked by non-Healthy risk state (DispatchAuth gate 1).
    // Gates 7-9 (Liquidity, NetEdge, Pricer) are skipped for HEDGE; gates 1-6 + 10 pass.
    let mut hedge_input = base_open_input();
    hedge_input.risk_state = degraded;
    hedge_input.intent_class = ChokeIntentClass::Hedge;
    let mut m3 = IntentPipelineMetrics::new();
    let r3 = evaluate_intent_pipeline(&hedge_input, &mut m3);
    assert!(
        matches!(r3.decision, ChokeResult::Approved { .. }),
        "HEDGE must NOT be blocked by Degraded risk state (risk-reducing intent)"
    );
    assert_eq!(
        m3.chokepoint.approved_total(),
        1,
        "HEDGE dispatch count must be 1 when Degraded"
    );

    // Part 4: CancelOnly + Degraded → approved (dispatch=1)
    // CancelOnly short-circuits at DispatchAuth gate 1 with no risk-state check.
    let mut cancel_input = base_open_input();
    cancel_input.risk_state = degraded;
    cancel_input.intent_class = ChokeIntentClass::CancelOnly;
    let mut m4 = IntentPipelineMetrics::new();
    let r4 = evaluate_intent_pipeline(&cancel_input, &mut m4);
    assert!(
        matches!(r4.decision, ChokeResult::Approved { .. }),
        "CancelOnly must NOT be blocked by Degraded risk state (always-pass short-circuit)"
    );
    assert_eq!(
        m4.chokepoint.approved_total(),
        1,
        "CancelOnly dispatch count must be 1 when Degraded"
    );
}

/// AT-920 pipeline-level proof: dispatch_consistency_passed=false → rejected at
/// DispatchConsistency gate with ContractsAmountMismatch reason, dispatch count = 0.
///
/// Companion to test_dispatch_map.rs::test_at920_mismatch_caller_sets_degraded_and_blocks_open
/// which proves: validate_and_dispatch mismatch → caller sets Degraded → OPEN rejected.
/// This test proves the gate itself fires correctly in the pipeline.
#[test]
fn test_at920_pipeline_dispatch_consistency_failure_rejected() {
    let mut input = base_open_input();
    input.dispatch_consistency_passed = false;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    // AT-920 criterion 1: rejected
    match &result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            // AT-920 criterion 2: correct gate
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::DispatchConsistency,
                        ..
                    }
                ),
                "expected DispatchConsistency gate rejection, got {reason:?}"
            );
            assert!(gate_trace.contains(&GateStep::DispatchConsistency));
        }
        other => panic!("expected Rejected, got {other:?}"),
    }
    // AT-920 criterion 3: dispatch count = 0
    assert_eq!(
        metrics.chokepoint.approved_total(),
        0,
        "dispatch count must be 0 when dispatch consistency fails"
    );
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::ContractsAmountMismatch)
    );
}

/// AT-920 supplement: dispatch_consistency_passed=false rejects CLOSE too.
/// Gate 4 is intent-class-agnostic (only CancelOnly short-circuits before it).
/// This test guards against a future refactor that accidentally excludes CLOSE.
#[test]
fn test_at920_pipeline_dispatch_consistency_rejects_close() {
    let mut input = base_open_input();
    input.intent_class = ChokeIntentClass::Close;
    input.dispatch_consistency_passed = false;
    let mut metrics = IntentPipelineMetrics::new();

    let result = evaluate_intent_pipeline(&input, &mut metrics);
    match &result.decision {
        ChokeResult::Rejected { reason, .. } => {
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::DispatchConsistency,
                        ..
                    }
                ),
                "CLOSE must also be rejected when dispatch consistency fails, got {reason:?}"
            );
        }
        other => panic!("expected Rejected for CLOSE, got {other:?}"),
    }
    assert_eq!(metrics.chokepoint.approved_total(), 0);
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::ContractsAmountMismatch)
    );
}
