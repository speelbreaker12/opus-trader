//! Trade-ID Idempotency Registry per CONTRACT.md (Ghost-Race Hardening).
//!
//! Persists processed trade IDs to prevent duplicate processing.
//!
//! **WS Fill Handler rule (idempotent):**
//! 1) On trade/fill event: if `trade_id` already in registry → NOOP
//! 2) Else: append `trade_id` first, then apply TLSM/positions/attribution updates.
//!
//! AT-269, AT-270.

use std::collections::HashMap;

// ─── Trade record ────────────────────────────────────────────────────────

/// Persisted record for a processed trade.
///
/// CONTRACT.md: `trade_id -> {group_id, leg_idx, ts, qty, price}`
#[derive(Debug, Clone, PartialEq)]
pub struct TradeRecord {
    /// The unique trade ID from the exchange.
    pub trade_id: String,
    /// Group ID of the intent this trade belongs to.
    pub group_id: String,
    /// Leg index within the group.
    pub leg_idx: u32,
    /// Timestamp of the trade event (ms).
    pub ts: u64,
    /// Trade quantity.
    pub qty: f64,
    /// Trade price.
    pub price: f64,
}

// ─── Insert result ───────────────────────────────────────────────────────

/// Result of attempting to insert a trade ID.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InsertResult {
    /// Trade ID was new — inserted successfully. Caller should apply updates.
    Inserted,
    /// Trade ID was already recorded — duplicate. Caller must NOOP.
    Duplicate,
}

// ─── Registry error ──────────────────────────────────────────────────────

/// Error returned when registry operations fail.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegistryError {
    /// Registry is at capacity.
    CapacityFull,
}

// ─── Metrics ─────────────────────────────────────────────────────────────

/// Observability metrics for the trade-ID registry.
#[derive(Debug)]
pub struct RegistryMetrics {
    /// `trade_id_duplicates_total` counter — increments on duplicate insert.
    trade_id_duplicates_total: u64,
    /// Total successful inserts.
    inserts_total: u64,
}

impl RegistryMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            trade_id_duplicates_total: 0,
            inserts_total: 0,
        }
    }

    /// Record a duplicate trade ID.
    pub fn record_duplicate(&mut self) {
        self.trade_id_duplicates_total += 1;
    }

    /// Record a successful insert.
    pub fn record_insert(&mut self) {
        self.inserts_total += 1;
    }

    /// Current value of `trade_id_duplicates_total`.
    pub fn trade_id_duplicates_total(&self) -> u64 {
        self.trade_id_duplicates_total
    }

    /// Current value of total inserts.
    pub fn inserts_total(&self) -> u64 {
        self.inserts_total
    }
}

impl Default for RegistryMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Trade-ID Registry ──────────────────────────────────────────────────

/// In-memory trade-ID idempotency registry with bounded capacity.
///
/// **Invariants:**
/// - Insert-if-absent is atomic (single HashMap insert).
/// - Duplicate trade IDs are detected and result in NOOP.
/// - Append trade_id BEFORE applying TLSM/position updates.
///
/// A production implementation would back this with Sled/SQLite.
#[derive(Debug)]
pub struct TradeIdRegistry {
    /// Map from trade_id to trade record.
    records: HashMap<String, TradeRecord>,
    /// Maximum registry capacity.
    capacity: usize,
}

impl TradeIdRegistry {
    /// Create a new trade-ID registry with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            records: HashMap::with_capacity(capacity),
            capacity,
        }
    }

    /// Insert a trade record if the trade_id is not already present.
    ///
    /// CONTRACT.md: "if trade_id already in WAL → NOOP"
    /// CONTRACT.md: "append trade_id to WAL first, then apply updates"
    ///
    /// Returns `InsertResult::Inserted` if new (caller should apply updates),
    /// or `InsertResult::Duplicate` if already recorded (caller must NOOP).
    ///
    /// Returns `Err(RegistryError::CapacityFull)` if at capacity.
    pub fn insert_if_absent(
        &mut self,
        record: TradeRecord,
        metrics: &mut RegistryMetrics,
    ) -> Result<InsertResult, RegistryError> {
        // Check if already recorded — duplicate
        if self.records.contains_key(&record.trade_id) {
            metrics.record_duplicate();
            return Ok(InsertResult::Duplicate);
        }

        // Check capacity
        if self.records.len() >= self.capacity {
            return Err(RegistryError::CapacityFull);
        }

        // Insert — atomic (single HashMap operation)
        self.records.insert(record.trade_id.clone(), record);
        metrics.record_insert();
        Ok(InsertResult::Inserted)
    }

    /// Check if a trade_id has been processed.
    pub fn contains(&self, trade_id: &str) -> bool {
        self.records.contains_key(trade_id)
    }

    /// Look up a trade record by trade_id.
    pub fn get(&self, trade_id: &str) -> Option<&TradeRecord> {
        self.records.get(trade_id)
    }

    /// Number of processed trade IDs in the registry.
    pub fn len(&self) -> usize {
        self.records.len()
    }

    /// Whether the registry is empty.
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    /// Registry capacity.
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}
