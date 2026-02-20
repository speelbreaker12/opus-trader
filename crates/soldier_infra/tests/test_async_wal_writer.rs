//! Tests for the async WAL writer thread per CONTRACT.md §2.4 / §2.4.1.
//!
//! AT-935: append() blocks on barrier — durable before dispatch.
//! AT-906: Writer degraded → fail-closed for OPEN intents.

use soldier_infra::store::{
    IntentRecord, LedgerAppendError, LedgerMetrics, TlsState, WalLedger, WalWriterConfig,
};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Helper: build a minimal intent record.
fn intent(hash: &str) -> IntentRecord {
    IntentRecord {
        intent_hash: hash.to_string(),
        group_id: "g1".to_string(),
        leg_idx: 0,
        instrument: "BTC-PERP".to_string(),
        side: "buy".to_string(),
        qty_q: 1.0,
        limit_price_q: 50000.0,
        tls_state: TlsState::Created,
        created_ts: 1000,
        sent_ts: 0,
        ack_ts: 0,
        last_fill_ts: 0,
        exchange_order_id: None,
        last_trade_id: None,
    }
}

fn temp_wal_path(tag: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "soldier_async_wal_{tag}_{}_{}.jsonl",
        std::process::id(),
        nanos
    ))
}

fn remove_if_exists(path: &Path) {
    let _ = std::fs::remove_file(path);
}

// ─── Barrier behavior ───────────────────────────────────────────────────

/// append() blocks on barrier — data is on disk when append returns.
#[test]
fn test_append_blocks_on_barrier() {
    let path = temp_wal_path("barrier_block");
    let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    let mut m = LedgerMetrics::new();

    // append() should succeed (barrier confirms fsync)
    ledger.append(intent("h1"), &mut m).unwrap();

    // Record is in memory
    assert!(ledger.get("h1").is_some());
    assert_eq!(m.appends_total(), 1);

    drop(ledger);
    remove_if_exists(&path);
}

/// update_state() returns immediately — no barrier wait.
#[test]
fn test_update_state_does_not_block() {
    let path = temp_wal_path("update_noblock");
    let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    let mut m = LedgerMetrics::new();

    ledger.append(intent("h1"), &mut m).unwrap();

    // update_state is async — should return immediately
    let start = std::time::Instant::now();
    ledger.update_state("h1", TlsState::Sent, &mut m).unwrap();
    let elapsed = start.elapsed();

    // Should be essentially instant (no barrier wait)
    // Allow generous margin for CI slowness
    assert!(
        elapsed.as_millis() < 100,
        "update_state should not block on barrier, took {}ms",
        elapsed.as_millis()
    );

    drop(ledger);
    remove_if_exists(&path);
}

// ─── Writer pause ───────────────────────────────────────────────────────

/// Pause writer, fill channel, verify barrier append returns QueueFull.
///
/// NOTE: This test uses `thread::sleep()` for writer thread coordination.
/// The 50ms sleeps are generous (writer pause check runs every 10ms), but
/// on extremely loaded CI machines this could theoretically flake. If seen
/// in CI, increase the sleep durations.
#[test]
fn test_queue_full_returns_error() {
    let path = temp_wal_path("queue_full");
    // Use channel capacity 1 so it fills quickly.
    let config = WalWriterConfig {
        channel_capacity: 1,
        ..WalWriterConfig::default()
    };
    let mut ledger =
        WalLedger::with_storage_path_configured(100, &path, config).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Seed a record while writer is running (append uses barrier)
    ledger.append(intent("seed"), &mut m).unwrap();

    // Pause writer and wait for it to enter the pause loop.
    ledger.pause_writer();
    std::thread::sleep(std::time::Duration::from_millis(50));

    // Send non-barrier events to fill the channel.
    // Event 1: may wake the writer from recv(), which then sees pause and spins.
    let _ = ledger.update_state("seed", TlsState::Sent, &mut m);
    // Give writer time to consume event 1 and enter pause loop
    std::thread::sleep(std::time::Duration::from_millis(50));
    // Event 2: fills the 1-slot channel (writer is paused, not calling recv)
    let _ = ledger.update_state("seed", TlsState::Acked, &mut m);

    // Channel is full — barrier append (OPEN intent) must fail with QueueFull
    let result = ledger.append(intent("h_full"), &mut m);
    assert_eq!(result, Err(LedgerAppendError::QueueFull));

    ledger.resume_writer();
    drop(ledger);
    remove_if_exists(&path);
}

// ─── Writer degraded ────────────────────────────────────────────────────

/// Verify degraded flag getter works.
#[test]
fn test_writer_degraded_default_false() {
    let path = temp_wal_path("degraded_default");
    let ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    assert!(!ledger.is_writer_degraded());
    drop(ledger);
    remove_if_exists(&path);
}

// ─── Graceful shutdown ──────────────────────────────────────────────────

/// Drop ledger, reload, verify all events persisted (graceful shutdown flushes).
#[test]
fn test_graceful_shutdown_flushes() {
    let path = temp_wal_path("shutdown_flush");

    {
        let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
        let mut m = LedgerMetrics::new();

        ledger.append(intent("h1"), &mut m).unwrap();
        ledger.append(intent("h2"), &mut m).unwrap();
        ledger.update_state("h1", TlsState::Sent, &mut m).unwrap();
        // Drop triggers graceful shutdown with flush
    }

    // Reload and verify
    {
        let ledger = WalLedger::with_storage_path(100, &path).expect("reload wal");
        assert_eq!(ledger.queue_depth(), 2);
        assert!(ledger.get("h1").is_some());
        assert!(ledger.get("h2").is_some());
        // h1 state transition persisted via async writer
        assert_eq!(ledger.get("h1").unwrap().tls_state, TlsState::Sent);
    }

    remove_if_exists(&path);
}

// ─── Durable round-trip ─────────────────────────────────────────────────

/// Write events via async writer, reload, verify integrity.
#[test]
fn test_durable_round_trip() {
    let path = temp_wal_path("round_trip");

    {
        let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
        let mut m = LedgerMetrics::new();

        for i in 0..5 {
            let hash = format!("h{i}");
            ledger.append(intent(&hash), &mut m).unwrap();
        }
        ledger.update_state("h0", TlsState::Sent, &mut m).unwrap();
        ledger.update_state("h0", TlsState::Acked, &mut m).unwrap();
        ledger.update_state("h0", TlsState::Filled, &mut m).unwrap();
        ledger.mark_sent("h1", 2000, &mut m).unwrap();
    }

    {
        let ledger = WalLedger::with_storage_path(100, &path).expect("reload wal");
        assert_eq!(ledger.queue_depth(), 5);

        // h0 should be Filled (terminal)
        assert_eq!(ledger.get("h0").unwrap().tls_state, TlsState::Filled);
        // h1 should be Sent (via mark_sent)
        assert_eq!(ledger.get("h1").unwrap().tls_state, TlsState::Sent);
        assert_eq!(ledger.get("h1").unwrap().sent_ts, 2000);
        // h2-h4 should be Created
        for i in 2..5 {
            let hash = format!("h{i}");
            assert_eq!(ledger.get(&hash).unwrap().tls_state, TlsState::Created);
        }

        let replay = ledger.replay();
        assert_eq!(replay.records_replayed, 5);
        // h0 is terminal, h1-h4 are in-flight
        assert_eq!(replay.in_flight_count, 4);
    }

    remove_if_exists(&path);
}

// ─── Barrier timeout ────────────────────────────────────────────────────

/// Pause writer, barrier-bearing append, verify timeout error.
/// Uses a short (200ms) barrier timeout to keep the test fast.
#[test]
fn test_barrier_timeout() {
    let path = temp_wal_path("barrier_timeout");
    let config = WalWriterConfig {
        channel_capacity: 1024,
        barrier_timeout: Duration::from_millis(200),
    };
    let mut ledger =
        WalLedger::with_storage_path_configured(100, &path, config).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Pause writer so barrier can never complete
    ledger.pause_writer();

    // append() uses barrier — should timeout after 200ms.
    // The event is enqueued (channel not full) but the writer is paused
    // so it never processes it. The barrier recv_timeout fires.
    let result = ledger.append(intent("h1"), &mut m);
    assert!(
        matches!(result, Err(LedgerAppendError::WriteFailed { .. })),
        "expected WriteFailed (barrier timeout), got {result:?}"
    );
    if let Err(LedgerAppendError::WriteFailed { reason }) = &result {
        assert!(
            reason.contains("barrier timeout"),
            "reason must mention timeout: {reason}"
        );
    }

    // Barrier timeout must set degraded flag to prevent further barrier appends
    // that would also likely time out (P1-1 fix).
    assert!(
        ledger.is_writer_degraded(),
        "barrier timeout must set writer_degraded flag"
    );

    // Subsequent barrier append must fail immediately (degraded, not another timeout)
    let result2 = ledger.append(intent("h2"), &mut m);
    assert!(
        matches!(result2, Err(LedgerAppendError::WriteFailed { .. })),
        "expected WriteFailed (degraded), got {result2:?}"
    );
    if let Err(LedgerAppendError::WriteFailed { reason }) = &result2 {
        assert!(
            reason.contains("degraded"),
            "reason must mention degraded: {reason}"
        );
    }

    // P2-1 fix: verify HashMap was NOT updated on barrier timeout.
    // The event may be on disk (phantom intent) but must not be in memory.
    assert!(
        ledger.get("h1").is_none(),
        "barrier timeout must NOT apply event to HashMap — prevents disk/memory divergence"
    );
    assert!(
        ledger.get("h2").is_none(),
        "degraded append must NOT apply event to HashMap"
    );

    ledger.resume_writer();
    drop(ledger);
    remove_if_exists(&path);
}

// ─── Channel disconnected ───────────────────────────────────────────────

/// Verify that in-memory ledger (no writer) has no degraded state.
#[test]
fn test_in_memory_no_writer_degraded() {
    let ledger = WalLedger::new(100);
    assert!(!ledger.is_writer_degraded());
    assert_eq!(ledger.wal_write_errors_shared(), 0);
}

/// Verify WalWriterConfig defaults.
#[test]
fn test_writer_config_default() {
    let config = WalWriterConfig::default();
    assert_eq!(config.channel_capacity, 1024);
    assert_eq!(config.barrier_timeout, Duration::from_secs(5));
}

// ─── Writer killed (channel disconnected) ────────────────────────────────

/// Kill writer thread, verify subsequent operations return WriteFailed.
#[test]
fn test_writer_killed_returns_write_failed() {
    let path = temp_wal_path("writer_killed");
    let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Seed a record while writer is alive
    ledger.append(intent("h1"), &mut m).unwrap();

    // Kill the writer — channel disconnects
    ledger.kill_writer();

    // Barrier-bearing append should fail with WriteFailed (disconnected)
    let result = ledger.append(intent("h2"), &mut m);
    assert!(
        matches!(result, Err(LedgerAppendError::WriteFailed { .. })),
        "expected WriteFailed after writer killed, got {result:?}"
    );
    if let Err(LedgerAppendError::WriteFailed { reason }) = &result {
        assert!(
            reason.contains("channel already closed"),
            "reason must mention channel closed: {reason}"
        );
    }

    // Non-barrier state transition should also fail (channel disconnected)
    let result = ledger.update_state("h1", TlsState::Sent, &mut m);
    assert!(
        matches!(result, Err(LedgerAppendError::WriteFailed { .. })),
        "expected WriteFailed for update_state after writer killed, got {result:?}"
    );

    remove_if_exists(&path);
}

// ─── Degraded behavior ──────────────────────────────────────────────────

/// Force degraded flag, verify barrier appends fail but non-barrier state
/// transitions still apply to HashMap (recoverable via reconciliation).
#[test]
fn test_degraded_blocks_barrier_allows_non_barrier() {
    let path = temp_wal_path("degraded_split");
    let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Seed a record while healthy
    ledger.append(intent("h1"), &mut m).unwrap();
    assert_eq!(ledger.get("h1").unwrap().tls_state, TlsState::Created);

    // Force degraded
    ledger.force_set_degraded(true);
    assert!(ledger.is_writer_degraded());

    // Barrier append (OPEN intent) must fail — can't guarantee durability
    let result = ledger.append(intent("h2"), &mut m);
    assert_eq!(
        result,
        Err(LedgerAppendError::WriteFailed {
            reason: "wal writer degraded".into()
        })
    );

    // Non-barrier state transition must succeed — applies to HashMap only
    // (skips channel when degraded, recoverable via reconciliation)
    ledger
        .update_state("h1", TlsState::Sent, &mut m)
        .expect("non-barrier update must succeed when degraded");
    assert_eq!(
        ledger.get("h1").unwrap().tls_state,
        TlsState::Sent,
        "HashMap must reflect state transition even when degraded"
    );

    // mark_sent is also non-barrier — must succeed
    ledger
        .mark_sent("h1", 9999, &mut m)
        .expect("mark_sent must succeed when degraded");
    assert_eq!(ledger.get("h1").unwrap().sent_ts, 9999);

    drop(ledger);
    remove_if_exists(&path);
}

/// Verify degraded flag blocks barrier appends and increments error counter.
///
/// Note: Triggering a real disk write error via read-only permissions doesn't
/// work because the writer thread already holds an open file handle (macOS/Linux
/// check permissions at open(), not write()). We use force_set_degraded() to
/// simulate the writer_loop setting the flag on I/O error. The writer_loop code
/// path (`write_errors.fetch_add + writer_degraded.store`) is verified by code
/// review; this test verifies the caller-side behavior.
#[test]
fn test_degraded_flag_blocks_barrier_increments_errors() {
    let path = temp_wal_path("degraded_errors");
    let mut ledger = WalLedger::with_storage_path(100, &path).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Healthy: append succeeds
    ledger.append(intent("h1"), &mut m).unwrap();
    assert!(!ledger.is_writer_degraded());
    let errors_before = ledger.wal_write_errors_shared();

    // Simulate writer entering degraded state (as writer_loop would on I/O error)
    ledger.force_set_degraded(true);
    assert!(ledger.is_writer_degraded());

    // Barrier append must fail
    let result = ledger.append(intent("h2"), &mut m);
    assert_eq!(
        result,
        Err(LedgerAppendError::WriteFailed {
            reason: "wal writer degraded".into()
        })
    );

    // Errors counter must reflect the rejection
    // (LedgerMetrics.record_write_error is called)
    assert_eq!(m.wal_write_errors(), 1);

    // Shared atomic counter is NOT incremented by the degraded check path —
    // it's only incremented by try_send failures and the writer_loop.
    // The LedgerMetrics counter tracks caller-side rejections.
    assert_eq!(ledger.wal_write_errors_shared(), errors_before);

    drop(ledger);
    remove_if_exists(&path);
}

// ─── QueueFull non-barrier fallthrough ──────────────────────────────────

/// Non-barrier state transitions apply to HashMap even when channel is full.
/// Consistent with degraded behavior — state transitions are recoverable.
#[test]
fn test_queue_full_non_barrier_applies_to_hashmap() {
    let path = temp_wal_path("qfull_fallthrough");
    let config = WalWriterConfig {
        channel_capacity: 1,
        ..WalWriterConfig::default()
    };
    let mut ledger =
        WalLedger::with_storage_path_configured(100, &path, config).expect("create wal");
    let mut m = LedgerMetrics::new();

    // Seed a record while writer is running
    ledger.append(intent("h1"), &mut m).unwrap();

    // Pause writer, fill channel
    ledger.pause_writer();
    std::thread::sleep(std::time::Duration::from_millis(50));
    let _ = ledger.update_state("h1", TlsState::Sent, &mut m);
    std::thread::sleep(std::time::Duration::from_millis(50));
    let _ = ledger.update_state("h1", TlsState::Acked, &mut m);

    // Channel is full — non-barrier state transition should still succeed
    // (falls through to HashMap-only apply, consistent with degraded behavior)
    let result = ledger.update_state("h1", TlsState::PartialFill, &mut m);
    assert!(
        result.is_ok(),
        "non-barrier QueueFull should fall through to HashMap: {result:?}"
    );
    assert_eq!(
        ledger.get("h1").unwrap().tls_state,
        TlsState::PartialFill,
        "HashMap must reflect state transition despite QueueFull"
    );

    ledger.resume_writer();
    drop(ledger);
    remove_if_exists(&path);
}

// ─── Channel capacity validation ────────────────────────────────────────

/// channel_capacity=0 must be rejected (creates rendezvous channel).
#[test]
fn test_channel_capacity_zero_rejected() {
    let path = temp_wal_path("cap_zero");
    let config = WalWriterConfig {
        channel_capacity: 0,
        ..WalWriterConfig::default()
    };
    let result = WalLedger::with_storage_path_configured(100, &path, config);
    assert!(result.is_err(), "channel_capacity=0 must be rejected");
    let err = result.unwrap_err();
    assert!(
        err.to_string().contains("channel_capacity"),
        "error must mention channel_capacity: {err}"
    );
    remove_if_exists(&path);
}
