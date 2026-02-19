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
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, mpsc};
use std::thread;
use std::time::Duration;

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

// ─── WAL Writer Config ──────────────────────────────────────────────────

/// Configuration for the async WAL writer thread.
#[derive(Debug, Clone)]
pub struct WalWriterConfig {
    /// Bounded channel capacity for the writer thread.
    /// Larger = more burst tolerance but wider state-transition-loss window on crash.
    pub channel_capacity: usize,
    /// Maximum time to wait for the writer thread to confirm fsync on barrier
    /// appends (OPEN intents). If exceeded, append returns `WriteFailed`.
    /// Default: 5 seconds. Typical SSD fsync: 0.2-2ms; this is deliberately
    /// conservative to avoid false failures under load.
    pub barrier_timeout: Duration,
}

impl Default for WalWriterConfig {
    fn default() -> Self {
        Self {
            channel_capacity: 1024,
            barrier_timeout: Duration::from_secs(5),
        }
    }
}

/// Internal message sent to the WAL writer thread.
enum WalWrite {
    Event {
        serialized: String,
        barrier: Option<mpsc::Sender<Result<(), String>>>,
    },
    Shutdown,
}

impl std::fmt::Debug for WalWrite {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Event {
                serialized,
                barrier,
            } => f
                .debug_struct("Event")
                .field("serialized_len", &serialized.len())
                .field("has_barrier", &barrier.is_some())
                .finish(),
            Self::Shutdown => write!(f, "Shutdown"),
        }
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
/// **Async Writer (§2.4.1):**
/// When backed by durable storage, a dedicated writer thread handles disk I/O.
/// `append()` waits for fsync confirmation (barrier) to preserve AT-935 durability.
/// `update_state()`/`mark_sent()` are non-blocking (no barrier) — state
/// transitions are recoverable via exchange reconciliation.
///
/// **Known limitations:**
/// - No WAL compaction: JSONL file grows without bound.
/// - Capacity counts all intents (including terminal).
pub struct WalLedger {
    /// Reconstructed latest state per intent hash.
    latest_by_hash: HashMap<String, IntentRecord>,
    /// Maximum queue capacity (intent records only).
    capacity: usize,
    /// Optional JSONL storage path (kept for `storage_path()` accessor).
    storage_path_value: Option<PathBuf>,
    /// Sender to the writer thread (replaces `storage_file` for durable ledgers).
    writer_tx: Option<mpsc::SyncSender<WalWrite>>,
    /// Writer thread handle (for graceful shutdown).
    writer_handle: Option<thread::JoinHandle<()>>,
    /// Pause flag: when true, writer thread sleeps between events.
    writer_paused: Arc<AtomicBool>,
    /// Degraded flag: set on disk write failure, blocks subsequent barrier appends.
    /// Uses `Relaxed` ordering — acceptable because:
    /// 1. The flag is monotonic (only false→true, never cleared).
    /// 2. The writer thread sets it after a disk error; the dispatch thread reads it
    ///    before the next `persist_and_apply`. A stale `false` read means one extra
    ///    attempt that will also fail and set the flag, so convergence is guaranteed.
    /// 3. `Acquire/Release` would add unnecessary overhead on the hot path for a
    ///    flag that is only set on an already-catastrophic I/O failure.
    writer_degraded: Arc<AtomicBool>,
    /// Shared write error counter between caller and writer threads.
    wal_write_errors: Arc<AtomicU64>,
    /// Barrier timeout for durable appends (OPEN intents).
    barrier_timeout: Duration,
}

impl std::fmt::Debug for WalLedger {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WalLedger")
            .field("capacity", &self.capacity)
            .field("queue_depth", &self.latest_by_hash.len())
            .field("storage_path", &self.storage_path_value)
            .field("has_writer", &self.writer_tx.is_some())
            .field(
                "writer_degraded",
                &self.writer_degraded.load(Ordering::Relaxed),
            )
            .field("barrier_timeout", &self.barrier_timeout)
            .field(
                "wal_write_errors",
                &self.wal_write_errors.load(Ordering::Relaxed),
            )
            .finish()
    }
}

impl WalLedger {
    /// Create a new in-memory WAL ledger with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            latest_by_hash: HashMap::new(),
            capacity,
            storage_path_value: None,
            writer_tx: None,
            writer_handle: None,
            writer_paused: Arc::new(AtomicBool::new(false)),
            writer_degraded: Arc::new(AtomicBool::new(false)),
            wal_write_errors: Arc::new(AtomicU64::new(0)),
            barrier_timeout: Duration::from_secs(5),
        }
    }

    /// Create/load a WAL ledger backed by a JSONL file with default writer config.
    pub fn with_storage_path(capacity: usize, storage_path: impl AsRef<Path>) -> io::Result<Self> {
        Self::with_storage_path_configured(capacity, storage_path, WalWriterConfig::default())
    }

    /// Create/load a WAL ledger backed by a JSONL file with custom writer config.
    ///
    /// Spawns a dedicated writer thread that owns the file handle and performs
    /// all disk I/O. The writer thread fsyncs (sync_data) per event.
    pub fn with_storage_path_configured(
        capacity: usize,
        storage_path: impl AsRef<Path>,
        config: WalWriterConfig,
    ) -> io::Result<Self> {
        if config.channel_capacity == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "WalWriterConfig.channel_capacity must be >= 1 (0 creates a rendezvous channel that serializes all writes)",
            ));
        }

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
        // Flush the directory entry once at file creation so that
        // subsequent appends only need sync_data() (metadata already stable).
        file.sync_all()?;

        let writer_degraded = Arc::new(AtomicBool::new(false));
        let writer_paused = Arc::new(AtomicBool::new(false));
        let wal_write_errors = Arc::new(AtomicU64::new(0));

        let barrier_timeout = config.barrier_timeout;
        let (tx, rx) = mpsc::sync_channel(config.channel_capacity);

        let degraded_clone = writer_degraded.clone();
        let paused_clone = writer_paused.clone();
        let errors_clone = wal_write_errors.clone();

        let handle = thread::Builder::new()
            .name("wal-writer".into())
            .spawn(move || {
                writer_loop(rx, file, errors_clone, paused_clone, degraded_clone);
            })
            .map_err(|e| io::Error::other(format!("failed to spawn wal writer: {e}")))?;

        Ok(Self {
            latest_by_hash,
            capacity,
            storage_path_value: Some(path),
            writer_tx: Some(tx),
            writer_handle: Some(handle),
            writer_paused,
            writer_degraded,
            wal_write_errors,
            barrier_timeout,
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
        // OPEN intents require durable persistence (barrier) before dispatch.
        self.persist_and_apply(event, metrics, true)?;
        Ok(())
    }

    /// Update the TLS state for an existing record (TLSM transition append).
    ///
    /// CONTRACT.md §2.4: "Write every TLSM transition immediately."
    /// State transitions are async (no barrier) — recoverable via reconciliation.
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
        // State transitions are async — no barrier needed.
        self.persist_and_apply(event, metrics, false)?;
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
        // mark_sent is async — no barrier needed.
        self.persist_and_apply(event, metrics, false)?;
        Ok(())
    }

    /// Replay the ledger on startup — reconstruct in-memory state.
    ///
    /// CONTRACT.md §2.4: "On startup, replay ledger into in-memory state
    /// and reconcile with exchange."
    ///
    /// **Phantom intent handling:** If a barrier timeout occurred before
    /// shutdown, the enqueued event may have been written to disk by the
    /// writer thread. On restart, replay will reconstruct this "phantom"
    /// intent in `Created` state. Callers MUST reconcile `in_flight_hashes`
    /// against the exchange to determine whether these intents were
    /// dispatched. Un-dispatched phantom intents should be cancelled.
    ///
    /// **Replay vs live dedup asymmetry:** During replay, `apply_event`
    /// uses last-writer-wins for `IntentRecorded` events (tolerates
    /// duplicates from crash-replay). During live operation, `append()`
    /// rejects duplicate `intent_hash` with `DuplicateIntentHash`. This
    /// asymmetry is intentional — live dedup prevents double-dispatch
    /// (CSP-002), while replay dedup handles crash artifacts.
    pub fn replay(&self) -> ReplayOutcome {
        let mut in_flight_hashes: Vec<_> = self
            .latest_by_hash
            .values()
            .filter(|r| !r.tls_state.is_terminal())
            .map(|r| r.intent_hash.clone())
            .collect();
        // Deterministic ordering independent of HashMap iteration order.
        in_flight_hashes.sort();

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

    /// Pause the WAL writer thread (for testing / controlled shutdown).
    #[doc(hidden)]
    pub fn pause_writer(&self) {
        self.writer_paused.store(true, Ordering::Relaxed);
    }

    /// Resume the WAL writer thread.
    #[doc(hidden)]
    pub fn resume_writer(&self) {
        self.writer_paused.store(false, Ordering::Relaxed);
    }

    /// Whether the writer thread has entered degraded mode (disk write failure).
    pub fn is_writer_degraded(&self) -> bool {
        self.writer_degraded.load(Ordering::Relaxed)
    }

    /// Shared write error counter (readable from any thread).
    pub fn wal_write_errors_shared(&self) -> u64 {
        self.wal_write_errors.load(Ordering::Relaxed)
    }

    /// Force-set the degraded flag (for testing fail-closed behavior).
    #[doc(hidden)]
    pub fn force_set_degraded(&self, degraded: bool) {
        self.writer_degraded.store(degraded, Ordering::Relaxed);
    }

    /// Shut down the writer thread and disconnect the channel.
    /// Subsequent writes will get `WriteFailed("wal writer thread died")`.
    #[doc(hidden)]
    pub fn kill_writer(&mut self) {
        self.writer_paused.store(false, Ordering::Relaxed);
        if let Some(tx) = self.writer_tx.take() {
            let _ = tx.send(WalWrite::Shutdown);
        }
        if let Some(handle) = self.writer_handle.take() {
            let _ = handle.join();
        }
    }

    /// Persist a WAL event to disk (if durable), then apply to in-memory state.
    ///
    /// **Barrier semantics:**
    /// - `need_barrier=true` (used by `append`): dispatch thread blocks until
    ///   the writer thread confirms fsync. Preserves AT-935 durability for
    ///   OPEN intents.
    /// - `need_barrier=false` (used by `update_state`/`mark_sent`): event is
    ///   enqueued without waiting. HashMap may be ahead of disk — acceptable
    ///   because state transitions are recoverable via exchange reconciliation.
    ///
    /// **In-memory mode:** When no writer thread exists (no durable storage),
    /// events are applied directly to the HashMap without disk I/O.
    ///
    /// **Convergence property:** On restart, `with_storage_path` replays the
    /// full event log from disk, converging in-memory state. Disk is truth.
    fn persist_and_apply(
        &mut self,
        event: WalEvent,
        metrics: &mut LedgerMetrics,
        need_barrier: bool,
    ) -> Result<(), LedgerAppendError> {
        // Detect dead writer: durable storage configured but writer channel gone.
        // This means the writer thread was killed or panicked after construction.
        if self.storage_path_value.is_some() && self.writer_tx.is_none() {
            self.wal_write_errors.fetch_add(1, Ordering::Relaxed);
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: "wal writer channel already closed (kill_writer or prior disconnect)"
                    .into(),
            });
        }

        if let Some(writer_tx) = &self.writer_tx {
            // Check degraded flag.
            // - Barrier path (OPEN intents): fail-closed — cannot guarantee durability.
            // - Non-barrier path (state transitions): skip channel, apply to HashMap
            //   only. State transitions are recoverable via reconciliation, and
            //   blocking them when degraded would prevent in-memory tracking of
            //   in-flight intents that already have orders on the exchange.
            if self.writer_degraded.load(Ordering::Relaxed) {
                if need_barrier {
                    metrics.record_write_error();
                    return Err(LedgerAppendError::WriteFailed {
                        reason: "wal writer degraded".into(),
                    });
                }
                // Non-barrier: skip channel, fall through to HashMap apply.
            } else {
                let serialized = serde_json::to_string(&event).map_err(|e| {
                    metrics.record_write_error();
                    LedgerAppendError::WriteFailed {
                        reason: e.to_string(),
                    }
                })?;

                // Build barrier channel if needed — destructure to avoid clone.
                let (barrier_tx, barrier_rx) = if need_barrier {
                    let (tx, rx) = mpsc::channel();
                    (Some(tx), Some(rx))
                } else {
                    (None, None)
                };

                match writer_tx.try_send(WalWrite::Event {
                    serialized,
                    barrier: barrier_tx,
                }) {
                    Ok(()) => {}
                    Err(mpsc::TrySendError::Full(_)) => {
                        self.wal_write_errors.fetch_add(1, Ordering::Relaxed);
                        metrics.record_write_error();
                        metrics.record_enqueue_failure();
                        if need_barrier {
                            return Err(LedgerAppendError::QueueFull);
                        }
                        // Non-barrier QueueFull: skip channel, fall through to
                        // HashMap-only apply. Consistent with degraded behavior —
                        // state transitions are recoverable via reconciliation.
                    }
                    Err(mpsc::TrySendError::Disconnected(_)) => {
                        self.wal_write_errors.fetch_add(1, Ordering::Relaxed);
                        metrics.record_write_error();
                        // Set degraded so subsequent calls skip the channel entirely
                        // rather than re-hitting try_send → Disconnected every time.
                        self.writer_degraded.store(true, Ordering::Relaxed);
                        if need_barrier {
                            return Err(LedgerAppendError::WriteFailed {
                                reason:
                                    "wal writer channel disconnected (writer thread panicked or exited)"
                                        .into(),
                            });
                        }
                        // Non-barrier Disconnected: fall through to HashMap-only apply.
                        // Consistent with QueueFull and degraded — state transitions
                        // are recoverable via reconciliation.
                    }
                }

                // Wait for barrier if needed (OPEN intents).
                if let Some(rx) = barrier_rx {
                    match rx.recv_timeout(self.barrier_timeout) {
                        Ok(Ok(())) => {}
                        Ok(Err(e)) => {
                            metrics.record_write_error();
                            return Err(LedgerAppendError::WriteFailed { reason: e });
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            // Event is enqueued — writer will eventually process it.
                            // Set degraded to prevent further barrier appends that
                            // would also likely time out. On restart, replay
                            // converges (the phantom intent in Created state is
                            // handled by reconciliation — AT-935).
                            self.writer_degraded.store(true, Ordering::Relaxed);
                            metrics.record_write_error();
                            return Err(LedgerAppendError::WriteFailed {
                                reason: "wal barrier timeout — writer degraded".into(),
                            });
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => {
                            metrics.record_write_error();
                            return Err(LedgerAppendError::WriteFailed {
                                reason: "wal barrier reply channel disconnected (writer exited before confirming)".into(),
                            });
                        }
                    }
                }
            }
        }

        // Apply to HashMap.
        // For barrier path: disk write confirmed, HashMap update is safe.
        // For non-barrier path: HashMap ahead of disk is acceptable.
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

// ─── Graceful shutdown ──────────────────────────────────────────────────

impl Drop for WalLedger {
    fn drop(&mut self) {
        // Unpause writer so shutdown message can be processed.
        self.writer_paused.store(false, Ordering::Relaxed);
        if let Some(tx) = self.writer_tx.take() {
            // Drop the sender to disconnect the channel. The writer thread will
            // see Err on rx.recv() and exit after draining queued events.
            // We do NOT use tx.send(Shutdown) because that blocks when the
            // channel is full, risking deadlock during panic unwind if the
            // writer is paused. Dropping tx is always non-blocking and
            // provides the same FIFO drain guarantee.
            drop(tx);
        }
        if let Some(handle) = self.writer_handle.take()
            && let Err(panic_payload) = handle.join()
        {
            tracing::error!(
                panic = ?panic_payload,
                "wal writer thread panicked during shutdown"
            );
        }
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
            // Last-writer-wins: if a duplicate intent_hash appears in the WAL
            // (e.g. crash-replay), the latest record overwrites the earlier one.
            // This is intentional — the WAL is append-only, so the last event
            // for a given hash is always the most recent state.
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

/// WAL writer thread loop.
///
/// Owns the file handle and performs all disk I/O. Uses `sync_data()`
/// (fdatasync) per event — the directory entry is flushed once at file
/// creation in `with_storage_path()`, so only data sync is needed.
///
/// **`sync_data()` safety:** After the initial `sync_all()` at file creation
/// ensures the directory entry is stable, `sync_data()` (fdatasync) is
/// sufficient for durability on modern filesystems (ext4 `data=ordered`,
/// XFS, APFS). On ext3 `data=writeback`, fdatasync may not flush file size
/// updates — this is a known limitation. Production deployments should use
/// ext4 or XFS.
///
/// On write failure: sets `writer_degraded`, increments `write_errors`,
/// and replies `Err` on the barrier (if present). **The degraded flag is
/// never cleared** — once set, the process must be restarted to recover
/// disk durability. This is intentional: a single transient I/O error
/// indicates an unreliable disk, and continuing barrier appends risks
/// further timeouts. Operators should monitor `writer_degraded` and
/// restart when the underlying issue resolves.
fn writer_loop(
    rx: mpsc::Receiver<WalWrite>,
    mut file: File,
    write_errors: Arc<AtomicU64>,
    writer_paused: Arc<AtomicBool>,
    writer_degraded: Arc<AtomicBool>,
) {
    loop {
        // Check pause BEFORE consuming from channel — when paused, events
        // accumulate in the channel allowing callers to observe QueueFull.
        while writer_paused.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(10));
        }

        match rx.recv() {
            Ok(WalWrite::Event {
                serialized,
                barrier,
            }) => {
                // Single write_all with newline appended — avoids partial-write
                // window between data and delimiter that two separate calls create.
                let mut line = serialized;
                line.push('\n');
                let write_result = (|| -> Result<(), String> {
                    file.write_all(line.as_bytes())
                        .map_err(|e| format!("write failed: {e}"))?;
                    file.sync_data().map_err(|e| format!("sync failed: {e}"))
                })();

                if let Err(ref e) = write_result {
                    write_errors.fetch_add(1, Ordering::Relaxed);
                    writer_degraded.store(true, Ordering::Relaxed);
                    tracing::error!(error = %e, "wal writer disk I/O failure — entering degraded mode");
                }

                if let Some(reply) = barrier
                    && reply.send(write_result).is_err()
                {
                    tracing::debug!("wal barrier reply dropped (caller timed out)");
                }
            }
            Ok(WalWrite::Shutdown) | Err(_) => break,
        }
    }
}

fn read_events_from_path(path: &Path) -> io::Result<Vec<WalEvent>> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Open for replay. The write handle is opened separately in
    // with_storage_path() after this function returns and the read handle
    // is dropped, ensuring no overlapping file descriptors.
    // Note: .append(true) is needed alongside .create(true) to satisfy
    // OpenOptions requirements (create requires a write mode).
    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(path)?;
    let reader = BufReader::new(file);

    let mut events = Vec::new();
    let mut trailing_corrupt: Vec<usize> = Vec::new();
    // Stream lines instead of collecting into Vec to bound memory usage
    // (WAL JSONL is unbounded — no compaction in Phase 1).
    for (index, line_result) in reader.lines().enumerate() {
        let line = line_result?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<WalEvent>(trimmed) {
            Ok(event) => {
                if !trailing_corrupt.is_empty() {
                    // A valid line after corrupt lines means the corrupt lines
                    // are mid-file corruption — not trailing crash artifacts.
                    let first_corrupt = trailing_corrupt[0];
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!(
                            "invalid wal event at line {} in {} (followed by valid line {})",
                            first_corrupt + 1,
                            path.display(),
                            index + 1,
                        ),
                    ));
                }
                events.push(event);
            }
            Err(e) => {
                // Accumulate trailing corrupt lines. If all remaining lines
                // are corrupt, they are crash artifacts (tolerated). If a valid
                // line follows, the first corrupt line is mid-file corruption
                // and we fail hard.
                //
                // This handles double-crash: crash #1 leaves a partial trailing
                // line; restart appends new events then crash #2 leaves another
                // partial line. On the third restart both trailing lines are
                // corrupt and should be tolerated.
                trailing_corrupt.push(index);
                tracing::warn!(
                    line = index + 1,
                    path = %path.display(),
                    error = %e,
                    "skipping malformed trailing wal line"
                );
            }
        }
    }

    Ok(events)
}
