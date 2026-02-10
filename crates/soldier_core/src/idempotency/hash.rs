//! Intent hash computation per CONTRACT.md §1.1.1.
//!
//! `intent_hash = xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`
//!
//! **Hard rule:** Do NOT include wall-clock timestamps in the idempotency hash.
//! All inputs MUST be quantized integer values (qty_steps, price_ticks),
//! not raw f64.

use xxhash_rust::xxh64::xxh64;

/// Input fields for computing an intent hash.
///
/// All fields are deterministic and stable. No timestamps.
/// `qty_steps` and `price_ticks` are integer values from quantization.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IntentHashInput<'a> {
    /// Instrument identifier (e.g., "BTC-PERPETUAL").
    pub instrument: &'a str,
    /// Order side as a stable string ("buy" or "sell").
    pub side: &'a str,
    /// Quantized quantity as integer steps: `floor(raw_qty / amount_step)`.
    pub qty_steps: i64,
    /// Quantized price as integer ticks (direction-dependent).
    pub price_ticks: i64,
    /// UUIDv4 shared by all legs in a single atomic attempt.
    pub group_id: &'a str,
    /// Leg index within the group (0 or 1).
    pub leg_idx: u32,
}

/// Compute the intent hash from quantized fields.
///
/// CONTRACT.md §1.1.1:
/// `intent_hash = xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`
///
/// Uses integer qty_steps and price_ticks (not raw floats) for determinism.
/// Excludes all wall-clock timestamps (AT-343).
pub fn compute_intent_hash(input: &IntentHashInput<'_>) -> u64 {
    // Build a deterministic byte buffer from the canonical fields.
    // Use a separator byte (0xFF) that cannot appear in UTF-8 strings
    // to prevent field-boundary ambiguity.
    let mut buf = Vec::with_capacity(128);

    buf.extend_from_slice(input.instrument.as_bytes());
    buf.push(0xFF);
    buf.extend_from_slice(input.side.as_bytes());
    buf.push(0xFF);
    buf.extend_from_slice(&input.qty_steps.to_le_bytes());
    buf.push(0xFF);
    buf.extend_from_slice(&input.price_ticks.to_le_bytes());
    buf.push(0xFF);
    buf.extend_from_slice(input.group_id.as_bytes());
    buf.push(0xFF);
    buf.extend_from_slice(&input.leg_idx.to_le_bytes());

    xxh64(&buf, 0)
}

/// Format an intent hash as a hex string.
pub fn format_intent_hash(hash: u64) -> String {
    format!("{hash:016x}")
}

/// Extract the first 16 characters of a formatted intent hash (ih16).
///
/// Used in s4 labels for collision-safe matching (CONTRACT.md §1.1.2).
pub fn intent_hash_ih16(hash: u64) -> String {
    format_intent_hash(hash)
}
