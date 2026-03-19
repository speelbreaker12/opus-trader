//! Fee cache staleness logic per CONTRACT.md §4.2.
//!
//! **Staleness windows:**
//! - Fresh: age <= `fee_cache_soft_s` → use actual rates.
//! - Soft-stale: `fee_cache_soft_s` < age <= `fee_cache_hard_s` → apply `fee_stale_buffer`.
//! - Hard-stale: age > `fee_cache_hard_s` → `RiskState::Degraded`, block OPEN.
//! - Missing/unparseable timestamp → hard-stale (fail-closed).
//!
//! AT-031, AT-032, AT-033, AT-042, AT-244, AT-246.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::{risk::RiskState, telemetry::EventSink};

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
    /// Conservative fallback fee rate when cached fee input is invalid (default: 0.01 = 100 bps).
    pub fee_rate_fail_closed: f64,
}

impl Default for FeeStalenessConfig {
    fn default() -> Self {
        Self {
            fee_cache_soft_s: 300,
            fee_cache_hard_s: 900,
            fee_stale_buffer: 0.20,
            fee_rate_fail_closed: 0.01,
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

/// Internal fee staleness events used for graybox testing.
/// Not part of the public risk façade.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum FeeEvent {
    HardStale,
}

struct ProductionFeeEvents;

impl EventSink<FeeEvent> for ProductionFeeEvents {
    fn emit(&mut self, event: FeeEvent) {
        match event {
            FeeEvent::HardStale => bump_fee_staleness_hard_stale(),
        }
    }
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

static FEE_STALENESS_HARD_STALE_TOTAL: AtomicU64 = AtomicU64::new(0);

const DEFAULT_FAIL_CLOSED_FEE_RATE: f64 = 0.01;

/// Process-lifetime counter for hard-stale fee cache evaluations.
///
/// Counts the number of times `evaluate_fee_staleness` classified the
/// fee cache as `HardStale` (Degraded, block OPEN). Use for production
/// monitoring and multi-hour root cause analysis. Compare with instance
/// `FeeMetrics` for tick-level debugging.
pub fn fee_staleness_hard_stale_total() -> u64 {
    FEE_STALENESS_HARD_STALE_TOTAL.load(Ordering::Relaxed)
}

fn bump_fee_staleness_hard_stale() {
    #[cfg(test)]
    {
        crate::execution::with_metrics_update_lock(|| {
            bump_fee_staleness_hard_stale_inner();
        })
    }

    #[cfg(not(test))]
    {
        bump_fee_staleness_hard_stale_inner();
    }
}

fn bump_fee_staleness_hard_stale_inner() {
    FEE_STALENESS_HARD_STALE_TOTAL.fetch_add(1, Ordering::Relaxed);
    crate::execution::emit_execution_metric_line(crate::execution::METRIC_FEE_STALENESS_REJECT, "");
    tracing::debug!("FeeStalenessHardStale");
}

fn safe_fail_closed_fee_rate(config: &FeeStalenessConfig) -> f64 {
    if !config.fee_rate_fail_closed.is_finite() || config.fee_rate_fail_closed <= 0.0 {
        tracing::warn!(
            rate = config.fee_rate_fail_closed,
            fallback = DEFAULT_FAIL_CLOSED_FEE_RATE,
            "fee staleness: non-finite/non-positive fail-closed fee rate, using default"
        );
        DEFAULT_FAIL_CLOSED_FEE_RATE
    } else {
        config.fee_rate_fail_closed
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
pub(crate) fn evaluate_fee_staleness_with_events<E: EventSink<FeeEvent>>(
    snapshot: &FeeCacheSnapshot,
    config: &FeeStalenessConfig,
    events: &mut E,
) -> FeeEvaluation {
    // Guard: non-finite or negative fee_rate → HardStale + Degraded (fail-closed)
    // Preserve a conservative fee estimate instead of making execution look free.
    if !snapshot.fee_rate.is_finite() || snapshot.fee_rate < 0.0 {
        events.emit(FeeEvent::HardStale);
        return FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: safe_fail_closed_fee_rate(config),
            cache_age_s: None,
            risk_state: RiskState::Degraded,
        };
    }

    // Guard: non-finite or negative buffer → treat as zero buffer (conservative)
    let safe_buffer = if !config.fee_stale_buffer.is_finite() || config.fee_stale_buffer < 0.0 {
        tracing::warn!(
            buffer = config.fee_stale_buffer,
            "fee staleness: non-finite/negative buffer, clamping to 0.0 (conservative)"
        );
        0.0
    } else {
        config.fee_stale_buffer
    };

    // Missing timestamp → hard-stale (fail-closed, AT-042)
    let cached_at_ms = match snapshot.fee_model_cached_at_ts_ms {
        Some(ts) => ts,
        None => {
            events.emit(FeeEvent::HardStale);
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
        events.emit(FeeEvent::HardStale);
        return FeeEvaluation {
            staleness: FeeStaleness::HardStale,
            fee_rate_effective: snapshot.fee_rate * (1.0 + safe_buffer),
            cache_age_s: Some(0),
            risk_state: RiskState::Degraded,
        };
    };

    if age_s > config.fee_cache_hard_s {
        // Hard-stale (AT-033)
        events.emit(FeeEvent::HardStale);
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

pub fn evaluate_fee_staleness(
    snapshot: &FeeCacheSnapshot,
    config: &FeeStalenessConfig,
) -> FeeEvaluation {
    let mut events = ProductionFeeEvents;
    evaluate_fee_staleness_with_events(snapshot, config, &mut events)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution::{
        begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids,
    };

    #[test]
    fn fee_graybox_hard_stale_emits_event_without_global_side_effects() {
        let _guard = begin_metrics_test();
        let before = fee_staleness_hard_stale_total();

        let snapshot = FeeCacheSnapshot {
            fee_rate: 0.001,
            fee_model_cached_at_ts_ms: None,
            now_ms: 1_000,
        };
        let config = FeeStalenessConfig::default();
        let mut events = Vec::new();

        let result = evaluate_fee_staleness_with_events(&snapshot, &config, &mut events);

        assert_eq!(result.staleness, FeeStaleness::HardStale);
        assert_eq!(events, vec![FeeEvent::HardStale]);
        assert_eq!(fee_staleness_hard_stale_total(), before);

        let lines = take_execution_metric_lines();
        assert!(
            lines.is_empty(),
            "graybox path must not emit global metric lines: {lines:?}"
        );
    }

    #[test]
    fn fee_graybox_invalid_rate_uses_conservative_fallback_without_global_side_effects() {
        let _guard = begin_metrics_test();
        let before = fee_staleness_hard_stale_total();

        let snapshot = FeeCacheSnapshot {
            fee_rate: f64::NAN,
            fee_model_cached_at_ts_ms: Some(1_000),
            now_ms: 1_500,
        };
        let config = FeeStalenessConfig::default();
        let mut events = Vec::new();

        let result = evaluate_fee_staleness_with_events(&snapshot, &config, &mut events);

        assert_eq!(result.staleness, FeeStaleness::HardStale);
        assert!((result.fee_rate_effective - 0.01).abs() < 1e-12);
        assert_eq!(result.cache_age_s, None);
        assert_eq!(result.risk_state, RiskState::Degraded);
        assert_eq!(events, vec![FeeEvent::HardStale]);
        assert_eq!(fee_staleness_hard_stale_total(), before);

        let lines = take_execution_metric_lines();
        assert!(
            lines.is_empty(),
            "graybox path must not emit global metric lines: {lines:?}"
        );
    }

    #[test]
    fn fee_wrapper_preserves_hard_stale_metric_contract() {
        let _guard = begin_metrics_test();
        let before = fee_staleness_hard_stale_total();

        let snapshot = FeeCacheSnapshot {
            fee_rate: 0.001,
            fee_model_cached_at_ts_ms: None,
            now_ms: 1_000,
        };
        let config = FeeStalenessConfig::default();

        let result = with_intent_trace_ids("intent-fee-001", "run-fee-001", || {
            evaluate_fee_staleness(&snapshot, &config)
        });

        assert_eq!(result.staleness, FeeStaleness::HardStale);
        assert_eq!(fee_staleness_hard_stale_total(), before + 1);

        let lines = take_execution_metric_lines();
        assert!(
            lines.iter().any(|line| {
                line.starts_with("fee_staleness_hard_stale_total")
                    && line.contains("intent_id=intent-fee-001")
                    && line.contains("run_id=run-fee-001")
            }),
            "expected fee staleness metric line, got {lines:?}"
        );
    }
}
