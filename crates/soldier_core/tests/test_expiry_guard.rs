//! Acceptance tests for the Expiry Cliff Guard (S1-012).
//!
//! CONTRACT.md §1.0.Y: Instrument lifecycle + expiry safety.
//!
//! Each test isolates the expiry guard as the sole cause of the outcome,
//! proving causality via dispatch count (0 vs 1), specific reject reason,
//! and/or instrument state transitions.
//!
//! AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966.

use soldier_core::risk::{
    ExpiryGuardInput, ExpiryGuardMetrics, ExpiryGuardResult, ExpiryIntentClass, ExpiryRejectReason,
    InstrumentLifecycleState, LifecycleErrorClass, TerminalLifecycleInput, evaluate_expiry_guard,
    handle_terminal_lifecycle_error,
};

// ─── AT-950: Expiry delist buffer rejects OPEN ──────────────────────────
//
// Given: expiration_timestamp_ms = Texp, expiry_delist_buffer_s = 60,
//        now_ms = Texp - 30_000 (within the 60s buffer).
// When:  an OPEN intent for that instrument is evaluated.
// Then:  Rejected(InstrumentExpiredOrDelisted), dispatch count = 0.

#[test]
fn test_expiry_delist_buffer_rejects_open() {
    let t_exp: u64 = 1_700_000_000_000; // arbitrary expiry
    let mut metrics = ExpiryGuardMetrics::new();

    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: t_exp - 30_000, // 30s before expiry, within 60s buffer
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);

    // Verify rejection with correct reason
    assert_eq!(
        result,
        ExpiryGuardResult::Rejected {
            reason: ExpiryRejectReason::InstrumentExpiredOrDelisted,
        },
        "OPEN within delist buffer must be rejected with InstrumentExpiredOrDelisted"
    );

    // Dispatch count = 0 (rejection means no dispatch)
    assert_eq!(metrics.reject_expired(), 1, "exactly one rejection");
    assert_eq!(metrics.allowed_total(), 0, "no dispatch allowed");
}

// ─── AT-965: Outside delist buffer allows OPEN ──────────────────────────
//
// Given: expiration_timestamp_ms = Texp, expiry_delist_buffer_s = 60,
//        now_ms = Texp - 120_000 (2 min before expiry, outside 60s buffer).
//        All other gates pass.
// When:  an OPEN intent for that instrument is evaluated.
// Then:  Allowed, dispatch count = 1, no InstrumentExpiredOrDelisted reject.

#[test]
fn test_expiry_outside_buffer_allows_open() {
    let t_exp: u64 = 1_700_000_000_000;
    let mut metrics = ExpiryGuardMetrics::new();

    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: t_exp - 120_000, // 120s before expiry, outside 60s buffer
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);

    assert_eq!(
        result,
        ExpiryGuardResult::Allowed,
        "OPEN outside delist buffer must be allowed"
    );

    assert_eq!(metrics.allowed_total(), 1, "dispatch count = 1");
    assert_eq!(metrics.reject_expired(), 0, "no expiry rejection");
}

// ─── AT-949: CANCEL on expired instrument with terminal error ───────────
//
// Given: expiration_timestamp_ms = Texp, now_ms = Texp + 1000, CANCEL attempted.
// When:  venue returns terminal lifecycle error (expired/not found).
// Then:  No crash; instrument_state = ExpiredOrDelisted; other instruments
//        continue; cancel treated as idempotently successful.

#[test]
fn test_expiry_cancel_idempotent_success() {
    let mut metrics = ExpiryGuardMetrics::new();

    // Step 1: Verify CANCEL is allowed through the guard even on expired instrument
    let t_exp: u64 = 1_700_000_000_000;
    let guard_input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::CancelOnly,
        now_ms: t_exp + 1_000, // past expiry
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };

    let guard_result = evaluate_expiry_guard(&guard_input, &mut metrics);
    assert_eq!(
        guard_result,
        ExpiryGuardResult::Allowed,
        "CANCEL must be allowed even on expired instrument"
    );

    // Step 2: Terminal error from venue → handle idempotently
    let terminal_input = TerminalLifecycleInput {
        error_class: LifecycleErrorClass::Terminal,
        instrument_id: "BTC-20240101-50000-C".to_string(),
        is_cancel: true,
        has_remaining_positions: false,
    };

    let lifecycle_result = handle_terminal_lifecycle_error(&terminal_input, &mut metrics);

    assert_eq!(
        lifecycle_result.instrument_state,
        InstrumentLifecycleState::ExpiredOrDelisted,
        "terminal error must mark instrument as ExpiredOrDelisted"
    );
    assert!(
        lifecycle_result.cancel_idempotent_success,
        "CANCEL returning terminal error must be treated as idempotently successful"
    );
    assert!(
        !lifecycle_result.should_retry,
        "terminal error must not trigger retry"
    );

    // Metrics confirm
    assert_eq!(metrics.terminal_errors_total(), 1);
    assert_eq!(metrics.cancel_idempotent_total(), 1);
}

// ─── AT-966: Non-terminal cancel does not mark expired ──────────────────
//
// Given: instrument is active (outside delist buffer), a CANCEL intent is
//        handled and venue returns a normal non-terminal response.
// Then:  instrument_state remains Active, NOT marked ExpiredOrDelisted.

#[test]
fn test_expiry_non_terminal_cancel_does_not_mark_expired() {
    let mut metrics = ExpiryGuardMetrics::new();

    let input = TerminalLifecycleInput {
        error_class: LifecycleErrorClass::NonTerminal,
        instrument_id: "BTC-PERPETUAL".to_string(),
        is_cancel: true,
        has_remaining_positions: true,
    };

    let result = handle_terminal_lifecycle_error(&input, &mut metrics);

    assert_eq!(
        result.instrument_state,
        InstrumentLifecycleState::Active,
        "non-terminal error must NOT mark instrument as ExpiredOrDelisted"
    );
    assert!(
        !result.cancel_idempotent_success,
        "non-terminal cancel is not idempotent success"
    );
    assert!(result.should_retry, "non-terminal error may be retried");

    // Terminal metrics should not increment
    assert_eq!(metrics.terminal_errors_total(), 0);
}

// ─── AT-961: Reconcile does not halt other instruments ──────────────────
//
// Given: Instrument A is expired (Texp + 1000), Instrument B is active.
// When:  portfolio reconcile processes both.
// Then:  A marked ExpiredOrDelisted, B continues to be managed. No crash.

#[test]
fn test_expiry_reconcile_does_not_halt_other_instruments() {
    let mut metrics = ExpiryGuardMetrics::new();
    let t_exp: u64 = 1_700_000_000_000;

    // Instrument A: expired
    let guard_a = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: t_exp + 1_000,
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };
    let result_a = evaluate_expiry_guard(&guard_a, &mut metrics);
    assert_eq!(
        result_a,
        ExpiryGuardResult::Rejected {
            reason: ExpiryRejectReason::InstrumentExpiredOrDelisted,
        },
        "expired instrument A must reject OPEN"
    );

    // Terminal error on A — mark as ExpiredOrDelisted
    let terminal_a = TerminalLifecycleInput {
        error_class: LifecycleErrorClass::Terminal,
        instrument_id: "INST-A".to_string(),
        is_cancel: false,
        has_remaining_positions: false,
    };
    let lifecycle_a = handle_terminal_lifecycle_error(&terminal_a, &mut metrics);
    assert_eq!(
        lifecycle_a.instrument_state,
        InstrumentLifecycleState::ExpiredOrDelisted,
    );

    // Instrument B: active, not expired
    let guard_b = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: t_exp + 1_000,
        expiration_timestamp_ms: None, // perpetual, no expiry
        expiry_delist_buffer_s: 60,
    };
    let result_b = evaluate_expiry_guard(&guard_b, &mut metrics);
    assert_eq!(
        result_b,
        ExpiryGuardResult::Allowed,
        "active instrument B must continue to be managed"
    );

    // Verify B is still allowed — no global halt from A's expiry.
    // Only B's OPEN was allowed (A's OPEN was rejected), so allowed_total == 1.
    assert_eq!(
        metrics.allowed_total(),
        1,
        "instrument B must be allowed (1 dispatch)"
    );
}

// ─── AT-960 + AT-962: No retry loop after positions clear ───────────────
//
// Given: instrument A returned Terminal(InstrumentExpiredOrDelisted) at T0.
//        Positions snapshot shows no remaining position for A.
// When:  duplicate CANCEL at T0+1; then reconcile confirms no positions.
// Then:  No extra dispatch, no retry loop. Ledger consistent.

#[test]
fn test_expiry_no_retry_loop_after_positions_clear() {
    let mut metrics = ExpiryGuardMetrics::new();

    // First terminal error on CANCEL → idempotent success
    let first_cancel = TerminalLifecycleInput {
        error_class: LifecycleErrorClass::Terminal,
        instrument_id: "BTC-20240101-50000-C".to_string(),
        is_cancel: true,
        has_remaining_positions: true, // positions existed at first error
    };
    let result_1 = handle_terminal_lifecycle_error(&first_cancel, &mut metrics);
    assert_eq!(
        result_1.instrument_state,
        InstrumentLifecycleState::ExpiredOrDelisted,
    );
    assert!(result_1.cancel_idempotent_success);
    assert!(!result_1.should_retry, "terminal = no retry");

    // Duplicate CANCEL at T0+1 — same terminal error, positions now cleared
    let dup_cancel = TerminalLifecycleInput {
        error_class: LifecycleErrorClass::Terminal,
        instrument_id: "BTC-20240101-50000-C".to_string(),
        is_cancel: true,
        has_remaining_positions: false, // positions cleared
    };
    let result_2 = handle_terminal_lifecycle_error(&dup_cancel, &mut metrics);
    assert_eq!(
        result_2.instrument_state,
        InstrumentLifecycleState::ExpiredOrDelisted,
    );
    assert!(result_2.cancel_idempotent_success);
    assert!(
        !result_2.should_retry,
        "must not retry — positions are cleared and instrument is terminal"
    );

    // Verify: exactly 2 terminal errors handled, 2 idempotent cancels
    assert_eq!(metrics.terminal_errors_total(), 2);
    assert_eq!(metrics.cancel_idempotent_total(), 2);
}

// ─── Additional edge cases ──────────────────────────────────────────────

#[test]
fn test_expiry_no_expiry_configured_always_allows() {
    let mut metrics = ExpiryGuardMetrics::new();

    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: 1_700_000_000_000,
        expiration_timestamp_ms: None, // no expiry (perpetual)
        expiry_delist_buffer_s: 60,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);
    assert_eq!(result, ExpiryGuardResult::Allowed);
    assert_eq!(metrics.allowed_total(), 1);
}

#[test]
fn test_expiry_close_allowed_within_buffer() {
    let t_exp: u64 = 1_700_000_000_000;
    let mut metrics = ExpiryGuardMetrics::new();

    // CLOSE within delist buffer → allowed
    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Close,
        now_ms: t_exp - 10_000, // 10s before expiry, well within 60s buffer
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);
    assert_eq!(
        result,
        ExpiryGuardResult::Allowed,
        "CLOSE must be allowed even within delist buffer"
    );
}

#[test]
fn test_expiry_hedge_allowed_within_buffer() {
    let t_exp: u64 = 1_700_000_000_000;
    let mut metrics = ExpiryGuardMetrics::new();

    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Hedge,
        now_ms: t_exp + 5_000, // past expiry
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: 60,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);
    assert_eq!(
        result,
        ExpiryGuardResult::Allowed,
        "HEDGE must be allowed even past expiry"
    );
}

#[test]
fn test_expiry_exactly_at_buffer_boundary_rejects_open() {
    let t_exp: u64 = 1_700_000_000_000;
    let buffer_s: u64 = 60;
    let threshold_ms = t_exp - (buffer_s * 1000);
    let mut metrics = ExpiryGuardMetrics::new();

    // now_ms == threshold_ms (exactly at boundary) → within buffer → reject
    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: threshold_ms,
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: buffer_s,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);
    assert_eq!(
        result,
        ExpiryGuardResult::Rejected {
            reason: ExpiryRejectReason::InstrumentExpiredOrDelisted,
        },
        "OPEN at exact buffer boundary must be rejected (fail-closed)"
    );
}

#[test]
fn test_expiry_one_ms_before_buffer_allows_open() {
    let t_exp: u64 = 1_700_000_000_000;
    let buffer_s: u64 = 60;
    let threshold_ms = t_exp - (buffer_s * 1000);
    let mut metrics = ExpiryGuardMetrics::new();

    // now_ms == threshold_ms - 1 (just outside buffer) → allowed
    let input = ExpiryGuardInput {
        intent_class: ExpiryIntentClass::Open,
        now_ms: threshold_ms - 1,
        expiration_timestamp_ms: Some(t_exp),
        expiry_delist_buffer_s: buffer_s,
    };

    let result = evaluate_expiry_guard(&input, &mut metrics);
    assert_eq!(
        result,
        ExpiryGuardResult::Allowed,
        "OPEN 1ms outside buffer must be allowed"
    );
}
