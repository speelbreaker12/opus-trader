//! Appendix A configuration defaults (safety-critical thresholds).
//!
//! CONTRACT.md Appendix A defines default values for safety-critical parameters.
//! If a parameter is missing at runtime and has an Appendix A default, that default
//! is applied. If no default exists, the system MUST fail-closed.

use std::fmt;

/// All safety-critical configuration parameters from CONTRACT.md Appendix A.
///
/// Each variant maps to a row in the A.7 Summary Table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ConfigParam {
    // A.1 Atomic Group Execution
    AtomicQtyEpsilon,
    InstrumentCacheTtlS,
    ContractsAmountMatchTolerance,

    // A.1.1 Inventory Skew Gate
    InventorySkewK,
    InventorySkewTickPenaltyMax,
    RescueCrossSpreadTicks,

    // A.2 Reflexive Cortex
    SpreadMaxBps,
    SpreadKillBps,
    DepthMin,
    DepthKillMin,
    CortexKillWindowS,
    DvolJumpPct,
    DvolJumpWindowS,
    DvolCooldownS,
    SpreadDepthCooldownS,

    // A.2 Basis Monitor
    BasisPriceMaxAgeMs,
    BasisReduceonlyBps,
    BasisReduceonlyWindowS,
    BasisReduceonlyCooldownS,
    BasisKillBps,
    BasisKillWindowS,

    // A.2.1 F1 Certification & Critical Inputs
    F1CertFreshnessWindowS,
    MmUtilMaxAgeMs,
    DiskUsedMaxAgeMs,

    // A.3 Watchdog & Recovery
    WatchdogKillS,
    EmergencyReduceonlyCooldownS,
    BunkerExitStableS,
    ExchangeHealthStaleS,
    WsZombieSilenceMs,
    WsZombieActivityWindowMs,

    // Self-Impact Guard
    PublicTradeFeedMaxAgeMs,
    FeedbackLoopWindowS,
    SelfTradeFractionTrip,
    SelfTradeMinSelfNotionalUsd,
    SelfTradeNotionalTripUsd,
    FeedbackLoopCooldownS,

    // Margin Headroom Gate
    MmUtilRejectOpens,
    MmUtilReduceonly,
    MmUtilKill,

    // Zombie Sweeper
    StaleOrderSec,

    // EvidenceGuard (GOP)
    EvidenceguardWindowS,
    EvidenceguardGlobalCooldown,
    EvidenceguardCountersMaxAgeMs,

    // Open Permission Latch
    PositionReconcileEpsilon,
    ReconcileTradeLookbackSec,

    // EvidenceGuard queue
    ParquetQueueTripPct,
    ParquetQueueTripWindowS,
    ParquetQueueClearPct,
    QueueClearWindowS,

    // Disk Watermarks
    DiskPauseArchivesPct,
    DiskDegradedPct,
    DiskKillPct,

    // Misc CSP
    GroupLockMaxWaitMs,
    BunkerJitterThresholdMs,
    TimeDriftThresholdMs,
    MaxPolicyAgeSec,
    RateLimitKillMin10028,
    CancelOpenBatchMax,
    CancelOpenBudgetMs,

    // A.3.1 Emergency Close & Liquidity Gates
    CloseBufferTicks,
    MaxSlippageBps,
    L2BookSnapshotMaxAgeMs,
    LimitsFetchFailuresTripCount,
    LimitsFetchFailureWindowS,

    // A.4 Fee Model Staleness
    FeeCacheSoftS,
    FeeCacheHardS,
    FeeStaleBuffer,

    // A.5 SVI Stability Guards
    SviGuardTripCount,
    SviGuardTripWindowS,

    // A.6 Retention & Replay (GOP)
    DecisionSnapshotRetentionDays,
    ReplayWindowHours,
    TickL2RetentionHours,
    ParquetAnalyticsRetentionDays,

    // GOP canary
    CanaryEvidenceAbortS,
}

/// Error when a required parameter is missing and has no Appendix A default.
#[derive(Debug, Clone, PartialEq)]
pub struct MissingConfigError {
    pub param_name: &'static str,
    pub reason: &'static str,
}

impl fmt::Display for MissingConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "config fail-closed: '{}' is missing and has no Appendix A default ({})",
            self.param_name, self.reason
        )
    }
}

impl std::error::Error for MissingConfigError {}

/// Returns the Appendix A default for a parameter, or `None` if no default exists.
///
/// Parameters without defaults require fail-closed behavior when missing.
pub fn appendix_a_default(param: ConfigParam) -> Option<f64> {
    match param {
        // A.1 Atomic Group Execution
        ConfigParam::AtomicQtyEpsilon => Some(1e-9),
        ConfigParam::InstrumentCacheTtlS => Some(3600.0),
        ConfigParam::ContractsAmountMatchTolerance => Some(0.001),

        // A.1.1 Inventory Skew Gate
        ConfigParam::InventorySkewK => Some(0.5),
        ConfigParam::InventorySkewTickPenaltyMax => Some(3.0),
        ConfigParam::RescueCrossSpreadTicks => Some(2.0),

        // A.2 Reflexive Cortex
        ConfigParam::SpreadMaxBps => Some(25.0),
        ConfigParam::SpreadKillBps => Some(75.0),
        ConfigParam::DepthMin => Some(300_000.0),
        ConfigParam::DepthKillMin => Some(100_000.0),
        ConfigParam::CortexKillWindowS => Some(10.0),
        ConfigParam::DvolJumpPct => Some(0.10),
        ConfigParam::DvolJumpWindowS => Some(60.0),
        ConfigParam::DvolCooldownS => Some(300.0),
        ConfigParam::SpreadDepthCooldownS => Some(120.0),

        // A.2 Basis Monitor
        ConfigParam::BasisPriceMaxAgeMs => Some(5000.0),
        ConfigParam::BasisReduceonlyBps => Some(50.0),
        ConfigParam::BasisReduceonlyWindowS => Some(5.0),
        ConfigParam::BasisReduceonlyCooldownS => Some(300.0),
        ConfigParam::BasisKillBps => Some(150.0),
        ConfigParam::BasisKillWindowS => Some(5.0),

        // A.2.1 F1 Certification & Critical Inputs
        ConfigParam::F1CertFreshnessWindowS => Some(86400.0),
        ConfigParam::MmUtilMaxAgeMs => Some(30000.0),
        ConfigParam::DiskUsedMaxAgeMs => Some(30000.0),

        // A.3 Watchdog & Recovery
        ConfigParam::WatchdogKillS => Some(10.0),
        ConfigParam::EmergencyReduceonlyCooldownS => Some(300.0),
        ConfigParam::BunkerExitStableS => Some(120.0),
        ConfigParam::ExchangeHealthStaleS => Some(180.0),
        ConfigParam::WsZombieSilenceMs => Some(15000.0),
        ConfigParam::WsZombieActivityWindowMs => Some(60000.0),

        // Self-Impact Guard
        ConfigParam::PublicTradeFeedMaxAgeMs => Some(5000.0),
        ConfigParam::FeedbackLoopWindowS => Some(10.0),
        ConfigParam::SelfTradeFractionTrip => Some(0.50),
        ConfigParam::SelfTradeMinSelfNotionalUsd => Some(5000.0),
        ConfigParam::SelfTradeNotionalTripUsd => Some(20000.0),
        ConfigParam::FeedbackLoopCooldownS => Some(300.0),

        // Margin Headroom Gate
        ConfigParam::MmUtilRejectOpens => Some(0.70),
        ConfigParam::MmUtilReduceonly => Some(0.85),
        ConfigParam::MmUtilKill => Some(0.95),

        // Zombie Sweeper
        ConfigParam::StaleOrderSec => Some(30.0),

        // EvidenceGuard (GOP)
        ConfigParam::EvidenceguardWindowS => Some(60.0),
        ConfigParam::EvidenceguardGlobalCooldown => Some(120.0),
        ConfigParam::EvidenceguardCountersMaxAgeMs => Some(60000.0),

        // Open Permission Latch
        ConfigParam::PositionReconcileEpsilon => Some(1e-6),
        ConfigParam::ReconcileTradeLookbackSec => Some(300.0),

        // EvidenceGuard queue
        ConfigParam::ParquetQueueTripPct => Some(0.90),
        ConfigParam::ParquetQueueTripWindowS => Some(5.0),
        ConfigParam::ParquetQueueClearPct => Some(0.70),
        ConfigParam::QueueClearWindowS => Some(120.0),

        // Disk Watermarks
        ConfigParam::DiskPauseArchivesPct => Some(0.80),
        ConfigParam::DiskDegradedPct => Some(0.85),
        ConfigParam::DiskKillPct => Some(0.92),

        // Misc CSP
        ConfigParam::GroupLockMaxWaitMs => Some(10.0),
        ConfigParam::BunkerJitterThresholdMs => Some(2000.0),
        ConfigParam::TimeDriftThresholdMs => Some(50.0),
        ConfigParam::MaxPolicyAgeSec => Some(300.0),
        ConfigParam::RateLimitKillMin10028 => Some(3.0),
        ConfigParam::CancelOpenBatchMax => Some(50.0),
        ConfigParam::CancelOpenBudgetMs => Some(200.0),

        // A.3.1 Emergency Close & Liquidity Gates
        ConfigParam::CloseBufferTicks => Some(5.0),
        ConfigParam::MaxSlippageBps => Some(10.0),
        ConfigParam::L2BookSnapshotMaxAgeMs => Some(1000.0),
        ConfigParam::LimitsFetchFailuresTripCount => Some(3.0),
        ConfigParam::LimitsFetchFailureWindowS => Some(300.0),

        // A.4 Fee Model Staleness
        ConfigParam::FeeCacheSoftS => Some(300.0),
        ConfigParam::FeeCacheHardS => Some(900.0),
        ConfigParam::FeeStaleBuffer => Some(0.20),

        // A.5 SVI Stability Guards
        ConfigParam::SviGuardTripCount => Some(3.0),
        ConfigParam::SviGuardTripWindowS => Some(300.0),

        // A.6 Retention & Replay (GOP)
        ConfigParam::DecisionSnapshotRetentionDays => Some(30.0),
        ConfigParam::ReplayWindowHours => Some(48.0),
        ConfigParam::TickL2RetentionHours => Some(72.0),
        ConfigParam::ParquetAnalyticsRetentionDays => Some(30.0),

        // GOP canary
        ConfigParam::CanaryEvidenceAbortS => Some(180.0),
    }
}

/// Returns the snake_case name for a parameter (matches CONTRACT.md naming).
pub fn param_name(param: ConfigParam) -> &'static str {
    match param {
        ConfigParam::AtomicQtyEpsilon => "atomic_qty_epsilon",
        ConfigParam::InstrumentCacheTtlS => "instrument_cache_ttl_s",
        ConfigParam::ContractsAmountMatchTolerance => "contracts_amount_match_tolerance",
        ConfigParam::InventorySkewK => "inventory_skew_k",
        ConfigParam::InventorySkewTickPenaltyMax => "inventory_skew_tick_penalty_max",
        ConfigParam::RescueCrossSpreadTicks => "rescue_cross_spread_ticks",
        ConfigParam::SpreadMaxBps => "spread_max_bps",
        ConfigParam::SpreadKillBps => "spread_kill_bps",
        ConfigParam::DepthMin => "depth_min",
        ConfigParam::DepthKillMin => "depth_kill_min",
        ConfigParam::CortexKillWindowS => "cortex_kill_window_s",
        ConfigParam::DvolJumpPct => "dvol_jump_pct",
        ConfigParam::DvolJumpWindowS => "dvol_jump_window_s",
        ConfigParam::DvolCooldownS => "dvol_cooldown_s",
        ConfigParam::SpreadDepthCooldownS => "spread_depth_cooldown_s",
        ConfigParam::BasisPriceMaxAgeMs => "basis_price_max_age_ms",
        ConfigParam::BasisReduceonlyBps => "basis_reduceonly_bps",
        ConfigParam::BasisReduceonlyWindowS => "basis_reduceonly_window_s",
        ConfigParam::BasisReduceonlyCooldownS => "basis_reduceonly_cooldown_s",
        ConfigParam::BasisKillBps => "basis_kill_bps",
        ConfigParam::BasisKillWindowS => "basis_kill_window_s",
        ConfigParam::F1CertFreshnessWindowS => "f1_cert_freshness_window_s",
        ConfigParam::MmUtilMaxAgeMs => "mm_util_max_age_ms",
        ConfigParam::DiskUsedMaxAgeMs => "disk_used_max_age_ms",
        ConfigParam::WatchdogKillS => "watchdog_kill_s",
        ConfigParam::EmergencyReduceonlyCooldownS => "emergency_reduceonly_cooldown_s",
        ConfigParam::BunkerExitStableS => "bunker_exit_stable_s",
        ConfigParam::ExchangeHealthStaleS => "exchange_health_stale_s",
        ConfigParam::WsZombieSilenceMs => "ws_zombie_silence_ms",
        ConfigParam::WsZombieActivityWindowMs => "ws_zombie_activity_window_ms",
        ConfigParam::PublicTradeFeedMaxAgeMs => "public_trade_feed_max_age_ms",
        ConfigParam::FeedbackLoopWindowS => "feedback_loop_window_s",
        ConfigParam::SelfTradeFractionTrip => "self_trade_fraction_trip",
        ConfigParam::SelfTradeMinSelfNotionalUsd => "self_trade_min_self_notional_usd",
        ConfigParam::SelfTradeNotionalTripUsd => "self_trade_notional_trip_usd",
        ConfigParam::FeedbackLoopCooldownS => "feedback_loop_cooldown_s",
        ConfigParam::MmUtilRejectOpens => "mm_util_reject_opens",
        ConfigParam::MmUtilReduceonly => "mm_util_reduceonly",
        ConfigParam::MmUtilKill => "mm_util_kill",
        ConfigParam::StaleOrderSec => "stale_order_sec",
        ConfigParam::EvidenceguardWindowS => "evidenceguard_window_s",
        ConfigParam::EvidenceguardGlobalCooldown => "evidenceguard_global_cooldown",
        ConfigParam::EvidenceguardCountersMaxAgeMs => "evidenceguard_counters_max_age_ms",
        ConfigParam::PositionReconcileEpsilon => "position_reconcile_epsilon",
        ConfigParam::ReconcileTradeLookbackSec => "reconcile_trade_lookback_sec",
        ConfigParam::ParquetQueueTripPct => "parquet_queue_trip_pct",
        ConfigParam::ParquetQueueTripWindowS => "parquet_queue_trip_window_s",
        ConfigParam::ParquetQueueClearPct => "parquet_queue_clear_pct",
        ConfigParam::QueueClearWindowS => "queue_clear_window_s",
        ConfigParam::DiskPauseArchivesPct => "disk_pause_archives_pct",
        ConfigParam::DiskDegradedPct => "disk_degraded_pct",
        ConfigParam::DiskKillPct => "disk_kill_pct",
        ConfigParam::GroupLockMaxWaitMs => "group_lock_max_wait_ms",
        ConfigParam::BunkerJitterThresholdMs => "bunker_jitter_threshold_ms",
        ConfigParam::TimeDriftThresholdMs => "time_drift_threshold_ms",
        ConfigParam::MaxPolicyAgeSec => "max_policy_age_sec",
        ConfigParam::RateLimitKillMin10028 => "rate_limit_kill_min_10028",
        ConfigParam::CancelOpenBatchMax => "cancel_open_batch_max",
        ConfigParam::CancelOpenBudgetMs => "cancel_open_budget_ms",
        ConfigParam::CloseBufferTicks => "close_buffer_ticks",
        ConfigParam::MaxSlippageBps => "max_slippage_bps",
        ConfigParam::L2BookSnapshotMaxAgeMs => "l2_book_snapshot_max_age_ms",
        ConfigParam::LimitsFetchFailuresTripCount => "limits_fetch_failures_trip_count",
        ConfigParam::LimitsFetchFailureWindowS => "limits_fetch_failure_window_s",
        ConfigParam::FeeCacheSoftS => "fee_cache_soft_s",
        ConfigParam::FeeCacheHardS => "fee_cache_hard_s",
        ConfigParam::FeeStaleBuffer => "fee_stale_buffer",
        ConfigParam::SviGuardTripCount => "svi_guard_trip_count",
        ConfigParam::SviGuardTripWindowS => "svi_guard_trip_window_s",
        ConfigParam::DecisionSnapshotRetentionDays => "decision_snapshot_retention_days",
        ConfigParam::ReplayWindowHours => "replay_window_hours",
        ConfigParam::TickL2RetentionHours => "tick_l2_retention_hours",
        ConfigParam::ParquetAnalyticsRetentionDays => "parquet_analytics_retention_days",
        ConfigParam::CanaryEvidenceAbortS => "canary_evidence_abort_s",
    }
}

/// Expected number of ConfigParam variants. Update when adding new variants.
/// This constant enables a compile-time-adjacent check that ALL_PARAMS is complete
/// (since Rust stable lacks variant_count for enums).
pub const EXPECTED_PARAM_COUNT: usize = 74;

/// All known `ConfigParam` variants (for exhaustive iteration in tests).
pub const ALL_PARAMS: &[ConfigParam] = &[
    ConfigParam::AtomicQtyEpsilon,
    ConfigParam::InstrumentCacheTtlS,
    ConfigParam::ContractsAmountMatchTolerance,
    ConfigParam::InventorySkewK,
    ConfigParam::InventorySkewTickPenaltyMax,
    ConfigParam::RescueCrossSpreadTicks,
    ConfigParam::SpreadMaxBps,
    ConfigParam::SpreadKillBps,
    ConfigParam::DepthMin,
    ConfigParam::DepthKillMin,
    ConfigParam::CortexKillWindowS,
    ConfigParam::DvolJumpPct,
    ConfigParam::DvolJumpWindowS,
    ConfigParam::DvolCooldownS,
    ConfigParam::SpreadDepthCooldownS,
    ConfigParam::BasisPriceMaxAgeMs,
    ConfigParam::BasisReduceonlyBps,
    ConfigParam::BasisReduceonlyWindowS,
    ConfigParam::BasisReduceonlyCooldownS,
    ConfigParam::BasisKillBps,
    ConfigParam::BasisKillWindowS,
    ConfigParam::F1CertFreshnessWindowS,
    ConfigParam::MmUtilMaxAgeMs,
    ConfigParam::DiskUsedMaxAgeMs,
    ConfigParam::WatchdogKillS,
    ConfigParam::EmergencyReduceonlyCooldownS,
    ConfigParam::BunkerExitStableS,
    ConfigParam::ExchangeHealthStaleS,
    ConfigParam::WsZombieSilenceMs,
    ConfigParam::WsZombieActivityWindowMs,
    ConfigParam::PublicTradeFeedMaxAgeMs,
    ConfigParam::FeedbackLoopWindowS,
    ConfigParam::SelfTradeFractionTrip,
    ConfigParam::SelfTradeMinSelfNotionalUsd,
    ConfigParam::SelfTradeNotionalTripUsd,
    ConfigParam::FeedbackLoopCooldownS,
    ConfigParam::MmUtilRejectOpens,
    ConfigParam::MmUtilReduceonly,
    ConfigParam::MmUtilKill,
    ConfigParam::StaleOrderSec,
    ConfigParam::EvidenceguardWindowS,
    ConfigParam::EvidenceguardGlobalCooldown,
    ConfigParam::EvidenceguardCountersMaxAgeMs,
    ConfigParam::PositionReconcileEpsilon,
    ConfigParam::ReconcileTradeLookbackSec,
    ConfigParam::ParquetQueueTripPct,
    ConfigParam::ParquetQueueTripWindowS,
    ConfigParam::ParquetQueueClearPct,
    ConfigParam::QueueClearWindowS,
    ConfigParam::DiskPauseArchivesPct,
    ConfigParam::DiskDegradedPct,
    ConfigParam::DiskKillPct,
    ConfigParam::GroupLockMaxWaitMs,
    ConfigParam::BunkerJitterThresholdMs,
    ConfigParam::TimeDriftThresholdMs,
    ConfigParam::MaxPolicyAgeSec,
    ConfigParam::RateLimitKillMin10028,
    ConfigParam::CancelOpenBatchMax,
    ConfigParam::CancelOpenBudgetMs,
    ConfigParam::CloseBufferTicks,
    ConfigParam::MaxSlippageBps,
    ConfigParam::L2BookSnapshotMaxAgeMs,
    ConfigParam::LimitsFetchFailuresTripCount,
    ConfigParam::LimitsFetchFailureWindowS,
    ConfigParam::FeeCacheSoftS,
    ConfigParam::FeeCacheHardS,
    ConfigParam::FeeStaleBuffer,
    ConfigParam::SviGuardTripCount,
    ConfigParam::SviGuardTripWindowS,
    ConfigParam::DecisionSnapshotRetentionDays,
    ConfigParam::ReplayWindowHours,
    ConfigParam::TickL2RetentionHours,
    ConfigParam::ParquetAnalyticsRetentionDays,
    ConfigParam::CanaryEvidenceAbortS,
];

/// Resolve a configuration value with Appendix A fail-safe semantics.
///
/// - If `value` is `Some`, returns that value (explicit config takes precedence).
/// - If `value` is `None` and the parameter has an Appendix A default, returns the default.
/// - If `value` is `None` and no Appendix A default exists, returns `Err` (fail-closed).
pub fn resolve_config_value(
    param: ConfigParam,
    value: Option<f64>,
) -> Result<f64, MissingConfigError> {
    if let Some(v) = value {
        if !v.is_finite() {
            return Err(MissingConfigError {
                param_name: param_name(param),
                reason: "value is non-finite (NaN or Infinity); fail-closed",
            });
        }
        if v < 0.0 {
            return Err(MissingConfigError {
                param_name: param_name(param),
                reason: "value is negative; all config params must be non-negative",
            });
        }
        return Ok(v);
    }
    appendix_a_default(param).ok_or_else(|| MissingConfigError {
        param_name: param_name(param),
        reason: "no Appendix A default; gate must fail-closed",
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_params_have_defaults() {
        // Every parameter in ALL_PARAMS currently has an Appendix A default.
        // This test ensures the table stays complete.
        for &param in ALL_PARAMS {
            assert!(
                appendix_a_default(param).is_some(),
                "ConfigParam::{:?} ({}) missing from appendix_a_default()",
                param,
                param_name(param),
            );
        }
    }

    #[test]
    fn all_params_have_names() {
        for &param in ALL_PARAMS {
            let name = param_name(param);
            assert!(!name.is_empty(), "ConfigParam::{param:?} has empty name");
        }
    }

    #[test]
    fn all_params_listed_in_constant() {
        // Verify ALL_PARAMS length matches EXPECTED_PARAM_COUNT.
        // If a new variant is added to ConfigParam but not ALL_PARAMS, this fails
        // (because EXPECTED_PARAM_COUNT must be bumped for the new variant's
        // exhaustive match arms, and then this count check catches the missing entry).
        assert_eq!(
            ALL_PARAMS.len(),
            EXPECTED_PARAM_COUNT,
            "ALL_PARAMS length ({}) != EXPECTED_PARAM_COUNT ({}). \
             Did you add a ConfigParam variant without updating ALL_PARAMS?",
            ALL_PARAMS.len(),
            EXPECTED_PARAM_COUNT,
        );
        // Also check no duplicates
        let mut names: Vec<&str> = ALL_PARAMS.iter().map(|&p| param_name(p)).collect();
        names.sort();
        names.dedup();
        assert_eq!(
            names.len(),
            ALL_PARAMS.len(),
            "ALL_PARAMS has duplicate entries"
        );
    }
}
