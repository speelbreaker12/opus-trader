#![allow(deprecated)] // WalBarrierConfig is deprecated; tests exercise legacy API
//! Tests for WAL durability barrier per CONTRACT.md §2.4 / §2.4.1.
//!
//! AT-935: RecordedBeforeDispatch + restart → dispatch exactly once.
//! AT-906: WAL enqueue failure blocks OPEN; hot loop continues.

use soldier_core::execution::RecordedBeforeDispatchGate;
use soldier_core::venue::LifecycleIntent;
use soldier_infra::store::{IntentRecord, LedgerAppendError, LedgerMetrics, TlsState, WalLedger};
use soldier_infra::wal::{
    BarrierMetrics, CreatedIntentRecordInput, DurableAppendResult, DurableWalGate,
    WalBarrierConfig, build_created_intent_record, durable_append, try_build_created_intent_record,
};

/// Helper: build a minimal intent record.
fn intent(hash: &str) -> IntentRecord {
    IntentRecord {
        intent_hash: hash.to_string(),
        group_id: "g1".to_string(),
        leg_idx: 0,
        instrument: "BTC-PERP".to_string(),
        side: "buy".to_string(),
        reduce_only: false,
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

fn created_record_input<'a>(
    intent_hash: &'a str,
    lifecycle_intent: LifecycleIntent,
) -> CreatedIntentRecordInput<'a> {
    CreatedIntentRecordInput {
        intent_hash,
        group_id: "g-real",
        leg_idx: 0,
        instrument: "BTC-PERP",
        side: "buy",
        lifecycle_intent,
        qty_q: 1.0,
        limit_price_q: 50_000.0,
        created_ts: 1_000,
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

// ─── Barrier: in-memory ledger has no fsync ──────────────────────────────

#[test]
fn test_in_memory_ledger_no_fsync_applied() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    // In-memory ledger: no durable storage → fsync_applied is false
    // regardless of config flag.
    let result = durable_append(&mut ledger, intent("h1"), &config, &mut lm, &mut bm).unwrap();

    assert!(!result.fsync_applied);
    // Record was still appended (RecordedBeforeDispatch)
    assert!(ledger.get("h1").is_some());
    assert_eq!(lm.appends_total(), 1);
    // No barrier wait for in-memory
    assert_eq!(bm.barrier_wait_count(), 0);
}

#[test]
fn test_in_memory_ledger_no_barrier_wait_time() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    // Multiple durable appends — in-memory, no barrier waits
    for i in 0..3 {
        let hash = format!("h{i}");
        let _ = durable_append(&mut ledger, intent(&hash), &config, &mut lm, &mut bm);
    }

    assert_eq!(bm.barrier_wait_count(), 0);
    assert_eq!(bm.barrier_wait_ms_total(), 0);
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

#[test]
fn test_real_record_construction_persists_reduce_only_by_intent_class() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();

    let cases = [
        ("open", LifecycleIntent::Open, false),
        ("close", LifecycleIntent::Close, true),
        ("hedge", LifecycleIntent::Hedge, true),
    ];

    for (label, lifecycle_intent, expected_reduce_only) in cases {
        let intent_hash = format!("real-path-{label}");
        let record =
            build_created_intent_record(&created_record_input(&intent_hash, lifecycle_intent));
        durable_append(&mut ledger, record, &config, &mut lm, &mut bm).expect("append should work");

        let persisted = ledger
            .get(&intent_hash)
            .expect("record must be persisted in WAL");
        assert_eq!(
            persisted.reduce_only, expected_reduce_only,
            "persisted reduce_only mismatch for {label}"
        );
    }
}

#[test]
fn test_legacy_created_record_constructor_keeps_cancel_compatibility() {
    let record = build_created_intent_record(&created_record_input(
        "cancel-created",
        LifecycleIntent::Cancel,
    ));

    assert!(
        record.reduce_only,
        "cancel compatibility path must remain reduce_only"
    );
    assert_eq!(record.tls_state, TlsState::Created);
}

#[test]
fn test_checked_created_record_rejects_cancel_intent() {
    let error = try_build_created_intent_record(&created_record_input(
        "cancel-created",
        LifecycleIntent::Cancel,
    ))
    .expect_err("cancel intent must not be persisted through the checked constructor");

    assert!(
        format!("{error:?}").contains("Cancel"),
        "expected error to mention cancel intent, got {error:?}"
    );
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

// ─── Multiple appends with mixed configs (in-memory) ─────────────────────

#[test]
fn test_mixed_barrier_configs_in_memory() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();

    // In-memory ledger: fsync_applied is false regardless of config
    let config_off = WalBarrierConfig {
        require_wal_fsync_before_dispatch: false,
    };
    let r1 = durable_append(&mut ledger, intent("h1"), &config_off, &mut lm, &mut bm).unwrap();
    assert!(!r1.fsync_applied);

    let config_on = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };
    let r2 = durable_append(&mut ledger, intent("h2"), &config_on, &mut lm, &mut bm).unwrap();
    assert!(!r2.fsync_applied); // no storage → no fsync

    assert_eq!(lm.appends_total(), 2);
    assert_eq!(bm.barrier_wait_count(), 0); // no storage → no barrier waits
}

// ─── DurableWalGate adapter ─────────────────────────────────────────────

#[test]
fn test_core_wal_gate_adapter_calls_durable_append() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig {
        require_wal_fsync_before_dispatch: true,
    };

    let mut gate = DurableWalGate::new(&mut ledger, &config, &mut lm, &mut bm, intent("gate-h1"));

    // Adapter implements the core trait
    let result = gate.record_before_dispatch();
    assert!(result.is_ok(), "gate adapter must succeed");

    // Verify side effects: record appended
    assert!(gate.ledger().get("gate-h1").is_some());
    assert_eq!(gate.ledger().queue_depth(), 1);
    // In-memory ledger → no barrier wait
    assert_eq!(gate.barrier_metrics().barrier_wait_count(), 0);
}

#[test]
fn test_core_wal_gate_adapter_single_use() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();

    let mut gate =
        DurableWalGate::new(&mut ledger, &config, &mut lm, &mut bm, intent("single-use"));

    // First call consumes the record
    assert!(gate.record_before_dispatch().is_ok());

    // Second call fails — record consumed
    let result = gate.record_before_dispatch();
    assert!(result.is_err(), "second call must fail (single-use)");
}

#[test]
fn test_core_wal_gate_adapter_set_record() {
    let mut ledger = WalLedger::new(10);
    let mut lm = LedgerMetrics::new();
    let mut bm = BarrierMetrics::new();
    let config = WalBarrierConfig::default();

    let mut gate = DurableWalGate::new(&mut ledger, &config, &mut lm, &mut bm, intent("first"));

    assert!(gate.record_before_dispatch().is_ok());

    // Reload with a new record
    gate.set_record(intent("second"));
    assert!(gate.record_before_dispatch().is_ok());

    assert!(gate.ledger().get("first").is_some());
    assert!(gate.ledger().get("second").is_some());
    assert_eq!(gate.ledger().queue_depth(), 2);
}
