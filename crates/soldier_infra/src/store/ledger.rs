//! Durable Intent Ledger (WAL Truth Source) per CONTRACT.md §2.4.
//!
//! All intents and state transitions are captured as append-only WAL events.
//! On startup, replay reduces the event stream into the latest per-intent view.
//!
//! **Persistence levels:**
//! - `RecordedBeforeDispatch`: intent is enqueued/appended before dispatch.
//! - `DurableBeforeDispatch`: durability barrier (fsync marker) before dispatch.
//!
//! **WAL Writer Isolation (§2.4.1):**
//! - Appends go through a bounded in-memory queue model.
//! - If queue is full → fail-closed for OPEN intents, increment wal_write_errors.
//! - Hot loop MUST NOT block on disk I/O.
//!
//! AT-935, AT-906, AT-233, AT-234.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

// ─── TLSM State ─────────────────────────────────────────────────────────

/// Trade Lifecycle State Machine states per CONTRACT.md §2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TlsState {
    /// Intent created, not yet sent to exchange.
    Created,
    /// Sent to exchange, awaiting ACK.
    Sent,
    /// Exchange acknowledged the order.
    Acked,
    /// Partially filled.
    PartialFill,
    /// Fully filled.
    Filled,
    /// Cancelled (by us or exchange).
    Cancelled,
    /// Rejected by exchange.
    ///
    /// **WAL-only state:** The core TLSM maps `TlsmEvent::Rejected` to
    /// `TlsmState::Failed`, so `map_core_tlsm_state` never produces this
    /// variant. `TlsState::Rejected` can only be set via direct
    /// `update_state()` calls on the WAL, preserving the exchange-level
    /// distinction between rejection and internal failure.
    Rejected,
    /// Failed (internal error).
    Failed,
}

impl TlsState {
    /// Whether this state is terminal (no further transitions expected).
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            TlsState::Filled | TlsState::Cancelled | TlsState::Rejected | TlsState::Failed
        )
    }

    /// Whether `to` is a valid successor state from `self`.
    ///
    /// Valid successors derived from Tlsm::apply() in soldier_core/execution/tlsm.rs — keep in sync.
    /// This is a state-level whitelist (less restrictive than event-based TLSM).
    pub fn is_valid_successor(self, to: TlsState) -> bool {
        match self {
            TlsState::Created => matches!(
                to,
                TlsState::Sent
                    | TlsState::Acked
                    | TlsState::PartialFill
                    | TlsState::Filled
                    | TlsState::Cancelled
                    | TlsState::Rejected
                    | TlsState::Failed
            ),
            TlsState::Sent => matches!(
                to,
                TlsState::Acked
                    | TlsState::PartialFill
                    | TlsState::Filled
                    | TlsState::Cancelled
                    | TlsState::Rejected
                    | TlsState::Failed
            ),
            TlsState::Acked => matches!(
                to,
                TlsState::PartialFill | TlsState::Filled | TlsState::Cancelled | TlsState::Failed
            ),
            TlsState::PartialFill => matches!(
                to,
                TlsState::PartialFill | TlsState::Filled | TlsState::Cancelled | TlsState::Failed
            ),
            // Terminal states: no valid successors
            TlsState::Filled | TlsState::Cancelled | TlsState::Rejected | TlsState::Failed => false,
        }
    }
}

// ─── Intent Record ──────────────────────────────────────────────────────

/// Persisted intent record per CONTRACT.md §2.4.
///
/// **Minimum persisted fields:**
/// intent_hash, group_id, leg_idx, instrument, side, qty, limit_price,
/// tls_state, created_ts, sent_ts, ack_ts, last_fill_ts,
/// exchange_order_id (if known), last_trade_id (if known).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct IntentRecord {
    /// xxhash64 intent hash (hex string).
    pub intent_hash: String,
    /// Group ID for multi-leg orders.
    pub group_id: String,
    /// Leg index within the group.
    pub leg_idx: u32,
    /// Instrument identifier.
    pub instrument: String,
    /// Order side ("buy" or "sell").
    pub side: String,
    /// Quantized quantity.
    pub qty_q: f64,
    /// Quantized limit price.
    pub limit_price_q: f64,
    /// Current TLSM state.
    pub tls_state: TlsState,
    /// Timestamp when the intent was created (ms).
    pub created_ts: u64,
    /// Timestamp when the intent was sent to exchange (ms). 0 if not yet sent.
    pub sent_ts: u64,
    /// Timestamp when the exchange ACK was received (ms). 0 if not yet acked.
    pub ack_ts: u64,
    /// Timestamp of last fill event (ms). 0 if no fills.
    pub last_fill_ts: u64,
    /// Exchange-assigned order ID, if known.
    pub exchange_order_id: Option<String>,
    /// Last trade ID processed for this intent, if known.
    pub last_trade_id: Option<String>,
}

// ─── WAL Event ──────────────────────────────────────────────────────────

/// Append-only WAL event.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum WalEvent {
    IntentRecorded {
        record: IntentRecord,
    },
    StateTransition {
        intent_hash: String,
        new_state: TlsState,
    },
    SentMarked {
        intent_hash: String,
        sent_ts: u64,
    },
}

// ─── Append error ───────────────────────────────────────────────────────

/// Error returned when WAL append fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LedgerAppendError {
    /// Bounded WAL queue is full — hot loop must not block.
    /// CONTRACT.md §2.4.1: "fail-closed for OPEN intents"
    QueueFull,
    /// Generic write failure.
    WriteFailed { reason: String },
    /// Attempted an illegal TLSM state transition.
    IllegalTransition { from: TlsState, to: TlsState },
    /// Duplicate intent_hash — CSP-002 idempotency requires rejection.
    DuplicateIntentHash,
}

impl std::fmt::Display for LedgerAppendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::QueueFull => write!(f, "wal queue full"),
            Self::WriteFailed { reason } => write!(f, "wal write failed: {reason}"),
            Self::IllegalTransition { from, to } => {
                write!(f, "illegal tls transition: {from:?} -> {to:?}")
            }
            Self::DuplicateIntentHash => write!(f, "duplicate intent_hash"),
        }
    }
}

impl std::error::Error for LedgerAppendError {}

// ─── Replay outcome ─────────────────────────────────────────────────────

/// Outcome of replaying the ledger on startup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplayOutcome {
    /// Number of intent records reconstructed.
    pub records_replayed: usize,
    /// Number of in-flight intents (non-terminal state) reconstructed.
    pub in_flight_count: usize,
    /// Intent hashes of in-flight intents (for reconciliation).
    pub in_flight_hashes: Vec<String>,
}

// ─── Metrics ────────────────────────────────────────────────────────────

/// Observability metrics for the WAL ledger.
#[derive(Debug)]
pub struct LedgerMetrics {
    /// `wal_write_errors` counter — increments on any append failure.
    wal_write_errors: u64,
    /// `wal_queue_enqueue_failures` counter.
    wal_queue_enqueue_failures: u64,
    /// Total successful appends.
    appends_total: u64,
}

impl LedgerMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            wal_write_errors: 0,
            wal_queue_enqueue_failures: 0,
            appends_total: 0,
        }
    }

    /// Record a write error.
    pub fn record_write_error(&mut self) {
        self.wal_write_errors += 1;
    }

    /// Record a queue enqueue failure.
    pub fn record_enqueue_failure(&mut self) {
        self.wal_queue_enqueue_failures += 1;
    }

    /// Record a successful append.
    pub fn record_append(&mut self) {
        self.appends_total += 1;
    }

    /// Current value of `wal_write_errors`.
    pub fn wal_write_errors(&self) -> u64 {
        self.wal_write_errors
    }

    /// Current value of `wal_queue_enqueue_failures`.
    pub fn wal_queue_enqueue_failures(&self) -> u64 {
        self.wal_queue_enqueue_failures
    }

    /// Current value of total appends.
    pub fn appends_total(&self) -> u64 {
        self.appends_total
    }
}

impl Default for LedgerMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── WAL Ledger ─────────────────────────────────────────────────────────

/// WAL ledger with append-only events and optional durable JSONL storage path.
///
/// **Invariants:**
/// - Append-only: records are never modified after append.
/// - Bounded queue: capacity enforced, QueueFull on overflow.
/// - RecordedBeforeDispatch: append must succeed before dispatch.
/// - Dedup: duplicate intent_hash is rejected.
///
/// **Threading model:** `WalLedger` is NOT behind a `Mutex` — it relies on
/// exclusive `&mut` borrows enforced by the Rust borrow checker. Single-threaded
/// access only. If multi-threaded access is needed, wrap in a `Mutex`.
///
/// **Known limitations (Phase 1):**
/// - No WAL compaction: JSONL file grows without bound. Production deployments
///   should implement periodic snapshot + truncate.
/// - Capacity counts all intents (including terminal). Long-running processes
///   should drain terminal intents or set capacity high enough.
/// - File I/O is synchronous. The hot-loop non-blocking I/O contract (§2.4.1)
///   is satisfied at the queue abstraction level, not at the file I/O level.
#[derive(Debug)]
pub struct WalLedger {
    /// Reconstructed latest state per intent hash.
    latest_by_hash: HashMap<String, IntentRecord>,
    /// Maximum queue capacity (intent records only).
    capacity: usize,
    /// Optional JSONL storage path (kept for `storage_path()` accessor).
    storage_path_value: Option<PathBuf>,
    /// Open file handle for append-only writes (kept open to avoid per-event reopen).
    storage_file: Option<File>,
}

impl WalLedger {
    /// Create a new in-memory WAL ledger with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            latest_by_hash: HashMap::new(),
            capacity,
            storage_path_value: None,
            storage_file: None,
        }
    }

    /// Create/load a WAL ledger backed by a JSONL file.
    ///
    /// Opens the file once and keeps the handle for the lifetime of the ledger,
    /// avoiding per-event file open/close overhead.
    pub fn with_storage_path(capacity: usize, storage_path: impl AsRef<Path>) -> io::Result<Self> {
        let path = storage_path.as_ref().to_path_buf();
        let events = read_events_from_path(&path)?;
        let latest_by_hash = reduce_events(&events)
            .map_err(|reason| io::Error::new(io::ErrorKind::InvalidData, reason))?;
        if latest_by_hash.len() > capacity {
            let reason = format!(
                "wal contains {} intents but capacity is {}",
                latest_by_hash.len(),
                capacity
            );
            return Err(io::Error::new(io::ErrorKind::InvalidInput, reason));
        }

        let file = OpenOptions::new().create(true).append(true).open(&path)?;

        Ok(Self {
            latest_by_hash,
            capacity,
            storage_path_value: Some(path),
            storage_file: Some(file),
        })
    }

    /// Storage path if this ledger is durable.
    pub fn storage_path(&self) -> Option<&Path> {
        self.storage_path_value.as_deref()
    }

    /// Append an intent record to the ledger (RecordedBeforeDispatch).
    ///
    /// CONTRACT.md §2.4: "Write intent record BEFORE network dispatch."
    /// CONTRACT.md §2.4.1: "If WAL queue is full → fail-closed."
    pub fn append(
        &mut self,
        record: IntentRecord,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if self.latest_by_hash.contains_key(&record.intent_hash) {
            metrics.record_write_error();
            return Err(LedgerAppendError::DuplicateIntentHash);
        }

        if self.latest_by_hash.len() >= self.capacity {
            metrics.record_write_error();
            metrics.record_enqueue_failure();
            return Err(LedgerAppendError::QueueFull);
        }

        let event = WalEvent::IntentRecorded { record };
        self.persist_and_apply(event, metrics)?;
        Ok(())
    }

    /// Update the TLS state for an existing record (TLSM transition append).
    ///
    /// CONTRACT.md §2.4: "Write every TLSM transition immediately."
    pub fn update_state(
        &mut self,
        intent_hash: &str,
        new_state: TlsState,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        let current_state = if let Some(record) = self.latest_by_hash.get(intent_hash) {
            record.tls_state
        } else {
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: format!("intent_hash not found: {intent_hash}"),
            });
        };

        if !current_state.is_valid_successor(new_state) {
            metrics.record_write_error();
            return Err(LedgerAppendError::IllegalTransition {
                from: current_state,
                to: new_state,
            });
        }

        let event = WalEvent::StateTransition {
            intent_hash: intent_hash.to_string(),
            new_state,
        };
        self.persist_and_apply(event, metrics)?;
        Ok(())
    }

    /// Mark an intent as sent at `sent_ts`.
    ///
    /// This is a **WAL-level operation** that intentionally operates outside
    /// the core TLSM state machine's `is_valid_successor` checks. It handles
    /// the common case where `sent_ts` needs to be recorded even when the
    /// TLSM has already advanced past `Created` (e.g., fill-before-ack).
    ///
    /// Behavior:
    /// - `Created` → transitions to `Sent` and records `sent_ts`.
    /// - Non-terminal, non-Created → only updates `sent_ts` (no state change).
    /// - Terminal → rejected with `IllegalTransition`.
    pub fn mark_sent(
        &mut self,
        intent_hash: &str,
        sent_ts: u64,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        let current_state = if let Some(record) = self.latest_by_hash.get(intent_hash) {
            record.tls_state
        } else {
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: format!("intent_hash not found: {intent_hash}"),
            });
        };

        // Reject mark_sent on terminal states — no further mutations allowed.
        if current_state.is_terminal() {
            metrics.record_write_error();
            return Err(LedgerAppendError::IllegalTransition {
                from: current_state,
                to: TlsState::Sent,
            });
        }

        let event = WalEvent::SentMarked {
            intent_hash: intent_hash.to_string(),
            sent_ts,
        };
        self.persist_and_apply(event, metrics)?;
        Ok(())
    }

    /// Replay the ledger on startup — reconstruct in-memory state.
    ///
    /// CONTRACT.md §2.4: "On startup, replay ledger into in-memory state
    /// and reconcile with exchange."
    pub fn replay(&self) -> ReplayOutcome {
        let mut in_flight_hashes = Vec::new();
        for record in self.latest_by_hash.values() {
            if !record.tls_state.is_terminal() {
                in_flight_hashes.push(record.intent_hash.clone());
            }
        }

        ReplayOutcome {
            records_replayed: self.latest_by_hash.len(),
            in_flight_count: in_flight_hashes.len(),
            in_flight_hashes,
        }
    }

    /// Look up an intent by its hash.
    pub fn get(&self, intent_hash: &str) -> Option<&IntentRecord> {
        self.latest_by_hash.get(intent_hash)
    }

    /// Current queue depth (unique intents).
    pub fn queue_depth(&self) -> usize {
        self.latest_by_hash.len()
    }

    /// Queue capacity.
    pub fn queue_capacity(&self) -> usize {
        self.capacity
    }

    /// Whether the record for this intent_hash indicates it was already sent.
    ///
    /// Used during replay to prevent resending (AT-233).
    pub fn was_sent(&self, intent_hash: &str) -> bool {
        self.get(intent_hash)
            .map(|r| r.sent_ts > 0 || r.tls_state != TlsState::Created)
            .unwrap_or(false)
    }

    /// Persist a WAL event to disk (if durable), then apply to in-memory state.
    ///
    /// **Invariant:** Callers (`append`, `update_state`, `mark_sent`) MUST
    /// pre-validate that `apply_event` will succeed before calling this method.
    /// Specifically:
    /// - `append` creates an `IntentRecorded` event → `apply_event` does a
    ///   HashMap::insert which is infallible.
    /// - `update_state` and `mark_sent` verify the intent_hash exists in
    ///   `latest_by_hash` before calling → the `.ok_or_else()` in `apply_event`
    ///   cannot fail.
    ///
    /// **Convergence property:** If `apply_event` were to fail after a
    /// successful disk write, the JSONL file would be ahead of in-memory state.
    /// On restart, `with_storage_path` replays the full event log, converging
    /// in-memory state to match the disk. The disk is the source of truth.
    fn persist_and_apply(
        &mut self,
        event: WalEvent,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if let Some(file) = &mut self.storage_file {
            write_event_to_file(file, &event).map_err(|reason| {
                metrics.record_write_error();
                LedgerAppendError::WriteFailed { reason }
            })?;
        }

        // Safety: callers pre-validate that the intent_hash exists (for
        // StateTransition/SentMarked) or create a new entry (IntentRecorded).
        // apply_event should never fail here. If it does, the disk is ahead
        // of memory — restart will converge via replay.
        let apply_result = apply_event(&mut self.latest_by_hash, &event);
        debug_assert!(
            apply_result.is_ok(),
            "apply_event failed after successful persist — callers must pre-validate: {:?}",
            apply_result
        );
        apply_result.map_err(|reason| {
            metrics.record_write_error();
            LedgerAppendError::WriteFailed { reason }
        })?;

        metrics.record_append();
        Ok(())
    }
}

// ─── LedgerTransitionSink ───────────────────────────────────────────────

/// Adapter that routes core TLSM transitions into this ledger.
pub struct LedgerTransitionSink<'a> {
    ledger: &'a mut WalLedger,
    metrics: &'a mut LedgerMetrics,
    intent_hash: String,
}

impl<'a> LedgerTransitionSink<'a> {
    pub fn new(
        ledger: &'a mut WalLedger,
        metrics: &'a mut LedgerMetrics,
        intent_hash: impl Into<String>,
    ) -> Self {
        Self {
            ledger,
            metrics,
            intent_hash: intent_hash.into(),
        }
    }
}

impl soldier_core::execution::TlsmTransitionSink for LedgerTransitionSink<'_> {
    fn append_transition(
        &mut self,
        transition: soldier_core::execution::PersistedTransition,
    ) -> Result<(), String> {
        // Cross-check: verify the TLSM's view of the current state matches
        // the ledger's current state for this intent. The ledger is the source
        // of truth, but divergence indicates a bug in the calling code.
        if let Some(record) = self.ledger.get(&self.intent_hash) {
            let expected_from = map_core_tlsm_state(transition.from);
            debug_assert_eq!(
                record.tls_state, expected_from,
                "TLSM/ledger state divergence for {}: ledger={:?}, tlsm.from={:?}",
                self.intent_hash, record.tls_state, expected_from
            );
        }

        let mapped_state = map_core_tlsm_state(transition.to);
        self.ledger
            .update_state(&self.intent_hash, mapped_state, self.metrics)
            .map_err(|e| e.to_string())
    }
}

fn map_core_tlsm_state(state: soldier_core::execution::TlsmState) -> TlsState {
    match state {
        soldier_core::execution::TlsmState::Created => TlsState::Created,
        soldier_core::execution::TlsmState::Sent => TlsState::Sent,
        soldier_core::execution::TlsmState::Acked => TlsState::Acked,
        soldier_core::execution::TlsmState::PartiallyFilled => TlsState::PartialFill,
        soldier_core::execution::TlsmState::Filled => TlsState::Filled,
        soldier_core::execution::TlsmState::Cancelled => TlsState::Cancelled,
        soldier_core::execution::TlsmState::Failed => TlsState::Failed,
    }
}

// ─── Event helpers ──────────────────────────────────────────────────────

fn apply_event(
    latest_by_hash: &mut HashMap<String, IntentRecord>,
    event: &WalEvent,
) -> Result<(), String> {
    match event {
        WalEvent::IntentRecorded { record } => {
            latest_by_hash.insert(record.intent_hash.clone(), record.clone());
            Ok(())
        }
        WalEvent::StateTransition {
            intent_hash,
            new_state,
        } => {
            let record = latest_by_hash
                .get_mut(intent_hash)
                .ok_or_else(|| format!("transition missing intent_hash: {intent_hash}"))?;
            record.tls_state = *new_state;
            Ok(())
        }
        WalEvent::SentMarked {
            intent_hash,
            sent_ts,
        } => {
            let record = latest_by_hash
                .get_mut(intent_hash)
                .ok_or_else(|| format!("sent marker missing intent_hash: {intent_hash}"))?;
            record.sent_ts = record.sent_ts.max(*sent_ts);
            if record.tls_state == TlsState::Created {
                record.tls_state = TlsState::Sent;
            }
            Ok(())
        }
    }
}

fn reduce_events(events: &[WalEvent]) -> Result<HashMap<String, IntentRecord>, String> {
    let mut latest_by_hash = HashMap::new();
    for event in events {
        apply_event(&mut latest_by_hash, event)?;
    }
    Ok(latest_by_hash)
}

/// Write a WAL event to an already-open file handle.
///
/// **Note:** `sync_all()` is called unconditionally. The
/// `WalBarrierConfig::require_wal_fsync_before_dispatch` flag in `wal.rs`
/// controls an *additional* barrier point after enqueue. Since `sync_all()`
/// is already called here, the barrier flag currently only adds timing
/// measurement. This is a Phase 1 simplification — a production async WAL
/// writer would decouple enqueue from fsync.
fn write_event_to_file(file: &mut File, event: &WalEvent) -> Result<(), String> {
    let mut line =
        serde_json::to_string(event).map_err(|e| format!("failed to encode wal event: {e}"))?;
    line.push('\n');
    file.write_all(line.as_bytes())
        .map_err(|e| format!("failed to write wal event: {e}"))?;
    file.sync_all()
        .map_err(|e| format!("failed to sync wal: {e}"))
}

fn read_events_from_path(path: &Path) -> io::Result<Vec<WalEvent>> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(path)?;
    let reader = BufReader::new(file);

    let mut events = Vec::new();
    let lines: Vec<_> = reader.lines().collect::<io::Result<_>>()?;
    let total = lines.len();
    for (index, line) in lines.into_iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<WalEvent>(trimmed) {
            Ok(event) => events.push(event),
            Err(e) => {
                // Tolerate a malformed final line — expected after a crash
                // during write. All earlier lines must be valid.
                if index + 1 == total {
                    eprintln!(
                        "WARNING: skipping malformed trailing wal line {} in {}: {e}",
                        index + 1,
                        path.display()
                    );
                } else {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!(
                            "invalid wal event at line {} in {}: {e}",
                            index + 1,
                            path.display()
                        ),
                    ));
                }
            }
        }
    }

    Ok(events)
}
