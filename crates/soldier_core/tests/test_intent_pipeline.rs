//! Integration tests for execution pipeline orchestration.

use soldier_core::execution::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateIntentClass, GateStep,
    IntentPipelineInput, IntentPipelineMetrics, L2BookSnapshot, L2Level, LiquidityGateInput,
    NetEdgeInput, OrderType, PostOnlyInput, PreflightInput, PricerInput, PricerSide,
    QuantizeConstraints, QuantizePipelineInput, Side, evaluate_intent_pipeline,
};
use soldier_core::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use soldier_core::venue::{BotFeatureFlags, InstrumentKind, VenueCapabilities};

fn book(asks: Vec<(f64, f64)>, bids: Vec<(f64, f64)>, ts: u64) -> L2BookSnapshot {
    L2BookSnapshot {
        asks: asks
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        bids: bids
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        timestamp_ms: ts,
    }
}

fn base_open_input<'a>() -> IntentPipelineInput<'a> {
    IntentPipelineInput {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Healthy,
        preflight: PreflightInput {
            instrument_kind: InstrumentKind::Option,
            order_type: OrderType::Limit,
            has_trigger: false,
            linked_order_type: None,
            linked_orders_allowed: false,
            post_only_input: None,
        },
        venue_capabilities: VenueCapabilities::default(),
        bot_feature_flags: BotFeatureFlags::default(),
        quantize: QuantizePipelineInput {
            raw_qty: 1.0,
            raw_limit_price: 100.0,
            side: Side::Buy,
            constraints: QuantizeConstraints {
                tick_size: 0.1,
                amount_step: 0.1,
                min_amount: 0.1,
            },
        },
        dispatch_consistency_passed: true,
        fee_snapshot: FeeCacheSnapshot {
            fee_rate: 0.0005,
            fee_model_cached_at_ts_ms: Some(1_000_000),
            now_ms: 1_010_000,
        },
        fee_config: FeeStalenessConfig::default(),
        liquidity: Some(LiquidityGateInput {
            order_qty: 1.0,
            is_buy: true,
            intent_class: GateIntentClass::Open,
            is_marketable: true,
            l2_snapshot: Some(book(vec![(100.0, 10.0)], vec![], 1_009_000)),
            now_ms: 1_010_000,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps: 10.0,
        }),
        net_edge: Some(NetEdgeInput {
            gross_edge_usd: Some(10.0),
            fee_usd: Some(2.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(2.0),
        }),
        pricer: Some(PricerInput {
            fair_price: 100.0,
            gross_edge_usd: 10.0,
            min_edge_usd: 2.0,
            fee_estimate_usd: 2.0,
            qty: 1.0,
            side: PricerSide::Buy,
        }),
        wal_recorded: true,
        requested_qty: Some(1.0),
        max_dispatch_qty: Some(1.0),
    }
}

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
}
