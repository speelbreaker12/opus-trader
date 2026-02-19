//! Durable storage bootstrap per CONTRACT.md §2.4.
//!
//! Provides `StorageConfig` and `bootstrap_storage()` for wiring the WAL ledger
//! and trade-ID registry from a single configuration source.
//!
//! # Safety contract for callers
//!
//! After a successful `bootstrap_storage()`, the caller MUST:
//! 1. Set `open_permission_blocked_latch = true` with reason
//!    `RESTART_RECONCILE_REQUIRED` (CONTRACT.md §2.2.4, AT-430).
//! 2. Complete reconciliation before permitting any dispatch.
//! 3. Wire `BootstrapResult.replay_outcome` into the startup latch
//!    decision — if `in_flight_count > 0`, reconciliation is mandatory.
//!
//! Failure to set the startup latch allows OPEN intents before
//! reconciliation, violating AT-935.

use std::io;
use std::path::PathBuf;

use crate::store::{LedgerMetrics, RegistryMetrics, ReplayOutcome, TradeIdRegistry, WalLedger};

/// Durable storage configuration per CONTRACT.md §2.4.
///
/// `wal_capacity` and `trade_id_capacity` count total records including
/// terminal intents. Long-running processes should set capacity high
/// enough to accommodate peak concurrency plus terminal accumulation
/// between compaction runs (no compaction in Phase 1).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StorageConfig {
    /// Root directory for all durable storage files.
    /// Must be on a local, durable (journaling) filesystem — not tmpfs or NFS.
    pub data_dir: PathBuf,
    /// Maximum number of intent records in the WAL ledger.
    /// Must be >= 10.
    pub wal_capacity: usize,
    /// Maximum number of trade IDs in the idempotency registry.
    /// Must be >= 10.
    pub trade_id_capacity: usize,
}

/// Result of bootstrapping durable storage.
///
/// To wire into `/status` (CONTRACT.md §2.4.1, §7.0):
/// - `wal_queue_depth`: `ledger.queue_depth()`
/// - `wal_queue_capacity`: `ledger.queue_capacity()`
/// - `wal_queue_enqueue_failures`: `ledger_metrics.wal_queue_enqueue_failures()`
#[derive(Debug)]
pub struct BootstrapResult {
    pub ledger: WalLedger,
    pub ledger_metrics: LedgerMetrics,
    pub trade_id_registry: TradeIdRegistry,
    pub trade_id_metrics: RegistryMetrics,
    /// Replay outcome from WAL initialization. Use this to determine
    /// whether reconciliation is needed before permitting dispatch.
    pub replay_outcome: ReplayOutcome,
}

const MIN_CAPACITY: usize = 10;
const CAPACITY_WARN_PCT: usize = 70;

/// Initialize durable WAL ledger and trade-ID registry.
///
/// Derived paths:
/// - `{data_dir}/wal/intents.jsonl`
/// - `{data_dir}/wal/trade_ids.jsonl`
///
/// Pre-creates the `{data_dir}/wal/` directory before opening storage files.
/// This is defense-in-depth: the stores also call `create_dir_all` internally,
/// but we create the root early to surface permission errors before touching
/// either store.
///
/// # Errors
///
/// Returns `Err` if:
/// - Capacity is below minimum (10)
/// - Directory creation fails (permissions, disk full)
/// - WAL or registry file open/replay fails
/// - WAL contains more intents than configured capacity
///
/// On error, no partial state is leaked to the caller. The WAL file may
/// exist on disk but is append-only and replay-converging — a subsequent
/// successful bootstrap will correctly replay it.
pub fn bootstrap_storage(config: &StorageConfig) -> io::Result<BootstrapResult> {
    if !config.data_dir.is_absolute() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "data_dir must be an absolute path (got {:?})",
                config.data_dir
            ),
        ));
    }
    if config.wal_capacity < MIN_CAPACITY {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "wal_capacity must be >= {} (got {})",
                MIN_CAPACITY, config.wal_capacity
            ),
        ));
    }
    if config.trade_id_capacity < MIN_CAPACITY {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "trade_id_capacity must be >= {} (got {})",
                MIN_CAPACITY, config.trade_id_capacity
            ),
        ));
    }

    let wal_dir = config.data_dir.join("wal");
    std::fs::create_dir_all(&wal_dir)?;

    let intents_path = wal_dir.join("intents.jsonl");
    let trade_ids_path = wal_dir.join("trade_ids.jsonl");

    tracing::info!(
        data_dir = %config.data_dir.display(),
        wal_capacity = config.wal_capacity,
        trade_id_capacity = config.trade_id_capacity,
        "bootstrapping durable storage"
    );

    let ledger = match WalLedger::with_storage_path(config.wal_capacity, &intents_path) {
        Ok(l) => l,
        Err(e) => {
            tracing::error!(
                error = %e,
                error_kind = ?e.kind(),
                path = %intents_path.display(),
                "WAL ledger init failed"
            );
            return Err(e);
        }
    };

    // Surface replay outcome before attempting registry init.
    let replay_outcome = ledger.replay();
    let depth = ledger.queue_depth();
    let capacity = ledger.queue_capacity();
    let depth_pct = if capacity > 0 {
        depth * 100 / capacity
    } else {
        0
    };

    tracing::info!(
        records_replayed = replay_outcome.records_replayed,
        in_flight_count = replay_outcome.in_flight_count,
        queue_depth = depth,
        queue_capacity = capacity,
        queue_depth_pct = depth_pct,
        "WAL replay complete"
    );

    if depth_pct >= CAPACITY_WARN_PCT {
        tracing::warn!(
            queue_depth = depth,
            queue_capacity = capacity,
            queue_depth_pct = depth_pct,
            "WAL replay at high capacity — new OPEN intents may be rejected soon"
        );
    }

    let trade_id_registry =
        match TradeIdRegistry::with_storage_path(config.trade_id_capacity, &trade_ids_path) {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(
                    error = %e,
                    error_kind = ?e.kind(),
                    path = %trade_ids_path.display(),
                    wal_init_succeeded = true,
                    "trade-ID registry init failed after WAL init succeeded — \
                     partial init is safe (WAL is append-only, replay-converging)"
                );
                return Err(e);
            }
        };

    tracing::info!(
        trade_ids_loaded = trade_id_registry.len(),
        "trade-ID registry loaded"
    );

    Ok(BootstrapResult {
        ledger,
        ledger_metrics: LedgerMetrics::new(),
        trade_id_registry,
        trade_id_metrics: RegistryMetrics::new(),
        replay_outcome,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(test_name: &str) -> PathBuf {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            // Test-only: system clock should always be after epoch.
            .expect("system clock before UNIX epoch")
            .as_nanos();
        let tid = std::thread::current().id();
        std::env::temp_dir().join(format!("bootstrap_test_{test_name}_{ts}_{tid:?}"))
    }

    /// RAII guard for test temp directories — cleans up even on panic.
    struct TempDirGuard(PathBuf);
    impl Drop for TempDirGuard {
        fn drop(&mut self) {
            if let Err(e) = std::fs::remove_dir_all(&self.0) {
                eprintln!("test cleanup failed for {}: {e}", self.0.display());
            }
        }
    }

    #[test]
    fn bootstrap_happy_path_creates_files() {
        let data_dir = unique_temp_dir("happy_path");
        let _guard = TempDirGuard(data_dir.clone());
        let config = StorageConfig {
            data_dir: data_dir.clone(),
            wal_capacity: 100,
            trade_id_capacity: 50,
        };

        let result = bootstrap_storage(&config).expect("bootstrap should succeed");

        // Verify files exist
        assert!(data_dir.join("wal/intents.jsonl").exists());
        assert!(data_dir.join("wal/trade_ids.jsonl").exists());

        // Verify replay is empty (fresh storage)
        assert_eq!(result.replay_outcome.records_replayed, 0);
        assert_eq!(result.replay_outcome.in_flight_count, 0);
        assert!(result.trade_id_registry.is_empty());

        // Verify metrics are freshly initialized
        assert_eq!(result.ledger.queue_depth(), 0);
        assert_eq!(result.ledger.queue_capacity(), 100);
    }

    #[test]
    fn bootstrap_second_call_replays_existing() {
        let data_dir = unique_temp_dir("replay");
        let _guard = TempDirGuard(data_dir.clone());
        let config = StorageConfig {
            data_dir: data_dir.clone(),
            wal_capacity: 100,
            trade_id_capacity: 50,
        };

        // First bootstrap: append an intent
        {
            let mut result = bootstrap_storage(&config).expect("first bootstrap");
            use crate::store::ledger::{IntentRecord, TlsState};
            let record = IntentRecord {
                intent_hash: "test-hash-001".to_string(),
                group_id: "g1".to_string(),
                leg_idx: 0,
                instrument: "BTC-PERPETUAL".to_string(),
                side: "buy".to_string(),
                qty_q: 1.0,
                limit_price_q: 100.0,
                tls_state: TlsState::Created,
                created_ts: 1_000_000,
                sent_ts: 0,
                ack_ts: 0,
                last_fill_ts: 0,
                exchange_order_id: None,
                last_trade_id: None,
            };
            result
                .ledger
                .append(record, &mut result.ledger_metrics)
                .expect("append should succeed");
            assert_eq!(result.ledger.queue_depth(), 1);
        }

        // Second bootstrap: should replay the appended intent
        {
            let result = bootstrap_storage(&config).expect("second bootstrap");
            assert_eq!(result.replay_outcome.records_replayed, 1);
            assert_eq!(result.replay_outcome.in_flight_count, 1);
            assert!(result.ledger.get("test-hash-001").is_some());
        }
    }

    #[test]
    fn bootstrap_rejects_capacity_below_minimum() {
        let data_dir = unique_temp_dir("low_cap");
        let _guard = TempDirGuard(data_dir.clone());

        // wal_capacity too low
        let config = StorageConfig {
            data_dir: data_dir.clone(),
            wal_capacity: 5,
            trade_id_capacity: 50,
        };
        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("wal_capacity"));

        // trade_id_capacity too low
        let config = StorageConfig {
            data_dir,
            wal_capacity: 100,
            trade_id_capacity: 3,
        };
        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("trade_id_capacity"));
    }

    #[test]
    fn bootstrap_accepts_exact_min_capacity() {
        let data_dir = unique_temp_dir("exact_min_cap");
        let _guard = TempDirGuard(data_dir.clone());
        let config = StorageConfig {
            data_dir,
            wal_capacity: 10,
            trade_id_capacity: 10,
        };
        let result = bootstrap_storage(&config).expect("exact MIN_CAPACITY should succeed");
        assert_eq!(result.ledger.queue_capacity(), 10);
    }

    #[test]
    fn bootstrap_rejects_relative_data_dir() {
        let config = StorageConfig {
            data_dir: PathBuf::from("relative/path/data"),
            wal_capacity: 100,
            trade_id_capacity: 50,
        };
        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("absolute path"));
    }

    #[test]
    fn bootstrap_fails_on_unwritable_dir() {
        // Use a path that cannot exist on any OS
        let config = StorageConfig {
            data_dir: PathBuf::from("/nonexistent_root_abc_xyz_123/data"),
            wal_capacity: 100,
            trade_id_capacity: 50,
        };

        let err = bootstrap_storage(&config).unwrap_err();
        // Should be an I/O error, not a panic. The exact ErrorKind varies
        // by OS (NotFound on Linux, PermissionDenied or Other on macOS).
        assert!(
            err.kind() != io::ErrorKind::InvalidInput,
            "expected filesystem error, got validation error: {err}"
        );
    }

    #[test]
    fn partial_init_wal_ok_registry_fails_then_recovers() {
        let data_dir = unique_temp_dir("partial_init");
        let _guard = TempDirGuard(data_dir.clone());

        // First: successful bootstrap + append an intent
        {
            let config = StorageConfig {
                data_dir: data_dir.clone(),
                wal_capacity: 100,
                trade_id_capacity: 50,
            };
            let mut result = bootstrap_storage(&config).expect("first bootstrap");
            use crate::store::ledger::{IntentRecord, TlsState};
            let record = IntentRecord {
                intent_hash: "partial-test-001".to_string(),
                group_id: "g1".to_string(),
                leg_idx: 0,
                instrument: "ETH-PERPETUAL".to_string(),
                side: "sell".to_string(),
                qty_q: 2.0,
                limit_price_q: 3000.0,
                tls_state: TlsState::Created,
                created_ts: 2_000_000,
                sent_ts: 0,
                ack_ts: 0,
                last_fill_ts: 0,
                exchange_order_id: None,
                last_trade_id: None,
            };
            result
                .ledger
                .append(record, &mut result.ledger_metrics)
                .expect("append");
        }

        // Second: simulate registry failure by making trade_ids.jsonl
        // a directory (which will cause open to fail).
        let trade_ids_path = data_dir.join("wal/trade_ids.jsonl");
        std::fs::remove_file(&trade_ids_path).ok();
        std::fs::create_dir_all(&trade_ids_path).expect("create dir as file");

        {
            let config = StorageConfig {
                data_dir: data_dir.clone(),
                wal_capacity: 100,
                trade_id_capacity: 50,
            };
            let err = bootstrap_storage(&config);
            assert!(
                err.is_err(),
                "should fail when registry path is a directory"
            );
        }

        // Third: fix the path and verify WAL data survived
        std::fs::remove_dir_all(&trade_ids_path).ok();

        {
            let config = StorageConfig {
                data_dir,
                wal_capacity: 100,
                trade_id_capacity: 50,
            };
            let result = bootstrap_storage(&config).expect("recovery bootstrap");
            assert_eq!(result.replay_outcome.records_replayed, 1);
            assert!(result.ledger.get("partial-test-001").is_some());
        }
    }

    #[test]
    fn bootstrap_fails_when_capacity_reduced_below_existing_records() {
        let data_dir = unique_temp_dir("cap_reduce");
        let _guard = TempDirGuard(data_dir.clone());

        // First bootstrap with large capacity, write 15 intents
        {
            let config = StorageConfig {
                data_dir: data_dir.clone(),
                wal_capacity: 100,
                trade_id_capacity: 50,
            };
            let mut result = bootstrap_storage(&config).expect("first bootstrap");
            use crate::store::ledger::{IntentRecord, TlsState};
            for i in 0..15 {
                let record = IntentRecord {
                    intent_hash: format!("cap-reduce-{i:03}"),
                    group_id: "g1".to_string(),
                    leg_idx: 0,
                    instrument: "BTC-PERPETUAL".to_string(),
                    side: "buy".to_string(),
                    qty_q: 1.0,
                    limit_price_q: 100.0,
                    tls_state: TlsState::Created,
                    created_ts: 1_000_000 + i as u64,
                    sent_ts: 0,
                    ack_ts: 0,
                    last_fill_ts: 0,
                    exchange_order_id: None,
                    last_trade_id: None,
                };
                result
                    .ledger
                    .append(record, &mut result.ledger_metrics)
                    .expect("append");
            }
            assert_eq!(result.ledger.queue_depth(), 15);
        }

        // Second bootstrap with capacity=10 — should fail because 15 > 10
        let config = StorageConfig {
            data_dir,
            wal_capacity: 10,
            trade_id_capacity: 50,
        };
        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
    }
}
