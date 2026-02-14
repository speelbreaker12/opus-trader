//! Durable Intent Ledger (WAL Truth Source) per CONTRACT.md section 2.4.
//!
//! All intents and state transitions are captured as append-only WAL events.
//! On startup, replay reduces the event stream into the latest per-intent view.
//!
//! Persistence levels:
//! - `RecordedBeforeDispatch`: intent is enqueued/appended before dispatch.
//! - `DurableBeforeDispatch`: durability barrier (fsync marker) before dispatch.
//!
//! WAL Writer Isolation (section 2.4.1):
//! - Appends go through a bounded in-memory queue model.
//! - If queue is full -> fail-closed for OPEN intents and increment counters.
//! - Hot loop MUST NOT block indefinitely.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

// --- TLSM State ---------------------------------------------------------

/// Trade Lifecycle State Machine states per CONTRACT.md section 2.1.
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
}

// --- Intent Record ------------------------------------------------------

/// Persisted intent record per CONTRACT.md section 2.4.
///
/// Minimum persisted fields:
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

// --- WAL Event ----------------------------------------------------------

/// Append-only WAL event.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
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

// --- Append error -------------------------------------------------------

/// Error returned when WAL append fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LedgerAppendError {
    /// Bounded WAL queue is full.
    QueueFull,
    /// Generic write failure.
    WriteFailed { reason: String },
}

impl std::fmt::Display for LedgerAppendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::QueueFull => write!(f, "wal queue full"),
            Self::WriteFailed { reason } => write!(f, "wal write failed: {reason}"),
        }
    }
}

impl std::error::Error for LedgerAppendError {}

// --- Replay outcome -----------------------------------------------------

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

// --- Metrics ------------------------------------------------------------

/// Observability metrics for the WAL ledger.
#[derive(Debug)]
pub struct LedgerMetrics {
    /// `wal_write_errors` counter.
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

// --- WAL Ledger ---------------------------------------------------------

/// WAL ledger with append-only events and optional durable storage path.
#[derive(Debug)]
pub struct WalLedger {
    /// Reconstructed latest state per intent hash.
    latest_by_hash: HashMap<String, IntentRecord>,
    /// Maximum queue capacity (intent records only).
    capacity: usize,
    /// Optional JSONL storage path.
    storage_path: Option<PathBuf>,
}

impl WalLedger {
    /// Create a new in-memory WAL ledger with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            latest_by_hash: HashMap::new(),
            capacity,
            storage_path: None,
        }
    }

    /// Create/load a WAL ledger backed by a JSONL file.
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

        Ok(Self {
            latest_by_hash,
            capacity,
            storage_path: Some(path),
        })
    }

    /// Storage path if this ledger is durable.
    pub fn storage_path(&self) -> Option<&Path> {
        self.storage_path.as_deref()
    }

    /// Append an intent record to the ledger (RecordedBeforeDispatch).
    pub fn append(
        &mut self,
        record: IntentRecord,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if self.latest_by_hash.len() >= self.capacity {
            metrics.record_write_error();
            metrics.record_enqueue_failure();
            return Err(LedgerAppendError::QueueFull);
        }
        if self.latest_by_hash.contains_key(&record.intent_hash) {
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: format!("intent_hash already exists: {}", record.intent_hash),
            });
        }

        let event = WalEvent::IntentRecorded { record };
        self.persist_and_apply(event, metrics)?;
        Ok(())
    }

    /// Append a TLSM state transition event.
    pub fn update_state(
        &mut self,
        intent_hash: &str,
        new_state: TlsState,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if !self.latest_by_hash.contains_key(intent_hash) {
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: format!("intent_hash not found: {intent_hash}"),
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
    pub fn mark_sent(
        &mut self,
        intent_hash: &str,
        sent_ts: u64,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if !self.latest_by_hash.contains_key(intent_hash) {
            metrics.record_write_error();
            return Err(LedgerAppendError::WriteFailed {
                reason: format!("intent_hash not found: {intent_hash}"),
            });
        }

        let event = WalEvent::SentMarked {
            intent_hash: intent_hash.to_string(),
            sent_ts,
        };
        self.persist_and_apply(event, metrics)?;
        Ok(())
    }

    /// Replay the ledger on startup.
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

    /// Look up an intent by hash.
    pub fn get(&self, intent_hash: &str) -> Option<&IntentRecord> {
        self.latest_by_hash.get(intent_hash)
    }

    /// Current queue depth.
    pub fn queue_depth(&self) -> usize {
        self.latest_by_hash.len()
    }

    /// Queue capacity.
    pub fn queue_capacity(&self) -> usize {
        self.capacity
    }

    /// Whether this intent was already sent.
    pub fn was_sent(&self, intent_hash: &str) -> bool {
        self.get(intent_hash)
            .map(|r| r.sent_ts > 0 || r.tls_state != TlsState::Created)
            .unwrap_or(false)
    }

    fn persist_and_apply(
        &mut self,
        event: WalEvent,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if let Some(path) = &self.storage_path {
            write_event_to_path(path, &event).map_err(|reason| {
                metrics.record_write_error();
                LedgerAppendError::WriteFailed { reason }
            })?;
        }

        apply_event(&mut self.latest_by_hash, &event).map_err(|reason| {
            metrics.record_write_error();
            LedgerAppendError::WriteFailed { reason }
        })?;

        metrics.record_append();
        Ok(())
    }
}

/// Adapter that routes core TLSM transitions into this ledger.
pub struct LedgerTransitionSink<'a> {
    ledger: &'a mut WalLedger,
    metrics: &'a mut LedgerMetrics,
    intent_hash: String,
    last_error: Option<LedgerAppendError>,
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
            last_error: None,
        }
    }

    pub fn last_error(&self) -> Option<&LedgerAppendError> {
        self.last_error.as_ref()
    }
}

impl soldier_core::execution::TlsmTransitionSink for LedgerTransitionSink<'_> {
    fn append_transition(
        &mut self,
        transition: soldier_core::execution::PersistedTransition,
    ) -> Result<(), String> {
        let mapped_state = map_core_tlsm_state(transition.to);
        if let Err(err) = self
            .ledger
            .update_state(&self.intent_hash, mapped_state, self.metrics)
        {
            let reason = err.to_string();
            self.last_error = Some(err);
            return Err(reason);
        }
        Ok(())
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

fn write_event_to_path(path: &Path, event: &WalEvent) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            format!(
                "failed to create wal parent directory {}: {e}",
                parent.display()
            )
        })?;
    }

    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|e| format!("failed to open wal {}: {e}", path.display()))?;
    let line =
        serde_json::to_string(event).map_err(|e| format!("failed to encode wal event: {e}"))?;
    file.write_all(line.as_bytes())
        .map_err(|e| format!("failed to write wal event {}: {e}", path.display()))?;
    file.write_all(b"\n")
        .map_err(|e| format!("failed to write wal newline {}: {e}", path.display()))?;
    file.flush()
        .map_err(|e| format!("failed to flush wal {}: {e}", path.display()))
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
    for (index, line_result) in reader.lines().enumerate() {
        let line = line_result?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let event: WalEvent = serde_json::from_str(trimmed).map_err(|e| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "invalid wal event at line {} in {}: {e}",
                    index + 1,
                    path.display()
                ),
            )
        })?;
        events.push(event);
    }

    Ok(events)
}
