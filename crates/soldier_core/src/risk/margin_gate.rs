//! Margin headroom gate (S6.4).
//!
//! Contract mapping:
//! - §1.4.3: reject new opens when mm_util >= reject-opens threshold.
//! - Threshold defaults: reject_opens=0.70, reduceonly=0.85, kill=0.95.
//! - Mode progression: Active -> ReduceOnly -> Kill.

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
}

/// Reject reason for margin gate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MarginGateRejectReason {
    MarginHeadroomRejectOpens,
}

/// Margin gate decision.
#[derive(Debug, Clone, PartialEq)]
pub enum MarginGateResult {
    Allowed {
        mm_util: f64,
        mode_hint: MarginGateMode,
    },
    Rejected {
        reason: MarginGateRejectReason,
        mm_util: Option<f64>,
        mode_hint: MarginGateMode,
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
pub fn evaluate_margin_headroom_gate(
    input: &MarginGateInput,
    metrics: &mut MarginGateMetrics,
) -> MarginGateResult {
    if !thresholds_valid(
        input.mm_util_reject_opens,
        input.mm_util_reduceonly,
        input.mm_util_kill,
    ) || !input.maintenance_margin_usd.is_finite()
        || !input.equity_usd.is_finite()
        || input.maintenance_margin_usd < 0.0
    {
        metrics.record_reject();
        return MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: None,
            mode_hint: MarginGateMode::Kill,
        };
    }

    const EQUITY_EPSILON: f64 = 1e-9;
    let safe_equity = input.equity_usd.max(EQUITY_EPSILON);
    let mm_util = input.maintenance_margin_usd / safe_equity;
    let mode_hint = compute_mode_hint(mm_util, input.mm_util_reduceonly, input.mm_util_kill);

    if mm_util >= input.mm_util_reject_opens {
        metrics.record_reject();
        return MarginGateResult::Rejected {
            reason: MarginGateRejectReason::MarginHeadroomRejectOpens,
            mm_util: Some(mm_util),
            mode_hint,
        };
    }

    metrics.record_allowed();
    MarginGateResult::Allowed { mm_util, mode_hint }
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
