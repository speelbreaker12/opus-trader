//! Property-based tests for GI-001: "OPEN intents MUST be blocked when
//! RiskState != Healthy" (CONTRACT.md §2.2).
//!
//! Properties under test:
//! - Open + non-Healthy risk state → Rejected with MarginHeadroomRejectOpens.
//! - Open + Healthy → pipeline does NOT reject at DispatchAuth (may reject elsewhere).
//! - Close/Hedge/CancelOnly + non-Healthy → NOT rejected with MarginHeadroomRejectOpens.

use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateStep,
};
use crate::execution::dispatch_map::DispatchConsistencyProof;
use crate::execution::gate::{GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput};
use crate::execution::gates::NetEdgeInput;
use crate::execution::pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, QuantizePipelineInput, evaluate_intent_pipeline,
};
use crate::execution::preflight::{OrderType, PreflightInput};
use crate::execution::pricer::PricerInput;
use crate::execution::quantize::{QuantizeConstraints, Side};
use crate::execution::reject_reason::RejectReasonCode;
use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};
use proptest::prelude::*;

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
        dispatch_consistency: DispatchConsistencyProof::no_contracts(),
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
            instrument_kind: Some(InstrumentKind::LinearFuture),
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

fn non_healthy_risk_state() -> impl Strategy<Value = RiskState> {
    prop_oneof![
        Just(RiskState::Degraded),
        Just(RiskState::Maintenance),
        Just(RiskState::Kill),
    ]
}

fn non_open_intent_class() -> impl Strategy<Value = ChokeIntentClass> {
    prop_oneof![
        Just(ChokeIntentClass::Close),
        Just(ChokeIntentClass::Hedge),
        Just(ChokeIntentClass::CancelOnly),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// GI-001: Open + non-Healthy → Rejected(RiskStateNotHealthy) with
    /// reject_reason_code == MarginHeadroomRejectOpens.
    #[test]
    fn gi001_open_non_healthy_rejected(risk_state in non_healthy_risk_state()) {
        let input = IntentPipelineInput {
            risk_state,
            ..base_open_input()
        };
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Must be Rejected
        match &result.decision {
            ChokeResult::Rejected { reason, gate_trace } => {
                prop_assert!(
                    matches!(reason, ChokeRejectReason::RiskStateNotHealthy),
                    "expected RiskStateNotHealthy, got {:?}", reason
                );
                prop_assert_eq!(
                    gate_trace.as_slice(),
                    &[GateStep::DispatchAuth],
                    "expected only DispatchAuth in gate_trace"
                );
            }
            other => {
                prop_assert!(false, "expected Rejected, got {:?}", other);
            }
        }

        // Reject reason code must be MarginHeadroomRejectOpens
        prop_assert_eq!(
            result.reject_reason_code,
            Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "GI-001: reject_reason_code should be MarginHeadroomRejectOpens"
        );

        // Chokepoint metrics: rejected_total should increment
        prop_assert!(
            metrics.chokepoint.rejected_total() > 0,
            "chokepoint rejected_total should be > 0"
        );

        // Preflight metrics should NOT increment (skipped due to short-circuit)
        prop_assert_eq!(
            metrics.preflight.reject_total(), 0,
            "preflight should not have been evaluated"
        );
    }

    /// Open + Healthy → NOT rejected at DispatchAuth (pipeline continues).
    #[test]
    fn open_healthy_passes_dispatch_auth(_dummy in 0..1u8) {
        let input = base_open_input();
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Should be Approved (all gates pass in base input)
        match &result.decision {
            ChokeResult::Approved { gate_trace } => {
                // Gate trace should include gates beyond DispatchAuth
                prop_assert!(
                    gate_trace.len() > 1,
                    "healthy open should pass multiple gates, trace={:?}", gate_trace
                );
            }
            ChokeResult::Rejected { reason, .. } => {
                // If rejected, it must NOT be RiskStateNotHealthy
                prop_assert!(
                    !matches!(reason, ChokeRejectReason::RiskStateNotHealthy),
                    "healthy open should not be rejected for RiskStateNotHealthy"
                );
            }
        }

        // Reject reason code should NOT be MarginHeadroomRejectOpens
        prop_assert!(
            result.reject_reason_code != Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "healthy open should not produce MarginHeadroomRejectOpens"
        );
    }

    /// Non-open intents + non-Healthy → NOT rejected with MarginHeadroomRejectOpens.
    /// (GI-001 only applies to Open intents.)
    #[test]
    fn non_open_non_healthy_not_margin_rejected(
        intent_class in non_open_intent_class(),
        risk_state in non_healthy_risk_state(),
    ) {
        let input = IntentPipelineInput {
            intent_class,
            risk_state,
            ..base_open_input()
        };
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Should NOT produce MarginHeadroomRejectOpens
        prop_assert!(
            result.reject_reason_code != Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "non-open intent {:?} with risk_state {:?} should not produce MarginHeadroomRejectOpens, got {:?}",
            intent_class, risk_state, result.reject_reason_code
        );
    }
}
