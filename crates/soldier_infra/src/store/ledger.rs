//! Durable Intent Ledger (WAL Truth Source) per CONTRACT.md §2.4.
//!
//! All intents + state transitions are persisted to a crash-safe
//! append-only ledger. On startup, replay reconstructs in-memory state.
//!
//! **Persistence levels:**
//! - `RecordedBeforeDispatch`: intent recorded (in-memory queue) before dispatch.
//! - `DurableBeforeDispatch`: durability barrier (fsync) before dispatch.
//!
//! **WAL Writer Isolation (§2.4.1):**
//! - Appends go through a bounded in-memory queue.
//! - If queue is full → fail-closed for OPEN intents, increment wal_write_errors.
//! - Hot loop MUST NOT block on disk I/O.
//!
//! AT-935, AT-906, AT-233, AT-234.

use std::collections::HashMap;

// ─── TLSM State ─────────────────────────────────────────────────────────

/// Trade Lifecycle State Machine states per CONTRACT.md §2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
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

// ─── Intent Record ──────────────────────────────────────────────────────

/// Persisted intent record per CONTRACT.md §2.4.
///
/// **Minimum persisted fields:**
/// intent_hash, group_id, leg_idx, instrument, side, qty, limit_price,
/// tls_state, created_ts, sent_ts, ack_ts, last_fill_ts,
/// exchange_order_id (if known), last_trade_id (if known).
#[derive(Debug, Clone, PartialEq)]
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

// ─── Append error ───────────────────────────────────────────────────────

/// Error returned when WAL append fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LedgerAppendError {
    /// Bounded WAL queue is full — hot loop must not block.
    /// CONTRACT.md §2.4.1: "fail-closed for OPEN intents"
    QueueFull,
    /// Generic write failure.
    WriteFailed { reason: String },
}

// ─── Replay outcome ─────────────────────────────────────────────────────

/// Outcome of replaying the ledger on startup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplayOutcome {
    /// Number of records replayed.
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
    /// Total successful appends.
    appends_total: u64,
}

impl LedgerMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            wal_write_errors: 0,
            appends_total: 0,
        }
    }

    /// Record a write error.
    pub fn record_write_error(&mut self) {
        self.wal_write_errors += 1;
    }

    /// Record a successful append.
    pub fn record_append(&mut self) {
        self.appends_total += 1;
    }

    /// Current value of `wal_write_errors`.
    pub fn wal_write_errors(&self) -> u64 {
        self.wal_write_errors
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

/// In-memory WAL ledger with bounded queue semantics.
///
/// This is a simplified in-memory implementation that models the WAL
/// contract. A production implementation would back this with Sled/SQLite.
///
/// **Invariants:**
/// - Append-only: records are never modified after append.
/// - Bounded queue: capacity enforced, QueueFull on overflow.
/// - RecordedBeforeDispatch: append must succeed before dispatch.
#[derive(Debug)]
pub struct WalLedger {
    /// Append-only log of intent records.
    records: Vec<IntentRecord>,
    /// Index by intent_hash for O(1) lookup.
    index: HashMap<String, usize>,
    /// Maximum queue capacity.
    capacity: usize,
}

impl WalLedger {
    /// Create a new WAL ledger with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            records: Vec::with_capacity(capacity),
            index: HashMap::new(),
            capacity,
        }
    }

    /// Append an intent record to the ledger (RecordedBeforeDispatch).
    ///
    /// CONTRACT.md §2.4: "Write intent record BEFORE network dispatch."
    /// CONTRACT.md §2.4.1: "If WAL queue is full → fail-closed."
    ///
    /// Returns Ok(()) if recorded successfully, Err if queue is full.
    pub fn append(
        &mut self,
        record: IntentRecord,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if self.records.len() >= self.capacity {
            metrics.record_write_error();
            return Err(LedgerAppendError::QueueFull);
        }

        let idx = self.records.len();
        self.index.insert(record.intent_hash.clone(), idx);
        self.records.push(record);
        metrics.record_append();
        Ok(())
    }

    /// Update the TLS state for an existing record (TLSM transition append).
    ///
    /// CONTRACT.md §2.4: "Write every TLSM transition immediately."
    ///
    /// In a real implementation, this would append a new WAL entry.
    /// Here we update in-place for simplicity (the append-only log
    /// would store the transition as a separate entry).
    pub fn update_state(
        &mut self,
        intent_hash: &str,
        new_state: TlsState,
        metrics: &mut LedgerMetrics,
    ) -> Result<(), LedgerAppendError> {
        if self.records.len() >= self.capacity {
            metrics.record_write_error();
            return Err(LedgerAppendError::QueueFull);
        }

        if let Some(&idx) = self.index.get(intent_hash) {
            self.records[idx].tls_state = new_state;
            metrics.record_append();
            Ok(())
        } else {
            let reason = format!("intent_hash not found: {intent_hash}");
            metrics.record_write_error();
            Err(LedgerAppendError::WriteFailed { reason })
        }
    }

    /// Replay the ledger on startup — reconstruct in-memory state.
    ///
    /// CONTRACT.md §2.4: "On startup, replay ledger into in-memory state
    /// and reconcile with exchange."
    ///
    /// Returns the replay outcome with counts and in-flight intent hashes.
    /// In-flight intents are those in non-terminal states (need reconciliation).
    pub fn replay(&self) -> ReplayOutcome {
        let mut in_flight_hashes = Vec::new();

        for record in &self.records {
            if !record.tls_state.is_terminal() {
                in_flight_hashes.push(record.intent_hash.clone());
            }
        }

        ReplayOutcome {
            records_replayed: self.records.len(),
            in_flight_count: in_flight_hashes.len(),
            in_flight_hashes,
        }
    }

    /// Look up an intent by its hash.
    pub fn get(&self, intent_hash: &str) -> Option<&IntentRecord> {
        self.index.get(intent_hash).map(|&idx| &self.records[idx])
    }

    /// Current queue depth.
    pub fn queue_depth(&self) -> usize {
        self.records.len()
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
}
