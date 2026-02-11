//! Global exposure budget (S6.3), correlation-aware and fail-closed.
//!
//! Contract mapping:
//! - §1.4.2.2: cross-instrument budget with conservative corr buckets.
//! - AT-226: reject when portfolio breach occurs after correlation adjustment.
//! - AT-911: rejection reason must be GlobalExposureBudgetExceeded.
//! - AT-929: evaluate with current + pending exposure.

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
    let limit = match input.global_delta_limit_usd {
        Some(v) if v.is_finite() && v > 0.0 => v,
        _ => {
            metrics.record_reject_limit_missing();
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
    variance.max(0.0).sqrt()
}
