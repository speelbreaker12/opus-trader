mod common;

use soldier_core::execution::{
    ChokeRejectReason, ChokeResult, GateStep, IntentPipelineMetrics, RejectReasonCode,
    evaluate_intent_pipeline,
};
use soldier_core::risk::InstrumentState;
use soldier_core::venue::{
    CancelOutcome, ExpiryGuardInput, ExpiryGuardResult, LifecycleErrorClass, LifecycleIntent,
    LifecycleTerminalReason, ReconcileScope, RetryDirective, VenueLifecycleError,
    classify_lifecycle_error, evaluate_expiry_guard,
};

#[test]
fn test_expiry_delist_buffer_rejects_open() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
    };

    let result = evaluate_expiry_guard(&input);
    assert_eq!(
        result,
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted)
    );
}

#[test]
fn test_expiry_outside_buffer_allows_open() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_090_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
    };

    assert_eq!(evaluate_expiry_guard(&input), ExpiryGuardResult::Allowed);
}

#[test]
fn test_expiry_cancel_idempotent_success() {
    let decision = classify_lifecycle_error(
        LifecycleIntent::Cancel,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );

    assert_eq!(
        decision.class,
        LifecycleErrorClass::Terminal(LifecycleTerminalReason::InstrumentExpiredOrDelisted)
    );
    assert_eq!(decision.retry, RetryDirective::DoNotRetry);
    assert_eq!(decision.cancel_outcome, CancelOutcome::IdempotentSuccess);
    assert_eq!(
        decision.instrument_state,
        InstrumentState::ExpiredOrDelisted
    );
}

#[test]
fn test_expiry_non_terminal_cancel_does_not_mark_expired() {
    let decision = classify_lifecycle_error(LifecycleIntent::Cancel, VenueLifecycleError::Other);

    assert_eq!(decision.class, LifecycleErrorClass::Retryable);
    assert_eq!(decision.retry, RetryDirective::RetryAllowed);
    assert_eq!(decision.cancel_outcome, CancelOutcome::RetryableFailure);
    assert_eq!(decision.instrument_state, InstrumentState::Active);
}

#[test]
fn test_expiry_reconcile_does_not_halt_other_instruments() {
    let instrument_a = classify_lifecycle_error(
        LifecycleIntent::Close,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );
    let instrument_b = classify_lifecycle_error(LifecycleIntent::Close, VenueLifecycleError::Other);

    assert_eq!(instrument_a.reconcile_scope, ReconcileScope::InstrumentOnly);
    assert_eq!(
        instrument_a.instrument_state,
        InstrumentState::ExpiredOrDelisted
    );

    assert_eq!(instrument_b.class, LifecycleErrorClass::Retryable);
    assert_eq!(instrument_b.instrument_state, InstrumentState::Active);
}

#[test]
fn test_expiry_no_retry_loop_after_positions_clear() {
    let decision = classify_lifecycle_error(
        LifecycleIntent::Close,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );

    assert_eq!(
        decision.class,
        LifecycleErrorClass::Terminal(LifecycleTerminalReason::InstrumentExpiredOrDelisted)
    );
    assert_eq!(decision.retry, RetryDirective::DoNotRetry);
    assert!(!decision.restart_required);
}

// ─── Pipeline integration tests: ExpiryGuard wired into chokepoint ──────────

/// AT-950: OPEN intent rejected when now_ms is within delist buffer.
///
/// Proves the guard is the *sole* reason for rejection:
/// - All other gates pass (via base_open_input)
/// - Reject reason is GateStep::ExpiryGuard
/// - Reject reason code is InstrumentExpiredOrDelisted
#[test]
fn test_at950_pipeline_rejects_open_within_expiry_buffer() {
    let mut input = common::base_open_input();
    // Put now_ms within the delist buffer (30s before expiry, 60s buffer)
    input.expiry_guard = Some(ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
    });

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    // Must be rejected
    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            // Gate trace must end at ExpiryGuard
            assert_eq!(
                gate_trace.last(),
                Some(&GateStep::ExpiryGuard),
                "reject must occur at ExpiryGuard gate"
            );
            // Reject reason must name ExpiryGuard
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::ExpiryGuard,
                        ..
                    }
                ),
                "reject reason must be ExpiryGuard, got {reason:?}"
            );
            // No OPEN-only gates should have run
            assert!(!gate_trace.contains(&GateStep::LiquidityGate));
            assert!(!gate_trace.contains(&GateStep::NetEdgeGate));
            assert!(!gate_trace.contains(&GateStep::Pricer));
        }
        other => panic!("expected Rejected, got {other:?}"),
    }

    // Reject reason code must be InstrumentExpiredOrDelisted
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::InstrumentExpiredOrDelisted)
    );
}

/// AT-965: OPEN intent allowed when now_ms is outside delist buffer.
#[test]
fn test_at965_pipeline_allows_open_outside_expiry_buffer() {
    let mut input = common::base_open_input();
    // Put now_ms well outside the delist buffer (90s before expiry, 60s buffer)
    input.expiry_guard = Some(ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_090_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
    });

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "OPEN outside buffer must be approved, got {:?}",
        result.decision
    );
    assert_eq!(result.reject_reason_code, None);
}

/// CLOSE/HEDGE intents pass through even when instrument is expired.
///
/// The evaluate_expiry_guard function returns Allowed for non-Open intents,
/// so CLOSE/HEDGE are never blocked by expiry.
#[test]
fn test_pipeline_close_passes_through_expired_instrument() {
    let mut input = common::base_open_input();
    input.intent_class = soldier_core::execution::ChokeIntentClass::Close;
    // now_ms within buffer (would reject OPEN)
    input.expiry_guard = Some(ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Close,
    });

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "CLOSE must pass through even with expired instrument, got {:?}",
        result.decision
    );
}

/// Fail-closed: OPEN intent rejected when expiry_guard input is None.
///
/// Missing expiry data for an OPEN intent must fail-closed (reject),
/// not fail-open (allow).
#[test]
fn test_pipeline_open_rejected_when_expiry_input_none() {
    let mut input = common::base_open_input();
    input.expiry_guard = None; // Missing expiry data

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    match result.decision {
        ChokeResult::Rejected { reason, gate_trace } => {
            assert_eq!(
                gate_trace.last(),
                Some(&GateStep::ExpiryGuard),
                "reject must occur at ExpiryGuard gate"
            );
            assert!(
                matches!(
                    reason,
                    ChokeRejectReason::GateRejected {
                        gate: GateStep::ExpiryGuard,
                        ..
                    }
                ),
                "reject reason must be ExpiryGuard, got {reason:?}"
            );
        }
        other => panic!("expected Rejected for OPEN with None expiry, got {other:?}"),
    }

    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::InstrumentExpiredOrDelisted)
    );
}

/// Regression: intent_class=Close with expiry_guard.intent=Open must still be
/// approved. The pipeline derives LifecycleIntent from intent_class, overriding
/// the caller-provided ExpiryGuardInput.intent. Without this override, the guard
/// would incorrectly reject CLOSE/HEDGE intents when the input drifts.
#[test]
fn test_intent_drift_close_with_open_expiry_input_allowed() {
    let mut input = common::base_open_input();
    input.intent_class = soldier_core::execution::ChokeIntentClass::Close;
    // Deliberately set expiry input to Open — simulates caller drift
    input.expiry_guard = Some(ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000), // within buffer
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open, // WRONG — but pipeline must override
    });

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "CLOSE must be approved even when ExpiryGuardInput.intent drifts to Open, got {:?}",
        result.decision
    );
    assert_eq!(result.reject_reason_code, None);
}

/// CLOSE intent with None expiry input is allowed (fail-closed only applies to OPEN).
#[test]
fn test_pipeline_close_allowed_when_expiry_input_none() {
    let mut input = common::base_open_input();
    input.intent_class = soldier_core::execution::ChokeIntentClass::Close;
    input.expiry_guard = None;

    let mut metrics = IntentPipelineMetrics::new();
    let result = evaluate_intent_pipeline(&input, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "CLOSE with None expiry must be allowed, got {:?}",
        result.decision
    );
}
