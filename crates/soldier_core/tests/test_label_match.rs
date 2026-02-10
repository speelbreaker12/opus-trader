//! Tests for label match disambiguation per CONTRACT.md §1.1.2.
//!
//! AT-217: tie-breaker disambiguation and ambiguity → Degraded.

use soldier_core::recovery::{
    IntentRecord, LabelMatchMetrics, MatchQuery, MatchResult, match_label,
};
use soldier_core::risk::RiskState;

/// Helper to build a standard intent record.
fn intent(
    gid12: &str,
    leg_idx: u32,
    ih16: &str,
    instrument: &str,
    side: &str,
    qty_q: f64,
) -> IntentRecord {
    IntentRecord {
        gid12: gid12.to_string(),
        leg_idx,
        ih16: ih16.to_string(),
        instrument: instrument.to_string(),
        side: side.to_string(),
        qty_q,
    }
}

/// Helper to build a query.
fn query<'a>(
    gid12: &'a str,
    leg_idx: u32,
    ih16: &'a str,
    instrument: &'a str,
    side: &'a str,
    qty_q: f64,
) -> MatchQuery<'a> {
    MatchQuery {
        gid12,
        leg_idx,
        ih16,
        instrument,
        side,
        qty_q,
    }
}

// ─── Single candidate ──────────────────────────────────────────────────

/// Single candidate by gid12 + leg_idx → immediate match
#[test]
fn test_single_candidate_matches() {
    let intents = [intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0)];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0);

    let result = match_label(&q, &intents, &mut metrics);
    match result {
        MatchResult::Matched(r) => assert_eq!(r.ih16, "aaaa"),
        other => panic!("expected Matched, got {other:?}"),
    }
    assert_eq!(metrics.ambiguity_total(), 0);
}

// ─── No candidates ─────────────────────────────────────────────────────

/// No matching gid12 + leg_idx → NoMatch
#[test]
fn test_no_candidates() {
    let intents = [intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0)];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("different_gid", 0, "aaaa", "BTC-PERP", "buy", 1.0);

    assert_eq!(
        match_label(&q, &intents, &mut metrics),
        MatchResult::NoMatch
    );
}

/// Wrong leg_idx → NoMatch
#[test]
fn test_wrong_leg_idx_no_match() {
    let intents = [intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0)];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 1, "aaaa", "BTC-PERP", "buy", 1.0);

    assert_eq!(
        match_label(&q, &intents, &mut metrics),
        MatchResult::NoMatch
    );
}

// ─── Tie-breaker A: ih16 ───────────────────────────────────────────────

/// Two candidates, ih16 disambiguates
#[test]
fn test_tiebreaker_ih16() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "bbbb", "BTC-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "bbbb", "BTC-PERP", "buy", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => assert_eq!(r.ih16, "bbbb"),
        other => panic!("expected Matched via ih16, got {other:?}"),
    }
    assert_eq!(metrics.ambiguity_total(), 0);
}

// ─── Tie-breaker B: instrument ─────────────────────────────────────────

/// ih16 doesn't disambiguate, instrument does
#[test]
fn test_tiebreaker_instrument() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "aaaa", "ETH-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "ETH-PERP", "buy", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => assert_eq!(r.instrument, "ETH-PERP"),
        other => panic!("expected Matched via instrument, got {other:?}"),
    }
}

// ─── Tie-breaker C: side ───────────────────────────────────────────────

/// ih16 + instrument same, side disambiguates
#[test]
fn test_tiebreaker_side() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "sell", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "sell", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => assert_eq!(r.side, "sell"),
        other => panic!("expected Matched via side, got {other:?}"),
    }
}

// ─── Tie-breaker D: qty_q ─────────────────────────────────────────────

/// All prior tie-breakers same, qty_q disambiguates
#[test]
fn test_tiebreaker_qty_q() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 2.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 2.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => assert!((r.qty_q - 2.0).abs() < 1e-9),
        other => panic!("expected Matched via qty_q, got {other:?}"),
    }
}

// ─── Ambiguity → Degraded ──────────────────────────────────────────────

/// All tie-breakers exhausted → Ambiguous with Degraded
#[test]
fn test_ambiguity_returns_degraded() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Ambiguous {
            remaining,
            risk_state,
        } => {
            assert_eq!(remaining, 2);
            assert_eq!(risk_state, RiskState::Degraded);
        }
        other => panic!("expected Ambiguous, got {other:?}"),
    }
}

/// Ambiguity increments counter
#[test]
fn test_ambiguity_increments_counter() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0);
    assert_eq!(metrics.ambiguity_total(), 0);

    let _ = match_label(&q, &intents, &mut metrics);
    assert_eq!(metrics.ambiguity_total(), 1);

    let _ = match_label(&q, &intents, &mut metrics);
    assert_eq!(metrics.ambiguity_total(), 2);
}

// ─── Determinism ───────────────────────────────────────────────────────

/// Same inputs → same result (deterministic)
#[test]
fn test_deterministic_matching() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "bbbb", "ETH-PERP", "sell", 2.0),
    ];
    let mut m1 = LabelMatchMetrics::new();
    let mut m2 = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "bbbb", "ETH-PERP", "sell", 2.0);

    let r1 = match_label(&q, &intents, &mut m1);
    let r2 = match_label(&q, &intents, &mut m2);
    assert_eq!(r1, r2);
}

// ─── Edge cases ────────────────────────────────────────────────────────

/// Empty intent list → NoMatch
#[test]
fn test_empty_intents() {
    let intents: Vec<IntentRecord> = vec![];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0);

    assert_eq!(
        match_label(&q, &intents, &mut metrics),
        MatchResult::NoMatch
    );
}

/// Three candidates, ih16 narrows to one
#[test]
fn test_three_candidates_ih16_resolves() {
    let intents = [
        intent("550e8400e29b", 0, "aaaa", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "bbbb", "BTC-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "cccc", "BTC-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    let q = query("550e8400e29b", 0, "cccc", "BTC-PERP", "buy", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => assert_eq!(r.ih16, "cccc"),
        other => panic!("expected Matched, got {other:?}"),
    }
    assert_eq!(metrics.ambiguity_total(), 0);
}

/// Tie-breaker order: ih16 before instrument
#[test]
fn test_tiebreaker_order_ih16_before_instrument() {
    let intents = [
        intent("550e8400e29b", 0, "target", "ETH-PERP", "buy", 1.0),
        intent("550e8400e29b", 0, "other", "BTC-PERP", "buy", 1.0),
    ];
    let mut metrics = LabelMatchMetrics::new();
    // ih16="target" matches first intent, instrument="BTC-PERP" matches second
    // ih16 should win (it's evaluated first)
    let q = query("550e8400e29b", 0, "target", "BTC-PERP", "buy", 1.0);

    match match_label(&q, &intents, &mut metrics) {
        MatchResult::Matched(r) => {
            assert_eq!(r.ih16, "target", "ih16 tie-breaker must take priority");
        }
        other => panic!("expected Matched via ih16, got {other:?}"),
    }
}
