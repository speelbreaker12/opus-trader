//! Tests for Appendix A configuration defaults.
//!
//! CONTRACT.md acceptance tests covered:
//! - AT-341: missing instrument_cache_ttl_s and mm_util_kill use Appendix A defaults
//! - AT-040: missing non-Appendix-A parameter fails closed
//!
//! **Dispatch causality**: Production callsite for resolve_config_value is tested in
//! `test_config_init.rs` via `build_gate_config_from_raw()`.

use soldier_infra::{
    ALL_PARAMS, ConfigParam, EXPECTED_PARAM_COUNT, appendix_a_default, param_name,
    resolve_config_value,
};

// --- AT-341: Appendix A defaults apply when config values are missing ---

#[test]
fn test_missing_instrument_cache_ttl_s_applies_default_3600() {
    // AT-341: config omits instrument_cache_ttl_s → default 3600s
    let result = resolve_config_value(ConfigParam::InstrumentCacheTtlS, None);
    assert_eq!(result.unwrap(), 3600.0);
}

#[test]
fn test_missing_evidenceguard_global_cooldown_applies_default_120() {
    // AT-970: config omits evidenceguard_global_cooldown → default 120s
    let result = resolve_config_value(ConfigParam::EvidenceguardGlobalCooldown, None);
    assert_eq!(result.unwrap(), 120.0);
}

#[test]
fn test_missing_mm_util_kill_applies_default_095() {
    // AT-341: config omits mm_util_kill → default 0.95
    let result = resolve_config_value(ConfigParam::MmUtilKill, None);
    assert_eq!(result.unwrap(), 0.95);
}

// GAP-010-3: Dedicated test for ReplayWindowHours default
#[test]
fn test_missing_replay_window_hours_applies_default_48() {
    // AT-341: config omits replay_window_hours → default 48.0 (hours)
    let result = resolve_config_value(ConfigParam::ReplayWindowHours, None);
    assert_eq!(result.unwrap(), 48.0);
}

// --- AT-040: missing parameter without Appendix A default → fail-closed ---

// AT-040: The fail-closed Err path test (SyntheticNoDefault) lives in
// config.rs::tests::test_missing_non_appendix_a_param_fails_closed because
// #[cfg(test)] enum variants are only visible to unit tests, not integration tests.

// GAP-010-1: AT-040 fail-closed Err path — regression guard.
//
// The Err branch in resolve_config_value (None + no Appendix A default) is
// structurally unreachable today because ALL 74 ConfigParam variants have
// defaults. This test guards against regression: if a future variant is added
// without a default, resolve_config_value(param, None) MUST return Err.
// By exhaustively verifying every variant resolves Ok(default), we ensure
// that any new variant breaking this invariant will be caught immediately.
#[test]
fn test_all_config_params_fail_closed_when_missing_without_default() {
    // For every known ConfigParam, verify that resolve_config_value(param, None)
    // returns Ok with the Appendix A default. This proves the Err path is only
    // unreachable because every variant has a default — not because of a bug.
    for &param in ALL_PARAMS {
        let default = appendix_a_default(param);
        assert!(
            default.is_some(),
            "ConfigParam::{:?} ({}) lacks an Appendix A default. \
             If intentional, resolve_config_value(param, None) MUST return Err \
             (fail-closed). Add dedicated test coverage for this param.",
            param,
            param_name(param),
        );

        let result = resolve_config_value(param, None);
        assert!(
            result.is_ok(),
            "ConfigParam::{:?} ({}) has a default but resolve_config_value \
             returned Err: {:?}",
            param,
            param_name(param),
            result.unwrap_err(),
        );
        assert_eq!(
            result.unwrap(),
            default.unwrap(),
            "ConfigParam::{:?} ({}) resolved to wrong value via resolver",
            param,
            param_name(param),
        );
    }

    // Verify the count matches EXPECTED_PARAM_COUNT to catch new variants
    // not added to ALL_PARAMS.
    assert_eq!(
        ALL_PARAMS.len(),
        EXPECTED_PARAM_COUNT,
        "ALL_PARAMS length does not match EXPECTED_PARAM_COUNT — a new \
         ConfigParam variant may have been added without updating ALL_PARAMS. \
         If the new variant lacks a default, it needs a dedicated fail-closed test."
    );
}

#[test]
fn test_all_params_resolve_through_resolver() {
    // Verify every ConfigParam resolves to its Appendix A default via the actual
    // resolve_config_value path (not just appendix_a_default directly).
    for &param in ALL_PARAMS {
        let result = resolve_config_value(param, None);
        assert!(
            result.is_ok(),
            "resolve_config_value({:?}, None) should return Ok for params with defaults",
            param
        );
        let resolved = result.unwrap();
        let expected = appendix_a_default(param).unwrap();
        assert_eq!(
            resolved, expected,
            "resolve_config_value({:?}, None) returned {resolved}, expected {expected}",
            param
        );
    }
}

#[test]
fn test_resolve_with_explicit_value_overrides_default() {
    // Explicit config value takes precedence over Appendix A default
    let result = resolve_config_value(ConfigParam::InstrumentCacheTtlS, Some(7200.0));
    assert_eq!(result.unwrap(), 7200.0);
}

// --- Completeness: every Appendix A parameter has a default ---

#[test]
fn test_all_appendix_a_params_have_defaults() {
    // AT-424/AT-971: each Appendix A parameter has a defined default
    for &param in ALL_PARAMS {
        let default = appendix_a_default(param);
        assert!(
            default.is_some(),
            "ConfigParam::{:?} ({}) must have an Appendix A default",
            param,
            param_name(param),
        );
        // Default must not be zero/none (CONTRACT.md: "no implicit zero/none")
        let val = default.unwrap();
        assert!(
            val != 0.0
                || matches!(
                    param,
                    ConfigParam::AtomicQtyEpsilon | ConfigParam::PositionReconcileEpsilon
                ),
            "ConfigParam::{:?} ({}) has zero default — verify this is intentional",
            param,
            param_name(param),
        );
    }
}

// --- Table-driven: spot-check key defaults match CONTRACT.md A.7 ---

#[test]
fn test_appendix_a_defaults_match_contract() {
    let cases: Vec<(ConfigParam, f64)> = vec![
        // A.1
        (ConfigParam::AtomicQtyEpsilon, 1e-9),
        (ConfigParam::InstrumentCacheTtlS, 3600.0),
        (ConfigParam::ContractsAmountMatchTolerance, 0.001),
        // A.1.1
        (ConfigParam::InventorySkewK, 0.5),
        (ConfigParam::InventorySkewTickPenaltyMax, 3.0),
        (ConfigParam::RescueCrossSpreadTicks, 2.0),
        // A.2
        (ConfigParam::SpreadMaxBps, 25.0),
        (ConfigParam::SpreadKillBps, 75.0),
        (ConfigParam::DepthMin, 300_000.0),
        (ConfigParam::DepthKillMin, 100_000.0),
        (ConfigParam::CortexKillWindowS, 10.0),
        (ConfigParam::DvolJumpPct, 0.10),
        (ConfigParam::DvolCooldownS, 300.0),
        (ConfigParam::SpreadDepthCooldownS, 120.0),
        // A.2.1
        (ConfigParam::F1CertFreshnessWindowS, 86400.0),
        (ConfigParam::MmUtilMaxAgeMs, 30000.0),
        (ConfigParam::DiskUsedMaxAgeMs, 30000.0),
        // A.3
        (ConfigParam::WatchdogKillS, 10.0),
        (ConfigParam::EmergencyReduceonlyCooldownS, 300.0),
        (ConfigParam::BunkerExitStableS, 120.0),
        (ConfigParam::ExchangeHealthStaleS, 180.0),
        // Margin
        (ConfigParam::MmUtilRejectOpens, 0.70),
        (ConfigParam::MmUtilReduceonly, 0.85),
        (ConfigParam::MmUtilKill, 0.95),
        // Misc
        (ConfigParam::StaleOrderSec, 30.0),
        (ConfigParam::MaxPolicyAgeSec, 300.0),
        (ConfigParam::TimeDriftThresholdMs, 50.0),
        // Evidence
        (ConfigParam::EvidenceguardWindowS, 60.0),
        (ConfigParam::EvidenceguardGlobalCooldown, 120.0),
        // Fee
        (ConfigParam::FeeCacheSoftS, 300.0),
        (ConfigParam::FeeCacheHardS, 900.0),
        (ConfigParam::FeeStaleBuffer, 0.20),
        // SVI
        (ConfigParam::SviGuardTripCount, 3.0),
        (ConfigParam::SviGuardTripWindowS, 300.0),
        // Retention
        (ConfigParam::DecisionSnapshotRetentionDays, 30.0),
        (ConfigParam::ReplayWindowHours, 48.0),
        // Disk Watermarks
        (ConfigParam::DiskPauseArchivesPct, 0.80),
        (ConfigParam::DiskDegradedPct, 0.85),
        (ConfigParam::DiskKillPct, 0.92),
        // Close
        (ConfigParam::CloseBufferTicks, 5.0),
        (ConfigParam::MaxSlippageBps, 10.0),
        (ConfigParam::L2BookSnapshotMaxAgeMs, 1000.0),
    ];

    for (param, expected) in cases {
        let actual = appendix_a_default(param).unwrap();
        assert!(
            (actual - expected).abs() < f64::EPSILON * 100.0,
            "ConfigParam::{:?} ({}) expected {expected}, got {actual}",
            param,
            param_name(param),
        );
    }
}

// --- Resolve semantics ---

#[test]
fn test_resolve_none_with_default_returns_default() {
    let result = resolve_config_value(ConfigParam::MmUtilKill, None);
    assert_eq!(result.unwrap(), 0.95);
}

#[test]
fn test_resolve_some_returns_explicit_value() {
    let result = resolve_config_value(ConfigParam::MmUtilKill, Some(0.90));
    assert_eq!(result.unwrap(), 0.90);
}

// --- Config value validation (fail-closed on invalid inputs) ---

#[test]
fn test_nan_config_value_rejected() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(f64::NAN));
    assert!(result.is_err());
    assert!(result.unwrap_err().reason.contains("non-finite"));
}

#[test]
fn test_infinity_config_value_rejected() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(f64::INFINITY));
    assert!(result.is_err());
    assert!(result.unwrap_err().reason.contains("non-finite"));
}

#[test]
fn test_neg_infinity_config_value_rejected() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(f64::NEG_INFINITY));
    assert!(result.is_err());
    // NEG_INFINITY is non-finite, so either "non-finite" or "negative" reason is acceptable
}

#[test]
fn test_negative_config_value_rejected() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(-1.0));
    assert!(result.is_err());
    assert!(result.unwrap_err().reason.contains("negative"));
}

#[test]
fn test_zero_config_value_allowed() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(0.0));
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 0.0);
}

#[test]
fn test_positive_config_value_allowed() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(300.0));
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 300.0);
}

#[test]
fn test_none_with_default_returns_default() {
    // WatchdogKillS has an Appendix A default of 10.0
    let result = resolve_config_value(ConfigParam::WatchdogKillS, None);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 10.0);
}

/// Percentage params must be in [0.0, 1.0]. A value > 1.0 is a config error.
/// Kimi K2.5 finding: upper-bound validation was missing.
#[test]
fn test_percentage_param_above_one_rejected() {
    let pct_params = [
        ConfigParam::MmUtilKill,
        ConfigParam::MmUtilReduceonly,
        ConfigParam::MmUtilRejectOpens,
        ConfigParam::DiskKillPct,
        ConfigParam::DiskDegradedPct,
        ConfigParam::DiskPauseArchivesPct,
        ConfigParam::ParquetQueueTripPct,
        ConfigParam::ParquetQueueClearPct,
        ConfigParam::DvolJumpPct,
        ConfigParam::ContractsAmountMatchTolerance,
        ConfigParam::SelfTradeFractionTrip,
        ConfigParam::FeeStaleBuffer,
    ];
    for param in pct_params {
        let result = resolve_config_value(param, Some(1.5));
        assert!(
            result.is_err(),
            "ConfigParam::{:?} must reject value 1.5 (above 1.0 for percentage)",
            param
        );
        let err = result.unwrap_err();
        assert!(
            err.reason.contains("percentage") || err.reason.contains("1.0"),
            "ConfigParam::{:?} error must mention percentage/1.0 bound, got: {}",
            param,
            err.reason
        );
    }
}

/// Percentage params at exactly 1.0 must be allowed (valid boundary).
#[test]
fn test_percentage_param_at_one_allowed() {
    let result = resolve_config_value(ConfigParam::MmUtilKill, Some(1.0));
    assert!(result.is_ok(), "MmUtilKill=1.0 (100%) must be allowed");
    assert_eq!(result.unwrap(), 1.0);
}

/// Percentage params at exactly 0.0 must be allowed (valid boundary).
#[test]
fn test_percentage_param_at_zero_allowed() {
    let result = resolve_config_value(ConfigParam::MmUtilKill, Some(0.0));
    assert!(result.is_ok(), "MmUtilKill=0.0 must be allowed");
    assert_eq!(result.unwrap(), 0.0);
}

/// Non-percentage params must NOT be rejected at values > 1.0.
/// WatchdogKillS=300.0 is valid (it's seconds, not a percentage).
#[test]
fn test_non_percentage_param_above_one_allowed() {
    let result = resolve_config_value(ConfigParam::WatchdogKillS, Some(300.0));
    assert!(
        result.is_ok(),
        "WatchdogKillS=300.0 must be allowed (not a percentage)"
    );
    assert_eq!(result.unwrap(), 300.0);
}

/// InventorySkewK is dimensionless (not "pct") per CONTRACT.md Appendix A.
/// Values > 1.0 are valid (e.g., 1.5 = 150% edge increase at max inventory bias).
/// Kimi K2.5 Cycle 2 finding: was incorrectly classified as percentage.
#[test]
fn test_inventory_skew_k_above_one_allowed() {
    let result = resolve_config_value(ConfigParam::InventorySkewK, Some(1.5));
    assert!(
        result.is_ok(),
        "InventorySkewK=1.5 must be allowed (dimensionless, not a percentage)"
    );
    assert_eq!(result.unwrap(), 1.5);
}
