//! Instrument lifecycle guardrails for expiry/delist behavior.

use crate::risk::InstrumentState;
use crate::venue::types::InstrumentKind;
use std::sync::atomic::{AtomicU64, Ordering};

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
    /// Instrument kind for lifecycle semantics.
    /// - `Some(Perpetual)` → no expiration needed.
    /// - `Some(Option | LinearFuture | InverseFuture)` → expiration required (fail-closed if missing).
    /// - `None` → unknown instrument → fail-closed (reject OPEN if timestamp missing).
    pub instrument_kind: Option<InstrumentKind>,
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

/// Observability metrics for the expiry guard.
#[derive(Debug)]
pub struct ExpiryGuardMetrics {
    reject_total: u64,
    allowed_total: u64,
}

impl ExpiryGuardMetrics {
    pub fn new() -> Self {
        Self {
            reject_total: 0,
            allowed_total: 0,
        }
    }
    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }
    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }
    pub fn record_reject(&mut self) {
        self.reject_total += 1;
    }
    pub fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }
}

impl Default for ExpiryGuardMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Static counters (3-layer observability) ───────────────────────────

static EXPIRY_GUARD_REJECT_TOTAL: AtomicU64 = AtomicU64::new(0);

fn bump_expiry_guard_reject() {
    EXPIRY_GUARD_REJECT_TOTAL.fetch_add(1, Ordering::Relaxed);
    crate::execution::emit_execution_metric_line(
        crate::execution::METRIC_EXPIRY_GUARD_REJECT,
        "reason=InstrumentExpiredOrDelisted",
    );
    tracing::debug!("ExpiryGuardReject reason=InstrumentExpiredOrDelisted");
}

pub fn expiry_guard_reject_total() -> u64 {
    EXPIRY_GUARD_REJECT_TOTAL.load(Ordering::Relaxed)
}

/// Reject OPEN intents inside the expiry/delist buffer.
///
/// Fail-closed behavior for missing `expiration_timestamp_ms`:
/// - `Perpetual` → Allowed (perpetuals have no expiration)
/// - `Option | LinearFuture | InverseFuture` → Rejected (expiration mandatory)
/// - `None` (unknown kind) → Rejected (fail-closed)
pub fn evaluate_expiry_guard(
    input: &ExpiryGuardInput,
    metrics: &mut ExpiryGuardMetrics,
) -> ExpiryGuardResult {
    if input.intent != LifecycleIntent::Open {
        metrics.record_allowed();
        return ExpiryGuardResult::Allowed;
    }

    let expiration_ms = match input.expiration_timestamp_ms {
        Some(value) => value,
        None => {
            return match input.instrument_kind {
                Some(InstrumentKind::Perpetual) => {
                    tracing::debug!(
                        intent = ?input.intent,
                        "expiry guard: perpetual instrument, no expiry check needed"
                    );
                    metrics.record_allowed();
                    ExpiryGuardResult::Allowed
                }
                Some(kind) => {
                    // Options, futures — expiration is mandatory
                    tracing::warn!(
                        intent = ?input.intent,
                        instrument_kind = ?Some(kind),
                        "expiry guard: missing expiration for expirable instrument, rejecting OPEN (fail-closed)"
                    );
                    metrics.record_reject();
                    bump_expiry_guard_reject();
                    ExpiryGuardResult::Rejected(
                        LifecycleTerminalReason::InstrumentExpiredOrDelisted,
                    )
                }
                None => {
                    // Unknown instrument — fail-closed
                    tracing::warn!(
                        intent = ?input.intent,
                        "expiry guard: unknown instrument kind + missing expiration, rejecting OPEN (fail-closed)"
                    );
                    metrics.record_reject();
                    bump_expiry_guard_reject();
                    ExpiryGuardResult::Rejected(
                        LifecycleTerminalReason::InstrumentExpiredOrDelisted,
                    )
                }
            };
        }
    };

    // Input bounds check: reject unreasonable expiration timestamps.
    // A corrupt feed could send u64::MAX, which would make
    // `opens_blocked_from_ms` enormous and silently allow OPEN.
    // Saturating arithmetic protects computation but not inputs.
    // Bound: year 2200 in milliseconds (~7.3e15). Anything beyond is garbage.
    const MAX_REASONABLE_EXPIRY_MS: u64 = 7_300_000_000_000;
    if expiration_ms > MAX_REASONABLE_EXPIRY_MS {
        tracing::warn!(
            expiration_ms,
            max_reasonable = MAX_REASONABLE_EXPIRY_MS,
            "expiry guard: expiration timestamp beyond sane range, rejecting OPEN (possible data corruption)"
        );
        metrics.record_reject();
        bump_expiry_guard_reject();
        return ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted);
    }

    let buffer_ms = input.expiry_delist_buffer_s.saturating_mul(1000);
    let opens_blocked_from_ms = expiration_ms.saturating_sub(buffer_ms);
    if input.now_ms >= opens_blocked_from_ms {
        tracing::info!(
            now_ms = input.now_ms,
            expiration_ms,
            buffer_ms,
            "expiry guard: rejecting OPEN inside expiry/delist buffer"
        );
        metrics.record_reject();
        bump_expiry_guard_reject();
        return ExpiryGuardResult::Rejected(LifecycleTerminalReason::InstrumentExpiredOrDelisted);
    }

    metrics.record_allowed();
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
