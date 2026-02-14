//! Instrument lifecycle guardrails for expiry/delist behavior.

use crate::risk::InstrumentState;

/// Intent type for lifecycle gating.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleIntent {
    Open,
    Close,
    Hedge,
    Cancel,
}

/// Input required to evaluate the expiry/delist OPEN guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExpiryGuardInput {
    pub now_ms: u64,
    pub expiration_timestamp_ms: Option<u64>,
    pub expiry_delist_buffer_s: u64,
    pub intent: LifecycleIntent,
}

/// Terminal lifecycle reason recognized by this guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleTerminalReason {
    InstrumentExpiredOrDelisted,
}

/// Result of evaluating lifecycle OPEN gating.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpiryGuardResult {
    Allowed,
    Rejected(LifecycleTerminalReason),
}

/// Venue error kind used by lifecycle classification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VenueLifecycleError {
    InstrumentExpiredOrDelisted,
    Other,
}

/// How a lifecycle error should be handled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleErrorClass {
    Terminal(LifecycleTerminalReason),
    Retryable,
}

/// Scope of reconciliation after lifecycle failure.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReconcileScope {
    InstrumentOnly,
    Global,
}

/// Retry directive for the current instrument.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RetryDirective {
    DoNotRetry,
    RetryAllowed,
}

/// Cancel-specific handling when lifecycle errors occur.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CancelOutcome {
    NotApplicable,
    IdempotentSuccess,
    RetryableFailure,
}

/// Full policy decision for lifecycle error handling.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LifecycleDecision {
    pub class: LifecycleErrorClass,
    pub restart_required: bool,
    pub reconcile_scope: ReconcileScope,
    pub retry: RetryDirective,
    pub instrument_state: InstrumentState,
    pub cancel_outcome: CancelOutcome,
}

/// Reject OPEN intents inside the expiry/delist buffer.
pub fn evaluate_expiry_guard(input: &ExpiryGuardInput) -> ExpiryGuardResult {
    if input.intent != LifecycleIntent::Open {
        return ExpiryGuardResult::Allowed;
    }

    let expiration_ms = match input.expiration_timestamp_ms {
        Some(value) => value,
        None => return ExpiryGuardResult::Allowed,
    };

    let buffer_ms = input.expiry_delist_buffer_s.saturating_mul(1000);
    let opens_blocked_from_ms = expiration_ms.saturating_sub(buffer_ms);
    if input.now_ms >= opens_blocked_from_ms {
        return ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted);
    }

    ExpiryGuardResult::Allowed
}

/// Classify lifecycle errors with fail-closed, non-panicking semantics.
pub fn classify_lifecycle_error(
    intent: LifecycleIntent,
    error: VenueLifecycleError,
) -> LifecycleDecision {
    match error {
        VenueLifecycleError::InstrumentExpiredOrDelisted => LifecycleDecision {
            class: LifecycleErrorClass::Terminal(
                LifecycleTerminalReason::InstrumentExpiredOrDelisted,
            ),
            restart_required: false,
            reconcile_scope: ReconcileScope::InstrumentOnly,
            retry: RetryDirective::DoNotRetry,
            instrument_state: InstrumentState::ExpiredOrDelisted,
            cancel_outcome: if intent == LifecycleIntent::Cancel {
                CancelOutcome::IdempotentSuccess
            } else {
                CancelOutcome::NotApplicable
            },
        },
        VenueLifecycleError::Other => LifecycleDecision {
            class: LifecycleErrorClass::Retryable,
            restart_required: false,
            reconcile_scope: ReconcileScope::Global,
            retry: RetryDirective::RetryAllowed,
            instrument_state: InstrumentState::Active,
            cancel_outcome: if intent == LifecycleIntent::Cancel {
                CancelOutcome::RetryableFailure
            } else {
                CancelOutcome::NotApplicable
            },
        },
    }
}
