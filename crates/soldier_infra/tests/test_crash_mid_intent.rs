//! Crash/restart tests for WAL replay semantics.
//!
//! CONTRACT.md AT-935, AT-233, AT-234, section 2.4.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use soldier_infra::store::{IntentRecord, LedgerMetrics, TlsState, WalLedger};
use soldier_infra::wal::{BarrierMetrics, WalBarrierConfig, durable_append};

fn test_intent(hash: &str, state: TlsState, sent_ts: u64) -> IntentRecord {
    IntentRecord {
        intent_hash: hash.to_string(),
        group_id: "group-001".to_string(),
        leg_idx: 0,
        instrument: "BTC-PERPETUAL".to_string(),
        side: "buy".to_string(),
        qty_q: 1.0,
        limit_price_q: 50000.0,
        tls_state: state,
        created_ts: 1000,
        sent_ts,
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
        "soldier_wal_{tag}_{}_{}.jsonl",
        std::process::id(),
        nanos
    ))
}

fn remove_if_exists(path: &Path) {
    let _ = std::fs::remove_file(path);
}

// --- AT-935 -------------------------------------------------------------

#[test]
fn test_at935_unsent_dispatches_exactly_once_across_two_restarts() {
    let wal_path = temp_wal_path("at935_once");

    // Phase 1: process records intent before any send.
    {
        let mut ledger = WalLedger::with_storage_path(100, &wal_path).expect("create wal");
        let mut lm = LedgerMetrics::new();
        let mut bm = BarrierMetrics::new();
        let config = WalBarrierConfig::default();

        durable_append(
            &mut ledger,
            test_intent("intent-at935", TlsState::Created, 0),
            &config,
            &mut lm,
            &mut bm,
        )
        .expect("append should succeed");
    }

    let mut dispatch_count = 0u32;

    // Restart #1: replay + reconcile, then dispatch once and mark sent.
    {
        let mut ledger = WalLedger::with_storage_path(100, &wal_path).expect("reload wal");
        let replay = ledger.replay();
        assert_eq!(replay.records_replayed, 1);
        assert_eq!(replay.in_flight_count, 1);
        assert!(!ledger.was_sent("intent-at935"));

        // Reconciliation confirms no open order/trade for the label.
        if !ledger.was_sent("intent-at935") {
            dispatch_count += 1;
            let mut lm = LedgerMetrics::new();
            ledger
                .mark_sent("intent-at935", 2000, &mut lm)
                .expect("mark_sent should append transition");
        }
    }

    // Restart #2: replay must not cause a second dispatch.
    {
        let ledger = WalLedger::with_storage_path(100, &wal_path).expect("reload wal #2");
        assert!(ledger.was_sent("intent-at935"));
        if !ledger.was_sent("intent-at935") {
            dispatch_count += 1;
        }
    }

    assert_eq!(
        dispatch_count, 1,
        "exactly one dispatch across two restarts"
    );
    remove_if_exists(&wal_path);
}

// --- AT-233 -------------------------------------------------------------

#[test]
fn test_at233_sent_intent_not_resent_on_restart() {
    let wal_path = temp_wal_path("at233_sent");

    {
        let mut ledger = WalLedger::with_storage_path(100, &wal_path).expect("create wal");
        let mut lm = LedgerMetrics::new();
        let mut bm = BarrierMetrics::new();
        let config = WalBarrierConfig::default();

        durable_append(
            &mut ledger,
            test_intent("intent-sent-002", TlsState::Sent, 2000),
            &config,
            &mut lm,
            &mut bm,
        )
        .expect("append should succeed");
    }

    let ledger = WalLedger::with_storage_path(100, &wal_path).expect("reload wal");
    let replay = ledger.replay();
    assert_eq!(replay.in_flight_count, 1);
    assert!(ledger.was_sent("intent-sent-002"));

    remove_if_exists(&wal_path);
}

// --- AT-234 -------------------------------------------------------------

#[test]
fn test_at234_terminal_states_not_in_flight_on_restart() {
    let mut ledger = WalLedger::new(100);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();

    durable_append(
        &mut ledger,
        test_intent("filled-001", TlsState::Filled, 1000),
        &config,
        &mut lm,
        &mut bm,
    )
    .unwrap();
    durable_append(
        &mut ledger,
        test_intent("cancelled-002", TlsState::Cancelled, 1000),
        &config,
        &mut lm,
        &mut bm,
    )
    .unwrap();
    durable_append(
        &mut ledger,
        test_intent("rejected-003", TlsState::Rejected, 0),
        &config,
        &mut lm,
        &mut bm,
    )
    .unwrap();

    let replay = ledger.replay();
    assert_eq!(replay.records_replayed, 3);
    assert_eq!(replay.in_flight_count, 0);
    assert!(replay.in_flight_hashes.is_empty());
}

// --- Fail-closed append -------------------------------------------------

#[test]
fn test_wal_append_failure_prevents_dispatch() {
    let mut ledger = WalLedger::new(0);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();

    let intent = test_intent("should-not-dispatch", TlsState::Created, 0);
    let result = durable_append(&mut ledger, intent, &config, &mut lm, &mut bm);

    assert!(result.is_err(), "WAL append must fail on full queue");
    assert_eq!(ledger.queue_depth(), 0, "No intent recorded");
    assert_eq!(lm.wal_write_errors(), 1);
    assert_eq!(lm.wal_queue_enqueue_failures(), 1);
}

// --- Durability barrier -------------------------------------------------

#[test]
fn test_durable_append_with_fsync_barrier() {
    let mut ledger = WalLedger::new(100);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    let intent = test_intent("fsync-test", TlsState::Created, 0);
    let result = durable_append(&mut ledger, intent, &config, &mut lm, &mut bm).unwrap();

    assert!(result.fsync_applied, "Fsync barrier must be applied");
    assert_eq!(bm.barrier_wait_count(), 1);
    assert_eq!(ledger.queue_depth(), 1);
}
