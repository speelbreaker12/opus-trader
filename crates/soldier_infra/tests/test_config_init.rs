//! Tests for GateConfig builder (production callsite for resolve_config_value).
//!
//! Dispatch causality: these tests prove that build_gate_config_from_raw
//! correctly wires resolve_config_value for safety-critical gate thresholds.
//!
//! Cross-reference: unit-level config tests in test_config_defaults.rs;
//! pipeline-level gate tests in soldier_core tests.

use soldier_infra::{RawThresholdConfig, build_gate_config_from_raw};

// ─── Fail-closed: NaN for safety param → error ──────────────────────────

/// NaN in a safety-critical config param must fail-closed (not silently apply).
/// Tests resolve_config_value's NaN rejection through the production callsite.
#[test]
fn test_build_gate_config_nan_fails_closed() {
    let raw = RawThresholdConfig {
        fee_cache_hard_s: Some(f64::NAN),
        ..RawThresholdConfig::default()
    };
    let result = build_gate_config_from_raw(&raw);
    assert!(
        result.is_err(),
        "NaN fee_cache_hard_s must fail-closed, got {result:?}"
    );
    let err = result.unwrap_err();
    assert_eq!(err.param_name, "fee_cache_hard_s");
}

/// Negative value in a safety config param must fail-closed.
#[test]
fn test_build_gate_config_negative_fails_closed() {
    let raw = RawThresholdConfig {
        max_slippage_bps: Some(-5.0),
        ..RawThresholdConfig::default()
    };
    let result = build_gate_config_from_raw(&raw);
    assert!(
        result.is_err(),
        "negative max_slippage_bps must fail-closed, got {result:?}"
    );
}

/// Percentage param exceeding 1.0 must fail-closed.
#[test]
fn test_build_gate_config_percentage_over_1_fails_closed() {
    let raw = RawThresholdConfig {
        fee_stale_buffer: Some(1.5), // percentage param, must be in [0.0, 1.0]
        ..RawThresholdConfig::default()
    };
    let result = build_gate_config_from_raw(&raw);
    assert!(
        result.is_err(),
        "fee_stale_buffer > 1.0 must fail-closed, got {result:?}"
    );
}

// ─── Appendix A defaults applied ────────────────────────────────────────

/// All-None raw config → all Appendix A defaults applied successfully.
/// Proves resolve_config_value is wired into the production builder.
#[test]
fn test_build_gate_config_appendix_a_defaults_applied() {
    let raw = RawThresholdConfig::default();
    let config = build_gate_config_from_raw(&raw)
        .expect("all-None config should resolve from Appendix A defaults");

    // Verify exact Appendix A defaults (CONTRACT.md A.4, A.1, A.3.1)
    assert_eq!(config.fee_cache_soft_s, 300.0, "fee_cache_soft_s default");
    assert_eq!(config.fee_cache_hard_s, 900.0, "fee_cache_hard_s default");
    assert_eq!(config.fee_stale_buffer, 0.20, "fee_stale_buffer default");
    assert_eq!(
        config.instrument_cache_ttl_s, 3600.0,
        "instrument_cache_ttl_s default"
    );
    assert_eq!(
        config.l2_book_snapshot_max_age_ms, 1000.0,
        "l2_book_snapshot_max_age_ms default"
    );
    assert_eq!(config.max_slippage_bps, 10.0, "max_slippage_bps default");
    assert_eq!(
        config.contracts_amount_match_tolerance, 0.001,
        "contracts_amount_match_tolerance default"
    );
}

/// Explicit values override Appendix A defaults.
#[test]
fn test_build_gate_config_explicit_overrides_defaults() {
    let raw = RawThresholdConfig {
        fee_cache_soft_s: Some(120.0),
        fee_cache_hard_s: Some(600.0),
        max_slippage_bps: Some(25.0),
        ..RawThresholdConfig::default()
    };
    let config = build_gate_config_from_raw(&raw).expect("valid explicit overrides");

    assert_eq!(config.fee_cache_soft_s, 120.0, "explicit soft override");
    assert_eq!(config.fee_cache_hard_s, 600.0, "explicit hard override");
    assert_eq!(config.max_slippage_bps, 25.0, "explicit slippage override");
    // Non-overridden fields still get defaults
    assert_eq!(
        config.instrument_cache_ttl_s, 3600.0,
        "non-overridden default"
    );
}
