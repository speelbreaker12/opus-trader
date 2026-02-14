//! Tests for Trade-ID Idempotency Registry per CONTRACT.md.
//!
//! AT-269: REST sweeper then WS duplicate ignored.
//! AT-270: Duplicate WS trade is NOOP.

use std::sync::{Arc, Barrier};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use soldier_infra::store::{
    InsertResult, RegistryError, RegistryMetrics, TradeIdRegistry, TradeRecord,
};

/// Helper: build a minimal trade record.
fn trade(trade_id: &str, group_id: &str, leg_idx: u32) -> TradeRecord {
    TradeRecord {
        trade_id: trade_id.to_string(),
        group_id: group_id.to_string(),
        leg_idx,
        ts: 1000,
        qty: 1.0,
        price: 50000.0,
    }
}

fn temp_registry_path(tag: &str) -> std::path::PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "soldier_trade_registry_{tag}_{}_{}.jsonl",
        std::process::id(),
        nanos
    ))
}

fn remove_if_exists(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
}

// --- Basic insert + lookup ---------------------------------------------

#[test]
fn test_insert_new_trade_id() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let result = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(result, InsertResult::Inserted);
    assert_eq!(m.inserts_total(), 1);
    assert_eq!(m.trade_id_duplicates_total(), 0);
}

#[test]
fn test_lookup_after_insert() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let _ = reg.insert_if_absent(trade("t1", "g1", 0), &m);
    assert!(reg.contains("t1"));

    let record = reg.get("t1").unwrap();
    assert_eq!(record.trade_id, "t1");
    assert_eq!(record.group_id, "g1");
    assert_eq!(record.leg_idx, 0);
}

#[test]
fn test_lookup_missing_returns_none() {
    let reg = TradeIdRegistry::new(10);
    assert!(!reg.contains("nonexistent"));
    assert!(reg.get("nonexistent").is_none());
}

#[test]
fn test_durable_registry_persists_across_restart() {
    let path = temp_registry_path("restart");

    {
        let reg = TradeIdRegistry::with_storage_path(10, &path).expect("open durable registry");
        let m = RegistryMetrics::new();
        let result = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
        assert_eq!(result, InsertResult::Inserted);
    }

    {
        let reg = TradeIdRegistry::with_storage_path(10, &path).expect("reopen durable registry");
        let m = RegistryMetrics::new();
        assert!(reg.contains("t1"));
        let result = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
        assert_eq!(result, InsertResult::Duplicate);
    }

    remove_if_exists(&path);
}

#[test]
fn test_durable_registry_appends_record_to_disk() {
    let path = temp_registry_path("append");

    {
        let reg = TradeIdRegistry::with_storage_path(10, &path).expect("open durable registry");
        let m = RegistryMetrics::new();
        let result = reg
            .insert_if_absent(trade("trade-789", "g1", 0), &m)
            .unwrap();
        assert_eq!(result, InsertResult::Inserted);
    }

    let contents = std::fs::read_to_string(&path).expect("read durable registry file");
    assert!(contents.contains("\"trade_id\":\"trade-789\""));
    remove_if_exists(&path);
}

#[test]
fn test_durable_registry_fails_closed_on_corrupt_file() {
    let path = temp_registry_path("corrupt");
    std::fs::write(&path, "not-json\n").expect("write corrupt durable registry file");

    let result = TradeIdRegistry::with_storage_path(10, &path);
    assert!(result.is_err(), "corrupt durable registry must fail closed");
    remove_if_exists(&path);
}

// --- AT-270: Duplicate trade ID is NOOP --------------------------------

#[test]
fn test_at270_duplicate_trade_id_returns_duplicate() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    // First insert succeeds.
    let r1 = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(r1, InsertResult::Inserted);

    // Second insert of same trade_id -> Duplicate.
    let r2 = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(r2, InsertResult::Duplicate);
    assert_eq!(m.trade_id_duplicates_total(), 1);
}

#[test]
fn test_at270_duplicate_does_not_overwrite() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let original = TradeRecord {
        trade_id: "t1".to_string(),
        group_id: "g1".to_string(),
        leg_idx: 0,
        ts: 1000,
        qty: 1.0,
        price: 50000.0,
    };
    let _ = reg.insert_if_absent(original, &m);

    let duplicate = TradeRecord {
        trade_id: "t1".to_string(),
        group_id: "g2".to_string(),
        leg_idx: 1,
        ts: 2000,
        qty: 2.0,
        price: 60000.0,
    };
    let r = reg.insert_if_absent(duplicate, &m).unwrap();
    assert_eq!(r, InsertResult::Duplicate);

    let record = reg.get("t1").unwrap();
    assert_eq!(record.group_id, "g1");
    assert_eq!(record.leg_idx, 0);
}

#[test]
fn test_at270_multiple_duplicates_increment_counter() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let _ = reg.insert_if_absent(trade("t1", "g1", 0), &m);

    for _ in 0..3 {
        let r = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
        assert_eq!(r, InsertResult::Duplicate);
    }
    assert_eq!(m.trade_id_duplicates_total(), 3);
    assert_eq!(m.inserts_total(), 1);
}

// --- AT-269: REST sweeper then WS duplicate ----------------------------

#[test]
fn test_at269_rest_sweeper_then_ws_duplicate() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let rest_result = reg
        .insert_if_absent(trade("trade-42", "g1", 0), &m)
        .unwrap();
    assert_eq!(rest_result, InsertResult::Inserted);

    let ws_result = reg
        .insert_if_absent(trade("trade-42", "g1", 0), &m)
        .unwrap();
    assert_eq!(ws_result, InsertResult::Duplicate);

    assert_eq!(m.inserts_total(), 1);
    assert_eq!(m.trade_id_duplicates_total(), 1);
    assert_eq!(reg.len(), 1);
}

// --- Capacity -----------------------------------------------------------

#[test]
fn test_capacity_full_returns_error() {
    let reg = TradeIdRegistry::new(1);
    let m = RegistryMetrics::new();

    let _ = reg.insert_if_absent(trade("t1", "g1", 0), &m);

    let result = reg.insert_if_absent(trade("t2", "g2", 0), &m);
    assert_eq!(result, Err(RegistryError::CapacityFull));
    assert!(!reg.contains("t2"));
}

#[test]
fn test_zero_capacity() {
    let reg = TradeIdRegistry::new(0);
    let m = RegistryMetrics::new();

    let result = reg.insert_if_absent(trade("t1", "g1", 0), &m);
    assert_eq!(result, Err(RegistryError::CapacityFull));
}

// --- Multiple distinct trade IDs ---------------------------------------

#[test]
fn test_multiple_distinct_trade_ids() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    for i in 0..5 {
        let id = format!("t{i}");
        let r = reg
            .insert_if_absent(trade(&id, "g1", i as u32), &m)
            .unwrap();
        assert_eq!(r, InsertResult::Inserted);
    }

    assert_eq!(reg.len(), 5);
    assert_eq!(m.inserts_total(), 5);
    assert_eq!(m.trade_id_duplicates_total(), 0);

    for i in 0..5 {
        let id = format!("t{i}");
        assert!(reg.contains(&id));
    }
}

// --- Concurrency atomicity ---------------------------------------------

#[test]
fn test_concurrent_same_trade_id_only_one_insert_wins() {
    let workers = 16;
    let reg = Arc::new(TradeIdRegistry::new(64));
    let metrics = Arc::new(RegistryMetrics::new());
    let barrier = Arc::new(Barrier::new(workers));

    let mut handles = Vec::new();
    for _ in 0..workers {
        let reg = Arc::clone(&reg);
        let metrics = Arc::clone(&metrics);
        let barrier = Arc::clone(&barrier);
        handles.push(thread::spawn(move || {
            barrier.wait();
            reg.insert_if_absent(trade("race-trade", "g1", 0), metrics.as_ref())
                .expect("insert_if_absent should not fail")
        }));
    }

    let mut inserted = 0usize;
    let mut duplicate = 0usize;
    for handle in handles {
        match handle.join().expect("worker panicked") {
            InsertResult::Inserted => inserted += 1,
            InsertResult::Duplicate => duplicate += 1,
        }
    }

    assert_eq!(inserted, 1, "exactly one thread should win insert");
    assert_eq!(duplicate, workers - 1, "all other inserts must dedupe");
    assert_eq!(reg.len(), 1, "only one stored trade id expected");
    assert_eq!(metrics.inserts_total(), 1);
    assert_eq!(metrics.trade_id_duplicates_total(), (workers - 1) as u64);
}

// --- Empty registry -----------------------------------------------------

#[test]
fn test_empty_registry() {
    let reg = TradeIdRegistry::new(10);
    assert!(reg.is_empty());
    assert_eq!(reg.len(), 0);
    assert_eq!(reg.capacity(), 10);
}

// --- Trade record schema ------------------------------------------------

#[test]
fn test_trade_record_has_all_required_fields() {
    let r = TradeRecord {
        trade_id: "t1".to_string(),
        group_id: "g1".to_string(),
        leg_idx: 0,
        ts: 1000,
        qty: 1.5,
        price: 50000.0,
    };

    assert_eq!(r.trade_id, "t1");
    assert_eq!(r.group_id, "g1");
    assert_eq!(r.leg_idx, 0);
    assert_eq!(r.ts, 1000);
    assert!((r.qty - 1.5).abs() < 1e-9);
    assert!((r.price - 50000.0).abs() < 1e-9);
}

// --- Metrics default ----------------------------------------------------

#[test]
fn test_metrics_default() {
    let m = RegistryMetrics::default();
    assert_eq!(m.trade_id_duplicates_total(), 0);
    assert_eq!(m.inserts_total(), 0);
}
