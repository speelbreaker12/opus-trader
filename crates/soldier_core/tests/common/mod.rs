// Shared test utilities — not all functions used by every test binary.
#![allow(dead_code)]

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateIntentClass, GateResults, GateStep,
    IntentPipelineInput, L2BookSnapshot, L2Level, LiquidityGateInput, NetEdgeInput, OrderType,
    PreflightInput, PricerInput, PricerSide, QuantizeConstraints, QuantizePipelineInput, Side,
    ChokeIntentClass, GateIntentClass, GateResults, IntentPipelineInput, L2BookSnapshot, L2Level,
    LiquidityGateInput, NetEdgeInput, OrderType, PreflightInput, PricerInput, QuantizeConstraints,
    QuantizePipelineInput, Side,
};
use soldier_core::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use soldier_core::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};

/// Test helper: returns GateResults with ALL gates passing.
///
/// Use this in integration tests that need a passing baseline.
/// For tests that check specific gate failures, override individual fields:
/// `GateResults { some_gate: false, ..gate_results_all_passing() }`
pub fn gate_results_all_passing() -> GateResults {
    GateResults {
        preflight_passed: true,
        quantize_passed: true,
        dispatch_consistency_passed: true,
        fee_cache_passed: true,
        expiry_guard_passed: true,
        liquidity_gate_passed: true,
        net_edge_passed: true,
        pricer_passed: true,
        wal_recorded: true,
        requested_qty: None,
        max_dispatch_qty: None,
    }
}

pub fn book(asks: Vec<(f64, f64)>, bids: Vec<(f64, f64)>, ts: u64) -> L2BookSnapshot {
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

/// Assert that a `build_order_intent` call produced a rejection with zero dispatches.
///
/// Use for ALL rejection tests, including WAL-gate failures where
/// `RecordedBeforeDispatch` appears in the gate trace before the check fails.
pub fn assert_no_dispatch(result: &ChokeResult, metrics: &ChokeMetrics, context: &str) {
    assert!(
        matches!(result, ChokeResult::Rejected { .. }),
        "{context}: expected ChokeResult::Rejected"
    );
    assert_eq!(
        metrics.approved_total(),
        0,
        "{context}: approved_total must be 0 after rejection"
    );
}

/// Assert rejection with zero dispatches AND confirm that
/// `RecordedBeforeDispatch` is NOT in the gate trace.
///
/// Use for rejections that stop before gate 10 (WAL gate). Do NOT use for
/// WAL-gate failures — the WAL gate pushes `RecordedBeforeDispatch` to the
/// trace before checking `wal_recorded`.
pub fn assert_no_dispatch_no_wal(result: &ChokeResult, metrics: &ChokeMetrics, context: &str) {
    assert_no_dispatch(result, metrics, context);
    let ChokeResult::Rejected { gate_trace, .. } = result else {
        // assert_no_dispatch already verified Rejected; this satisfies the compiler.
        return;
    };
    assert!(
        !gate_trace.contains(&GateStep::RecordedBeforeDispatch),
        "{context}: gate_trace must not contain RecordedBeforeDispatch for pre-WAL rejections"
    );
}

/// Known-passing baseline: all gates pass, risk_state Healthy, all feeds fresh.
///
/// Single source of truth — used by test_intent_pipeline.rs,
/// adversarial_gi_enforcement.rs, and prop_pipeline_gi001.rs.
pub fn base_open_input<'a>() -> IntentPipelineInput<'a> {
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
        expiry_guard: Some(ExpiryGuardInput {
            now_ms: 1_000_000,
            expiration_timestamp_ms: Some(2_000_000),
            expiry_delist_buffer_s: 60,
            intent: LifecycleIntent::Open,
        }),
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
            side: Side::Buy,
        }),
        wal_recorded: true,
        requested_qty: Some(1.0),
        max_dispatch_qty: Some(1.0),
    }
}
