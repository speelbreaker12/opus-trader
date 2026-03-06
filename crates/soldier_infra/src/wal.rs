//! WAL durability barrier per CONTRACT.md §2.4 / §2.4.1.
//!
//! **Persistence levels:**
//! - `RecordedBeforeDispatch`: intent recorded before dispatch. For durable
//!   storage, `WalLedger::append()` waits for fsync confirmation (barrier)
//!   before returning — OPEN intents are crash-safe.
//! - `DurableBeforeDispatch`: guaranteed by the barrier in `append()`.
//!
//! **WAL Writer Isolation (§2.4.1):**
//! - Append failure → return error, increment wal_write_errors, never block.
//! - State transitions (update_state/mark_sent) are async — no barrier.
//!
//! AT-935, AT-906.

use crate::store::{IntentRecord, LedgerAppendError, LedgerMetrics, TlsState, WalLedger};
use soldier_core::execution::RecordedBeforeDispatchGate;
use soldier_core::venue::LifecycleIntent;
use std::time::Instant;

// ─── Configuration ──────────────────────────────────────────────────────

/// Derive persisted `reduce_only` classifier from lifecycle intent.
///
/// CONTRACT + implementation plan invariant:
/// - OPEN -> reduce_only=false
/// - CLOSE/HEDGE/CANCEL -> reduce_only=true
pub fn reduce_only_from_lifecycle_intent(intent: LifecycleIntent) -> bool {
    matches!(
        intent,
        LifecycleIntent::Close | LifecycleIntent::Hedge | LifecycleIntent::Cancel
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildCreatedIntentRecordError {
    UnsupportedLifecycleIntent(LifecycleIntent),
}

/// Construct a CREATED-state WAL intent record from runtime intent fields.
///
/// This is the canonical constructor for newly-persisted pre-dispatch intents.
/// `reduce_only` is derived from `lifecycle_intent` (never from TradingMode).
pub fn build_created_intent_record(
    intent_hash: &str,
    group_id: &str,
    leg_idx: u32,
    instrument: &str,
    side: &str,
    lifecycle_intent: LifecycleIntent,
    qty_q: f64,
    limit_price_q: f64,
    created_ts: u64,
) -> Result<IntentRecord, BuildCreatedIntentRecordError> {
    if lifecycle_intent == LifecycleIntent::Cancel {
        return Err(BuildCreatedIntentRecordError::UnsupportedLifecycleIntent(
            lifecycle_intent,
        ));
    }

    Ok(IntentRecord {
        intent_hash: intent_hash.to_string(),
        group_id: group_id.to_string(),
        leg_idx,
        instrument: instrument.to_string(),
        side: side.to_string(),
        reduce_only: reduce_only_from_lifecycle_intent(lifecycle_intent),
        qty_q,
        limit_price_q,
        tls_state: TlsState::Created,
        created_ts,
        sent_ts: 0,
        ack_ts: 0,
        last_fill_ts: 0,
        exchange_order_id: None,
        last_trade_id: None,
    })
}

/// WAL durability barrier configuration.
///
/// **Deprecated:** With the async writer, barrier semantics are now handled by
/// `WalLedger::append()` directly — `append()` always waits for fsync when
/// durable storage is configured. This struct is retained only for API
/// stability; its fields are ignored by `durable_append()`.
/// Use `WalWriterConfig` in `store::ledger` to configure barrier timeout
/// and channel capacity.
#[deprecated(
    since = "0.2.0",
    note = "Barrier is now always applied by WalLedger::append(). Use WalWriterConfig instead."
)]
#[derive(Debug, Clone, Default)]
pub struct WalBarrierConfig {
    /// **Ignored.** Barrier is always applied for `append()` when durable
    /// storage is configured. This field has no effect.
    pub require_wal_fsync_before_dispatch: bool,
}

// ─── Barrier result ─────────────────────────────────────────────────────

/// Result of a durable append operation.
#[derive(Debug, Clone, PartialEq)]
pub struct DurableAppendResult {
    /// Whether the fsync barrier was applied.
    pub fsync_applied: bool,
    /// Time spent waiting on the durability barrier (ms).
    /// 0 if barrier is disabled or not applicable.
    pub barrier_wait_ms: u64,
}

// ─── Barrier metrics ────────────────────────────────────────────────────

/// Observability metrics for the WAL durability barrier.
#[derive(Debug)]
pub struct BarrierMetrics {
    /// Histogram proxy: total barrier wait time in ms (sum).
    barrier_wait_ms_total: u64,
    /// Number of barrier waits recorded.
    barrier_wait_count: u64,
}

impl BarrierMetrics {
    /// Create a new barrier metrics tracker.
    pub fn new() -> Self {
        Self {
            barrier_wait_ms_total: 0,
            barrier_wait_count: 0,
        }
    }

    /// Record a barrier wait duration.
    pub fn record_barrier_wait(&mut self, wait_ms: u64) {
        self.barrier_wait_ms_total += wait_ms;
        self.barrier_wait_count += 1;
    }

    /// Total barrier wait time in ms.
    pub fn barrier_wait_ms_total(&self) -> u64 {
        self.barrier_wait_ms_total
    }

    /// Number of barrier waits.
    pub fn barrier_wait_count(&self) -> u64 {
        self.barrier_wait_count
    }
}

impl Default for BarrierMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Core gate adapter ──────────────────────────────────────────────────

/// Adapter that lets core chokepoint gate 10 call into infra durable append.
///
/// The adapter is single-use by default: one append attempt consumes
/// `record_to_append`. Callers can provide a new record via `set_record`.
#[allow(deprecated)]
pub struct DurableWalGate<'a> {
    ledger: &'a mut WalLedger,
    config: &'a WalBarrierConfig,
    ledger_metrics: &'a mut LedgerMetrics,
    barrier_metrics: &'a mut BarrierMetrics,
    record_to_append: Option<IntentRecord>,
}

#[allow(deprecated)]
impl<'a> DurableWalGate<'a> {
    pub fn new(
        ledger: &'a mut WalLedger,
        config: &'a WalBarrierConfig,
        ledger_metrics: &'a mut LedgerMetrics,
        barrier_metrics: &'a mut BarrierMetrics,
        record_to_append: IntentRecord,
    ) -> Self {
        Self {
            ledger,
            config,
            ledger_metrics,
            barrier_metrics,
            record_to_append: Some(record_to_append),
        }
    }

    pub fn set_record(&mut self, record: IntentRecord) {
        self.record_to_append = Some(record);
    }

    /// Access the underlying ledger (read-only).
    pub fn ledger(&self) -> &WalLedger {
        self.ledger
    }

    /// Access the barrier metrics (read-only).
    pub fn barrier_metrics(&self) -> &BarrierMetrics {
        self.barrier_metrics
    }
}

#[allow(deprecated)]
impl RecordedBeforeDispatchGate for DurableWalGate<'_> {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        let record = self
            .record_to_append
            .take()
            .ok_or_else(|| "durable wal gate missing record".to_string())?;
        durable_append(
            self.ledger,
            record,
            self.config,
            self.ledger_metrics,
            self.barrier_metrics,
        )
        .map(|_| ())
        .map_err(|e| e.to_string())
    }
}

// ─── Durable append ─────────────────────────────────────────────────────

/// Append an intent record with durability barrier.
///
/// CONTRACT.md §2.4: "RecordedBeforeDispatch is mandatory."
///
/// The barrier is now handled inside `WalLedger::append()` — when durable
/// storage is configured, append waits for the async writer thread to confirm
/// fsync before returning. For in-memory ledgers, there is no disk I/O.
///
/// Returns `DurableAppendResult` with barrier timing for observability.
#[allow(deprecated)]
pub fn durable_append(
    ledger: &mut WalLedger,
    record: IntentRecord,
    _config: &WalBarrierConfig,
    ledger_metrics: &mut LedgerMetrics,
    barrier_metrics: &mut BarrierMetrics,
) -> Result<DurableAppendResult, LedgerAppendError> {
    let has_storage = ledger.storage_path().is_some();
    let start = Instant::now();

    // append() handles barrier internally for durable storage.
    ledger.append(record, ledger_metrics)?;

    let elapsed_ms = if has_storage {
        let ms = start.elapsed().as_millis() as u64;
        barrier_metrics.record_barrier_wait(ms);
        ms
    } else {
        0
    };

    Ok(DurableAppendResult {
        fsync_applied: has_storage,
        barrier_wait_ms: elapsed_ms,
    })
}
