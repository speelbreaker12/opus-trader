//! Parity tests: legacy orchestration paths vs `ExecutionEngine::decide`.

use super::{
    CancelOnlyExecutionInput, CloseExecutionInput, ExecutionDecision, ExecutionEngine,
    ExecutionInput, ExecutionRuntime, HedgeExecutionInput, OpenExecutionInput,
    open_runtime_to_decision, pipeline_result_to_decision,
};
use crate::execution::base_gates::BaseGatesInput;
use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateStep,
};
use crate::execution::dispatch_map::DispatchConsistencyProof;
use crate::execution::gate::{GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput};
use crate::execution::gates::NetEdgeInput;
use crate::execution::inventory_skew::InventorySkewInput;
use crate::execution::open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, OpenRuntimeOutput, build_open_order_intent_runtime,
};
use crate::execution::pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, QuantizePipelineInput, evaluate_intent_pipeline,
};
use crate::execution::preflight::{OrderType, PreflightInput};
use crate::execution::pricer::PricerInput;
use crate::execution::quantize::{QuantizeConstraints, Side};
use crate::execution::{GateRejectCodes, RejectReasonCode};
use crate::risk::{
    ExposureBucket, ExposureBudgetInput, FeeCacheSnapshot, FeeStalenessConfig, MarginGateInput,
    PendingExposureBook, ReservationId, RiskState,
};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};

fn open_l2_snapshot() -> L2BookSnapshot {
    L2BookSnapshot {
        asks: vec![L2Level {
            price: 100.0,
            qty: 10.0,
        }],
        bids: vec![L2Level {
            price: 99.0,
            qty: 10.0,
        }],
        timestamp_ms: 1_000,
    }
}

fn base_open_input<'a>() -> OpenRuntimeInput<'a> {
    OpenRuntimeInput {
        base_gates: BaseGatesInput {
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
        },
        wal_recorded: true,
        current_delta: 0.0,
        delta_impact_est: 10.0,
        liquidity_input: LiquidityGateInput {
            order_qty: 1.0,
            is_buy: true,
            intent_class: GateIntentClass::Open,
            is_marketable: true,
            l2_snapshot: Some(open_l2_snapshot()),
            now_ms: 1_050,
            l2_book_snapshot_max_age_ms: 100,
            max_slippage_bps: 20.0,
        },
        net_edge_input: NetEdgeInput {
            gross_edge_usd: Some(12.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(9.0),
        },
        inventory_skew_input: InventorySkewInput {
            current_delta: 0.0,
            pending_delta: 0.0,
            delta_limit: Some(100.0),
            side: Side::Buy,
            min_edge_usd: 9.0,
            net_edge_usd: 10.0,
            limit_price: 100.0,
            tick_size: 0.5,
            inventory_skew_k: 0.1,
            inventory_skew_tick_penalty_max: 3,
        },
        pricer_input: PricerInput {
            fair_price: 100.0,
            gross_edge_usd: 20.0,
            min_edge_usd: 9.0,
            fee_estimate_usd: 2.0,
            qty: 1.0,
            side: Side::Buy,
        },
        exposure_budget_input: ExposureBudgetInput {
            current_btc_delta_usd: 0.0,
            pending_btc_delta_usd: 0.0,
            current_eth_delta_usd: 0.0,
            pending_eth_delta_usd: 0.0,
            current_alts_delta_usd: 0.0,
            pending_alts_delta_usd: 0.0,
            candidate_bucket: ExposureBucket::Btc,
            candidate_delta_usd: 10.0,
            global_delta_limit_usd: Some(1_000.0),
        },
        margin_gate_input: MarginGateInput {
            maintenance_margin_usd: 10.0,
            equity_usd: 100.0,
            mm_util_reject_opens: 0.70,
            mm_util_reduceonly: 0.85,
            mm_util_kill: 0.95,
        },
        reservation_id: ReservationId::new("test-intent-0000".to_string())
            .expect("valid reservation id"),
        instrument_id: "BTC-PERPETUAL".to_string(),
    }
}

fn make_pending_book(limit: f64) -> PendingExposureBook {
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC-PERPETUAL", Some(limit));
    book
}

fn base_pipeline_input<'a>() -> IntentPipelineInput<'a> {
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
            l2_snapshot: Some(open_l2_snapshot()),
            now_ms: 1_050,
            l2_book_snapshot_max_age_ms: 100,
            max_slippage_bps: 20.0,
        }),
        net_edge: Some(NetEdgeInput {
            gross_edge_usd: Some(10.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(3.0),
        }),
        pricer: Some(PricerInput {
            fair_price: 100.0,
            gross_edge_usd: 10.0,
            min_edge_usd: 3.0,
            fee_estimate_usd: 1.0,
            qty: 1.0,
            side: Side::Buy,
        }),
        wal_recorded: true,
        requested_qty: Some(1.0),
        max_dispatch_qty: Some(1.0),
    }
}

fn legacy_pipeline_decision(input: &IntentPipelineInput<'_>) -> ExecutionDecision {
    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(input, &mut metrics);
    pipeline_result_to_decision(
        result.decision,
        result.reject_reason_code,
        &GateRejectCodes::default(),
    )
}

fn legacy_open_decision(
    input: &OpenRuntimeInput<'_>,
    pending_book: &PendingExposureBook,
    gate_reject_codes: GateRejectCodes,
) -> ExecutionDecision {
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();
    let output = build_open_order_intent_runtime(
        input,
        pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );
    open_runtime_to_decision(&output, &gate_reject_codes)
}

fn assert_approved_with_recorded_before_dispatch(decision: &ExecutionDecision) {
    match decision {
        ExecutionDecision::Approved { gate_trace, .. } => {
            assert!(
                gate_trace.contains(&GateStep::RecordedBeforeDispatch),
                "expected trace to include RecordedBeforeDispatch, got {gate_trace:?}"
            );
        }
        other => panic!("expected approved decision, got {other:?}"),
    }
}

fn assert_approved_without_recorded_before_dispatch(decision: &ExecutionDecision) {
    match decision {
        ExecutionDecision::Approved { gate_trace, .. } => {
            assert!(
                !gate_trace.contains(&GateStep::RecordedBeforeDispatch),
                "expected trace to exclude RecordedBeforeDispatch, got {gate_trace:?}"
            );
        }
        other => panic!("expected approved decision, got {other:?}"),
    }
}

#[test]
fn engine_open_approved_matches_legacy_path() {
    let input = base_open_input();
    let legacy_book = make_pending_book(100.0);
    let engine_book = make_pending_book(100.0);
    let gate_codes = GateRejectCodes::default();

    let legacy = legacy_open_decision(&input, &legacy_book, gate_codes);

    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Open(OpenExecutionInput {
        input,
        gate_reject_codes: gate_codes,
    });
    let mut runtime = ExecutionRuntime::new(Some(&engine_book));
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    match delegated {
        ExecutionDecision::Approved { open_metadata, .. } => {
            let meta = open_metadata.expect("open metadata must be present on open approval");
            assert!(meta.pending_reservation_id.is_some());
            assert_eq!(meta.effective_risk_state, RiskState::Healthy);
            assert!(meta.adjusted_min_edge_usd.is_some());
        }
        _ => panic!("expected approved open decision"),
    }
}

#[test]
fn engine_open_rejected_matches_legacy_code_and_step() {
    let mut input = base_open_input();
    input.exposure_budget_input.global_delta_limit_usd = Some(5.0);
    let legacy_book = make_pending_book(100.0);
    let engine_book = make_pending_book(100.0);
    let gate_codes = GateRejectCodes {
        liquidity_gate: Some(RejectReasonCode::GlobalExposureBudgetExceeded),
        ..Default::default()
    };

    let legacy = legacy_open_decision(&input, &legacy_book, gate_codes);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Open(OpenExecutionInput {
        input,
        gate_reject_codes: gate_codes,
    });
    let mut runtime = ExecutionRuntime::new(Some(&engine_book));
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert!(matches!(
        delegated,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::GlobalExposureBudgetExceeded,
            step: GateStep::LiquidityGate,
            detail,
        } if detail == "GLOBAL_EXPOSURE_BUDGET_REJECT"
    ));
}

#[test]
fn engine_open_rejected_pending_exposure_overfill_maps_to_expected_reason_code() {
    let input = base_open_input();
    let legacy_book = make_pending_book(5.0);
    let engine_book = make_pending_book(5.0);
    let gate_codes = GateRejectCodes::default();

    let legacy = legacy_open_decision(&input, &legacy_book, gate_codes);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Open(OpenExecutionInput {
        input,
        gate_reject_codes: gate_codes,
    });
    let mut runtime = ExecutionRuntime::new(Some(&engine_book));
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert!(matches!(
        delegated,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            step: GateStep::LiquidityGate,
            detail,
        } if detail == "PENDING_EXPOSURE_OVERFILL"
    ));
}

#[test]
fn engine_open_rejected_unregistered_instrument_maps_to_expected_reason_code() {
    let input = base_open_input();
    let legacy_book = PendingExposureBook::new(None);
    let engine_book = PendingExposureBook::new(None);
    let gate_codes = GateRejectCodes::default();

    let legacy = legacy_open_decision(&input, &legacy_book, gate_codes);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Open(OpenExecutionInput {
        input,
        gate_reject_codes: gate_codes,
    });
    let mut runtime = ExecutionRuntime::new(Some(&engine_book));
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert!(matches!(
        delegated,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            step: GateStep::LiquidityGate,
            detail,
        } if detail == "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED"
    ));
}

#[test]
fn engine_close_approved_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Close;
    input.risk_state = RiskState::Degraded;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Close(CloseExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_with_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_close_rejected_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Close;
    input.quantize.raw_qty = 0.01;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Close(CloseExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert!(matches!(
        delegated,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::TooSmallAfterQuantization,
            step: GateStep::Quantize,
            ..
        }
    ));
}

#[test]
fn engine_hedge_approved_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Hedge;
    input.risk_state = RiskState::Degraded;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Hedge(HedgeExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_with_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_hedge_reject_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Hedge;
    input.quantize.raw_qty = 0.01;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Hedge(HedgeExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert!(matches!(
        delegated,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::TooSmallAfterQuantization,
            step: GateStep::Quantize,
            ..
        }
    ));
}

#[test]
fn engine_close_wal_signal_false_is_non_blocking_and_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Close;
    input.wal_recorded = false;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Close(CloseExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_with_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_hedge_wal_signal_false_is_non_blocking_and_matches_legacy_pipeline_path() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::Hedge;
    input.wal_recorded = false;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Hedge(HedgeExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_with_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_cancel_only_short_circuit_is_approved_and_skips_recorded_before_dispatch() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::CancelOnly;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::CancelOnly(CancelOnlyExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_without_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_cancel_only_wal_signal_false_matches_short_circuit_and_skips_recorded_before_dispatch() {
    let mut input = base_pipeline_input();
    input.intent_class = ChokeIntentClass::CancelOnly;
    input.wal_recorded = false;

    let legacy = legacy_pipeline_decision(&input);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::CancelOnly(CancelOnlyExecutionInput { input });
    let mut runtime = ExecutionRuntime::default();
    let delegated = engine.decide(&engine_input, &mut runtime);

    assert_eq!(delegated, legacy);
    assert_approved_without_recorded_before_dispatch(&delegated);
}

#[test]
fn engine_open_without_pending_book_is_fail_closed() {
    let engine = ExecutionEngine::new();
    let input = ExecutionInput::Open(OpenExecutionInput {
        input: base_open_input(),
        gate_reject_codes: GateRejectCodes::default(),
    });
    let mut runtime = ExecutionRuntime::default();
    let decision = engine.decide(&input, &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::AssemblyFailed,
            step: GateStep::LiquidityGate,
            detail,
        } if detail == "missing runtime dependency: pending_exposure_book"
    ));
}

#[test]
fn execution_engine_evaluate_alias_matches_decide() {
    let input = ExecutionInput::Close(CloseExecutionInput {
        input: base_pipeline_input(),
    });
    let engine = ExecutionEngine::new();
    let mut runtime_for_decide = ExecutionRuntime::default();
    let mut runtime_for_evaluate = ExecutionRuntime::default();

    let decide = engine.decide(&input, &mut runtime_for_decide);
    let evaluate = engine.evaluate(&input, &mut runtime_for_evaluate);

    assert_eq!(evaluate, decide);
}

#[test]
fn conversion_helper_open_runtime_liquidity_detail_overrides_reason_code() {
    let gate_codes = GateRejectCodes {
        liquidity_gate: Some(RejectReasonCode::LiquidityGateNoL2),
        ..Default::default()
    };

    let overfill = OpenRuntimeOutput {
        choke_result: ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::LiquidityGate,
                reason: "PENDING_EXPOSURE_OVERFILL".to_string(),
            },
            gate_trace: vec![
                GateStep::DispatchAuth,
                GateStep::Preflight,
                GateStep::Quantize,
                GateStep::DispatchConsistency,
                GateStep::FeeCacheCheck,
                GateStep::ExpiryGuard,
                GateStep::LiquidityGate,
            ],
        },
        gate_results: crate::execution::build_gate_results(
            true,
            true,
            true,
            true,
            true,
            false,
            false,
            false,
            true,
            Some(1.0),
            None,
        ),
        pending_reservation_id: None,
        mode_hint: crate::risk::MarginGateMode::Active,
        effective_risk_state: RiskState::Healthy,
        adjusted_min_edge_usd: None,
    };
    let instrument_not_registered = OpenRuntimeOutput {
        choke_result: ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::LiquidityGate,
                reason: "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED".to_string(),
            },
            gate_trace: vec![
                GateStep::DispatchAuth,
                GateStep::Preflight,
                GateStep::Quantize,
                GateStep::DispatchConsistency,
                GateStep::FeeCacheCheck,
                GateStep::ExpiryGuard,
                GateStep::LiquidityGate,
            ],
        },
        gate_results: crate::execution::build_gate_results(
            true,
            true,
            true,
            true,
            true,
            false,
            false,
            false,
            true,
            Some(1.0),
            None,
        ),
        pending_reservation_id: None,
        mode_hint: crate::risk::MarginGateMode::Active,
        effective_risk_state: RiskState::Healthy,
        adjusted_min_edge_usd: None,
    };
    let global_budget_reject = OpenRuntimeOutput {
        choke_result: ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::LiquidityGate,
                reason: "GLOBAL_EXPOSURE_BUDGET_REJECT".to_string(),
            },
            gate_trace: vec![
                GateStep::DispatchAuth,
                GateStep::Preflight,
                GateStep::Quantize,
                GateStep::DispatchConsistency,
                GateStep::FeeCacheCheck,
                GateStep::ExpiryGuard,
                GateStep::LiquidityGate,
            ],
        },
        gate_results: crate::execution::build_gate_results(
            true,
            true,
            true,
            true,
            true,
            false,
            false,
            false,
            true,
            Some(1.0),
            None,
        ),
        pending_reservation_id: None,
        mode_hint: crate::risk::MarginGateMode::Active,
        effective_risk_state: RiskState::Healthy,
        adjusted_min_edge_usd: None,
    };

    assert!(matches!(
        open_runtime_to_decision(&overfill, &gate_codes),
        ExecutionDecision::Rejected {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            ..
        }
    ));
    assert!(matches!(
        open_runtime_to_decision(&instrument_not_registered, &gate_codes),
        ExecutionDecision::Rejected {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            ..
        }
    ));
    assert!(matches!(
        open_runtime_to_decision(&global_budget_reject, &gate_codes),
        ExecutionDecision::Rejected {
            code: RejectReasonCode::GlobalExposureBudgetExceeded,
            ..
        }
    ));
}

#[test]
fn conversion_helper_pipeline_risk_state_maps_to_margin_headroom() {
    let result = ChokeResult::Rejected {
        reason: ChokeRejectReason::RiskStateNotHealthy,
        gate_trace: vec![],
    };
    let decision = pipeline_result_to_decision(result, None, &GateRejectCodes::default());

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected {
            code: RejectReasonCode::MarginHeadroomRejectOpens,
            step: GateStep::DispatchAuth,
            ..
        }
    ));
}
