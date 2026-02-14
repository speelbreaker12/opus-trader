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
