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
/// Fields are private to enforce the startup latch contract (AT-430, AT-935):
/// callers MUST call [`acknowledge()`](BootstrapResult::acknowledge) to extract
/// components, which returns the `ReplayOutcome` in the same tuple — forcing
/// the caller to receive it. This makes it a compile-time error to access the
/// ledger or registry without going through the latch-acknowledgement path.
///
/// To wire into `/status` (CONTRACT.md §2.4.1, §7.0):
/// - `wal_queue_depth`: `ledger.queue_depth()`
/// - `wal_queue_capacity`: `ledger.queue_capacity()`
/// - `wal_queue_enqueue_failures`: `ledger_metrics.wal_queue_enqueue_failures()`
#[derive(Debug)]
#[must_use = "BootstrapResult contains replay_outcome needed for startup latch decisions (AT-430) — call .acknowledge()"]
pub struct BootstrapResult {
    ledger: WalLedger,
    ledger_metrics: LedgerMetrics,
    trade_id_registry: TradeIdRegistry,
    trade_id_metrics: RegistryMetrics,
    replay_outcome: ReplayOutcome,
}

impl BootstrapResult {
    /// Inspect the replay outcome without consuming the result.
    ///
    /// Use this to log or make decisions before acknowledging.
    pub fn replay_outcome(&self) -> &ReplayOutcome {
        &self.replay_outcome
    }

    /// Acknowledge the bootstrap result and extract components.
    ///
    /// Returns `(ReplayOutcome, AcknowledgedBootstrap)`. The tuple forces
    /// the caller to receive the replay outcome — the compiler prevents
    /// accessing ledger/registry without going through this path.
    ///
    /// **Caller contract (AT-430, AT-935):**
    /// - After calling this, the caller MUST set
    ///   `open_permission_blocked_latch = true` with reason
    ///   `RESTART_RECONCILE_REQUIRED` on every restart.
    /// - The caller MUST use the returned `ReplayOutcome` (e.g.,
    ///   `in_flight_count > 0`) to decide when reconciliation is mandatory
    ///   before clearing the latch or permitting any dispatch.
    pub fn acknowledge(self) -> (ReplayOutcome, AcknowledgedBootstrap) {
        (
            self.replay_outcome,
            AcknowledgedBootstrap {
                ledger: self.ledger,
                ledger_metrics: self.ledger_metrics,
                trade_id_registry: self.trade_id_registry,
                trade_id_metrics: self.trade_id_metrics,
            },
        )
    }
}

/// Components extracted from [`BootstrapResult::acknowledge()`].
///
/// Only obtainable by going through the acknowledgement path, which
/// ensures the caller has received the `ReplayOutcome` for latch decisions.
#[derive(Debug)]
pub struct AcknowledgedBootstrap {
    pub ledger: WalLedger,
    pub ledger_metrics: LedgerMetrics,
    pub trade_id_registry: TradeIdRegistry,
    pub trade_id_metrics: RegistryMetrics,
}

const MIN_CAPACITY: usize = 10;
const CAPACITY_WARN_PCT: usize = 70;

/// Initialize durable WAL ledger and trade-ID registry.
///
/// **This function performs blocking I/O** (directory creation, file open,
/// WAL replay). Call at startup, not from an async runtime without
/// `spawn_blocking`.
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
/// # Capacity enforcement
///
/// Capacity overflow (existing records > configured capacity) is enforced by
/// `WalLedger::with_storage_path` and `TradeIdRegistry::with_storage_path`
/// during construction. This function delegates to those constructors and
/// does not perform a redundant post-replay check.
///
/// # Errors
///
/// Returns `Err` if:
/// - `data_dir` is not an absolute path
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
            if self.0.exists() {
                if let Err(e) = std::fs::remove_dir_all(&self.0) {
                    tracing::warn!(
                        path = %self.0.display(),
                        error = %e,
                        "test cleanup failed"
                    );
                }
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

        // Acknowledge and extract components (typestate enforcement)
        let (outcome, boot) = result.acknowledge();

        // Verify replay is empty (fresh storage)
        assert_eq!(outcome.records_replayed, 0);
        assert_eq!(outcome.in_flight_count, 0);
        assert!(boot.trade_id_registry.is_empty());

        // Verify metrics are freshly initialized
        assert_eq!(boot.ledger.queue_depth(), 0);
        assert_eq!(boot.ledger.queue_capacity(), 100);
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
            let (_, mut boot) = bootstrap_storage(&config)
                .expect("first bootstrap")
                .acknowledge();
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
            boot.ledger
                .append(record, &mut boot.ledger_metrics)
                .expect("append should succeed");
            assert_eq!(boot.ledger.queue_depth(), 1);
        }

        // Second bootstrap: should replay the appended intent
        {
            let (outcome, boot) = bootstrap_storage(&config)
                .expect("second bootstrap")
                .acknowledge();
            assert_eq!(outcome.records_replayed, 1);
            assert_eq!(outcome.in_flight_count, 1);
            assert!(boot.ledger.get("test-hash-001").is_some());
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
        let (_, boot) = bootstrap_storage(&config)
            .expect("exact MIN_CAPACITY should succeed")
            .acknowledge();
        assert_eq!(boot.ledger.queue_capacity(), 10);
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
            let (_, mut boot) = bootstrap_storage(&config)
                .expect("first bootstrap")
                .acknowledge();
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
            boot.ledger
                .append(record, &mut boot.ledger_metrics)
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
            let (outcome, boot) = bootstrap_storage(&config)
                .expect("recovery bootstrap")
                .acknowledge();
            assert_eq!(outcome.records_replayed, 1);
            assert!(boot.ledger.get("partial-test-001").is_some());
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
            let (_, mut boot) = bootstrap_storage(&config)
                .expect("first bootstrap")
                .acknowledge();
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
                boot.ledger
                    .append(record, &mut boot.ledger_metrics)
                    .expect("append");
            }
            assert_eq!(boot.ledger.queue_depth(), 15);
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

    #[test]
    fn bootstrap_fails_when_trade_id_capacity_reduced_below_existing() {
        let data_dir = unique_temp_dir("tid_cap_reduce");
        let _guard = TempDirGuard(data_dir.clone());

        // First bootstrap: insert 12 trade IDs
        {
            let config = StorageConfig {
                data_dir: data_dir.clone(),
                wal_capacity: 100,
                trade_id_capacity: 50,
            };
            let (_, boot) = bootstrap_storage(&config)
                .expect("first bootstrap")
                .acknowledge();
            use crate::store::trade_id_registry::TradeRecord;
            let metrics = &boot.trade_id_metrics;
            for i in 0..12 {
                let record = TradeRecord {
                    trade_id: format!("tid-reduce-{i:03}"),
                    group_id: "g1".to_string(),
                    leg_idx: 0,
                    ts: 1_000_000 + i as u64,
                    qty: 1.0,
                    price: 100.0,
                };
                boot.trade_id_registry
                    .insert_if_absent(record, metrics)
                    .expect("insert");
            }
            assert_eq!(boot.trade_id_registry.len(), 12);
        }

        // Second bootstrap with trade_id_capacity=10 — should fail (12 > 10)
        let config = StorageConfig {
            data_dir,
            wal_capacity: 100,
            trade_id_capacity: 10,
        };
        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("trade-id registry"));
    }

    #[test]
    fn bootstrap_high_capacity_does_not_panic() {
        // Exercises the 70% capacity warning code path.
        // With capacity=10 and 8 intents, depth_pct = 80% >= 70%.
        let data_dir = unique_temp_dir("high_cap_warn");
        let _guard = TempDirGuard(data_dir.clone());

        // First bootstrap: write 8 intents into capacity=10
        {
            let config = StorageConfig {
                data_dir: data_dir.clone(),
                wal_capacity: 10,
                trade_id_capacity: 10,
            };
            let (_, mut boot) = bootstrap_storage(&config)
                .expect("first bootstrap")
                .acknowledge();
            use crate::store::ledger::{IntentRecord, TlsState};
            for i in 0..8 {
                let record = IntentRecord {
                    intent_hash: format!("warn-test-{i:03}"),
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
                boot.ledger
                    .append(record, &mut boot.ledger_metrics)
                    .expect("append");
            }
        }

        // Second bootstrap: replay triggers depth_pct = 80% >= CAPACITY_WARN_PCT
        let config = StorageConfig {
            data_dir,
            wal_capacity: 10,
            trade_id_capacity: 10,
        };
        let result = bootstrap_storage(&config).expect("should succeed despite high capacity");
        // Verify via replay_outcome before acknowledging
        assert_eq!(result.replay_outcome().in_flight_count, 8);

        let (outcome, boot) = result.acknowledge();
        // Verify the capacity warning branch is reachable and doesn't panic.
        // Use queue_depth (the actual metric used in bootstrap_storage) rather
        // than in_flight_count as proxy.
        let depth = boot.ledger.queue_depth();
        let capacity = boot.ledger.queue_capacity();
        let depth_pct = depth * 100 / capacity;
        assert_eq!(outcome.in_flight_count, 8);
        assert!(
            depth_pct >= CAPACITY_WARN_PCT,
            "test setup error: depth_pct={depth_pct} should be >= {CAPACITY_WARN_PCT}"
        );
    }
}
