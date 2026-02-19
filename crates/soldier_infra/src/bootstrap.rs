//! Durable storage bootstrap per CONTRACT.md §2.4.
//!
//! Provides `StorageConfig` and `bootstrap_storage()` for wiring the WAL ledger
//! and trade-ID registry from a single configuration source.

use std::io;
use std::path::PathBuf;

use crate::store::{LedgerMetrics, RegistryMetrics, TradeIdRegistry, WalLedger};

/// Durable storage configuration per CONTRACT.md §2.4.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StorageConfig {
    /// Root directory for all durable storage files.
    pub data_dir: PathBuf,
    /// Maximum number of intent records in the WAL ledger.
    pub wal_capacity: usize,
    /// Maximum number of trade IDs in the idempotency registry.
    pub trade_id_capacity: usize,
}

/// Result of bootstrapping durable storage.
#[derive(Debug)]
pub struct BootstrapResult {
    pub ledger: WalLedger,
    pub ledger_metrics: LedgerMetrics,
    pub trade_id_registry: TradeIdRegistry,
    pub trade_id_metrics: RegistryMetrics,
}

/// Initialize durable WAL ledger and trade-ID registry.
///
/// Derived paths:
/// - `{data_dir}/wal/intents.jsonl`
/// - `{data_dir}/wal/trade_ids.jsonl`
///
/// Pre-creates the `{data_dir}/wal/` directory before opening storage files.
pub fn bootstrap_storage(config: &StorageConfig) -> io::Result<BootstrapResult> {
    if config.wal_capacity == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "wal_capacity must be >= 1",
        ));
    }
    if config.trade_id_capacity == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "trade_id_capacity must be >= 1",
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
            tracing::error!(error = %e, path = %intents_path.display(), "WAL ledger init failed");
            return Err(e);
        }
    };

    let trade_id_registry =
        match TradeIdRegistry::with_storage_path(config.trade_id_capacity, &trade_ids_path) {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(
                    error = %e,
                    path = %trade_ids_path.display(),
                    "trade-ID registry init failed"
                );
                return Err(e);
            }
        };

    Ok(BootstrapResult {
        ledger,
        ledger_metrics: LedgerMetrics::new(),
        trade_id_registry,
        trade_id_metrics: RegistryMetrics::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(test_name: &str) -> PathBuf {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        std::env::temp_dir().join(format!("bootstrap_test_{test_name}_{ts}"))
    }

    #[test]
    fn bootstrap_happy_path_creates_files() {
        let data_dir = unique_temp_dir("happy_path");
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
        let replay = result.ledger.replay();
        assert_eq!(replay.records_replayed, 0);
        assert_eq!(replay.in_flight_count, 0);

        assert!(result.trade_id_registry.is_empty());

        // Cleanup
        let _ = std::fs::remove_dir_all(&data_dir);
    }

    #[test]
    fn bootstrap_second_call_replays_existing() {
        let data_dir = unique_temp_dir("replay");
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
            let replay = result.ledger.replay();
            assert_eq!(replay.records_replayed, 1);
            assert_eq!(replay.in_flight_count, 1);
            assert!(result.ledger.get("test-hash-001").is_some());
        }

        // Cleanup
        let _ = std::fs::remove_dir_all(&data_dir);
    }

    #[test]
    fn bootstrap_rejects_zero_wal_capacity() {
        let data_dir = unique_temp_dir("zero_wal");
        let config = StorageConfig {
            data_dir,
            wal_capacity: 0,
            trade_id_capacity: 50,
        };

        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("wal_capacity"));
    }

    #[test]
    fn bootstrap_rejects_zero_trade_id_capacity() {
        let data_dir = unique_temp_dir("zero_tid");
        let config = StorageConfig {
            data_dir,
            wal_capacity: 100,
            trade_id_capacity: 0,
        };

        let err = bootstrap_storage(&config).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        assert!(err.to_string().contains("trade_id_capacity"));
    }
}
