//! CI tests proving rejected intents do not trigger dispatch-side effects.
//!
//! CONTRACT.md AT-201: Rejected intents must not produce WAL entries,
//! open orders, position deltas, or exposure increments. Only
//! observability counters (metrics) may change.
//!
//! Side-effect causality is asserted through the observable chokepoint
//! surface: `RecordedBeforeDispatch` gate invocation count.

use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    RecordedBeforeDispatchGate, build_order_intent_with_wal_gate,
};
use crate::execution::gates::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};
use crate::execution::preflight::{
    OrderType, PreflightInput, PreflightMetrics, PreflightResult, preflight_intent,
};
use crate::execution::pricer::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, compute_limit_price,
};
use crate::execution::quantize::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, Side, quantize,
};
use crate::risk::RiskState;
use crate::venue::InstrumentKind;

fn gate_results_all_passing() -> GateResults {
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

fn assert_no_dispatch(result: &ChokeResult, metrics: &ChokeMetrics, context: &str) {
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

fn assert_no_dispatch_no_wal(result: &ChokeResult, metrics: &ChokeMetrics, context: &str) {
    assert_no_dispatch(result, metrics, context);
    let ChokeResult::Rejected { gate_trace, .. } = result else {
        return;
    };
    assert!(
        !gate_trace.contains(&GateStep::RecordedBeforeDispatch),
        "{context}: gate_trace must not contain RecordedBeforeDispatch for pre-WAL rejections"
    );
}

#[allow(deprecated)]
fn legacy_build_order_intent(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
) -> ChokeResult {
    crate::execution::build_order_intent::build_order_intent(
        intent_class,
        risk_state,
        metrics,
        gate_results,
    )
}

#[derive(Debug)]
struct CountingWalGate {
    calls: usize,
    succeed: bool,
}

impl RecordedBeforeDispatchGate for CountingWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.calls += 1;
        if self.succeed {
            Ok(())
        } else {
            Err("simulated wal failure".to_string())
        }
    }
}

// ─── Canonical P1-C proof: rejected intent has no side effects ──────────

#[test]
fn test_rejected_intent_has_no_side_effects() {
    let mut metrics = ChokeMetrics::new();
    let gates = gate_results_all_passing();

    let result = legacy_build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
    );

    assert_no_dispatch_no_wal(&result, &metrics, "Canonical P1-C rejection");
    assert_eq!(metrics.rejected_total(), 1);
}

// ─── Case 1: RiskState rejection (OPEN + Degraded) ──────────────────────

#[test]
fn test_rejected_risk_state_no_side_effects() {
    let mut metrics = ChokeMetrics::new();
    let gates = gate_results_all_passing();

    let result = legacy_build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
    );

    assert_no_dispatch_no_wal(&result, &metrics, "RiskState rejection");
    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
    assert_eq!(metrics.rejected_total(), 1);
    assert_eq!(metrics.rejected_risk_state(), 1);
}

#[test]
fn test_pre_wal_rejection_does_not_invoke_recorded_before_dispatch_gate() {
    let mut metrics = ChokeMetrics::new();
    let gates = gate_results_all_passing();
    let mut wal_gate = CountingWalGate {
        calls: 0,
        succeed: true,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
    assert_eq!(
        wal_gate.calls, 0,
        "RecordedBeforeDispatch must not be invoked for pre-WAL rejection paths"
    );
}

#[test]
fn test_approved_open_invokes_recorded_before_dispatch_gate_once() {
    let mut metrics = ChokeMetrics::new();
    let gates = gate_results_all_passing();
    let mut wal_gate = CountingWalGate {
        calls: 0,
        succeed: true,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(
        matches!(result, ChokeResult::Approved { .. }),
        "all-pass OPEN path should be approved"
    );
    assert_eq!(
        wal_gate.calls, 1,
        "approved OPEN path must invoke RecordedBeforeDispatch exactly once"
    );
}

// ─── Case 2: Preflight rejection (market order forbidden) ────────────────

#[test]
fn test_rejected_preflight_no_side_effects() {
    let mut metrics = PreflightMetrics::new();

    let input = PreflightInput {
        instrument_kind: InstrumentKind::Perpetual,
        order_type: OrderType::Market,
        has_trigger: false,
        linked_order_type: None,
        linked_orders_allowed: false,
        post_only_input: None,
    };

    let result = preflight_intent(&input, &mut metrics);

    // Verify rejection
    assert!(matches!(result, PreflightResult::Rejected(_)));

    // Only metrics should change
    assert_eq!(metrics.reject_total(), 1);
}

// ─── Case 3: Quantization failure (too small after quantize) ─────────────

#[test]
fn test_rejected_quantize_no_side_effects() {
    let mut metrics = QuantizeMetrics::new();

    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 1.0,
        min_amount: 1.0,
    };

    // qty=0.5 rounds to 0 steps, which is < min_amount=1.0
    let result = quantize(0.5, 100.0, Side::Buy, &constraints, &mut metrics);

    // Verify rejection
    assert!(matches!(
        result,
        Err(QuantizeError::TooSmallAfterQuantization { .. })
    ));

    // Only metrics should change
    assert_eq!(metrics.reject_too_small_total(), 1);
}

// ─── Case 4: Net edge too low rejection ──────────────────────────────────

#[test]
fn test_rejected_net_edge_no_side_effects() {
    let mut metrics = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(5.0),
        fee_usd: Some(3.0),
        expected_slippage_usd: Some(2.0),
        min_edge_usd: Some(2.0),
    };
    // net = 5 - 3 - 2 = 0 < min_edge=2 → reject

    let result = evaluate_net_edge(&input, &mut metrics);

    // Verify rejection
    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeTooLow,
            ..
        }
    ));

    assert_eq!(metrics.reject_too_low(), 1);
    assert_eq!(metrics.allowed_total(), 0);
}

// ─── Case 5: Net edge missing input (fail-closed) ───────────────────────

#[test]
fn test_rejected_net_edge_missing_input_no_side_effects() {
    let mut metrics = NetEdgeMetrics::new();

    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: None, // missing → fail-closed
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(2.0),
    };

    let result = evaluate_net_edge(&input, &mut metrics);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));

    assert_eq!(metrics.reject_input_missing(), 1);
}

// ─── Case 6: Pricer net edge too low rejection ───────────────────────────

#[test]
fn test_rejected_pricer_no_side_effects() {
    let mut metrics = PricerMetrics::new();

    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 3.0,
        min_edge_usd: 5.0,
        fee_estimate_usd: 2.0,
        qty: 1.0,
        side: Side::Buy,
    };
    // net = 3 - 2 = 1 < min_edge=5 → reject

    let result = compute_limit_price(&input, &mut metrics);

    assert!(matches!(
        result,
        PricerResult::Rejected {
            reason: PricerRejectReason::NetEdgeTooLow,
            ..
        }
    ));

    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(metrics.priced_total(), 0);
}

// ─── Case 7: Chokepoint gate rejection (WAL not recorded) ───────────────

#[test]
fn test_rejected_wal_gate_no_side_effects() {
    let mut metrics = ChokeMetrics::new();

    let gates = GateResults {
        wal_recorded: false,
        ..gate_results_all_passing()
    };

    let result = legacy_build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
    );

    // WAL gate pushes RecordedBeforeDispatch to trace before checking — use
    // assert_no_dispatch (NOT _no_wal).
    assert_no_dispatch(&result, &metrics, "WAL gate rejection");
    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::RecordedBeforeDispatch,
                ..
            },
            ..
        }
    ));
    assert_eq!(metrics.rejected_total(), 1);
}

// ─── Case 8: Invalid instrument metadata rejection ───────────────────────

#[test]
fn test_rejected_invalid_metadata_no_side_effects() {
    let mut metrics = QuantizeMetrics::new();

    let constraints = QuantizeConstraints {
        tick_size: 0.0, // invalid — zero tick_size
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut metrics);

    assert!(matches!(
        result,
        Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" })
    ));

    assert_eq!(metrics.reject_metadata_missing_total(), 1);
}

// ─── Case 9: Multiple sequential rejections — no accumulation ────────────

#[test]
fn test_multiple_rejections_no_state_accumulation() {
    let mut choke_metrics = ChokeMetrics::new();
    let mut quantize_metrics = QuantizeMetrics::new();

    // Rejection 1: RiskState
    let gates = gate_results_all_passing();
    legacy_build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Kill,
        &mut choke_metrics,
        &gates,
    );

    // Rejection 2: Quantize
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 1.0,
        min_amount: 1.0,
    };
    let _ = quantize(0.1, 100.0, Side::Buy, &constraints, &mut quantize_metrics);

    // Rejection 3: Gate failure
    let bad_gates = GateResults {
        preflight_passed: false,
        ..gate_results_all_passing()
    };
    legacy_build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut choke_metrics,
        &bad_gates,
    );

    // Metrics track counts correctly
    assert_eq!(choke_metrics.rejected_total(), 2);
    assert_eq!(quantize_metrics.reject_too_small_total(), 1);
}

// ─── Case 10: Stop order preflight rejection ─────────────────────────────

#[test]
fn test_rejected_stop_order_no_side_effects() {
    let mut metrics = PreflightMetrics::new();

    let input = PreflightInput {
        instrument_kind: InstrumentKind::Option,
        order_type: OrderType::StopLimit,
        has_trigger: true,
        linked_order_type: None,
        linked_orders_allowed: false,
        post_only_input: None,
    };

    let result = preflight_intent(&input, &mut metrics);

    assert!(matches!(result, PreflightResult::Rejected(_)));
    assert_eq!(metrics.reject_total(), 1);
}
