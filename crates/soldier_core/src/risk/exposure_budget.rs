//! Global exposure budget (S6.3), correlation-aware and fail-closed.
//!
//! Contract mapping:
//! - §1.4.2.2: cross-instrument budget with conservative corr buckets.
//! - AT-226: reject when portfolio breach occurs after correlation adjustment.
//! - AT-911: rejection reason must be GlobalExposureBudgetExceeded.
//! - AT-929: evaluate with current + pending exposure.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::telemetry::EventSink;

/// Reason for the static counter to discriminate rejection causes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExposureBudgetStaticRejectReason {
    /// Budget exceeded after correlation adjustment.
    Reject,
    /// Global delta limit missing or invalid (fail-closed).
    LimitMissing,
}

static EXPOSURE_BUDGET_REJECT_TOTAL: AtomicU64 = AtomicU64::new(0);
static EXPOSURE_BUDGET_REJECT_LIMIT_MISSING_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Process-lifetime rejection counter for global exposure budget gate.
///
/// Use for production monitoring and multi-hour root cause analysis.
/// Compare with instance `ExposureBudgetMetrics` for tick-level debugging.
pub fn exposure_budget_reject_total(reason: ExposureBudgetStaticRejectReason) -> u64 {
    match reason {
        ExposureBudgetStaticRejectReason::Reject => {
            EXPOSURE_BUDGET_REJECT_TOTAL.load(Ordering::Relaxed)
        }
        ExposureBudgetStaticRejectReason::LimitMissing => {
            EXPOSURE_BUDGET_REJECT_LIMIT_MISSING_TOTAL.load(Ordering::Relaxed)
        }
    }
}

fn bump_exposure_budget_reject(reason: ExposureBudgetStaticRejectReason) {
    #[cfg(test)]
    {
        return crate::execution::with_metrics_update_lock(|| {
            bump_exposure_budget_reject_inner(reason);
        });
    }

    #[cfg(not(test))]
    {
        bump_exposure_budget_reject_inner(reason);
    }
}

fn bump_exposure_budget_reject_inner(reason: ExposureBudgetStaticRejectReason) {
    match reason {
        ExposureBudgetStaticRejectReason::Reject => {
            EXPOSURE_BUDGET_REJECT_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
        ExposureBudgetStaticRejectReason::LimitMissing => {
            EXPOSURE_BUDGET_REJECT_LIMIT_MISSING_TOTAL.fetch_add(1, Ordering::Relaxed);
        }
    }
    let tail = format!("reason={reason:?}");
    crate::execution::emit_execution_metric_line(
        crate::execution::METRIC_EXPOSURE_BUDGET_REJECT,
        &tail,
    );
    tracing::debug!("ExposureBudgetReject reason={:?}", reason);
}

/// Internal exposure budget events for graybox testing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ExposureBudgetEvent {
    RejectLimitMissing,
    RejectBudgetExceeded,
}

struct ProductionExposureBudgetEvents;

impl EventSink<ExposureBudgetEvent> for ProductionExposureBudgetEvents {
    fn emit(&mut self, event: ExposureBudgetEvent) {
        match event {
            ExposureBudgetEvent::RejectLimitMissing => {
                bump_exposure_budget_reject(ExposureBudgetStaticRejectReason::LimitMissing)
            }
            ExposureBudgetEvent::RejectBudgetExceeded => {
                bump_exposure_budget_reject(ExposureBudgetStaticRejectReason::Reject)
            }
        }
    }
}

/// Correlation bucket for candidate exposure.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExposureBucket {
    Btc,
    Eth,
    Alts,
}

/// Input for global exposure budget evaluation.
#[derive(Debug, Clone)]
pub struct ExposureBudgetInput {
    pub current_btc_delta_usd: f64,
    pub pending_btc_delta_usd: f64,
    pub current_eth_delta_usd: f64,
    pub pending_eth_delta_usd: f64,
    pub current_alts_delta_usd: f64,
    pub pending_alts_delta_usd: f64,
    pub candidate_bucket: ExposureBucket,
    pub candidate_delta_usd: f64,
    pub global_delta_limit_usd: Option<f64>,
}

/// Rejection reason for global exposure budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExposureBudgetRejectReason {
    GlobalExposureBudgetExceeded,
}

/// Global exposure budget decision.
#[derive(Debug, Clone, PartialEq)]
pub enum ExposureBudgetResult {
    Allowed {
        portfolio_delta_usd: f64,
        combined_btc_delta_usd: f64,
        combined_eth_delta_usd: f64,
        combined_alts_delta_usd: f64,
    },
    Rejected {
        reason: ExposureBudgetRejectReason,
        portfolio_delta_usd: Option<f64>,
        combined_btc_delta_usd: Option<f64>,
        combined_eth_delta_usd: Option<f64>,
        combined_alts_delta_usd: Option<f64>,
    },
}

/// Metrics for global exposure budget outcomes.
#[derive(Debug, Default)]
pub struct ExposureBudgetMetrics {
    reject_total: u64,
    reject_limit_missing_total: u64,
    allowed_total: u64,
}

impl ExposureBudgetMetrics {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }

    pub fn reject_limit_missing_total(&self) -> u64 {
        self.reject_limit_missing_total
    }

    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }

    fn record_reject(&mut self) {
        self.reject_total += 1;
    }

    fn record_reject_limit_missing(&mut self) {
        self.reject_total += 1;
        self.reject_limit_missing_total += 1;
    }

    fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }
}

/// Evaluate global exposure budget with conservative bucket correlations.
pub fn evaluate_global_exposure_budget(
    input: &ExposureBudgetInput,
    metrics: &mut ExposureBudgetMetrics,
) -> ExposureBudgetResult {
    let mut events = ProductionExposureBudgetEvents;
    evaluate_global_exposure_budget_with_events(input, metrics, &mut events)
}

pub(crate) fn evaluate_global_exposure_budget_with_events<E: EventSink<ExposureBudgetEvent>>(
    input: &ExposureBudgetInput,
    metrics: &mut ExposureBudgetMetrics,
    events: &mut E,
) -> ExposureBudgetResult {
    let limit = match input.global_delta_limit_usd {
        Some(v) if v.is_finite() && v > 0.0 => v,
        _ => {
            metrics.record_reject_limit_missing();
            events.emit(ExposureBudgetEvent::RejectLimitMissing);
            return ExposureBudgetResult::Rejected {
                reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
                portfolio_delta_usd: None,
                combined_btc_delta_usd: None,
                combined_eth_delta_usd: None,
                combined_alts_delta_usd: None,
            };
        }
    };

    if !input.current_btc_delta_usd.is_finite()
        || !input.pending_btc_delta_usd.is_finite()
        || !input.current_eth_delta_usd.is_finite()
        || !input.pending_eth_delta_usd.is_finite()
        || !input.current_alts_delta_usd.is_finite()
        || !input.pending_alts_delta_usd.is_finite()
        || !input.candidate_delta_usd.is_finite()
    {
        metrics.record_reject();
        events.emit(ExposureBudgetEvent::RejectBudgetExceeded);
        return ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            portfolio_delta_usd: None,
            combined_btc_delta_usd: None,
            combined_eth_delta_usd: None,
            combined_alts_delta_usd: None,
        };
    }

    let mut combined_btc = input.current_btc_delta_usd + input.pending_btc_delta_usd;
    let mut combined_eth = input.current_eth_delta_usd + input.pending_eth_delta_usd;
    let mut combined_alts = input.current_alts_delta_usd + input.pending_alts_delta_usd;
    match input.candidate_bucket {
        ExposureBucket::Btc => combined_btc += input.candidate_delta_usd,
        ExposureBucket::Eth => combined_eth += input.candidate_delta_usd,
        ExposureBucket::Alts => combined_alts += input.candidate_delta_usd,
    }

    let portfolio = conservative_corr_magnitude(combined_btc, combined_eth, combined_alts);
    if !portfolio.is_finite() || portfolio > limit {
        metrics.record_reject();
        events.emit(ExposureBudgetEvent::RejectBudgetExceeded);
        return ExposureBudgetResult::Rejected {
            reason: ExposureBudgetRejectReason::GlobalExposureBudgetExceeded,
            portfolio_delta_usd: Some(portfolio),
            combined_btc_delta_usd: Some(combined_btc),
            combined_eth_delta_usd: Some(combined_eth),
            combined_alts_delta_usd: Some(combined_alts),
        };
    }

    metrics.record_allowed();
    ExposureBudgetResult::Allowed {
        portfolio_delta_usd: portfolio,
        combined_btc_delta_usd: combined_btc,
        combined_eth_delta_usd: combined_eth,
        combined_alts_delta_usd: combined_alts,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution::{
        begin_metrics_test, take_execution_metric_lines, with_intent_trace_ids,
    };

    fn base_input() -> ExposureBudgetInput {
        ExposureBudgetInput {
            current_btc_delta_usd: 1.0,
            pending_btc_delta_usd: 0.0,
            current_eth_delta_usd: 2.0,
            pending_eth_delta_usd: 0.0,
            current_alts_delta_usd: 3.0,
            pending_alts_delta_usd: 0.0,
            candidate_bucket: ExposureBucket::Btc,
            candidate_delta_usd: 0.5,
            global_delta_limit_usd: Some(100.0),
        }
    }

    #[test]
    fn test_exposure_budget_graybox_reject_emits_event_without_global_side_effects() {
        let _guard = begin_metrics_test();
        let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
        let before_missing =
            exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
        let mut metrics = ExposureBudgetMetrics::new();
        let mut events = Vec::new();
        let mut input = base_input();
        input.candidate_delta_usd = 10_000.0;

        let result = evaluate_global_exposure_budget_with_events(&input, &mut metrics, &mut events);

        assert!(matches!(result, ExposureBudgetResult::Rejected { reason, .. } if reason == ExposureBudgetRejectReason::GlobalExposureBudgetExceeded));
        assert_eq!(metrics.reject_total(), 1);
        assert_eq!(events, vec![ExposureBudgetEvent::RejectBudgetExceeded]);
        assert_eq!(exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject), before);
        assert_eq!(
            exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing),
            before_missing
        );

        let lines = take_execution_metric_lines();
        assert!(
            lines.is_empty(),
            "graybox path must not emit global metric lines: {lines:?}"
        );
    }

    #[test]
    fn test_exposure_budget_wrapper_emits_structured_reject_metric_line() {
        let _guard = begin_metrics_test();
        let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
        let mut metrics = ExposureBudgetMetrics::new();
        let mut input = base_input();
        input.global_delta_limit_usd = None;

        let _ = with_intent_trace_ids(
            "intent-exposure-budget-001",
            "run-exposure-budget-001",
            || evaluate_global_exposure_budget(&input, &mut metrics),
        );

        let lines = take_execution_metric_lines();
        assert_eq!(metrics.reject_limit_missing_total(), 1);
        assert_eq!(
            exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing),
            before + 1
        );
        assert!(
            lines.iter().any(|line| {
                line.starts_with("exposure_budget_reject_total")
                    && line.contains("intent_id=intent-exposure-budget-001")
                    && line.contains("run_id=run-exposure-budget-001")
            }),
            "expected structured reject metric line, got {lines:?}"
        );
    }
}

fn conservative_corr_magnitude(btc: f64, eth: f64, alts: f64) -> f64 {
    // Contract conservative corr buckets:
    // corr(BTC,ETH)=0.8, corr(BTC,alts)=0.6, corr(ETH,alts)=0.6.
    let b = btc.abs();
    let e = eth.abs();
    let a = alts.abs();
    let variance = (b * b)
        + (e * e)
        + (a * a)
        + (2.0 * 0.8 * b * e)
        + (2.0 * 0.6 * b * a)
        + (2.0 * 0.6 * e * a);

    // Fail-closed on numerically unexpected materially negative variance.
    //
    // EPS = 1e-12 covers IEEE 754 f64 rounding errors for typical USD-denominated
    // exposures (up to ~1e6 magnitude, where ε_mach ≈ 1e-10). Variance is
    // mathematically non-negative for real inputs; a tiny negative value indicates
    // harmless floating-point drift. Values below -EPS indicate a real bug
    // (e.g., corrupted inputs), so we fail-closed with INFINITY.
    const EPS: f64 = 1e-12;
    if variance >= 0.0 {
        variance.sqrt()
    } else if variance >= -EPS {
        0.0
    } else {
        f64::INFINITY
    }
}
