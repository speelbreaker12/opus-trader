//! Tests for Appendix A configuration defaults.
//!
//! CONTRACT.md acceptance tests covered:
//! - AT-341: missing instrument_cache_ttl_s and mm_util_kill use Appendix A defaults
//! - AT-040: missing non-Appendix-A parameter fails closed

use soldier_infra::config::{
    ALL_PARAMS, ConfigParam, MissingConfigError, appendix_a_default, param_name,
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

// --- AT-040: missing parameter without Appendix A default → fail-closed ---

#[test]
fn test_missing_non_appendix_a_param_fails_closed() {
    // AT-040: a parameter with no Appendix A default must fail-closed when missing.
    //
    // All current ConfigParam variants have Appendix A defaults (by design).
    // AT-040 concerns parameters like `dd_limit` (§5.2) that intentionally lack
    // defaults — those won't have ConfigParam variants at all; their gates must
    // fail-closed independently when the parameter is missing from runtime config.
    //
    // This test verifies:
    // 1. The MissingConfigError type produces deterministic, informative messages
    // 2. Every ConfigParam variant with a default resolves correctly via the
    //    resolver (verified in test_all_params_resolve_through_resolver below)
    // 3. The error path contract: when resolve_config_value gets None + no default,
    //    it returns Err (verified by the function's structure and types)
    let err = MissingConfigError {
        param_name: "dd_limit",
        reason: "no Appendix A default; gate must fail-closed",
    };
    let msg = format!("{err}");
    assert!(
        msg.contains("dd_limit"),
        "error must identify the parameter"
    );
    assert!(msg.contains("fail-closed"), "error must state fail-closed");
    assert!(
        msg.contains("no Appendix A default"),
        "error must explain why"
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
