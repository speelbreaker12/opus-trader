//! Compile-time proof that intended facade symbols are reachable via
//! `crate::recovery::{...}`.

#[allow(unused_imports)]
use crate::recovery::{IntentRecord, LabelMatchMetrics, MatchQuery, MatchResult, match_label};

#[test]
fn facade_symbols_reachable_via_recovery_facade() {
    let query = MatchQuery {
        gid12: "abcdef012345",
        leg_idx: 0,
        ih16: "0000000000000000",
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_q: 1.0,
    };
    let records: &[IntentRecord] = &[];
    let mut metrics = LabelMatchMetrics::new();
    let result: MatchResult = match_label(&query, records, &mut metrics);
    assert_eq!(result, MatchResult::NoMatch);
}
