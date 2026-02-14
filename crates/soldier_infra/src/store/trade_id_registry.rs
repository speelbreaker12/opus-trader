//! Trade-ID Idempotency Registry per CONTRACT.md (Ghost-Race Hardening).
//!
//! Persists processed trade IDs to prevent duplicate processing.
//!
//! WS Fill Handler rule (idempotent):
//! 1) On trade/fill event: if `trade_id` already in registry -> NOOP
//! 2) Else: append `trade_id` first, then apply TLSM/positions/attribution updates.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::path::Path;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

// --- Trade record -------------------------------------------------------

/// Persisted record for a processed trade.
///
/// CONTRACT.md: `trade_id -> {group_id, leg_idx, ts, qty, price}`
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
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

// --- Insert result ------------------------------------------------------

/// Result of attempting to insert a trade ID.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InsertResult {
    /// Trade ID was new - inserted successfully. Caller should apply updates.
    Inserted,
    /// Trade ID was already recorded - duplicate. Caller must NOOP.
    Duplicate,
}

// --- Registry error -----------------------------------------------------

/// Error returned when registry operations fail.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegistryError {
    /// Registry is at capacity.
    CapacityFull,
    /// Durable append failed.
    WriteFailed { reason: String },
}

// --- Metrics ------------------------------------------------------------

/// Observability metrics for the trade-ID registry.
#[derive(Debug)]
pub struct RegistryMetrics {
    /// `trade_id_duplicates_total` counter.
    trade_id_duplicates_total: AtomicU64,
    /// Total successful inserts.
    inserts_total: AtomicU64,
}

impl RegistryMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            trade_id_duplicates_total: AtomicU64::new(0),
            inserts_total: AtomicU64::new(0),
        }
    }

    /// Record a duplicate trade ID.
    pub fn record_duplicate(&self) {
        self.trade_id_duplicates_total
            .fetch_add(1, Ordering::Relaxed);
    }

    /// Record a successful insert.
    pub fn record_insert(&self) {
        self.inserts_total.fetch_add(1, Ordering::Relaxed);
    }

    /// Current value of `trade_id_duplicates_total`.
    pub fn trade_id_duplicates_total(&self) -> u64 {
        self.trade_id_duplicates_total.load(Ordering::Relaxed)
    }

    /// Current value of total inserts.
    pub fn inserts_total(&self) -> u64 {
        self.inserts_total.load(Ordering::Relaxed)
    }
}

impl Default for RegistryMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// --- Trade-ID Registry --------------------------------------------------

#[derive(Debug)]
struct RegistryState {
    records: HashMap<String, TradeRecord>,
    storage_file: Option<File>,
}

/// Thread-safe trade-ID idempotency registry with bounded capacity.
///
/// Invariants:
/// - Insert-if-absent is atomic under the registry mutex.
/// - Duplicate trade IDs are detected and result in NOOP.
/// - trade_id is recorded before downstream apply logic runs.
#[derive(Debug)]
pub struct TradeIdRegistry {
    state: Mutex<RegistryState>,
    capacity: usize,
}

impl TradeIdRegistry {
    /// Create a new trade-ID registry with the given capacity.
    pub fn new(capacity: usize) -> Self {
        Self {
            state: Mutex::new(RegistryState {
                records: HashMap::with_capacity(capacity),
                storage_file: None,
            }),
            capacity,
        }
    }

    /// Create/load a durable trade-ID registry backed by a JSONL file.
    pub fn with_storage_path(capacity: usize, storage_path: impl AsRef<Path>) -> io::Result<Self> {
        let path = storage_path.as_ref();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let records = load_records(path)?;
        if records.len() > capacity {
            let reason = format!(
                "trade-id registry contains {} IDs but capacity is {}",
                records.len(),
                capacity
            );
            return Err(io::Error::new(io::ErrorKind::InvalidInput, reason));
        }

        let storage_file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(Self {
            state: Mutex::new(RegistryState {
                records,
                storage_file: Some(storage_file),
            }),
            capacity,
        })
    }

    /// Insert a trade record if the trade_id is not already present.
    ///
    /// Returns `Inserted` if new, `Duplicate` if already present, and
    /// `Err(CapacityFull)` if the registry cannot accept a new ID.
    pub fn insert_if_absent(
        &self,
        record: TradeRecord,
        metrics: &RegistryMetrics,
    ) -> Result<InsertResult, RegistryError> {
        let mut state = self.state.lock().expect("trade id registry mutex poisoned");

        if state.records.contains_key(&record.trade_id) {
            metrics.record_duplicate();
            return Ok(InsertResult::Duplicate);
        }
        if state.records.len() >= self.capacity {
            return Err(RegistryError::CapacityFull);
        }

        if let Some(file) = state.storage_file.as_mut() {
            persist_record(file, &record).map_err(|e| RegistryError::WriteFailed {
                reason: e.to_string(),
            })?;
        }

        state.records.insert(record.trade_id.clone(), record);
        metrics.record_insert();
        Ok(InsertResult::Inserted)
    }

    /// Check if a trade_id has been processed.
    pub fn contains(&self, trade_id: &str) -> bool {
        self.state
            .lock()
            .expect("trade id registry mutex poisoned")
            .records
            .contains_key(trade_id)
    }

    /// Look up a trade record by trade_id.
    pub fn get(&self, trade_id: &str) -> Option<TradeRecord> {
        self.state
            .lock()
            .expect("trade id registry mutex poisoned")
            .records
            .get(trade_id)
            .cloned()
    }

    /// Number of processed trade IDs in the registry.
    pub fn len(&self) -> usize {
        self.state
            .lock()
            .expect("trade id registry mutex poisoned")
            .records
            .len()
    }

    /// Whether the registry is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Registry capacity.
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

fn load_records(path: &Path) -> io::Result<HashMap<String, TradeRecord>> {
    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(path)?;
    let reader = BufReader::new(file);
    let mut records = HashMap::new();
    for (index, line_result) in reader.lines().enumerate() {
        let line = line_result?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let record: TradeRecord = serde_json::from_str(trimmed).map_err(|e| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "invalid trade-id record at line {} in {}: {e}",
                    index + 1,
                    path.display()
                ),
            )
        })?;
        if records.contains_key(&record.trade_id) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "duplicate trade_id '{}' in {}",
                    record.trade_id,
                    path.display()
                ),
            ));
        }
        records.insert(record.trade_id.clone(), record);
    }

    Ok(records)
}

fn persist_record(file: &mut File, record: &TradeRecord) -> io::Result<()> {
    let line = serde_json::to_string(record).map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("failed to encode trade-id record: {e}"),
        )
    })?;
    file.write_all(line.as_bytes())?;
    file.write_all(b"\n")?;
    file.sync_all()
}
