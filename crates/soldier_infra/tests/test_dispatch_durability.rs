//! Tests for WAL durability barrier per CONTRACT.md §2.4 / §2.4.1.
//!
//! AT-935: RecordedBeforeDispatch + restart → dispatch exactly once.
//! AT-906: WAL enqueue failure blocks OPEN; hot loop continues.

use soldier_core::execution::RecordedBeforeDispatchGate;
use soldier_infra::store::{IntentRecord, LedgerAppendError, LedgerMetrics, TlsState, WalLedger};
use soldier_infra::wal::{
    BarrierMetrics, DurableAppendResult, DurableWalGate, WalBarrierConfig, durable_append,
};

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

// ─── Barrier disabled: immediate return ─────────────────────────────────

#[test]
fn test_barrier_disabled_returns_immediately() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: false,
    };

    let result = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm).unwrap();

    assert_eq!(
        result,
        DurableAppendResult {
            fsync_applied: false,
            barrier_wait_ms: 0,
        }
    );
    // Record was still appended (RecordedBeforeDispatch)
    assert!(ledger.get("h1").is_some());
    assert_eq!(lm.appends_total(), 1);
    // No barrier wait recorded
    assert_eq!(bm.barrier_wait_count(), 0);
}

#[test]
fn test_barrier_disabled_no_fsync() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default(); // default is disabled

    let result = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm).unwrap();
    assert!(!result.fsync_applied);
}

// ─── Barrier enabled: fsync applied ─────────────────────────────────────

#[test]
fn test_barrier_enabled_fsync_applied() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    let result = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm).unwrap();

    assert!(result.fsync_applied);
    // Record was appended
    assert!(ledger.get("h1").is_some());
    assert_eq!(lm.appends_total(), 1);
    // Barrier wait was recorded
    assert_eq!(bm.barrier_wait_count(), 1);
}

#[test]
fn test_barrier_enabled_records_wait_time() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    // Multiple durable appends
    for i in 0..3 {
        let hash = format!("h{i}");
        let _ = durable_append(&mut ledger, intent(&hash), &config, &mut lm, &mut bm);
    }

    assert_eq!(bm.barrier_wait_count(), 3);
    // barrier_wait_ms_total is >= 0 (in-memory fsync is instant)
    // Just verify it's tracked
    assert!(bm.barrier_wait_ms_total() < 1000); // sanity check
}

// ─── Append failure: error, no block ────────────────────────────────────

#[test]
fn test_queue_full_returns_error_not_block() {
    let mut ledger = WalLedger::new(1);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    // First append succeeds
    let r1 = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm);
    assert!(r1.is_ok());

    // Second append fails — queue full, should not block
    let r2 = durable_append(&mut ledger, intent("h2"), &config, &mut lm, &mut bm);
    assert_eq!(r2, Err(LedgerAppendError::QueueFull));
    assert_eq!(lm.wal_write_errors(), 1);
    assert_eq!(lm.wal_queue_enqueue_failures(), 1);
}

#[test]
fn test_queue_full_increments_wal_write_errors() {
    let mut ledger = WalLedger::new(0);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: false,
    };

    let _ = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm);
    assert_eq!(lm.wal_write_errors(), 1);
    assert_eq!(lm.wal_queue_enqueue_failures(), 1);

    let _ = durable_append(&mut ledger, intent("h2"), &config, &mut lm, &mut bm);
    assert_eq!(lm.wal_write_errors(), 2);
    assert_eq!(lm.wal_queue_enqueue_failures(), 2);
}

#[test]
fn test_queue_full_no_barrier_wait() {
    let mut ledger = WalLedger::new(0);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    let _ = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm);
    // No barrier wait because append failed before reaching barrier
    assert_eq!(bm.barrier_wait_count(), 0);
}

// ─── RecordedBeforeDispatch verified ─────────────────────────────────────

#[test]
fn test_recorded_before_dispatch_on_success() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();

    // Both configs: record must exist after successful durable_append
    for fsync in [false, true] {
        let config = WalBarrierConfig {
            require_wal_fsync_before_dispatch: fsync,
        };
        let hash = format!("h_{fsync}");
        let r = durable_append(&mut ledger, intent(&hash), &config, &mut lm, &mut bm);
        assert!(r.is_ok());
        assert!(
            ledger.get(&hash).is_some(),
            "record must exist after durable_append (fsync={fsync})"
        );
    }
}

// ─── Config default ─────────────────────────────────────────────────────

#[test]
fn test_config_default_disabled() {
    let config = WalBarrierConfig::default();
    assert!(!config.require_wal_fsync_before_dispatch);
}

// ─── Barrier metrics default ─────────────────────────────────────────────

#[test]
fn test_barrier_metrics_default() {
    let m = BarrierMetrics::default();
    assert_eq!(m.barrier_wait_ms_total(), 0);
    assert_eq!(m.barrier_wait_count(), 0);
}

// ─── Multiple appends with mixed configs ─────────────────────────────────

#[test]
fn test_mixed_barrier_configs() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();

    // First: no barrier
    let config_off = WalBarrierConfig {
        require_wal_fsync_before_dispatch: false,
    };
    let r1 = durable_append(&mut ledger, intent("h1"), &config_off, &mut lm, &mut bm).unwrap();
    assert!(!r1.fsync_applied);

    // Second: with barrier
    let config_on = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };
    let r2 = durable_append(&mut ledger, intent("h2"), &config_on, &mut lm, &mut bm).unwrap();
    assert!(r2.fsync_applied);

    assert_eq!(lm.appends_total(), 2);
    assert_eq!(bm.barrier_wait_count(), 1); // only the second had barrier
}

#[test]
fn test_core_wal_gate_adapter_calls_durable_append() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();
    let record = intent("gate-adapter");

    let mut gate = DurableWalGate::new(&mut ledger, &config, &mut lm, &mut bm, record);
    gate.record_before_dispatch()
        .expect("gate append should pass");

    assert!(ledger.get("gate-adapter").is_some());
    assert_eq!(lm.appends_total(), 1);
}
