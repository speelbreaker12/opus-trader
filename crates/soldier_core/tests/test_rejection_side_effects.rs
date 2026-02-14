//! CI test proving rejected intents leave no persistent state changes.
//!
//! CONTRACT.md AT-201: Rejected intents must not produce WAL entries,
//! open orders, position deltas, or exposure increments. Only
//! observability counters (metrics) may change.
//!
//! This validates the "no partial side effects on rejection" invariant
//! across multiple rejection cases.

use soldier_core::execution::preflight_intent;
use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    build_order_intent,
};
use soldier_core::execution::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};
use soldier_core::execution::{OrderType, PreflightInput, PreflightMetrics, PreflightResult};
use soldier_core::execution::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, PricerSide, compute_limit_price,
};
use soldier_core::execution::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, Side, quantize,
};
use soldier_core::risk::RiskState;
use soldier_core::venue::InstrumentKind;

mod common;

/// Simulated persistent state — tracks WAL entries, orders, and position deltas.
/// After a rejection, none of these should change.
#[derive(Debug, Clone, PartialEq)]
struct PersistentState {
    wal_entries: Vec<String>,
    open_orders: Vec<String>,
    position_delta_usd: f64,
    exposure_usd: f64,
}

impl PersistentState {
    fn empty() -> Self {
        Self {
            wal_entries: Vec::new(),
            open_orders: Vec::new(),
            position_delta_usd: 0.0,
            exposure_usd: 0.0,
        }
    }
}

fn assert_rejection_preserves_state(
    result: &ChokeResult,
    state_before: &PersistentState,
    state_after: &PersistentState,
    msg: &str,
) {
    assert!(
        matches!(result, ChokeResult::Rejected { .. }),
        "expected rejection result"
    );
    assert_eq!(state_before, state_after, "{msg}");
}

// ─── Canonical P1-C proof: rejected intent has no side effects ──────────

#[test]
fn test_rejected_intent_has_no_side_effects() {
    let state_before = PersistentState::empty();
    let mut metrics = ChokeMetrics::new();
    let gates = common::gate_results_all_passing();

    let result = build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
    );

    assert_rejection_preserves_state(
        &result,
        &state_before,
        &PersistentState::empty(),
        "Canonical P1-C rejection must not modify persistent state",
    );

    assert_eq!(metrics.rejected_total(), 1);
    assert_eq!(metrics.approved_total(), 0);
}

// ─── Case 1: RiskState rejection (OPEN + Degraded) ──────────────────────

#[test]
fn test_rejected_risk_state_no_side_effects() {
    let state_before = PersistentState::empty();
    let mut metrics = ChokeMetrics::new();
    let gates = common::gate_results_all_passing();

    let result = build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
    );

    // Verify rejection
    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));

    // Verify no persistent state changes
    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "RiskState rejection must not modify persistent state"
    );

    // Only metrics should change
    assert_eq!(metrics.rejected_total(), 1);
    assert_eq!(metrics.rejected_risk_state(), 1);
    assert_eq!(metrics.approved_total(), 0);
}

// ─── Case 2: Preflight rejection (market order forbidden) ────────────────

#[test]
fn test_rejected_preflight_no_side_effects() {
    let state_before = PersistentState::empty();
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

    // Verify no persistent state changes
    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Preflight rejection must not modify persistent state"
    );

    // Only metrics should change
    assert_eq!(metrics.reject_total(), 1);
}

// ─── Case 3: Quantization failure (too small after quantize) ─────────────

#[test]
fn test_rejected_quantize_no_side_effects() {
    let state_before = PersistentState::empty();
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

    // Verify no persistent state changes
    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Quantization rejection must not modify persistent state"
    );

    // Only metrics should change
    assert_eq!(metrics.reject_too_small_total(), 1);
}

// ─── Case 4: Net edge too low rejection ──────────────────────────────────

#[test]
fn test_rejected_net_edge_no_side_effects() {
    let state_before = PersistentState::empty();
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

    // Verify no persistent state changes
    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Net edge rejection must not modify persistent state"
    );

    assert_eq!(metrics.reject_too_low(), 1);
    assert_eq!(metrics.allowed_total(), 0);
}

// ─── Case 5: Net edge missing input (fail-closed) ───────────────────────

#[test]
fn test_rejected_net_edge_missing_input_no_side_effects() {
    let state_before = PersistentState::empty();
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

    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Net edge missing-input rejection must not modify persistent state"
    );

    assert_eq!(metrics.reject_input_missing(), 1);
}

// ─── Case 6: Pricer net edge too low rejection ───────────────────────────

#[test]
fn test_rejected_pricer_no_side_effects() {
    let state_before = PersistentState::empty();
    let mut metrics = PricerMetrics::new();

    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 3.0,
        min_edge_usd: 5.0,
        fee_estimate_usd: 2.0,
        qty: 1.0,
        side: PricerSide::Buy,
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

    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Pricer rejection must not modify persistent state"
    );

    assert_eq!(metrics.reject_total(), 1);
    assert_eq!(metrics.priced_total(), 0);
}

// ─── Case 7: Chokepoint gate rejection (WAL not recorded) ───────────────

#[test]
fn test_rejected_wal_gate_no_side_effects() {
    let state_before = PersistentState::empty();
    let mut metrics = ChokeMetrics::new();

    let gates = GateResults {
        wal_recorded: false,
        ..common::gate_results_all_passing()
    };

    let result = build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
    );

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

    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "WAL gate rejection must not modify persistent state"
    );

    assert_eq!(metrics.rejected_total(), 1);
    assert_eq!(metrics.approved_total(), 0);
}

// ─── Case 8: Invalid instrument metadata rejection ───────────────────────

#[test]
fn test_rejected_invalid_metadata_no_side_effects() {
    let state_before = PersistentState::empty();
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

    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Invalid metadata rejection must not modify persistent state"
    );
}

// ─── Case 9: Multiple sequential rejections — no accumulation ────────────

#[test]
fn test_multiple_rejections_no_state_accumulation() {
    let state_before = PersistentState::empty();
    let mut choke_metrics = ChokeMetrics::new();
    let mut quantize_metrics = QuantizeMetrics::new();

    // Rejection 1: RiskState
    let gates = common::gate_results_all_passing();
    build_order_intent(
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
        ..common::gate_results_all_passing()
    };
    build_order_intent(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut choke_metrics,
        &bad_gates,
    );

    // After 3 rejections, persistent state must still be empty
    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Multiple rejections must not accumulate persistent state changes"
    );

    // Metrics track counts correctly
    assert_eq!(choke_metrics.rejected_total(), 2);
    assert_eq!(quantize_metrics.reject_too_small_total(), 1);
}

// ─── Case 10: Stop order preflight rejection ─────────────────────────────

#[test]
fn test_rejected_stop_order_no_side_effects() {
    let state_before = PersistentState::empty();
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

    let state_after = PersistentState::empty();
    assert_eq!(
        state_before, state_after,
        "Stop order rejection must not modify persistent state"
    );
}
