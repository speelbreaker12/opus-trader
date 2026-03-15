//! Runtime wiring tests for Slice 6 gate integration at the OPEN chokepoint.
trait TestValueExt<T> {
    fn must(self) -> T;
}

impl<T, E: std::fmt::Debug> TestValueExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

impl<T> TestValueExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

use crate::execution::base_gates::BaseGatesInput;
use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateStep,
};
use crate::execution::dispatch_map::DispatchConsistencyProof;
use crate::execution::gate::{GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput};
use crate::execution::gates::NetEdgeInput;
use crate::execution::inventory_skew::InventorySkewInput;
use crate::execution::open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, build_open_order_intent_runtime,
    settle_pending_on_tlsm_terminal,
};
use crate::execution::pipeline::QuantizePipelineInput;
use crate::execution::preflight::{OrderType, PreflightInput};
use crate::execution::pricer::PricerInput;
use crate::execution::quantize::{QuantizeConstraints, Side};
use crate::risk::{
    ExposureBucket, ExposureBudgetInput, FeeCacheSnapshot, FeeStalenessConfig, MarginGateInput,
    MarginGateMode, PendingExposureBook, ReservationId, RiskState,
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
            expected_slippage_usd: 1.0,
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
            now_ms: 1_000,
            mm_util_last_update_ts_ms: Some(1_000),
            mm_util_max_age_ms: 30_000,
        },
        reservation_id: ReservationId::new("test-intent-0000").must(),
        instrument_id: "BTC-PERPETUAL".to_string(),
    }
}

const INST: &str = "BTC-PERPETUAL";

/// Helper: create a PendingExposureBook with BTC-PERPETUAL registered.
fn make_pending_book(limit: f64) -> PendingExposureBook {
    let book = PendingExposureBook::new(None);
    book.register_instrument(INST, Some(limit));
    book
}

#[test]
fn test_runtime_wiring_releases_pending_reservation_on_reject() {
    let mut input = base_open_input();
    input.exposure_budget_input.global_delta_limit_usd = Some(5.0);

    let pending_book = make_pending_book(100.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    match out.choke_result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert_eq!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: "GLOBAL_EXPOSURE_BUDGET_REJECT".to_string(),
                }
            );
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected global budget rejection, got {other:?}"),
    }

    assert!(!out.gate_results.liquidity_gate_passed);
    assert!(!out.gate_results.net_edge_passed);
    assert!(out.pending_reservation_id.is_none());
    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(runtime_metrics.pending_exposure.release_total(), 1);
    assert_eq!(runtime_metrics.reject_override_mismatch_total, 0);
}

#[test]
fn test_runtime_wiring_pending_reject_takes_precedence_over_global_budget_reject() {
    let mut input = base_open_input();
    input.exposure_budget_input.global_delta_limit_usd = Some(5.0);
    input.delta_impact_est = 10.0;

    let pending_book = make_pending_book(5.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    match out.choke_result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert_eq!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: "PENDING_EXPOSURE_OVERFILL".to_string(),
                }
            );
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected pending exposure rejection, got {other:?}"),
    }

    assert!(!out.gate_results.liquidity_gate_passed);
    assert!(!out.gate_results.net_edge_passed);
    assert!(out.pending_reservation_id.is_none());
    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(runtime_metrics.global_exposure.reject_total(), 0);
    assert_eq!(runtime_metrics.reject_override_mismatch_total, 0);
}

#[test]
fn test_runtime_wiring_inventory_skew_forces_net_edge_recheck_before_pricer() {
    let mut input = base_open_input();
    input.inventory_skew_input.current_delta = 100.0;

    let pending_book = make_pending_book(200.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert!(matches!(out.choke_result, ChokeResult::Approved { .. }));
    assert!(out.pending_reservation_id.is_some());
    assert_eq!(runtime_metrics.net_edge.allowed_total(), 2);
}

#[test]
fn test_runtime_wiring_margin_kill_rejects_before_open_dispatch() {
    let mut input = base_open_input();
    input.margin_gate_input.maintenance_margin_usd = 96.0;
    input.margin_gate_input.equity_usd = 100.0;

    let pending_book = make_pending_book(200.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert_eq!(out.mode_hint, MarginGateMode::Kill);
    assert!(out.pending_reservation_id.is_none());
    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(runtime_metrics.pending_exposure.reserve_attempt_total(), 0);

    match out.choke_result {
        ChokeResult::Rejected { reason, .. } => {
            assert_eq!(reason, ChokeRejectReason::RiskStateNotHealthy);
        }
        other => panic!("expected risk-state rejection, got {other:?}"),
    }
}

#[test]
fn test_runtime_wiring_margin_reject_preserves_stricter_incoming_risk_state() {
    let base_input = base_open_input();
    let mut input = OpenRuntimeInput {
        base_gates: BaseGatesInput {
            risk_state: RiskState::Maintenance,
            ..base_input.base_gates
        },
        ..base_input
    };
    input.margin_gate_input.maintenance_margin_usd = 80.0;
    input.margin_gate_input.equity_usd = 100.0;

    let pending_book = make_pending_book(200.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert_eq!(out.mode_hint, MarginGateMode::Active);
    assert_eq!(out.effective_risk_state, RiskState::Maintenance);
    assert!(out.pending_reservation_id.is_none());
    assert_eq!(runtime_metrics.pending_exposure.reserve_attempt_total(), 0);

    match out.choke_result {
        ChokeResult::Rejected { reason, .. } => {
            assert_eq!(reason, ChokeRejectReason::RiskStateNotHealthy);
        }
        other => panic!("expected risk-state rejection, got {other:?}"),
    }
}

#[test]
fn test_runtime_wiring_inventory_skew_can_recover_initial_net_edge_reject() {
    let mut input = base_open_input();
    input.current_delta = 100.0;
    input.liquidity_input.is_buy = false;
    input.inventory_skew_input.side = Side::Sell;
    input.net_edge_input.min_edge_usd = Some(11.0);
    input.pricer_input.side = Side::Sell;
    input.pricer_input.min_edge_usd = 11.0;

    let pending_book = make_pending_book(200.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert!(matches!(out.choke_result, ChokeResult::Approved { .. }));
    assert!(out.pending_reservation_id.is_some());
    assert_eq!(runtime_metrics.net_edge.reject_too_low(), 1);
    assert_eq!(runtime_metrics.net_edge.allowed_total(), 1);
    let adjusted_min_edge_usd = out.adjusted_min_edge_usd.must();
    assert!(adjusted_min_edge_usd < 11.0);
}

#[test]
fn test_runtime_wiring_delta_limit_missing_degrades_even_if_net_edge_fails_first() {
    let mut input = base_open_input();
    input.net_edge_input.min_edge_usd = Some(50.0);
    input.inventory_skew_input.delta_limit = None;

    let pending_book = make_pending_book(200.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert_eq!(out.effective_risk_state, RiskState::Degraded);
    assert_eq!(runtime_metrics.net_edge.reject_too_low(), 1);
    assert_eq!(
        runtime_metrics.inventory_skew.reject_delta_limit_missing(),
        1
    );

    match out.choke_result {
        ChokeResult::Rejected { reason, .. } => {
            assert_eq!(reason, ChokeRejectReason::RiskStateNotHealthy);
        }
        other => panic!("expected risk-state rejection, got {other:?}"),
    }
}

/// Helper: Set up TLSM settlement test with pending exposure reservation.
fn setup_tlsm_settlement_test() -> (
    crate::execution::Tlsm,
    PendingExposureBook,
    crate::risk::PendingExposureMetrics,
) {
    use crate::execution::Tlsm;
    use crate::risk::PendingExposureMetrics;

    let input = base_open_input();
    let pending_book = make_pending_book(100.0);
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert!(matches!(out.choke_result, ChokeResult::Approved { .. }));
    let reservation_id = out.pending_reservation_id.must();

    assert_eq!(pending_book.active_reservations(INST), 1);
    assert!(pending_book.pending_total(INST) > 0.0);

    let tlsm = Tlsm::with_pending_reservation(reservation_id, INST.to_string());
    let pending_metrics = PendingExposureMetrics::new();

    (tlsm, pending_book, pending_metrics)
}

#[test]
fn test_tlsm_settles_pending_exposure_on_filled() {
    use crate::execution::TlsmEvent;

    let (mut tlsm, pending_book, mut pending_metrics) = setup_tlsm_settlement_test();

    tlsm.apply(TlsmEvent::Sent);
    tlsm.apply(TlsmEvent::Acked);
    tlsm.apply(TlsmEvent::Filled);

    assert_eq!(pending_book.active_reservations(INST), 1);

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);

    assert_eq!(pending_book.active_reservations(INST), 0);
    assert!((pending_book.pending_total(INST) - 0.0).abs() < 1e-9);
    assert_eq!(pending_metrics.release_total(), 1);
}

#[test]
fn test_tlsm_settles_pending_exposure_on_cancelled() {
    use crate::execution::TlsmEvent;

    let (mut tlsm, pending_book, mut pending_metrics) = setup_tlsm_settlement_test();

    tlsm.apply(TlsmEvent::Sent);
    tlsm.apply(TlsmEvent::Cancelled);

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);

    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(pending_metrics.release_total(), 1);
}

#[test]
fn test_tlsm_settles_pending_exposure_on_failed() {
    use crate::execution::TlsmEvent;

    let (mut tlsm, pending_book, mut pending_metrics) = setup_tlsm_settlement_test();

    tlsm.apply(TlsmEvent::Sent);
    tlsm.apply(TlsmEvent::Failed);

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);

    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(pending_metrics.release_total(), 1);
}

#[test]
fn test_tlsm_settlement_noop_on_non_terminal_state() {
    use crate::execution::TlsmEvent;

    let (mut tlsm, pending_book, mut pending_metrics) = setup_tlsm_settlement_test();

    tlsm.apply(TlsmEvent::Sent);
    tlsm.apply(TlsmEvent::Acked);

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);

    assert_eq!(pending_book.active_reservations(INST), 1);
    assert_eq!(pending_metrics.release_total(), 0);

    tlsm.apply(TlsmEvent::Filled);
    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);

    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(pending_metrics.release_total(), 1);
}

#[test]
fn test_tlsm_settlement_is_idempotent_on_duplicate_terminal_events() {
    use crate::execution::TlsmEvent;

    let (mut tlsm, pending_book, mut pending_metrics) = setup_tlsm_settlement_test();

    tlsm.apply(TlsmEvent::Sent);
    tlsm.apply(TlsmEvent::Cancelled);

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);
    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(pending_metrics.release_total(), 1);

    let result = tlsm.apply(TlsmEvent::Filled);
    assert!(matches!(
        result,
        crate::execution::TransitionResult::Ignored { .. }
    ));

    settle_pending_on_tlsm_terminal(&mut tlsm, &pending_book, &mut pending_metrics);
    assert_eq!(pending_book.active_reservations(INST), 0);
    assert_eq!(pending_metrics.release_total(), 1);
}

#[test]
fn test_unregistered_instrument_rejected_through_runtime() {
    // P1 #3: Register a DIFFERENT instrument than what base_open_input uses ("BTC-PERPETUAL").
    // The runtime should reject with PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED.
    let input = base_open_input();
    let book = PendingExposureBook::new(None);
    // Register ETH-PERPETUAL only — BTC-PERPETUAL is NOT registered.
    book.register_instrument("ETH-PERPETUAL", Some(500.0));

    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out =
        build_open_order_intent_runtime(&input, &book, &mut choke_metrics, &mut runtime_metrics);

    assert!(
        matches!(out.choke_result, ChokeResult::Rejected { .. }),
        "should reject when instrument not registered"
    );
    assert!(
        out.pending_reservation_id.is_none(),
        "no reservation should be created for unregistered instrument"
    );
    assert_eq!(
        runtime_metrics
            .pending_exposure
            .reserve_instrument_not_registered_total(),
        1,
        "instrument_not_registered metric should fire"
    );
}
