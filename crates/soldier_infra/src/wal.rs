//! WAL durability barrier per CONTRACT.md §2.4 / §2.4.1.
//!
//! **Persistence levels:**
//! - `RecordedBeforeDispatch`: intent recorded (in-memory queue) before dispatch.
//!   Always satisfied when `WalLedger::append()` returns `Ok(())`.
//! - `DurableBeforeDispatch`: durability barrier (fsync) before dispatch.
//!   Only enforced when `require_wal_fsync_before_dispatch` config flag is enabled.
//!
//! **WAL Writer Isolation (§2.4.1):**
//! - Append failure → return error, increment wal_write_errors, never block.
//!
//! AT-935, AT-906.

use crate::store::{IntentRecord, LedgerAppendError, LedgerMetrics, WalLedger};
use soldier_core::execution::RecordedBeforeDispatchGate;
use std::time::Instant;

// ─── Configuration ──────────────────────────────────────────────────────

/// WAL durability barrier configuration.
#[derive(Debug, Clone, Default)]
pub struct WalBarrierConfig {
    /// If true, `durable_append` simulates an fsync barrier after enqueue.
    /// If false, `durable_append` returns immediately after enqueue.
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

// --- Core gate adapter --------------------------------------------------

/// Adapter that lets core chokepoint gate 9 call into infra durable append.
///
/// The adapter is single-use by default: one append attempt consumes
/// `record_to_append`. Callers can provide a new record via `set_record`.
pub struct DurableWalGate<'a> {
    pub ledger: &'a mut WalLedger,
    pub config: &'a WalBarrierConfig,
    pub ledger_metrics: &'a mut LedgerMetrics,
    pub barrier_metrics: &'a mut BarrierMetrics,
    record_to_append: Option<IntentRecord>,
}

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
}

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

/// Append an intent record with optional durability barrier.
///
/// CONTRACT.md §2.4: "RecordedBeforeDispatch is mandatory.
/// DurableBeforeDispatch is required when the durability barrier flag is enabled."
///
/// 1. Appends the record to the WAL (RecordedBeforeDispatch).
/// 2. If `config.require_wal_fsync_before_dispatch` is true, simulates an
///    fsync barrier (DurableBeforeDispatch).
/// 3. If append fails, returns error — never blocks.
///
/// Returns `DurableAppendResult` with barrier timing for observability.
pub fn durable_append(
    ledger: &mut WalLedger,
    record: IntentRecord,
    config: &WalBarrierConfig,
    ledger_metrics: &mut LedgerMetrics,
    barrier_metrics: &mut BarrierMetrics,
) -> Result<DurableAppendResult, LedgerAppendError> {
    // Step 1: RecordedBeforeDispatch — enqueue to WAL
    ledger.append(record, ledger_metrics)?;

    // Step 2: DurableBeforeDispatch — fsync barrier if configured
    if config.require_wal_fsync_before_dispatch {
        let start = Instant::now();
        // In a real implementation, this would call fsync() on the WAL file.
        // For the in-memory implementation, the "barrier" is a no-op
        // but we still measure timing for observability.
        simulate_fsync_barrier();
        let elapsed_ms = start.elapsed().as_millis() as u64;
        barrier_metrics.record_barrier_wait(elapsed_ms);

        Ok(DurableAppendResult {
            fsync_applied: true,
            barrier_wait_ms: elapsed_ms,
        })
    } else {
        Ok(DurableAppendResult {
            fsync_applied: false,
            barrier_wait_ms: 0,
        })
    }
}

/// Simulate an fsync barrier.
///
/// In production, this would call `File::sync_all()` or equivalent.
/// In the in-memory implementation, this is intentionally a no-op.
fn simulate_fsync_barrier() {
    // No-op for in-memory WAL. Production would fsync here.
}
