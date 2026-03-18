//! Tests for Trade-ID Idempotency Registry per CONTRACT.md (Ghost-Race Hardening).
//!
//! AT-269: REST sweeper then WS duplicate ignored.
//! AT-270: Duplicate WS trade is NOOP.

use soldier_infra::{InsertResult, RegistryError, RegistryMetrics, TradeIdRegistry, TradeRecord};

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

// ─── Basic insert + lookup ──────────────────────────────────────────────

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

// ─── AT-270: Duplicate trade ID is NOOP ──────────────────────────────────

#[test]
fn test_at270_duplicate_trade_id_returns_duplicate() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    // First insert succeeds
    let r1 = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(r1, InsertResult::Inserted);

    // Second insert of same trade_id → Duplicate
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

    // Try to insert with different data but same trade_id
    let duplicate = TradeRecord {
        trade_id: "t1".to_string(),
        group_id: "g2".to_string(), // different group
        leg_idx: 1,                 // different leg
        ts: 2000,
        qty: 2.0,
        price: 60000.0,
    };
    let r = reg.insert_if_absent(duplicate, &m).unwrap();
    assert_eq!(r, InsertResult::Duplicate);

    // Original data preserved
    let record = reg.get("t1").unwrap();
    assert_eq!(record.group_id, "g1");
    assert_eq!(record.leg_idx, 0);
}

#[test]
fn test_at270_multiple_duplicates_increment_counter() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    let _ = reg.insert_if_absent(trade("t1", "g1", 0), &m);

    // 3 duplicate attempts
    for _ in 0..3 {
        let r = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
        assert_eq!(r, InsertResult::Duplicate);
    }
    assert_eq!(m.trade_id_duplicates_total(), 3);
    assert_eq!(m.inserts_total(), 1); // only the first one counted
}

// ─── AT-269: REST sweeper then WS duplicate ──────────────────────────────

#[test]
fn test_at269_rest_sweeper_then_ws_duplicate() {
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    // Step 1: REST sweeper processes the trade first
    let rest_result = reg
        .insert_if_absent(trade("trade-42", "g1", 0), &m)
        .unwrap();
    assert_eq!(rest_result, InsertResult::Inserted);

    // Step 2: WS replay delivers the same trade → ignored
    let ws_result = reg
        .insert_if_absent(trade("trade-42", "g1", 0), &m)
        .unwrap();
    assert_eq!(ws_result, InsertResult::Duplicate);

    // Only one insert, one duplicate
    assert_eq!(m.inserts_total(), 1);
    assert_eq!(m.trade_id_duplicates_total(), 1);
    assert_eq!(reg.len(), 1);
}

// ─── Capacity ────────────────────────────────────────────────────────────

#[test]
fn test_capacity_full_returns_error() {
    let reg = TradeIdRegistry::new(1);
    let m = RegistryMetrics::new();

    let _ = reg.insert_if_absent(trade("t1", "g1", 0), &m);

    // Second distinct trade_id fails — capacity full
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

// ─── Multiple distinct trade IDs ─────────────────────────────────────────

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

// ─── Atomic insert-if-absent ─────────────────────────────────────────────

#[test]
fn test_insert_is_atomic_single_operation() {
    // In-memory HashMap insert is inherently atomic for single-threaded access.
    // This test verifies that insert_if_absent does not partially insert.
    let reg = TradeIdRegistry::new(10);
    let m = RegistryMetrics::new();

    // Insert succeeds
    let r1 = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(r1, InsertResult::Inserted);
    assert!(reg.contains("t1"));

    // Immediate re-check is consistent
    let r2 = reg.insert_if_absent(trade("t1", "g1", 0), &m).unwrap();
    assert_eq!(r2, InsertResult::Duplicate);
    assert_eq!(reg.len(), 1);
}

// ─── Empty registry ─────────────────────────────────────────────────────

#[test]
fn test_empty_registry() {
    let reg = TradeIdRegistry::new(10);
    assert!(reg.is_empty());
    assert_eq!(reg.len(), 0);
    assert_eq!(reg.capacity(), 10);
}

// ─── Trade record schema ────────────────────────────────────────────────

#[test]
fn test_trade_record_has_all_required_fields() {
    // CONTRACT.md: trade_id -> {group_id, leg_idx, ts, qty, price}
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

// ─── Metrics default ────────────────────────────────────────────────────

#[test]
fn test_metrics_default() {
    let m = RegistryMetrics::default();
    assert_eq!(m.trade_id_duplicates_total(), 0);
    assert_eq!(m.inserts_total(), 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// Trailing corruption tolerance (TRIP / NON-TRIP pairs per §0.Z.2.2 item A)
// ═══════════════════════════════════════════════════════════════════════════

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

fn temp_registry_path(tag: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "soldier_registry_{tag}_{}_{}.jsonl",
        std::process::id(),
        nanos
    ))
}

fn remove_if_exists(path: &Path) {
    let _ = std::fs::remove_file(path);
}

/// Helper: serialize a TradeRecord as a JSONL line (no trailing newline).
fn trade_line(trade_id: &str, group_id: &str) -> String {
    let record = trade(trade_id, group_id, 0);
    serde_json::to_string(&record).unwrap()
}

/// NON-TRIP: Single trailing corrupt line is tolerated.
/// Valid records before the corruption are loaded.
#[test]
fn test_trailing_corruption_single_line_tolerated() {
    let path = temp_registry_path("trail_single");

    let content = format!(
        "{}\n{}\n{}\n",
        trade_line("t1", "g1"),
        trade_line("t2", "g2"),
        "THIS IS CORRUPT GARBAGE",
    );
    std::fs::write(&path, &content).unwrap();

    let reg =
        TradeIdRegistry::with_storage_path(10, &path).expect("should tolerate trailing corruption");
    assert_eq!(reg.len(), 2);
    assert!(reg.contains("t1"));
    assert!(reg.contains("t2"));

    remove_if_exists(&path);
}

/// NON-TRIP: Multiple trailing corrupt lines (double-crash) are tolerated.
/// Valid records before the corruption are loaded.
#[test]
fn test_trailing_corruption_multiple_lines_tolerated() {
    let path = temp_registry_path("trail_multi");

    let content = format!(
        "{}\n{}\n{}\n{}\n{}\n",
        trade_line("t1", "g1"),
        trade_line("t2", "g2"),
        "CORRUPT LINE FROM CRASH 1",
        "CORRUPT LINE FROM CRASH 2",
        "{\"bad_field\":true}", // also corrupt (missing required fields)
    );
    std::fs::write(&path, &content).unwrap();

    let reg = TradeIdRegistry::with_storage_path(10, &path)
        .expect("should tolerate multiple trailing corrupt lines");
    assert_eq!(reg.len(), 2);
    assert!(reg.contains("t1"));
    assert!(reg.contains("t2"));

    remove_if_exists(&path);
}

/// TRIP: Mid-file corrupt line followed by a valid line → hard error.
/// This proves mid-file corruption is detected and rejected.
#[test]
fn test_midfile_corruption_returns_error() {
    let path = temp_registry_path("midfile_corrupt");

    let content = format!(
        "{}\nCORRUPT MID-FILE LINE\n{}\n",
        trade_line("t1", "g1"),
        trade_line("t2", "g2"),
    );
    std::fs::write(&path, &content).unwrap();

    let result = TradeIdRegistry::with_storage_path(10, &path);
    assert!(
        result.is_err(),
        "mid-file corruption must cause a hard error"
    );
    let err = result.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    let msg = err.to_string();
    assert!(
        msg.contains("invalid trade-id record at line 2"),
        "error should identify the corrupt line number, got: {msg}"
    );
    assert!(
        msg.contains("followed by valid line 3"),
        "error should mention the valid line that proves mid-file corruption, got: {msg}"
    );

    remove_if_exists(&path);
}

/// Edge case: All lines corrupt → empty registry (no valid records, all treated as trailing).
#[test]
fn test_all_lines_corrupt_returns_empty() {
    let path = temp_registry_path("all_corrupt");

    let content = "GARBAGE LINE 1\nGARBAGE LINE 2\n{\"bad\":true}\n";
    std::fs::write(&path, content).unwrap();

    // Sanity: file is non-empty (rules out "reader ignored the file").
    let file_len = std::fs::metadata(&path).unwrap().len();
    assert!(
        file_len > 0,
        "test file must be non-empty to prove reader processed it"
    );

    let reg = TradeIdRegistry::with_storage_path(10, &path)
        .expect("all-corrupt file should be tolerated (all trailing)");
    assert_eq!(reg.len(), 0);
    assert!(reg.is_empty());

    remove_if_exists(&path);
}

/// Round-trip: verify that trade_line() output is parseable by the production reader.
#[test]
fn test_trade_line_round_trip() {
    let path = temp_registry_path("roundtrip");
    let content = format!("{}\n", trade_line("rt1", "g1"));
    std::fs::write(&path, &content).unwrap();

    let reg = TradeIdRegistry::with_storage_path(10, &path)
        .expect("trade_line output must be parseable by production reader");
    assert_eq!(
        reg.len(),
        1,
        "round-trip: registry reader must parse trade_line output as a valid record"
    );
    assert!(reg.contains("rt1"));

    remove_if_exists(&path);
}
