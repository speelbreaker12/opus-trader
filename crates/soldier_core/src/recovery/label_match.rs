//! Label match disambiguation per CONTRACT.md §1.1.2.
//!
//! Algorithm:
//! 1. Parse label → extract `{sid8, gid12, leg_idx, ih16}`.
//! 2. Candidate set = all local intents where `gid12` matches AND `leg_idx` matches.
//! 3. If candidate set size == 1 → match.
//! 4. Else disambiguate using tie-breakers in order:
//!    A) `ih16` match
//!    B) instrument match
//!    C) side match
//!    D) qty_q match
//! 5. If still ambiguous → `RiskState::Degraded`, block opens.

use crate::risk::RiskState;

/// A local intent record used for label matching.
#[derive(Debug, Clone, PartialEq)]
pub struct IntentRecord {
    /// First 12 chars of group_id (UUID without dashes).
    pub gid12: String,
    /// Leg index within the group.
    pub leg_idx: u32,
    /// First 16 hex chars of intent_hash.
    pub ih16: String,
    /// Instrument identifier (e.g., "BTC-PERPETUAL").
    pub instrument: String,
    /// Order side ("buy" or "sell").
    pub side: String,
    /// Quantized quantity.
    pub qty_q: f64,
}

/// Result of label matching.
#[derive(Debug, Clone, PartialEq)]
pub enum MatchResult {
    /// Exactly one candidate matched.
    Matched(IntentRecord),
    /// No candidates found for the given gid12 + leg_idx.
    NoMatch,
    /// Multiple candidates remain after all tie-breakers.
    /// Caller MUST set `RiskState::Degraded` and block opens.
    Ambiguous {
        /// Number of remaining candidates.
        remaining: usize,
        /// Risk state to apply.
        risk_state: RiskState,
    },
}

/// Observability metrics for label matching.
#[derive(Debug)]
pub struct LabelMatchMetrics {
    /// `label_match_ambiguity_total` counter.
    ambiguity_total: u64,
}

impl LabelMatchMetrics {
    /// Create a new metrics tracker.
    pub fn new() -> Self {
        Self { ambiguity_total: 0 }
    }

    /// Increment the ambiguity counter.
    pub fn record_ambiguity(&mut self) {
        self.ambiguity_total += 1;
    }

    /// Current value of `label_match_ambiguity_total`.
    pub fn ambiguity_total(&self) -> u64 {
        self.ambiguity_total
    }
}

impl Default for LabelMatchMetrics {
    fn default() -> Self {
        Self::new()
    }
}

/// Query parameters for label matching.
///
/// Extracted from the parsed label and the exchange order context.
#[derive(Debug, Clone)]
pub struct MatchQuery<'a> {
    /// First 12 chars of group_id.
    pub gid12: &'a str,
    /// Leg index.
    pub leg_idx: u32,
    /// First 16 hex chars of intent_hash.
    pub ih16: &'a str,
    /// Instrument identifier.
    pub instrument: &'a str,
    /// Order side.
    pub side: &'a str,
    /// Quantized quantity.
    pub qty_q: f64,
}

/// Match a parsed label against a set of local intent records.
///
/// CONTRACT.md §1.1.2 algorithm:
/// 1. Filter candidates by `gid12` and `leg_idx`.
/// 2. If exactly one → match.
/// 3. Apply tie-breakers in order: ih16, instrument, side, qty_q.
/// 4. If still ambiguous → Degraded.
pub fn match_label(
    query: &MatchQuery<'_>,
    intents: &[IntentRecord],
    metrics: &mut LabelMatchMetrics,
) -> MatchResult {
    // Step 1: filter by gid12 + leg_idx
    let mut candidates: Vec<&IntentRecord> = intents
        .iter()
        .filter(|i| i.gid12 == query.gid12 && i.leg_idx == query.leg_idx)
        .collect();

    if candidates.is_empty() {
        return MatchResult::NoMatch;
    }

    if candidates.len() == 1 {
        return MatchResult::Matched(candidates[0].clone());
    }

    // Step 2: tie-breaker A — ih16
    let ih16_matches: Vec<&IntentRecord> = candidates
        .iter()
        .filter(|i| i.ih16 == query.ih16)
        .copied()
        .collect();
    if ih16_matches.len() == 1 {
        return MatchResult::Matched(ih16_matches[0].clone());
    }
    if !ih16_matches.is_empty() {
        candidates = ih16_matches;
    }

    // Step 3: tie-breaker B — instrument
    let inst_matches: Vec<&IntentRecord> = candidates
        .iter()
        .filter(|i| i.instrument == query.instrument)
        .copied()
        .collect();
    if inst_matches.len() == 1 {
        return MatchResult::Matched(inst_matches[0].clone());
    }
    if !inst_matches.is_empty() {
        candidates = inst_matches;
    }

    // Step 4: tie-breaker C — side
    let side_matches: Vec<&IntentRecord> = candidates
        .iter()
        .filter(|i| i.side == query.side)
        .copied()
        .collect();
    if side_matches.len() == 1 {
        return MatchResult::Matched(side_matches[0].clone());
    }
    if !side_matches.is_empty() {
        candidates = side_matches;
    }

    // Step 5: tie-breaker D — qty_q
    let qty_matches: Vec<&IntentRecord> = candidates
        .iter()
        .filter(|i| (i.qty_q - query.qty_q).abs() < 1e-9)
        .copied()
        .collect();
    if qty_matches.len() == 1 {
        return MatchResult::Matched(qty_matches[0].clone());
    }

    // Still ambiguous → Degraded
    let remaining = if qty_matches.is_empty() {
        candidates.len()
    } else {
        qty_matches.len()
    };

    metrics.record_ambiguity();
    MatchResult::Ambiguous {
        remaining,
        risk_state: RiskState::Degraded,
    }
}
