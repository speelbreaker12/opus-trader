//! Tests for `ExecutionEngine::decide` and internal conversion helpers.

use super::*;
use crate::execution::build_order_intent::{
    ChokeRejectReason, ChokeResult, GateStep, build_gate_results,
};
use crate::execution::open_runtime::OpenRuntimeOutput;
use crate::risk::{
    ExposureBucket, ExposureBudgetInput, MarginGateInput, MarginGateMode, PendingExposureBook,
    ReservationId, RiskState,
};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};

struct OkWalGate {
    calls: usize,
}

impl RecordedBeforeDispatchGate for OkWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.calls += 1;
        Ok(())
    }
}

struct ErrWalGate {
    calls: usize,
}

impl RecordedBeforeDispatchGate for ErrWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.calls += 1;
        Err("wal append failed".to_string())
    }
}

fn base_execution_input<'a>() -> ExecutionBaseInput<'a> {
    base_execution_input_with_risk_state(RiskState::Healthy)
}

fn base_execution_input_with_risk_state<'a>(risk_state: RiskState) -> ExecutionBaseInput<'a> {
    ExecutionBaseInput {
        risk_state,
        preflight: ExecutionPreflightInput {
            instrument_kind: InstrumentKind::Option,
            order_type: ExecutionOrderType::Limit,
            has_trigger: false,
            linked_order_type: None,
            linked_orders_allowed: false,
            post_only: None,
        },
        venue_capabilities: VenueCapabilities::default(),
        bot_feature_flags: BotFeatureFlags::default(),
        quantize: QuantizeExecutionInput {
            raw_qty: 1.0,
            raw_limit_price: 100.0,
            side: Side::Buy,
            tick_size: 0.1,
            amount_step: 0.1,
            min_amount: 0.1,
        },
        dispatch_consistency_passed: true,
        fee_snapshot: crate::risk::FeeCacheSnapshot {
            fee_rate: 0.0005,
            fee_model_cached_at_ts_ms: Some(1_000_000),
            now_ms: 1_010_000,
        },
        fee_config: crate::risk::FeeStalenessConfig::default(),
        expiry_guard: Some(ExpiryGuardInput {
            now_ms: 1_000_000,
            expiration_timestamp_ms: Some(2_000_000),
            expiry_delist_buffer_s: 60,
            intent: LifecycleIntent::Open,
            instrument_kind: Some(InstrumentKind::LinearFuture),
        }),
    }
}

fn open_l2_snapshot() -> ExecutionL2BookSnapshot {
    ExecutionL2BookSnapshot {
        asks: vec![ExecutionL2Level {
            price: 100.0,
            qty: 10.0,
        }],
        bids: vec![ExecutionL2Level {
            price: 99.0,
            qty: 10.0,
        }],
        timestamp_ms: 1_000,
    }
}

fn base_open_input() -> OpenExecutionInput<'static> {
    OpenExecutionInput {
        base: base_execution_input(),
        gate_reject_codes: GateRejectCodes::default(),
        current_delta: 0.0,
        delta_impact_est: 10.0,
        liquidity: LiquidityExecutionInput {
            order_qty: 1.0,
            side: Side::Buy,
            is_marketable: true,
            l2_snapshot: Some(open_l2_snapshot()),
            now_ms: 1_050,
            l2_book_snapshot_max_age_ms: 100,
            max_slippage_bps: 20.0,
        },
        net_edge: NetEdgeExecutionInput {
            gross_edge_usd: Some(12.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(9.0),
        },
        inventory_skew: InventorySkewExecutionInput {
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
        pricer: PricerExecutionInput {
            fair_price: 100.0,
            gross_edge_usd: 20.0,
            min_edge_usd: 9.0,
            fee_estimate_usd: 2.0,
            qty: 1.0,
            side: Side::Buy,
        },
        exposure_budget: ExposureBudgetInput {
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
        margin_gate: MarginGateInput {
            maintenance_margin_usd: 10.0,
            equity_usd: 100.0,
            mm_util_reject_opens: 0.70,
            mm_util_reduceonly: 0.85,
            mm_util_kill: 0.95,
        },
        reservation_id: match ReservationId::new("test-intent-0000".to_string()) {
            Some(value) => value,
            None => panic!("invalid reservation id fixture"),
        },
        instrument_id: "BTC-PERPETUAL".to_string(),
    }
}

fn make_pending_book(limit: f64) -> PendingExposureBook {
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC-PERPETUAL", Some(limit));
    book
}

#[test]
fn engine_open_approved_with_all_fields() {
    let input = base_open_input();
    let engine_book = make_pending_book(100.0);

    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Open(input);
    let mut wal_gate = OkWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), Some(&engine_book));
    let decision = engine.decide(&engine_input, &mut runtime);

    assert_eq!(wal_gate.calls, 1, "open path should consult WAL gate once");

    match decision {
        ExecutionDecision::Approved(approved) => {
            assert_eq!(approved.effective_risk_state, RiskState::Healthy);
            assert!(approved.pending_reservation_id.is_some());
            assert!(approved.adjusted_min_edge_usd.is_some());
        }
        other => panic!("expected open approval, got {other:?}"),
    }
}

#[test]
fn engine_open_rejected_global_budget_maps_runtime_step() {
    let mut input = base_open_input();
    input.exposure_budget.global_delta_limit_usd = Some(5.0);

    let engine_book = make_pending_book(100.0);

    let engine = ExecutionEngine::new();
    let mut wal_gate = OkWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), Some(&engine_book));
    let decision = engine.decide(&ExecutionInput::Open(input), &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::GlobalExposureBudgetExceeded,
            step: ExecutionStep::Runtime(RuntimeStep::GlobalExposureBudget),
            ref detail,
        }) if detail == "GLOBAL_EXPOSURE_BUDGET_REJECT"
    ));
}

#[test]
fn engine_open_rejected_pending_exposure_maps_runtime_step() {
    let input = base_open_input();
    let engine_book = make_pending_book(5.0);

    let engine = ExecutionEngine::new();
    let mut wal_gate = OkWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), Some(&engine_book));
    let decision = engine.decide(&ExecutionInput::Open(input), &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            step: ExecutionStep::Runtime(RuntimeStep::PendingExposure),
            ref detail,
        }) if detail == "PENDING_EXPOSURE_OVERFILL"
    ));
}

#[test]
fn engine_open_without_pending_book_is_fail_closed() {
    let engine = ExecutionEngine::new();
    let mut wal_gate = OkWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), None);

    let decision = engine.decide(&ExecutionInput::Open(base_open_input()), &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::AssemblyFailed,
            step: ExecutionStep::Runtime(RuntimeStep::Assembly),
            ref detail,
        }) if detail == "missing runtime dependency: pending_exposure_book"
    ));
}

#[test]
fn engine_open_without_wal_gate_fails_recorded_before_dispatch() {
    let engine = ExecutionEngine::new();
    let book = make_pending_book(100.0);
    let mut runtime = ExecutionRuntime::new(None, Some(&book));

    let decision = engine.decide(&ExecutionInput::Open(base_open_input()), &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::RecordedBeforeDispatchFailed,
            step: ExecutionStep::Gate(GateStep::RecordedBeforeDispatch),
            ..
        })
    ));
}

#[test]
fn engine_close_wal_failure_is_non_blocking() {
    let base = base_execution_input_with_risk_state(RiskState::Degraded);

    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Close(CloseExecutionInput { base });
    let mut wal_gate = ErrWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), None);
    let decision = engine.decide(&engine_input, &mut runtime);

    assert_eq!(wal_gate.calls, 1, "close path should attempt WAL once");
    assert!(matches!(decision, ExecutionDecision::Approved(_)));
}

#[test]
fn engine_close_wal_failure_emits_csp32_visibility_metric() {
    let _metrics_guard = match crate::execution::METRICS_TEST_LOCK.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let _ = crate::execution::take_execution_metric_lines();

    let base = base_execution_input_with_risk_state(RiskState::Degraded);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Close(CloseExecutionInput { base });
    let mut wal_gate = ErrWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), None);

    let delegated = engine.decide(&engine_input, &mut runtime);
    assert!(matches!(delegated, ExecutionDecision::Approved(_)));
    assert_eq!(wal_gate.calls, 1, "close path should attempt WAL once");

    let lines = crate::execution::take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with(crate::execution::METRIC_WAL_NONBLOCKING_ALLOWED_TOTAL)
                && line.contains("intent_class=Close")
        }),
        "expected CSP.3.2 non-blocking WAL visibility metric line, got {lines:?}"
    );
}

#[test]
fn engine_hedge_rejected_quantize() {
    let mut base = base_execution_input_with_risk_state(RiskState::Degraded);
    base.quantize.raw_qty = 0.01;

    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Hedge(HedgeExecutionInput { base });
    let mut runtime = ExecutionRuntime::default();
    let decision = engine.decide(&engine_input, &mut runtime);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::TooSmallAfterQuantization,
            step: ExecutionStep::Gate(GateStep::Quantize),
            ..
        })
    ));
}

#[test]
fn engine_hedge_wal_failure_emits_csp32_visibility_metric() {
    // AT-CSP32-HEDGE: Hedge shares the Close|Hedge branch in pipeline_wal_recorded.
    // A WAL failure must be non-blocking AND must emit a metric line with intent_class=Hedge,
    // proving both sides of the shared branch are independently observable.
    let _metrics_guard = match crate::execution::METRICS_TEST_LOCK.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let _ = crate::execution::take_execution_metric_lines();

    let base = base_execution_input_with_risk_state(RiskState::Degraded);
    let engine = ExecutionEngine::new();
    let engine_input = ExecutionInput::Hedge(HedgeExecutionInput { base });
    let mut wal_gate = ErrWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), None);

    let delegated = engine.decide(&engine_input, &mut runtime);
    assert!(matches!(delegated, ExecutionDecision::Approved(_)));
    assert_eq!(wal_gate.calls, 1, "hedge path should attempt WAL once");

    let lines = crate::execution::take_execution_metric_lines();
    assert!(
        lines.iter().any(|line| {
            line.starts_with(crate::execution::METRIC_WAL_NONBLOCKING_ALLOWED_TOTAL)
                && line.contains("intent_class=Hedge")
        }),
        "expected CSP.3.2 non-blocking WAL visibility metric line for Hedge, got {lines:?}"
    );
}

#[test]
fn engine_cancel_short_circuits_and_skips_wal() {
    let base = base_execution_input();
    let engine = ExecutionEngine::new();
    let mut wal_gate = ErrWalGate { calls: 0 };
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), None);

    let decision = engine.decide(
        &ExecutionInput::Cancel(CancelExecutionInput { base }),
        &mut runtime,
    );

    assert!(matches!(decision, ExecutionDecision::Approved(_)));
    assert_eq!(
        wal_gate.calls, 0,
        "cancel path must not consult recorded-before-dispatch gate"
    );
}

#[test]
fn pipeline_assembly_failed_maps_to_runtime_step() {
    let decision = pipeline_result_to_decision(
        ChokeResult::Rejected {
            reason: ChokeRejectReason::AssemblyFailed,
            gate_trace: vec![],
        },
        Some(RejectReasonCode::AssemblyFailed),
        RiskState::Healthy,
        &GateRejectCodes::default(),
    );

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::AssemblyFailed,
            step: ExecutionStep::Runtime(RuntimeStep::Assembly),
            ..
        })
    ));
}

fn synthetic_open_output(reason: ChokeRejectReason) -> OpenRuntimeOutput {
    let rejected_gate = match &reason {
        ChokeRejectReason::GateRejected { gate, .. } => Some(*gate),
        _ => None,
    };
    let mut gate_trace = vec![
        GateStep::DispatchAuth,
        GateStep::Preflight,
        GateStep::Quantize,
        GateStep::DispatchConsistency,
        GateStep::FeeCacheCheck,
        GateStep::ExpiryGuard,
    ];
    if let Some(gate) = rejected_gate {
        if !gate_trace.contains(&gate) {
            gate_trace.push(gate);
        }
    }
    OpenRuntimeOutput {
        choke_result: ChokeResult::Rejected {
            reason,
            gate_trace,
        },
        gate_results: build_gate_results(
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
        mode_hint: MarginGateMode::Active,
        effective_risk_state: RiskState::Healthy,
        adjusted_min_edge_usd: None,
    }
}

#[test]
fn open_runtime_step_maps_base_gates_to_runtime_stage() {
    let output = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::Preflight,
        reason: "preflight rejected".to_string(),
    });

    let decision = open_runtime_to_decision(&base_open_input(), &output);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            step: ExecutionStep::Runtime(RuntimeStep::BaseGates),
            ..
        })
    ));
}

#[test]
fn open_runtime_step_maps_margin_gate_transition() {
    let output = OpenRuntimeOutput {
        effective_risk_state: RiskState::Degraded,
        ..synthetic_open_output(ChokeRejectReason::RiskStateNotHealthy)
    };

    let decision = open_runtime_to_decision(&base_open_input(), &output);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            step: ExecutionStep::Runtime(RuntimeStep::MarginGate),
            ..
        })
    ));
}

#[test]
fn open_runtime_step_maps_inventory_skew_on_adjusted_net_edge_reject() {
    let mut output = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::NetEdgeGate,
        reason: "net edge too low".to_string(),
    });
    output.adjusted_min_edge_usd = Some(12.0);

    let decision = open_runtime_to_decision(&base_open_input(), &output);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            step: ExecutionStep::Runtime(RuntimeStep::InventorySkew),
            ..
        })
    ));
}

#[test]
fn open_runtime_override_reasons_map_to_registry_codes() {
    let input = base_open_input();

    let overfill = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: "PENDING_EXPOSURE_OVERFILL".to_string(),
    });
    let unregistered = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED".to_string(),
    });
    let global = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: "GLOBAL_EXPOSURE_BUDGET_REJECT".to_string(),
    });

    assert!(matches!(
        open_runtime_to_decision(&input, &overfill),
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            step: ExecutionStep::Runtime(RuntimeStep::PendingExposure),
            ..
        })
    ));
    assert!(matches!(
        open_runtime_to_decision(&input, &unregistered),
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::PendingExposureBudgetExceeded,
            step: ExecutionStep::Runtime(RuntimeStep::PendingExposure),
            ..
        })
    ));
    assert!(matches!(
        open_runtime_to_decision(&input, &global),
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::GlobalExposureBudgetExceeded,
            step: ExecutionStep::Runtime(RuntimeStep::GlobalExposureBudget),
            ..
        })
    ));
}

#[test]
fn open_runtime_unknown_liquidity_detail_falls_back_to_gate_reject_codes() {
    let input = base_open_input();
    let mut input_with_codes = input;
    input_with_codes.gate_reject_codes = GateRejectCodes {
        liquidity_gate: Some(RejectReasonCode::LiquidityGateNoL2),
        ..Default::default()
    };
    let output = synthetic_open_output(ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: "UNEXPECTED_LIQUIDITY_DETAIL".to_string(),
    });

    let decision = open_runtime_to_decision(&input_with_codes, &output);

    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::LiquidityGateNoL2,
            ..
        })
    ));
}
