//! Fee cache staleness logic per CONTRACT.md §4.2.
//!
//! **Staleness windows:**
//! - Fresh: age <= `fee_cache_soft_s` → use actual rates.
//! - Soft-stale: `fee_cache_soft_s` < age <= `fee_cache_hard_s` → apply `fee_stale_buffer`.
//! - Hard-stale: age > `fee_cache_hard_s` → `RiskState::Degraded`, block OPEN.
//! - Missing/unparseable timestamp → hard-stale (fail-closed).
//!
//! AT-031, AT-032, AT-033, AT-042, AT-244, AT-246.

use crate::risk::RiskState;

use std::sync::atomic::{AtomicU64, Ordering};

static FEE_STALENESS_HARD_STALE_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Returns the total number of fee staleness hard-stale events (atomic counter).
pub fn fee_staleness_hard_stale_total() -> u64 {
    FEE_STALENESS_HARD_STALE_TOTAL.load(Ordering::Relaxed)
}

fn bump_fee_staleness_reject(staleness: FeeStaleness, cache_age_s: Option<u64>) {
    FEE_STALENESS_HARD_STALE_TOTAL.fetch_add(1, Ordering::Relaxed);
    let tail = format!("staleness={staleness:?} cache_age_s={cache_age_s:?}");
    crate::execution::emit_execution_metric_line(
        crate::execution::METRIC_FEE_STALENESS_REJECT,
        &tail,
    );
    tracing::debug!(
        "FeeStalenessReject staleness={:?} cache_age_s={:?}",
        staleness,
        cache_age_s
    );
}

// ─── Configuration ──────────────────────────────────────────────────────

/// Fee staleness configuration per CONTRACT.md §4.2 / Appendix A.
#[derive(Debug, Clone)]
pub struct FeeStalenessConfig {
    /// Soft-stale threshold in seconds (default: 300).
    pub fee_cache_soft_s: u64,
    /// Hard-stale threshold in seconds (default: 900).
    pub fee_cache_hard_s: u64,
    /// Multiplicative buffer for soft-stale window (default: 0.20).
    pub fee_stale_buffer: f64,
}

impl Default for FeeStalenessConfig {
    fn default() -> Self {
        Self {
            fee_cache_soft_s: 300,
            fee_cache_hard_s: 900,
            fee_stale_buffer: 0.20,
        }
    }
}

// ─── Fee cache snapshot ─────────────────────────────────────────────────

/// Current state of the fee model cache.
#[derive(Debug, Clone)]
pub struct FeeCacheSnapshot {
    /// Fee rate from the exchange (e.g., maker/taker rate).
    pub fee_rate: f64,
    /// Epoch milliseconds when the fee model was last cached.
    /// `None` if missing or unparseable (fail-closed → hard-stale).
    pub fee_model_cached_at_ts_ms: Option<u64>,
    /// Current time in epoch milliseconds.
    pub now_ms: u64,
}

// ─── Staleness classification ───────────────────────────────────────────

/// Fee cache staleness classification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeeStaleness {
    /// Cache is fresh — use actual rates.
    Fresh,
    /// Cache is soft-stale — apply conservative buffer.
    SoftStale,
    /// Cache is hard-stale or missing — Degraded, block OPEN.
    HardStale,
}

// ─── Evaluation result ──────────────────────────────────────────────────

/// Result of fee staleness evaluation.
#[derive(Debug, Clone, PartialEq)]
pub struct FeeEvaluation {
    /// Staleness classification.
    pub staleness: FeeStaleness,
    /// Effective fee rate after any buffer is applied.
    pub fee_rate_effective: f64,
    /// Cache age in seconds (None if timestamp missing).
    pub cache_age_s: Option<u64>,
    /// Risk state implication.
    pub risk_state: RiskState,
}

// ─── Metrics ─────────────────────────────────────────────────────────────

/// Observability metrics for fee staleness.
#[derive(Debug)]
pub struct FeeMetrics {
    /// Number of times fee refresh failed.
    fee_model_refresh_fail_total: u64,
}

impl FeeMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self {
            fee_model_refresh_fail_total: 0,
        }
    }

    /// Record a refresh failure.
    pub fn record_refresh_fail(&mut self) {
        self.fee_model_refresh_fail_total += 1;
    }

    /// Total refresh failures.
    pub fn fee_model_refresh_fail_total(&self) -> u64 {
        self.fee_model_refresh_fail_total
    }
}

impl Default for FeeMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Evaluator ──────────────────────────────────────────────────────────

/// Evaluate fee cache staleness per CONTRACT.md §4.2.
///
/// - Fresh: age <= fee_cache_soft_s → actual rate, Healthy.
/// - Soft-stale: soft < age <= hard → buffered rate, Healthy.
/// - Hard-stale or missing: → Degraded, block OPEN.
///
/// CONTRACT.md: "If fee_model_cached_at_ts is missing or unparseable,
/// treat the fee cache as hard-stale (RiskState::Degraded)."
pub fn evaluate_fee_staleness(
    snapshot: &FeeCacheSnapshot,
    config: &FeeStalenessConfig,
) -> FeeEvaluation {
    // Guard: non-finite or negative fee_rate → HardStale + Degraded (fail-closed)
    // Do NOT propagate bad rate via multiplication — use 0.0 as safe default.
    if !snapshot.fee_rate.is_finite() || snapshot.fee_rate < 0.0 {
        bump_fee_staleness_reject(FeeStaleness::HardStale, None);
        return FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: 0.0,
            cache_age_s: None,
            risk_state: RiskState::Degraded,
        };
    }

    // S7-AUD-003: non-finite or negative buffer → fail-closed (HardStale + Degraded).
    // Previously fell back to 0.0 (fail-OPEN), silently removing the conservative
    // uplift on soft-stale fees. Now blocks OPEN until buffer is fixed.
    if !config.fee_stale_buffer.is_finite() || config.fee_stale_buffer < 0.0 {
        tracing::warn!(
            buffer = config.fee_stale_buffer,
            "fee staleness: non-finite/negative buffer, fail-closed to HardStale+Degraded"
        );
        bump_fee_staleness_reject(FeeStaleness::HardStale, None);
        return FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: 0.0,
            cache_age_s: None,
            risk_state: RiskState::Degraded,
        };
    }
    let safe_buffer = config.fee_stale_buffer;

    // Missing timestamp → hard-stale (fail-closed, AT-042)
    let cached_at_ms = match snapshot.fee_model_cached_at_ts_ms {
        Some(ts) => ts,
        None => {
            bump_fee_staleness_reject(FeeStaleness::HardStale, None);
            return FeeEvaluation {
                staleness: FeeStaleness::HardStale,
                fee_rate_effective: snapshot.fee_rate * (1.0 + safe_buffer),
                cache_age_s: None,
                risk_state: RiskState::Degraded,
            };
        }
    };

    // Compute age in seconds from epoch timestamps (AT-031: survives restart)
    let age_s = if snapshot.now_ms >= cached_at_ms {
        (snapshot.now_ms - cached_at_ms) / 1000
    } else {
        // Clock skew — fail-closed: treat as hard-stale
        bump_fee_staleness_reject(FeeStaleness::HardStale, Some(0));
        return FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: snapshot.fee_rate * (1.0 + safe_buffer),
            cache_age_s: Some(0),
            risk_state: RiskState::Degraded,
        };
    };

    if age_s > config.fee_cache_hard_s {
        // Hard-stale (AT-033)
        bump_fee_staleness_reject(FeeStaleness::HardStale, Some(age_s));
        FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: snapshot.fee_rate * (1.0 + safe_buffer),
            cache_age_s: Some(age_s),
            risk_state: RiskState::Degraded,
        }
    } else if age_s > config.fee_cache_soft_s {
        // Soft-stale (AT-032): apply buffer
        FeeEvaluation {
            staleness: FeeStaleness::SoftStale,
            fee_rate_effective: snapshot.fee_rate * (1.0 + safe_buffer),
            cache_age_s: Some(age_s),
            risk_state: RiskState::Healthy,
        }
    } else {
        // Fresh (AT-244): use actual rate
        FeeEvaluation {
            staleness: FeeStaleness::Fresh,
            fee_rate_effective: snapshot.fee_rate,
            cache_age_s: Some(age_s),
            risk_state: RiskState::Healthy,
        }
    }
}
