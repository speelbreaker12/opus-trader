//! Integration tests for execution pipeline orchestration.

mod common;

use soldier_core::execution::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateStep,
    IntentPipelineMetrics, LiquidityGateInput,
    OrderType, PostOnlyInput,
    RejectReasonCode, Side, evaluate_intent_pipeline,
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
