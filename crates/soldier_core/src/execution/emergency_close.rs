//! Deterministic emergency-close fallback price selection.
//!
//! CONTRACT.md §3.1:
//! - AT-937: fresh L1 fallback when L2 is unavailable.
//! - AT-938: venue-band fallback when L2/L1 are unavailable.
//! - AT-1217: fail closed with no price when all sources are unavailable.
//! - AT-1239: venue-band fallback requires fresh instrument metadata.

use super::quantize::Side;

/// Top-of-book snapshot used by emergency-close fallback selection.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmergencyTopOfBookSnapshot {
    pub best_bid: f64,
    pub best_ask: f64,
    pub timestamp_ms: u64,
}

/// Venue metadata band used as the emergency fallback source.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmergencyVenueBand {
    pub min_price: f64,
    pub max_price: f64,
    pub tick_size: f64,
}

/// Inputs required to choose an emergency-close fallback price.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmergencyClosePriceInput {
    pub side: Side,
    pub now_ms: u64,
    pub l2_book_snapshot_max_age_ms: u64,
    pub instrument_cache_age_s: f64,
    pub instrument_cache_ttl_s: f64,
    pub l2: Option<EmergencyTopOfBookSnapshot>,
    pub l1: Option<EmergencyTopOfBookSnapshot>,
    pub venue_band: Option<EmergencyVenueBand>,
}

/// Which source produced the chosen emergency-close price.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EmergencyClosePriceSource {
    L2,
    L1,
    VenueBand,
}

/// Selected emergency-close best price and its source.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EmergencyClosePriceSelection {
    pub source: EmergencyClosePriceSource,
    pub best_price: f64,
}

/// Choose emergency-close best price from L2 -> L1 -> venue-band.
///
/// Returns `None` when no valid source exists.
pub fn select_emergency_close_best_price(
    input: &EmergencyClosePriceInput,
) -> Option<EmergencyClosePriceSelection> {
    if let Some(best_price) = best_price_from_snapshot(
        input.side,
        input.l2,
        input.now_ms,
        input.l2_book_snapshot_max_age_ms,
    ) {
        return Some(EmergencyClosePriceSelection {
            source: EmergencyClosePriceSource::L2,
            best_price,
        });
    }

    if let Some(best_price) = best_price_from_snapshot(
        input.side,
        input.l1,
        input.now_ms,
        input.l2_book_snapshot_max_age_ms,
    ) {
        return Some(EmergencyClosePriceSelection {
            source: EmergencyClosePriceSource::L1,
            best_price,
        });
    }

    let best_price = best_price_from_venue_band(
        input.side,
        input.venue_band,
        input.instrument_cache_age_s,
        input.instrument_cache_ttl_s,
    )?;
    Some(EmergencyClosePriceSelection {
        source: EmergencyClosePriceSource::VenueBand,
        best_price,
    })
}

fn best_price_from_snapshot(
    side: Side,
    snapshot: Option<EmergencyTopOfBookSnapshot>,
    now_ms: u64,
    max_age_ms: u64,
) -> Option<f64> {
    let snapshot = snapshot?;
    if !snapshot_is_fresh(snapshot.timestamp_ms, now_ms, max_age_ms) {
        return None;
    }

    let best_price = match side {
        Side::Buy => snapshot.best_ask,
        Side::Sell => snapshot.best_bid,
    };
    if !best_price.is_finite() || best_price <= 0.0 {
        return None;
    }
    Some(best_price)
}

fn snapshot_is_fresh(timestamp_ms: u64, now_ms: u64, max_age_ms: u64) -> bool {
    if timestamp_ms > now_ms {
        return false;
    }
    now_ms - timestamp_ms <= max_age_ms
}

fn best_price_from_venue_band(
    side: Side,
    venue_band: Option<EmergencyVenueBand>,
    instrument_cache_age_s: f64,
    instrument_cache_ttl_s: f64,
) -> Option<f64> {
    if !instrument_metadata_fresh(instrument_cache_age_s, instrument_cache_ttl_s) {
        return None;
    }

    let venue_band = venue_band?;
    if !venue_band.min_price.is_finite()
        || !venue_band.max_price.is_finite()
        || venue_band.min_price <= 0.0
        || venue_band.max_price <= 0.0
        || venue_band.max_price < venue_band.min_price
    {
        return None;
    }
    if !venue_band.tick_size.is_finite() || venue_band.tick_size <= 0.0 {
        return None;
    }

    let raw_price = match side {
        Side::Buy => venue_band.max_price,
        Side::Sell => venue_band.min_price,
    };
    quantize_price(raw_price, venue_band.tick_size, side)
}

fn instrument_metadata_fresh(instrument_cache_age_s: f64, instrument_cache_ttl_s: f64) -> bool {
    if !instrument_cache_age_s.is_finite() || !instrument_cache_ttl_s.is_finite() {
        return false;
    }
    if instrument_cache_age_s < 0.0 || instrument_cache_ttl_s <= 0.0 {
        return false;
    }
    instrument_cache_age_s <= instrument_cache_ttl_s
}

fn quantize_price(raw_price: f64, tick_size: f64, side: Side) -> Option<f64> {
    if !raw_price.is_finite() || raw_price <= 0.0 {
        return None;
    }
    let ratio = raw_price / tick_size;
    if !ratio.is_finite() {
        return None;
    }
    let ticks = match side {
        Side::Buy => ratio.floor(),
        Side::Sell => ratio.ceil(),
    };
    let quantized = ticks * tick_size;
    if !quantized.is_finite() || quantized <= 0.0 {
        return None;
    }
    Some(quantized)
}
