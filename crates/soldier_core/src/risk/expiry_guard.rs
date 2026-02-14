//! Expiry Cliff Guard per CONTRACT.md §S1.4.
//!
//! **Purpose:** Prevent new exposure (OPEN intents) on instruments approaching
//! or past their expiration timestamp. CLOSE/HEDGE/CANCEL remain allowed.
//!
//! **Algorithm:**
//! 1. If `expiration_timestamp_ms` is absent → `Allowed` (no expiry configured).
//! 2. Compute `buffer_ms = expiry_delist_buffer_s * 1000`.
//! 3. If `now_ms >= expiration_timestamp_ms - buffer_ms` → instrument is within
//!    delist buffer or already expired.
//! 4. OPEN intents within the buffer → `Rejected(InstrumentExpiredOrDelisted)`.
//! 5. CLOSE/HEDGE/CANCEL → `Allowed` regardless of expiry state.
//!
//! **Terminal lifecycle error handling:**
//! - Terminal errors on expired/delisted instruments are classified as
//!   `Terminal(InstrumentExpiredOrDelisted)` — MUST NOT panic.
//! - CANCEL on expired instrument returning terminal error is idempotently successful.
//! - After positions clear, no retry loop for that instrument.
//! - Other instruments continue unaffected.
//!
//! AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966.

// ─── Intent class ────────────────────────────────────────────────────────

/// Intent classification for the expiry guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpiryIntentClass {
    /// Risk-increasing intent — blocked within delist buffer.
    Open,
    /// Risk-reducing order placement — allowed even near expiry.
    Close,
    /// Hedge intent — allowed even near expiry.
    Hedge,
    /// Cancel-only intent — always allowed.
    CancelOnly,
}

// ─── Guard input ─────────────────────────────────────────────────────────

/// Input to the Expiry Cliff Guard evaluator.
#[derive(Debug, Clone)]
pub struct ExpiryGuardInput {
    /// Intent classification.
    pub intent_class: ExpiryIntentClass,
    /// Current time in milliseconds.
    pub now_ms: u64,
    /// Instrument expiration timestamp in milliseconds, if configured.
    /// `None` means the instrument has no expiry (e.g., perpetual).
    pub expiration_timestamp_ms: Option<u64>,
    /// Buffer in seconds before expiry during which OPEN intents are blocked.
    pub expiry_delist_buffer_s: u64,
}

// ─── Guard result ────────────────────────────────────────────────────────

/// Reject reason from the Expiry Cliff Guard.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpiryRejectReason {
    /// Instrument is expired or within the delist buffer — OPEN blocked.
    InstrumentExpiredOrDelisted,
}

/// Result of the Expiry Cliff Guard evaluation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExpiryGuardResult {
    /// Intent is allowed to proceed.
    Allowed,
    /// Intent is rejected.
    Rejected {
        /// Rejection reason.
        reason: ExpiryRejectReason,
    },
}

// ─── Instrument lifecycle state ──────────────────────────────────────────

/// Lifecycle state for an instrument.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstrumentLifecycleState {
    /// Instrument is active and tradeable.
    Active,
    /// Instrument is expired or delisted — no new exposure allowed.
    ExpiredOrDelisted,
}

// ─── Terminal lifecycle error handling ────────────────────────────────────

/// Classification of a venue lifecycle error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleErrorClass {
    /// Terminal error: instrument is permanently unavailable (expired, delisted,
    /// orderbook closed, not found).
    Terminal,
    /// Non-terminal error: transient failure, may retry.
    NonTerminal,
}

/// Input for terminal lifecycle error handling.
#[derive(Debug, Clone)]
pub struct TerminalLifecycleInput {
    /// The error classification from the venue response.
    pub error_class: LifecycleErrorClass,
    /// The instrument identifier.
    pub instrument_id: String,
    /// Whether this was a CANCEL intent.
    pub is_cancel: bool,
    /// Whether positions remain for this instrument.
    pub has_remaining_positions: bool,
}

/// Result of terminal lifecycle error handling.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerminalLifecycleResult {
    /// Updated instrument lifecycle state.
    pub instrument_state: InstrumentLifecycleState,
    /// Whether the caller should retry this operation.
    pub should_retry: bool,
    /// Whether a CANCEL was treated as idempotently successful.
    pub cancel_idempotent_success: bool,
}

// ─── Metrics ─────────────────────────────────────────────────────────────

/// Observability metrics for the Expiry Cliff Guard.
#[derive(Debug)]
pub struct ExpiryGuardMetrics {
    /// Total intents evaluated.
    checks_total: u64,
    /// Rejections due to instrument expired/delisted.
    reject_expired: u64,
    /// Allowed evaluations.
    allowed_total: u64,
    /// Terminal lifecycle errors handled.
    terminal_errors_total: u64,
    /// Idempotent cancel successes on expired instruments.
    cancel_idempotent_total: u64,
}

impl ExpiryGuardMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            checks_total: 0,
            reject_expired: 0,
            allowed_total: 0,
            terminal_errors_total: 0,
            cancel_idempotent_total: 0,
        }
    }

    pub fn record_check(&mut self) {
        self.checks_total += 1;
    }

    pub fn record_reject_expired(&mut self) {
        self.reject_expired += 1;
    }

    pub fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }

    pub fn record_terminal_error(&mut self) {
        self.terminal_errors_total += 1;
    }

    pub fn record_cancel_idempotent(&mut self) {
        self.cancel_idempotent_total += 1;
    }

    pub fn checks_total(&self) -> u64 {
        self.checks_total
    }

    pub fn reject_expired(&self) -> u64 {
        self.reject_expired
    }

    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }

    pub fn terminal_errors_total(&self) -> u64 {
        self.terminal_errors_total
    }

    pub fn cancel_idempotent_total(&self) -> u64 {
        self.cancel_idempotent_total
    }
}

impl Default for ExpiryGuardMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Guard evaluator ─────────────────────────────────────────────────────

/// Evaluate an intent against the Expiry Cliff Guard.
///
/// CONTRACT.md §S1.4:
/// - If `expiration_timestamp_ms` is present and `now_ms` is within
///   `expiry_delist_buffer_s` of expiry, reject OPEN with
///   `Rejected(InstrumentExpiredOrDelisted)`.
/// - CLOSE/HEDGE/CANCEL remain allowed subject to TradingMode.
///
/// AT-950: OPEN within buffer → rejected.
/// AT-965: OPEN outside buffer → allowed.
pub fn evaluate_expiry_guard(
    input: &ExpiryGuardInput,
    metrics: &mut ExpiryGuardMetrics,
) -> ExpiryGuardResult {
    metrics.record_check();

    // No expiry configured → always allowed (perpetuals, etc.)
    let expiry_ms = match input.expiration_timestamp_ms {
        Some(ts) => ts,
        None => {
            metrics.record_allowed();
            return ExpiryGuardResult::Allowed;
        }
    };

    // CLOSE/HEDGE/CANCEL are always allowed regardless of expiry state
    match input.intent_class {
        ExpiryIntentClass::Close | ExpiryIntentClass::Hedge | ExpiryIntentClass::CancelOnly => {
            metrics.record_allowed();
            return ExpiryGuardResult::Allowed;
        }
        ExpiryIntentClass::Open => {} // continue to expiry check
    }

    // Check if within delist buffer: now_ms >= expiry_ms - buffer_ms
    let buffer_ms = input.expiry_delist_buffer_s.saturating_mul(1000);
    let threshold_ms = expiry_ms.saturating_sub(buffer_ms);

    if input.now_ms >= threshold_ms {
        // Within delist buffer or past expiry — reject OPEN
        metrics.record_reject_expired();
        return ExpiryGuardResult::Rejected {
            reason: ExpiryRejectReason::InstrumentExpiredOrDelisted,
        };
    }

    // Outside delist buffer — OPEN allowed
    metrics.record_allowed();
    ExpiryGuardResult::Allowed
}

// ─── Terminal lifecycle error handler ────────────────────────────────────

/// Handle a terminal lifecycle error for an instrument.
///
/// CONTRACT.md §S1.4:
/// - Terminal errors → classify as `Terminal(InstrumentExpiredOrDelisted)`.
/// - MUST NOT panic. MUST NOT restart process.
/// - Reconcile that instrument only, mark `instrument_state=ExpiredOrDelisted`.
/// - CANCEL returning terminal error → idempotently successful.
/// - Once positions clear, no retry loop for that instrument (AT-962).
/// - Other instruments continue unaffected (AT-961).
///
/// Non-terminal errors leave the instrument state as Active (AT-966).
pub fn handle_terminal_lifecycle_error(
    input: &TerminalLifecycleInput,
    metrics: &mut ExpiryGuardMetrics,
) -> TerminalLifecycleResult {
    match input.error_class {
        LifecycleErrorClass::Terminal => {
            metrics.record_terminal_error();

            let cancel_idempotent_success = input.is_cancel;
            if cancel_idempotent_success {
                metrics.record_cancel_idempotent();
            }

            // AT-962: If no remaining positions, do not retry.
            // AT-949: Mark instrument as ExpiredOrDelisted regardless.
            let should_retry = false; // Terminal = never retry this instrument

            TerminalLifecycleResult {
                instrument_state: InstrumentLifecycleState::ExpiredOrDelisted,
                should_retry,
                cancel_idempotent_success,
            }
        }
        LifecycleErrorClass::NonTerminal => {
            // AT-966: Non-terminal errors do NOT mark instrument as expired.
            TerminalLifecycleResult {
                instrument_state: InstrumentLifecycleState::Active,
                should_retry: true, // non-terminal = may retry
                cancel_idempotent_success: false,
            }
        }
    }
}
