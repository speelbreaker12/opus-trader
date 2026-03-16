//! Emergency-close fallback ladder tests (CONTRACT.md §3.1).
//!
//! AT-937, AT-938, AT-1217, AT-1239

use soldier_core::execution::{
    EmergencyClosePriceInput, EmergencyClosePriceSource, EmergencyTopOfBookSnapshot,
    EmergencyVenueBand, Side, select_emergency_close_best_price,
};

fn base_input(side: Side) -> EmergencyClosePriceInput {
    EmergencyClosePriceInput {
        side,
        now_ms: 10_000,
        book_snapshot_max_age_ms: 1_000,
        instrument_cache_age_s: 10.0,
        instrument_cache_ttl_s: 3_600.0,
        l2: None,
        l1: None,
        venue_band: None,
    }
}

#[test]
fn test_at937_fresh_l1_fallback_used_when_l2_unavailable() {
    let mut input = base_input(Side::Buy);
    input.l1 = Some(EmergencyTopOfBookSnapshot {
        best_bid: 99.5,
        best_ask: 100.0,
        timestamp_ms: 9_500, // fresh (age=500ms)
    });

    let selected = select_emergency_close_best_price(&input)
        .expect("fresh L1 fallback should produce an emergency-close price");
    assert_eq!(selected.source, EmergencyClosePriceSource::L1);
    assert!((selected.best_price - 100.0).abs() < 1e-9);
}

#[test]
fn test_at938_venue_band_fallback_used_when_l2_l1_unavailable_and_metadata_fresh() {
    let mut input = base_input(Side::Buy);
    input.l1 = Some(EmergencyTopOfBookSnapshot {
        best_bid: 99.5,
        best_ask: 100.0,
        timestamp_ms: 1_000, // stale (age=9000ms)
    });
    input.venue_band = Some(EmergencyVenueBand {
        min_price: 99.91,
        max_price: 100.09,
        tick_size: 0.1,
    });

    let selected = select_emergency_close_best_price(&input)
        .expect("fresh metadata + valid venue-band must produce fallback price");
    assert_eq!(selected.source, EmergencyClosePriceSource::VenueBand);
    // BUY venue-band fallback: use max_price, quantized to tick via floor.
    assert!((selected.best_price - 100.0).abs() < 1e-9);
}

#[test]
fn test_at1217_no_price_when_all_sources_unavailable() {
    let input = base_input(Side::Sell);
    let selected = select_emergency_close_best_price(&input);
    assert!(
        selected.is_none(),
        "no L2/L1/venue-band source must fail closed with no price"
    );
}

#[test]
fn test_at1239_stale_instrument_metadata_blocks_venue_band_fallback() {
    let mut input = base_input(Side::Buy);
    input.instrument_cache_age_s = 3_601.0; // stale
    input.instrument_cache_ttl_s = 3_600.0;
    input.venue_band = Some(EmergencyVenueBand {
        min_price: 99.0,
        max_price: 101.0,
        tick_size: 0.5,
    });

    let selected = select_emergency_close_best_price(&input);
    assert!(
        selected.is_none(),
        "stale metadata must disable venue-band fallback"
    );
}

#[test]
fn test_l2_priority_over_l1_when_both_fresh() {
    // Mutation-6 guard: a wrong impl that checks L1 first would still pass AT-937
    // (L2=None there). This test proves L2 takes priority over L1 when BOTH are fresh.
    let mut input = base_input(Side::Sell);
    input.l2 = Some(EmergencyTopOfBookSnapshot {
        best_bid: 99.80,
        best_ask: 100.20,
        timestamp_ms: 9_800, // fresh (age=200ms)
    });
    input.l1 = Some(EmergencyTopOfBookSnapshot {
        best_bid: 99.70,
        best_ask: 100.30,
        timestamp_ms: 9_500, // also fresh (age=500ms)
    });

    let selected =
        select_emergency_close_best_price(&input).expect("both L2 and L1 fresh → L2 must win");
    assert_eq!(
        selected.source,
        EmergencyClosePriceSource::L2,
        "L2 must take priority over L1 even when both snapshots are fresh"
    );
    assert!((selected.best_price - 99.80).abs() < 1e-9); // Sell → best_bid
}

#[test]
fn test_boundary_cache_age_equals_ttl_allows_venue_band() {
    // Off-by-one guard: instrument_metadata_fresh uses `age <= ttl` (inclusive).
    // age == ttl must be treated as fresh (venue-band allowed).
    let mut input = base_input(Side::Buy);
    input.instrument_cache_age_s = 3_600.0;
    input.instrument_cache_ttl_s = 3_600.0;
    input.venue_band = Some(EmergencyVenueBand {
        min_price: 99.0,
        max_price: 101.0,
        tick_size: 0.5,
    });

    let selected = select_emergency_close_best_price(&input)
        .expect("age == ttl is fresh (<=), venue-band must be allowed");
    assert_eq!(selected.source, EmergencyClosePriceSource::VenueBand);
}

#[test]
fn test_inverted_venue_band_fails_closed() {
    // Mutation-A7 guard: a wrong impl that omits the `max_price < min_price` guard
    // in `best_price_from_venue_band` would compute and return a valid-looking price
    // (e.g. 99.0) for an inverted band. This test proves the guard is present.
    let mut input = base_input(Side::Buy);
    input.venue_band = Some(EmergencyVenueBand {
        min_price: 101.0,
        max_price: 99.0, // inverted: max < min
        tick_size: 0.5,
    });
    assert!(
        select_emergency_close_best_price(&input).is_none(),
        "inverted venue-band (max_price < min_price) must fail closed with no price"
    );
}

#[test]
fn test_fix01_neighbor_fresh_l2_wins_even_if_metadata_stale() {
    let mut input = base_input(Side::Sell);
    input.instrument_cache_age_s = 7_200.0; // stale metadata
    input.instrument_cache_ttl_s = 3_600.0;
    input.l2 = Some(EmergencyTopOfBookSnapshot {
        best_bid: 99.75,
        best_ask: 100.25,
        timestamp_ms: 9_900, // fresh (age=100ms)
    });
    input.venue_band = Some(EmergencyVenueBand {
        min_price: 98.0,
        max_price: 102.0,
        tick_size: 0.5,
    });

    let selected =
        select_emergency_close_best_price(&input).expect("fresh L2 should be selected first");
    assert_eq!(selected.source, EmergencyClosePriceSource::L2);
    assert!((selected.best_price - 99.75).abs() < 1e-9);
}
