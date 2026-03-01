//! CI test proving missing critical config causes fail-closed rejection.
//!
//! CONTRACT.md Appendix A: Safety-Critical Thresholds.
//! Missing or invalid config MUST cause rejection with an enumerated
//! reason code — never silently default to an unsafe value.

#![allow(deprecated)]

use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    RecordedBeforeDispatchGate, build_order_intent, build_order_intent_with_wal_gate,
};
use crate::execution::gate::{
    GateIntentClass, LiquidityGateDecision, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateRejectReason, evaluate_liquidity_gate,
};
use crate::execution::gates::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};
use crate::execution::pricer::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, compute_limit_price,
};
use crate::execution::quantize::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, Side, quantize,
};
use crate::risk::RiskState;

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

#[derive(Debug)]
struct CountingWalGate {
    calls: usize,
}

impl RecordedBeforeDispatchGate for CountingWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.calls += 1;
        Ok(())
    }
}

// ─── Missing quantize constraints ────────────────────────────────────────

#[test]
fn test_missing_tick_size_fails_closed() {
    let mut m = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.0, // invalid — zero
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut m);

    match result {
        Err(QuantizeError::InstrumentMetadataMissing { field }) => {
            assert_eq!(field, "tick_size", "Rejection must name the missing field");
        }
        other => panic!("expected InstrumentMetadataMissing, got {other:?}"),
    }
}

#[test]
fn test_missing_amount_step_fails_closed() {
    let mut m = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.0, // invalid — zero
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut m);

    match result {
        Err(QuantizeError::InstrumentMetadataMissing { field }) => {
            assert_eq!(field, "amount_step");
        }
        other => panic!("expected InstrumentMetadataMissing, got {other:?}"),
    }
}

#[test]
fn test_nan_tick_size_fails_closed() {
    let mut m = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: f64::NAN,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut m);

    assert!(
        matches!(result, Err(QuantizeError::InstrumentMetadataMissing { .. })),
        "NaN tick_size must fail-closed"
    );
}

#[test]
fn test_infinity_amount_step_fails_closed() {
    let mut m = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: f64::INFINITY,
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut m);

    assert!(
        matches!(result, Err(QuantizeError::InstrumentMetadataMissing { .. })),
        "Infinity amount_step must fail-closed"
    );
}

#[test]
fn test_negative_tick_size_fails_closed() {
    let mut m = QuantizeMetrics::new();
    let constraints = QuantizeConstraints {
        tick_size: -0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let result = quantize(1.0, 100.0, Side::Buy, &constraints, &mut m);

    assert!(
        matches!(result, Err(QuantizeError::InstrumentMetadataMissing { .. })),
        "Negative tick_size must fail-closed"
    );
}

// ─── Missing net edge inputs (fail-closed) ───────────────────────────────

#[test]
fn test_missing_gross_edge_fails_closed() {
    let mut m = NetEdgeMetrics::new();
    let input = NetEdgeInput {
        gross_edge_usd: None, // missing
        fee_usd: Some(3.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(2.0),
    };

    let result = evaluate_net_edge(&input, &mut m);

    assert!(
        matches!(
            result,
            NetEdgeResult::Rejected {
                reason: NetEdgeRejectReason::NetEdgeInputMissing,
                ..
            }
        ),
        "Missing gross_edge must fail-closed with NetEdgeInputMissing"
    );
}

#[test]
fn test_missing_fee_usd_fails_closed() {
    let mut m = NetEdgeMetrics::new();
    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: None, // missing
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(2.0),
    };

    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_missing_slippage_fails_closed() {
    let mut m = NetEdgeMetrics::new();
    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(3.0),
        expected_slippage_usd: None, // missing
        min_edge_usd: Some(2.0),
    };

    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

#[test]
fn test_missing_min_edge_fails_closed() {
    let mut m = NetEdgeMetrics::new();
    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(3.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: None, // missing
    };

    let result = evaluate_net_edge(&input, &mut m);

    assert!(matches!(
        result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));
}

// ─── Missing L2 book data (fail-closed) ──────────────────────────────────

#[test]
fn test_missing_l2_book_fails_closed() {
    let mut m = LiquidityGateMetrics::new();
    let input = LiquidityGateInput {
        order_qty: 1.0,
        is_buy: true,
        intent_class: GateIntentClass::Open,
        is_marketable: true,
        l2_snapshot: None, // missing book
        now_ms: 1000,
        l2_book_snapshot_max_age_ms: 5000,
        max_slippage_bps: 200.0,
    };

    let result = evaluate_liquidity_gate(&input, &mut m);

    assert!(
        matches!(
            result.decision,
            LiquidityGateDecision::Rejected {
                reason: LiquidityGateRejectReason::LiquidityGateNoL2
            }
        ),
        "Missing L2 book must fail-closed with LiquidityGateNoL2"
    );
}

// ─── Missing pricer input (invalid qty) ──────────────────────────────────

#[test]
fn test_zero_qty_pricer_fails_closed() {
    let mut m = PricerMetrics::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 10.0,
        min_edge_usd: 2.0,
        fee_estimate_usd: 3.0,
        qty: 0.0, // invalid
        side: Side::Buy,
    };

    let result = compute_limit_price(&input, &mut m);

    assert!(
        matches!(
            result,
            PricerResult::Rejected {
                reason: PricerRejectReason::InvalidInput,
                ..
            }
        ),
        "Zero qty must fail-closed with InvalidInput"
    );
}

// ─── Chokepoint with unhealthy risk state ────────────────────────────────

#[test]
fn test_unhealthy_risk_state_fails_closed() {
    let gates = gate_results_all_passing();

    // All non-Healthy states must reject OPEN
    for risk_state in [RiskState::Degraded, RiskState::Maintenance, RiskState::Kill] {
        let mut m = ChokeMetrics::new();
        let result = build_order_intent(ChokeIntentClass::Open, risk_state, &mut m, &gates);

        assert_no_dispatch_no_wal(
            &result,
            &m,
            &format!("RiskState::{risk_state:?} fail-closed"),
        );
        assert!(
            matches!(
                result,
                ChokeResult::Rejected {
                    reason: ChokeRejectReason::RiskStateNotHealthy,
                    ..
                }
            ),
            "RiskState::{risk_state:?} must fail-closed for OPEN intents"
        );
    }
}

// ─── Rejections must expose concrete enumerated reason variants ───────────

#[test]
fn test_rejection_paths_return_enumerated_reason_variants() {
    // Quantize: invalid metadata -> InstrumentMetadataMissing
    let mut quantize_metrics = QuantizeMetrics::new();
    let quantize_result = quantize(
        1.0,
        100.0,
        Side::Buy,
        &QuantizeConstraints {
            tick_size: 0.0,
            amount_step: 0.1,
            min_amount: 0.1,
        },
        &mut quantize_metrics,
    );
    assert!(matches!(
        quantize_result,
        Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" })
    ));

    // NetEdge: missing inputs -> NetEdgeInputMissing
    let mut net_edge_metrics = NetEdgeMetrics::new();
    let net_edge_result = evaluate_net_edge(
        &NetEdgeInput {
            gross_edge_usd: None,
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(1.0),
        },
        &mut net_edge_metrics,
    );
    assert!(matches!(
        net_edge_result,
        NetEdgeResult::Rejected {
            reason: NetEdgeRejectReason::NetEdgeInputMissing,
            ..
        }
    ));

    // Pricer: invalid qty -> InvalidInput
    let mut pricer_metrics = PricerMetrics::new();
    let pricer_result = compute_limit_price(
        &PricerInput {
            fair_price: 100.0,
            gross_edge_usd: 10.0,
            min_edge_usd: 1.0,
            fee_estimate_usd: 1.0,
            qty: 0.0,
            side: Side::Buy,
        },
        &mut pricer_metrics,
    );
    assert!(matches!(
        pricer_result,
        PricerResult::Rejected {
            reason: PricerRejectReason::InvalidInput,
            ..
        }
    ));

    // Chokepoint: unhealthy risk state -> RiskStateNotHealthy
    let mut choke_metrics = ChokeMetrics::new();
    let choke_result = build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut choke_metrics,
        &gate_results_all_passing(),
    );
    assert!(matches!(
        choke_result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));

    // Liquidity gate: missing L2 -> LiquidityGateNoL2
    let mut liquidity_metrics = LiquidityGateMetrics::new();
    let liquidity_result = evaluate_liquidity_gate(
        &LiquidityGateInput {
            order_qty: 1.0,
            is_buy: true,
            intent_class: GateIntentClass::Open,
            is_marketable: true,
            l2_snapshot: None,
            now_ms: 1_000,
            l2_book_snapshot_max_age_ms: 5_000,
            max_slippage_bps: 200.0,
        },
        &mut liquidity_metrics,
    );
    assert!(matches!(
        liquidity_result.decision,
        LiquidityGateDecision::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2
        }
    ));
}

// ─── No persistent side effects on config-missing rejections ─────────────

#[test]
fn test_config_missing_no_side_effects() {
    // Run all config-missing scenarios and verify zero persistent state

    // 1. Missing tick_size
    let mut qm = QuantizeMetrics::new();
    let bad_constraints = QuantizeConstraints {
        tick_size: 0.0,
        amount_step: 0.1,
        min_amount: 0.1,
    };
    let _ = quantize(1.0, 100.0, Side::Buy, &bad_constraints, &mut qm);

    // 2. Missing net edge input
    let mut nem = NetEdgeMetrics::new();
    let _ = evaluate_net_edge(
        &NetEdgeInput {
            gross_edge_usd: None,
            fee_usd: None,
            expected_slippage_usd: None,
            min_edge_usd: None,
        },
        &mut nem,
    );

    // 3. Missing L2
    let mut lgm = LiquidityGateMetrics::new();
    let _ = evaluate_liquidity_gate(
        &LiquidityGateInput {
            order_qty: 1.0,
            is_buy: true,
            intent_class: GateIntentClass::Open,
            is_marketable: true,
            l2_snapshot: None,
            now_ms: 1000,
            l2_book_snapshot_max_age_ms: 5000,
            max_slippage_bps: 200.0,
        },
        &mut lgm,
    );

    // 4. Quantize gate rejection at chokepoint must not invoke WAL gate.
    let mut choke_metrics = ChokeMetrics::new();
    let quantize_rejected = GateResults {
        quantize_passed: false,
        ..gate_results_all_passing()
    };
    let mut wal_gate = CountingWalGate { calls: 0 };

    let choke_result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut choke_metrics,
        &quantize_rejected,
        &mut wal_gate,
    );

    assert!(matches!(
        choke_result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::Quantize,
                ..
            },
            ..
        }
    ));
    assert_eq!(
        wal_gate.calls, 0,
        "pre-WAL rejection must not call RecordedBeforeDispatch gate"
    );
    assert_eq!(
        choke_metrics.approved_total(),
        0,
        "rejection path must not approve dispatch"
    );

    // Only gate-local metrics changed during config-missing failures.
    assert!(nem.reject_input_missing() >= 1);
}
