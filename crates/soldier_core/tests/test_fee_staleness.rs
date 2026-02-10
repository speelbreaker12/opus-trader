//! Tests for fee cache staleness logic per CONTRACT.md §4.2.
//!
//! AT-244: Fresh cache → actual rates.
//! AT-032: Soft-stale → apply fee_stale_buffer.
//! AT-033: Hard-stale → RiskState::Degraded, block OPEN.
//! AT-042: Missing timestamp → hard-stale (fail-closed).

use soldier_core::risk::{
    FeeCacheSnapshot, FeeStaleness, FeeStalenessConfig, RiskState, evaluate_fee_staleness,
};

fn default_config() -> FeeStalenessConfig {
    FeeStalenessConfig::default()
}

// ─── AT-244: Fresh cache → actual rates ─────────────────────────────────

#[test]
fn test_at244_fresh_cache_uses_actual_rate() {
    let config = default_config();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_100_000, // age = 100s, well under soft threshold of 300s
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::Fresh);
    assert!((eval.fee_rate_effective - 0.0005).abs() < 1e-12);
    assert_eq!(eval.risk_state, RiskState::Healthy);
    assert_eq!(eval.cache_age_s, Some(100));
}

#[test]
fn test_at244_fresh_at_boundary() {
    let config = default_config();
    // Exactly at soft threshold boundary (300s)
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_300_000, // age = 300s = fee_cache_soft_s
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::Fresh);
    assert!((eval.fee_rate_effective - 0.0005).abs() < 1e-12);
}

// ─── AT-032: Soft-stale → apply buffer ──────────────────────────────────

#[test]
fn test_at032_soft_stale_applies_buffer() {
    let config = default_config();
    // age = 301s → soft-stale (> 300, <= 900)
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_301_000,
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::SoftStale);
    // fee_rate_effective = 0.0005 * 1.20 = 0.0006
    assert!((eval.fee_rate_effective - 0.0006).abs() < 1e-12);
    assert_eq!(eval.risk_state, RiskState::Healthy);
    assert_eq!(eval.cache_age_s, Some(301));
}

#[test]
fn test_at032_soft_stale_at_hard_boundary() {
    let config = default_config();
    // Exactly at hard boundary (900s) — still soft-stale
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_900_000, // age = 900s = fee_cache_hard_s
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::SoftStale);
    // fee_rate_effective = 0.001 * 1.20 = 0.0012
    assert!((eval.fee_rate_effective - 0.0012).abs() < 1e-12);
    assert_eq!(eval.risk_state, RiskState::Healthy);
}

#[test]
fn test_at032_buffer_not_applied_when_fresh() {
    let config = default_config();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_050_000, // age = 50s — fresh
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::Fresh);
    // No buffer applied
    assert!((eval.fee_rate_effective - 0.0005).abs() < 1e-12);
}

// ─── AT-033: Hard-stale → Degraded ──────────────────────────────────────

#[test]
fn test_at033_hard_stale_sets_degraded() {
    let config = default_config();
    // age = 901s → hard-stale (> 900)
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_901_000,
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::HardStale);
    assert_eq!(eval.risk_state, RiskState::Degraded);
    assert_eq!(eval.cache_age_s, Some(901));
}

#[test]
fn test_at033_hard_stale_open_blocked() {
    let config = default_config();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 2_000_000, // age = 1000s — hard stale
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.risk_state, RiskState::Degraded);
    // Caller (PolicyGuard) uses RiskState::Degraded → ReduceOnly → block OPEN
}

// ─── AT-042: Missing timestamp → hard-stale ─────────────────────────────

#[test]
fn test_at042_missing_timestamp_is_hard_stale() {
    let config = default_config();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.0005,
        fee_model_cached_at_ts_ms: None,
        now_ms: 1_000_000,
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.staleness, FeeStaleness::HardStale);
    assert_eq!(eval.risk_state, RiskState::Degraded);
    assert_eq!(eval.cache_age_s, None);
}

#[test]
fn test_at042_missing_timestamp_blocks_open() {
    let config = default_config();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: None,
        now_ms: 1_000_000,
    };

    let eval = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(eval.risk_state, RiskState::Degraded);
    // Degraded → ReduceOnly → OPEN blocked
}

// ─── Config defaults ────────────────────────────────────────────────────

#[test]
fn test_config_defaults() {
    let config = FeeStalenessConfig::default();
    assert_eq!(config.fee_cache_soft_s, 300);
    assert_eq!(config.fee_cache_hard_s, 900);
    assert!((config.fee_stale_buffer - 0.20).abs() < 1e-12);
}
