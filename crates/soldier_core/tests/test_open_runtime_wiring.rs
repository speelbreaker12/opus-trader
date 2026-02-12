//! Runtime wiring tests for Slice 6 gate integration at the OPEN chokepoint.

use soldier_core::execution::{
    ChokeMetrics, ChokeRejectReason, ChokeResult, GateIntentClass, GateStep, InventorySkewInput,
    InventorySkewSide, L2BookSnapshot, L2Level, LiquidityGateInput, NetEdgeInput, OpenRuntimeInput,
    OpenRuntimeMetrics, PricerInput, PricerSide, build_open_order_intent_runtime,
};
use soldier_core::risk::{
    ExposureBucket, ExposureBudgetInput, MarginGateInput, MarginGateMode, PendingExposureBook,
    RiskState,
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

fn base_open_input() -> OpenRuntimeInput {
    OpenRuntimeInput {
        risk_state: soldier_core::risk::RiskState::Healthy,
        preflight_passed: true,
        quantize_passed: true,
        dispatch_consistency_passed: true,
        fee_cache_passed: true,
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
            side: InventorySkewSide::Buy,
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
            side: PricerSide::Buy,
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
    }
}

#[test]
fn test_runtime_wiring_releases_pending_reservation_on_reject() {
    let mut input = base_open_input();
    input.exposure_budget_input.global_delta_limit_usd = Some(5.0);

    let mut pending_book = PendingExposureBook::new(Some(100.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    match out.choke_result {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert_eq!(
                reason,
                ChokeRejectReason::GateRejected {
                    gate: GateStep::LiquidityGate,
                    reason: "liquidity gate rejected".to_string(),
                }
            );
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected liquidity gate rejection, got {other:?}"),
    }

    assert!(!out.gate_results.liquidity_gate_passed);
    assert!(!out.gate_results.net_edge_passed);
    assert_eq!(out.pending_reservation_id, None);
    assert_eq!(pending_book.active_reservations(), 0);
    assert_eq!(runtime_metrics.pending_exposure.release_total(), 1);
}

#[test]
fn test_runtime_wiring_inventory_skew_forces_net_edge_recheck_before_pricer() {
    let mut input = base_open_input();
    input.inventory_skew_input.current_delta = 100.0;

    let mut pending_book = PendingExposureBook::new(Some(200.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
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

    let mut pending_book = PendingExposureBook::new(Some(200.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert_eq!(out.mode_hint, MarginGateMode::Kill);
    assert_eq!(out.pending_reservation_id, None);
    assert_eq!(pending_book.active_reservations(), 0);
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
    let mut input = base_open_input();
    input.risk_state = RiskState::Maintenance;
    input.margin_gate_input.maintenance_margin_usd = 80.0;
    input.margin_gate_input.equity_usd = 100.0;

    let mut pending_book = PendingExposureBook::new(Some(200.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert_eq!(out.mode_hint, MarginGateMode::Active);
    assert_eq!(out.effective_risk_state, RiskState::Maintenance);
    assert_eq!(out.pending_reservation_id, None);
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
    input.inventory_skew_input.side = InventorySkewSide::Sell;
    input.net_edge_input.min_edge_usd = Some(11.0);
    input.pricer_input.side = PricerSide::Sell;
    input.pricer_input.min_edge_usd = 11.0;

    let mut pending_book = PendingExposureBook::new(Some(200.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
        &mut choke_metrics,
        &mut runtime_metrics,
    );

    assert!(matches!(out.choke_result, ChokeResult::Approved { .. }));
    assert!(out.pending_reservation_id.is_some());
    assert_eq!(runtime_metrics.net_edge.reject_too_low(), 1);
    assert_eq!(runtime_metrics.net_edge.allowed_total(), 1);
    assert!(out.adjusted_min_edge_usd.unwrap_or(f64::INFINITY) < 11.0);
}

#[test]
fn test_runtime_wiring_delta_limit_missing_degrades_even_if_net_edge_fails_first() {
    let mut input = base_open_input();
    input.net_edge_input.min_edge_usd = Some(50.0);
    input.inventory_skew_input.delta_limit = None;

    let mut pending_book = PendingExposureBook::new(Some(200.0));
    let mut choke_metrics = ChokeMetrics::new();
    let mut runtime_metrics = OpenRuntimeMetrics::default();

    let out = build_open_order_intent_runtime(
        &input,
        &mut pending_book,
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
