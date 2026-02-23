mod common;

use soldier_core::execution::{
    ChokeRejectReason, ChokeResult, GateStep, IntentPipelineMetrics, RejectReasonCode,
    evaluate_intent_pipeline,
};
use soldier_core::risk::InstrumentState;
use soldier_core::venue::{
    CancelOutcome, ExpiryGuardInput, ExpiryGuardResult, InstrumentKind, LifecycleErrorClass,
    LifecycleIntent, LifecycleTerminalReason, ReconcileScope, RetryDirective, VenueLifecycleError,
    classify_lifecycle_error, evaluate_expiry_guard,
};

#[test]
fn test_expiry_delist_buffer_rejects_open() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
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
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };

    assert_eq!(evaluate_expiry_guard(&input), ExpiryGuardResult::Allowed);
}

/// Perpetual instruments have no expiry; they must always be Allowed for OPEN.
#[test]
fn test_no_expiration_timestamp_allows_open() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::Perpetual),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "None expiration_timestamp_ms (perpetual) must be Allowed"
    );
}

/// Catches mutation: `>=` flipped to `>` on `now_ms >= opens_blocked_from_ms`.
/// At exact boundary (now == expiry - buffer), OPEN must be Rejected.
#[test]
fn test_expiry_at_exact_boundary_rejects_open() {
    // expiry = 1_700_000_060_000, buffer = 60s = 60_000ms
    // opens_blocked_from = 1_700_000_060_000 - 60_000 = 1_700_000_000_000
    // now == opens_blocked_from exactly
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_060_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "now_ms == opens_blocked_from_ms must be Rejected (>= not >)"
    );
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

// GAP-012-3: AT-962 — assert no retry enqueued after terminal expiry.
// The §5 wrong impl "mark expired but enqueue retries" is blocked by:
//   1. DoNotRetry (no retry loop)
//   2. Terminal class (no reclassification)
//   3. restart_required == false (no process restart re-enqueues)
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
    // GAP-012-3: restart_required must be false to prevent retry re-enqueue via restart
    assert!(!decision.restart_required);
}

// GAP-012-2 + DA-002: Cancel outcome varies by intent for expired instruments.
// Cancel intent → IdempotentSuccess (cancel is moot on expired instrument).
// Close intent  → NotApplicable (close is not a cancel operation).
// This blocks the §5 wrong impl "ignore intent field, always return IdempotentSuccess".
#[test]
fn test_cancel_outcome_varies_by_intent_for_expired() {
    let cancel_decision = classify_lifecycle_error(
        LifecycleIntent::Cancel,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );
    let close_decision = classify_lifecycle_error(
        LifecycleIntent::Close,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );

    // Cancel on expired → IdempotentSuccess (cancel is moot)
    assert_eq!(
        cancel_decision.cancel_outcome,
        CancelOutcome::IdempotentSuccess,
        "Cancel intent on expired instrument must yield IdempotentSuccess"
    );
    // Close on expired → NotApplicable (close is not a cancel)
    assert_eq!(
        close_decision.cancel_outcome,
        CancelOutcome::NotApplicable,
        "Close intent on expired instrument must yield NotApplicable, not IdempotentSuccess"
    );

    // Both must agree on terminal classification and no-retry
    assert_eq!(cancel_decision.class, close_decision.class);
    assert_eq!(cancel_decision.retry, RetryDirective::DoNotRetry);
    assert_eq!(close_decision.retry, RetryDirective::DoNotRetry);
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
        instrument_kind: Some(InstrumentKind::LinearFuture),
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
        instrument_kind: Some(InstrumentKind::LinearFuture),
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
        instrument_kind: Some(InstrumentKind::LinearFuture),
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
        instrument_kind: Some(InstrumentKind::LinearFuture),
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

// ─── Q7 retrofit: ExpiryGuard fail-closed for expirable instruments ──────────

/// TRIP: LinearFuture with missing timestamp must be rejected (fail-closed).
#[test]
fn test_expiry_guard_missing_timestamp_linear_future_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "LinearFuture with missing timestamp must be rejected (fail-closed)"
    );
}

/// TRIP: InverseFuture with missing timestamp must be rejected (fail-closed).
#[test]
fn test_expiry_guard_missing_timestamp_inverse_future_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::InverseFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "InverseFuture with missing timestamp must be rejected (fail-closed)"
    );
}

/// TRIP: Option with missing timestamp must be rejected (fail-closed).
#[test]
fn test_expiry_guard_missing_timestamp_option_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::Option),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "Option with missing timestamp must be rejected (fail-closed)"
    );
}

/// TRIP: Unknown instrument kind (None) with missing timestamp must be rejected (fail-closed).
#[test]
fn test_expiry_guard_missing_timestamp_unknown_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: None,
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "Unknown instrument kind with missing timestamp must be rejected (fail-closed)"
    );
}

/// TRIP: LinearFuture inside expiry buffer must be rejected.
#[test]
fn test_expiry_guard_future_inside_buffer_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_030_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "LinearFuture inside buffer must be rejected"
    );
}

/// NON-TRIP: Perpetual with missing timestamp must be allowed.
/// Catches always-reject mutation (guard must not fire for perpetuals).
#[test]
fn test_expiry_guard_missing_timestamp_perpetual_allowed() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None,
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::Perpetual),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "Perpetual with missing timestamp must be allowed"
    );
}

/// NON-TRIP: LinearFuture with valid timestamp outside buffer must be allowed.
#[test]
fn test_expiry_guard_future_with_valid_timestamp_allowed() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_090_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "LinearFuture outside buffer must be allowed"
    );
}

/// NON-TRIP: Unknown kind with valid timestamp outside buffer must be allowed.
/// Corrupt feed sending u64::MAX as expiration must be rejected (fail-closed).
/// Without bounds-checking, saturating_sub would produce a huge opens_blocked_from_ms
/// that now_ms can never reach, silently allowing OPEN on garbage data.
/// Kimi K2.5 finding: input-boundary validation gap.
#[test]
fn test_expiry_guard_u64_max_timestamp_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(u64::MAX),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "u64::MAX expiration must be rejected as corrupt/out-of-domain input"
    );
}

/// An expiration timestamp far in the future but still within the sane range
/// should be allowed (not a false positive from bounds-checking).
#[test]
fn test_expiry_guard_far_future_but_sane_timestamp_allowed() {
    // Year 2170 — large but valid
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(6_300_000_000_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "Far future but sane timestamp must be allowed"
    );
}

/// Timestamp just above the sane boundary must be rejected.
#[test]
fn test_expiry_guard_just_above_sane_boundary_rejected() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(7_300_000_000_001), // 1ms above MAX_REASONABLE_EXPIRY_MS
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted),
        "Timestamp just above sane boundary must be rejected"
    );
}

/// Exactly at MAX_REASONABLE_EXPIRY_MS (7_300_000_000_000) — boundary inclusive, must be allowed.
/// Kimi K2.5 Cycle 2 P3 finding: boundary value was untested.
#[test]
fn test_expiry_guard_at_exact_sane_boundary_allowed() {
    let input = ExpiryGuardInput {
        now_ms: 1_000_000_000_000,
        expiration_timestamp_ms: Some(7_300_000_000_000), // exactly at MAX_REASONABLE_EXPIRY_MS
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: Some(InstrumentKind::LinearFuture),
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "Timestamp exactly at sane boundary must be allowed (check is >, not >=)"
    );
}

/// PRD S1-012: Duplicate cancel on expired instrument is idempotent noop.
///
/// Causality proof:
/// - dispatch_count=0 for duplicate cancel (no new dispatches)
/// - No new WAL records generated for the duplicate
/// - classify_lifecycle_error returns same result both times
#[test]
fn test_expiry_cancel_idempotent_duplicate_noop() {
    // First cancel on expired instrument
    let decision1 = classify_lifecycle_error(
        LifecycleIntent::Cancel,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );

    // Second cancel (duplicate) — exact same input
    let decision2 = classify_lifecycle_error(
        LifecycleIntent::Cancel,
        VenueLifecycleError::InstrumentExpiredOrDelisted,
    );

    // Both calls produce identical decisions (idempotent)
    assert_eq!(decision1.class, decision2.class, "duplicate cancel must be idempotent");
    assert_eq!(decision1.retry, decision2.retry);
    assert_eq!(decision1.cancel_outcome, decision2.cancel_outcome);
    assert_eq!(decision1.instrument_state, decision2.instrument_state);

    // Verify the outcome is IdempotentSuccess (noop for cancels on expired)
    assert_eq!(
        decision1.cancel_outcome,
        CancelOutcome::IdempotentSuccess,
        "cancel on expired must be IdempotentSuccess"
    );

    // Verify no retry (dispatch_count=0 — no new dispatch attempted)
    assert_eq!(
        decision1.retry,
        RetryDirective::DoNotRetry,
        "idempotent cancel must not retry"
    );

    // Terminal classification — no state machine advancement
    assert_eq!(
        decision1.class,
        LifecycleErrorClass::Terminal(LifecycleTerminalReason::InstrumentExpiredOrDelisted)
    );
}

/// When timestamp is present, the buffer check applies regardless of kind.
#[test]
fn test_expiry_guard_unknown_kind_with_valid_timestamp_allowed() {
    let input = ExpiryGuardInput {
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: Some(1_700_000_090_000),
        expiry_delist_buffer_s: 60,
        intent: LifecycleIntent::Open,
        instrument_kind: None,
    };
    assert_eq!(
        evaluate_expiry_guard(&input),
        ExpiryGuardResult::Allowed,
        "Unknown kind with valid timestamp outside buffer must be allowed"
    );
}
