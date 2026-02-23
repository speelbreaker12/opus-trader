//! Unit tests for the shared base gate evaluator (gates 1-6).
//!
//! Covers gate isolation (TRIP + NON-TRIP), early-exit ordering,
//! proof token intermediate values, and rejection reason code fidelity.

mod common;

use soldier_core::execution::reject_reason::RejectReasonCode;
use soldier_core::execution::{
    BaseGatesInput, BaseGatesLegacy, BaseGatesMetrics, ChokeIntentClass, DispatchConsistencyProof, GateStep, OrderType,
    PreflightInput, QuantizeConstraints, QuantizePipelineInput, Side, evaluate_base_gates,
};
use soldier_core::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use soldier_core::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};

/// Build a known-passing BaseGatesInput for OPEN + Healthy.
fn passing_base_input<'a>() -> BaseGatesInput<'a> {
    BaseGatesInput {
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
        dispatch_consistency: DispatchConsistencyProof::unchecked(true),
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
    }
}

// ─── NON-TRIP: all gates pass → Ok proof ─────────────────────────────────

#[test]
fn test_base_gates_all_pass_returns_proof() {
    let input = passing_base_input();
    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);
    assert!(result.is_ok(), "all gates should pass: {result:?}");

    let proof = result.unwrap();
    assert!(!proof.dispatch_auth_short_circuit());
    assert_eq!(proof.lifecycle_intent(), LifecycleIntent::Open);

    // Legacy bools: all true
    let legacy = BaseGatesLegacy::from(&proof);
    assert!(legacy.preflight_passed);
    assert!(legacy.quantize_passed);
    assert!(legacy.dispatch_consistency_passed);
    assert!(legacy.fee_cache_passed);
    assert!(legacy.expiry_guard_passed);
}

// ─── TRIP: Gate 1 — DispatchAuth ─────────────────────────────────────────

#[test]
fn test_base_gates_gate1_dispatch_auth_open_degraded_short_circuits() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::Open;
    input.risk_state = RiskState::Degraded;

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    // OPEN + !Healthy → short-circuit Ok with dispatch_auth_short_circuit=true
    assert!(
        result.is_ok(),
        "dispatch auth short-circuit returns Ok: {result:?}"
    );
    let proof = result.unwrap();
    assert!(proof.dispatch_auth_short_circuit());
    // Short-circuit accessors return None for placeholder values
    assert!(
        proof.quantized().is_none(),
        "short-circuit proof should not expose placeholder quantized values"
    );
    assert!(
        proof.fee_evaluation().is_none(),
        "short-circuit proof should not expose placeholder fee evaluation"
    );
}

#[test]
fn test_base_gates_gate1_cancel_only_short_circuits() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::CancelOnly;

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_ok(),
        "CancelOnly short-circuit returns Ok: {result:?}"
    );
    let proof = result.unwrap();
    assert!(proof.dispatch_auth_short_circuit());
    assert_eq!(proof.lifecycle_intent(), LifecycleIntent::Cancel);
}

// ─── TRIP: Gate 2 — Preflight ────────────────────────────────────────────

#[test]
fn test_base_gates_gate2_preflight_rejects_invalid_order() {
    let mut input = passing_base_input();
    input.preflight.order_type = OrderType::Market; // forbidden

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_err(),
        "market order should be rejected by preflight"
    );
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::Preflight);
    assert_eq!(
        rejection.reason_code,
        RejectReasonCode::OrderTypeMarketForbidden
    );
}

// ─── TRIP: Gate 3 — Quantize ─────────────────────────────────────────────

#[test]
fn test_base_gates_gate3_quantize_rejects_too_small() {
    let mut input = passing_base_input();
    input.quantize.raw_qty = 0.001; // below min_amount=0.1

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_err(),
        "qty below min should be rejected by quantize"
    );
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::Quantize);
}

// ─── TRIP: Gate 4 — DispatchConsistency ──────────────────────────────────

#[test]
fn test_base_gates_gate4_dispatch_consistency_rejects_mismatch() {
    let mut input = passing_base_input();
    input.dispatch_consistency = DispatchConsistencyProof::unchecked(false);

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_err(),
        "dispatch consistency mismatch should reject"
    );
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::DispatchConsistency);
    assert_eq!(
        rejection.reason_code,
        RejectReasonCode::ContractsAmountMismatch
    );
}

// ─── TRIP: Gate 5 — FeeCacheCheck ────────────────────────────────────────

#[test]
fn test_base_gates_gate5_fee_cache_rejects_hard_stale() {
    let mut input = passing_base_input();
    // Make fee cache hard-stale: cached 2000s ago, hard threshold is 900s
    input.fee_snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_000_000 + 2_000_000, // 2000s later
    };

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(result.is_err(), "hard-stale fee cache should reject");
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::FeeCacheCheck);
}

// ─── TRIP: Gate 6 — ExpiryGuard ──────────────────────────────────────────

#[test]
fn test_base_gates_gate6_expiry_guard_rejects_expired() {
    let mut input = passing_base_input();
    // Instrument expires at 1_000_000ms, now is 1_100_000ms → expired
    input.expiry_guard = Some(ExpiryGuardInput {
        now_ms: 1_100_000,
        expiration_timestamp_ms: Some(1_000_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    });

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(result.is_err(), "expired instrument should reject");
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::ExpiryGuard);
    assert_eq!(
        rejection.reason_code,
        RejectReasonCode::InstrumentExpiredOrDelisted
    );
}

#[test]
fn test_base_gates_gate6_missing_expiry_open_fail_closed() {
    let mut input = passing_base_input();
    input.expiry_guard = None; // missing expiry data

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_err(),
        "missing expiry data for OPEN should fail-closed"
    );
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::ExpiryGuard);
    assert_eq!(
        rejection.reason_code,
        RejectReasonCode::InstrumentExpiredOrDelisted
    );
}

#[test]
fn test_base_gates_gate6_missing_expiry_close_allowed() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::Close;
    input.expiry_guard = None; // missing expiry data — allowed for non-OPEN

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(
        result.is_ok(),
        "missing expiry data for CLOSE should be allowed: {result:?}"
    );
}

// ─── Early-exit ordering ─────────────────────────────────────────────────

#[test]
fn test_base_gates_gate2_failure_skips_gate3_evaluation() {
    let mut input = passing_base_input();
    input.preflight.order_type = OrderType::Market; // gate 2 fails

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(result.is_err());
    let rejection = result.unwrap_err();
    assert_eq!(rejection.gate, GateStep::Preflight);
    // Gate outcomes should only contain the Preflight rejection — Quantize was never reached
    assert_eq!(
        rejection.gate_outcomes.len(),
        1,
        "only Preflight outcome should be present (gate 3 was never called): {:?}",
        rejection.gate_outcomes
    );
}

#[test]
fn test_base_gates_gate_outcomes_stop_at_failure() {
    let mut input = passing_base_input();
    input.dispatch_consistency = DispatchConsistencyProof::unchecked(false); // gate 4 fails

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);

    assert!(result.is_err());
    let rejection = result.unwrap_err();
    // Gates 1 (DispatchAuth, implicit), 2 (Preflight), 3 (Quantize), 4 (DispatchConsistency fail)
    // gate_outcomes should have: Preflight(Allow) + Quantize(Allow) + DispatchConsistency(Reject) = 3
    assert_eq!(
        rejection.gate_outcomes.len(),
        3,
        "gate_outcomes should contain gates 2, 3, 4 only: {:?}",
        rejection.gate_outcomes
    );
}

// ─── Proof token intermediate values ─────────────────────────────────────

#[test]
fn test_base_gates_proof_quantized_values_present() {
    let input = passing_base_input();
    let mut metrics = BaseGatesMetrics::new();
    let proof = evaluate_base_gates(&input, &mut metrics).unwrap();

    // Quantized qty should be >= min_amount (0.1) since raw_qty is 1.0
    let quantized = proof
        .quantized()
        .expect("non-short-circuit proof has quantized values");
    assert!(quantized.qty_q > 0.0, "quantized qty should be positive");
    assert!(
        quantized.limit_price_q > 0.0,
        "quantized price should be positive"
    );
}

#[test]
fn test_base_gates_proof_fee_evaluation_present() {
    let input = passing_base_input();
    let mut metrics = BaseGatesMetrics::new();
    let proof = evaluate_base_gates(&input, &mut metrics).unwrap();

    // Fee eval should show Fresh staleness since cache is recent
    let fee_eval = proof
        .fee_evaluation()
        .expect("non-short-circuit proof has fee evaluation");
    assert_eq!(fee_eval.staleness, soldier_core::risk::FeeStaleness::Fresh);
}

// ─── Rejection reason code fidelity ──────────────────────────────────────

#[test]
fn test_base_gates_rejection_legacy_preserves_reason() {
    let mut input = passing_base_input();
    input.preflight.order_type = OrderType::Market;

    let mut metrics = BaseGatesMetrics::new();
    let rejection = evaluate_base_gates(&input, &mut metrics).unwrap_err();

    let legacy = BaseGatesLegacy::from(&rejection);
    assert!(!legacy.preflight_passed);
    assert_eq!(
        legacy.preflight_reject_code,
        Some(RejectReasonCode::OrderTypeMarketForbidden)
    );
    // Other gates should remain true (not cascaded)
    assert!(legacy.quantize_passed);
    assert!(legacy.dispatch_consistency_passed);
    assert!(legacy.fee_cache_passed);
    assert!(legacy.expiry_guard_passed);
}

#[test]
fn test_base_gates_rejection_gate_step_matches_failure_point() {
    // Test each gate failure produces the correct GateStep
    type Mutator = Box<dyn Fn(&mut BaseGatesInput<'_>)>;
    let cases: Vec<(&str, Mutator, GateStep)> = vec![
        (
            "preflight",
            Box::new(|input: &mut BaseGatesInput<'_>| {
                input.preflight.order_type = OrderType::Market;
            }),
            GateStep::Preflight,
        ),
        (
            "dispatch_consistency",
            Box::new(|input: &mut BaseGatesInput<'_>| {
                input.dispatch_consistency = DispatchConsistencyProof::unchecked(false);
            }),
            GateStep::DispatchConsistency,
        ),
        (
            "expiry_guard",
            Box::new(|input: &mut BaseGatesInput<'_>| {
                input.expiry_guard = Some(ExpiryGuardInput {
                    now_ms: 1_100_000,
                    expiration_timestamp_ms: Some(1_000_000),
                    expiry_delist_buffer_s: 60,
                    intent: LifecycleIntent::Open,
                    instrument_kind: Some(InstrumentKind::LinearFuture),
                });
            }),
            GateStep::ExpiryGuard,
        ),
    ];

    for (name, mutator, expected_gate) in &cases {
        let mut input = passing_base_input();
        mutator(&mut input);
        let mut metrics = BaseGatesMetrics::new();
        let rejection = evaluate_base_gates(&input, &mut metrics).unwrap_err();
        assert_eq!(
            rejection.gate, *expected_gate,
            "case '{name}': expected gate {expected_gate:?}, got {:?}",
            rejection.gate
        );
    }
}

// ─── CLOSE/HEDGE paths pass without expiry guard ─────────────────────────

#[test]
fn test_base_gates_close_no_expiry_passes() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::Close;
    input.expiry_guard = None;

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);
    assert!(
        result.is_ok(),
        "CLOSE without expiry should pass: {result:?}"
    );
    assert_eq!(result.unwrap().lifecycle_intent(), LifecycleIntent::Close);
}

#[test]
fn test_base_gates_hedge_no_expiry_passes() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::Hedge;
    input.expiry_guard = None;

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);
    assert!(
        result.is_ok(),
        "HEDGE without expiry should pass: {result:?}"
    );
    assert_eq!(result.unwrap().lifecycle_intent(), LifecycleIntent::Hedge);
}

/// CLOSE + Degraded runs all 6 gates (no dispatch_auth short-circuit).
/// Catches mutation where CLOSE + !Healthy incorrectly short-circuits.
#[test]
fn test_base_gates_close_degraded_evaluates_all_gates() {
    let mut input = passing_base_input();
    input.intent_class = ChokeIntentClass::Close;
    input.risk_state = RiskState::Degraded;
    input.expiry_guard = None; // allowed for CLOSE

    let mut metrics = BaseGatesMetrics::new();
    let result = evaluate_base_gates(&input, &mut metrics);
    assert!(
        result.is_ok(),
        "CLOSE + Degraded should evaluate gates normally: {result:?}"
    );
    let proof = result.unwrap();
    // Must NOT short-circuit — gates were actually evaluated
    assert!(
        !proof.dispatch_auth_short_circuit(),
        "CLOSE + Degraded must not short-circuit dispatch auth"
    );
    assert_eq!(proof.lifecycle_intent(), LifecycleIntent::Close);
    // gate_outcomes should contain actual evaluations (Preflight, Quantize, etc.)
    assert!(
        !proof.gate_outcomes().is_empty(),
        "gates should have been evaluated, not short-circuited"
    );
}

// ─── Legacy conversion for DispatchConsistency rejection ─────────────────

/// Verify BaseGatesLegacy correctly marks dispatch_consistency_passed=false
/// and does NOT carry a reject code (gate 4 has no typed reason code).
#[test]
fn test_base_gates_legacy_dispatch_consistency_rejection() {
    let mut input = passing_base_input();
    input.dispatch_consistency = DispatchConsistencyProof::unchecked(false);

    let mut metrics = BaseGatesMetrics::new();
    let rejection = evaluate_base_gates(&input, &mut metrics).unwrap_err();
    assert_eq!(rejection.gate, GateStep::DispatchConsistency);

    let legacy = BaseGatesLegacy::from(&rejection);
    assert!(
        !legacy.dispatch_consistency_passed,
        "dispatch_consistency_passed should be false"
    );
    // Gates before the failure should remain true
    assert!(legacy.preflight_passed);
    assert!(legacy.quantize_passed);
    // Gates after the failure should remain true (legacy marks only the failed gate)
    assert!(legacy.fee_cache_passed);
    assert!(legacy.expiry_guard_passed);
}

// ─── Lifecycle intent derivation ─────────────────────────────────────────

#[test]
fn test_base_gates_lifecycle_intent_derivation() {
    let cases = vec![
        (ChokeIntentClass::Open, LifecycleIntent::Open),
        (ChokeIntentClass::Close, LifecycleIntent::Close),
        (ChokeIntentClass::Hedge, LifecycleIntent::Hedge),
        (ChokeIntentClass::CancelOnly, LifecycleIntent::Cancel),
    ];

    for (intent_class, expected_lifecycle) in cases {
        let mut input = passing_base_input();
        input.intent_class = intent_class;
        // CancelOnly and non-Healthy will short-circuit; skip expiry for CLOSE/HEDGE
        if intent_class != ChokeIntentClass::Open {
            input.expiry_guard = None;
        }

        let mut metrics = BaseGatesMetrics::new();
        let result = evaluate_base_gates(&input, &mut metrics);
        assert!(
            result.is_ok(),
            "intent_class {intent_class:?} should pass: {result:?}"
        );
        assert_eq!(
            result.unwrap().lifecycle_intent(),
            expected_lifecycle,
            "intent_class {intent_class:?} should map to {expected_lifecycle:?}"
        );
    }
}
