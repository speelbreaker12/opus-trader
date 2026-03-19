//! Margin headroom gate (S6.4).
//!
//! Contract mapping:
//! - §1.4.3: reject new opens when mm_util >= reject-opens threshold.
//! - Threshold defaults: reject_opens=0.70, reduceonly=0.85, kill=0.95.
//! - Mode progression: Active -> ReduceOnly -> Kill.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::telemetry::EventSink;

static MARGIN_GATE_REJECT_TOTAL: AtomicU64 = AtomicU64::new(0);

/// Process-lifetime rejection counter for margin headroom gate.
///
/// Use for production monitoring and multi-hour root cause analysis.
/// Compare with instance `MarginGateMetrics` for tick-level debugging.
pub fn margin_gate_reject_total() -> u64 {
    MARGIN_GATE_REJECT_TOTAL.load(Ordering::Relaxed)
}

fn bump_margin_gate_reject(reason: MarginGateRejectReason) {
    #[cfg(test)]
    {
        crate::execution::with_metrics_update_lock(|| {
            bump_margin_gate_reject_inner(reason);
        })
    }

    #[cfg(not(test))]
    {
        bump_margin_gate_reject_inner(reason);
    }
}

fn bump_margin_gate_reject_inner(reason: MarginGateRejectReason) {
    MARGIN_GATE_REJECT_TOTAL.fetch_add(1, Ordering::Relaxed);
    let tail = format!("reason={reason:?}");
    crate::execution::emit_execution_metric_line(
        crate::execution::METRIC_MARGIN_GATE_REJECT,
        &tail,
    );
    tracing::debug!("MarginGateReject reason={:?}", reason);
}

/// Internal margin gate events for graybox testing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MarginGateEvent {
    Reject { reason: MarginGateRejectReason },
}

struct ProductionMarginGateEvents;

impl EventSink<MarginGateEvent> for ProductionMarginGateEvents {
    fn emit(&mut self, event: MarginGateEvent) {
        match event {
            MarginGateEvent::Reject { reason } => bump_margin_gate_reject(reason),
        }
    }
}

/// Margin gate mode hint for PolicyGuard integration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MarginGateMode {
    Active,
    ReduceOnly,
    Kill,
}

/// Input for margin headroom gate evaluation.
#[derive(Debug, Clone)]
pub struct MarginGateInput {
    pub maintenance_margin_usd: f64,
    pub equity_usd: f64,
    pub mm_util_reject_opens: f64,
    pub mm_util_reduceonly: f64,
    pub mm_util_kill: f64,
    pub now_ms: u64,
    pub mm_util_last_update_ts_ms: Option<u64>,
    pub mm_util_max_age_ms: u64,
}

/// Reject reason for margin gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MarginGateRejectReason {
    MarginHeadroomRejectOpens,
    MarginHeadroomInputStale,
}

/// Margin gate decision (binary allow/reject, decoupled from mode hint).
#[derive(Debug, Clone, PartialEq)]
pub enum MarginGateDecision {
    Allowed {
        mm_util: f64,
    },
    Rejected {
        reason: MarginGateRejectReason,
        mm_util: Option<f64>,
    },
}

/// Metrics for margin gate outcomes.
#[derive(Debug, Default)]
pub struct MarginGateMetrics {
    reject_total: u64,
    allowed_total: u64,
}

impl MarginGateMetrics {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reject_total(&self) -> u64 {
        self.reject_total
    }

    pub fn allowed_total(&self) -> u64 {
        self.allowed_total
    }

    fn record_reject(&mut self) {
        self.reject_total += 1;
    }

    fn record_allowed(&mut self) {
        self.allowed_total += 1;
    }
}

/// Evaluate margin headroom gate for NEW OPEN intents.
///
/// CONTRACT.md §1.4.3 specifies `mm_util = maintenance_margin / max(equity, epsilon)`.
/// This implementation uses `equity_usd > 0.0` as a precondition instead of epsilon-clamping.
/// This is strictly more conservative: tiny positive equity produces a huge `mm_util` that
/// triggers rejection, whereas epsilon-clamping would cap it at a large but bounded value.
/// Both approaches lead to the same outcome (reject/Kill) — raw division just does so
/// with a larger computed `mm_util`, which is cosmetically odd in logs but never dangerous.
pub fn evaluate_margin_headroom_gate(
    input: &MarginGateInput,
    metrics: &mut MarginGateMetrics,
) -> MarginGateDecision {
    let mut events = ProductionMarginGateEvents;
    evaluate_margin_headroom_gate_with_events(input, metrics, &mut events)
}

pub(crate) fn evaluate_margin_headroom_gate_with_events<E: EventSink<MarginGateEvent>>(
    input: &MarginGateInput,
    metrics: &mut MarginGateMetrics,
    events: &mut E,
) -> MarginGateDecision {
    if !freshness_is_current(input) {
        return reject_with_events(
            MarginGateRejectReason::MarginHeadroomInputStale,
            None,
            metrics,
            events,
        );
    }

    if !thresholds_valid(
        input.mm_util_reject_opens,
        input.mm_util_reduceonly,
        input.mm_util_kill,
    ) || !input.maintenance_margin_usd.is_finite()
        || !input.equity_usd.is_finite()
        || input.maintenance_margin_usd < 0.0
        || input.equity_usd <= 0.0
    {
        return reject_with_events(
            MarginGateRejectReason::MarginHeadroomRejectOpens,
            None,
            metrics,
            events,
        );
    }

    let mm_util = input.maintenance_margin_usd / input.equity_usd;

    if mm_util >= input.mm_util_reject_opens {
        return reject_with_events(
            MarginGateRejectReason::MarginHeadroomRejectOpens,
            Some(mm_util),
            metrics,
            events,
        );
    }

    metrics.record_allowed();
    MarginGateDecision::Allowed { mm_util }
}

fn reject_with_events<E: EventSink<MarginGateEvent>>(
    reason: MarginGateRejectReason,
    mm_util: Option<f64>,
    metrics: &mut MarginGateMetrics,
    events: &mut E,
) -> MarginGateDecision {
    metrics.record_reject();
    events.emit(MarginGateEvent::Reject { reason });
    MarginGateDecision::Rejected { reason, mm_util }
}

/// Compute margin mode hint independently of the allow/reject decision.
///
/// Takes `&MarginGateInput` for ergonomics — recomputes mm_util internally (cheap f64 division).
/// Freshness failures fail closed to `ReduceOnly`; invalid/corrupt numeric inputs fail
/// closed to `Kill`.
pub fn compute_margin_mode_hint(input: &MarginGateInput) -> MarginGateMode {
    if !freshness_is_current(input) {
        return MarginGateMode::ReduceOnly;
    }

    // Intentionally re-validates: standalone function must be self-contained.
    if !input.equity_usd.is_finite()
        || !input.maintenance_margin_usd.is_finite()
        || input.equity_usd <= 0.0
        || input.maintenance_margin_usd < 0.0
        || !thresholds_valid(
            input.mm_util_reject_opens,
            input.mm_util_reduceonly,
            input.mm_util_kill,
        )
    {
        return MarginGateMode::Kill;
    }
    let mm_util = input.maintenance_margin_usd / input.equity_usd;
    compute_mode_hint(mm_util, input.mm_util_reduceonly, input.mm_util_kill)
}

fn compute_mode_hint(mm_util: f64, reduceonly: f64, kill: f64) -> MarginGateMode {
    if mm_util >= kill {
        MarginGateMode::Kill
    } else if mm_util >= reduceonly {
        MarginGateMode::ReduceOnly
    } else {
        MarginGateMode::Active
    }
}

fn thresholds_valid(reject_opens: f64, reduceonly: f64, kill: f64) -> bool {
    if !reject_opens.is_finite() || !reduceonly.is_finite() || !kill.is_finite() {
        return false;
    }
    if reject_opens <= 0.0 || kill > 1.0 {
        return false;
    }
    reject_opens <= reduceonly && reduceonly <= kill
}

fn freshness_is_current(input: &MarginGateInput) -> bool {
    matches!(
        input.mm_util_last_update_ts_ms,
        Some(last_update_ts_ms)
            if input.now_ms >= last_update_ts_ms
                && input.now_ms - last_update_ts_ms <= input.mm_util_max_age_ms
    )
}

#[cfg(test)]
#[path = "margin_gate_tests.rs"]
mod margin_gate_tests;
