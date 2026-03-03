//! Intent hash computation per CONTRACT.md §1.1.1.
//!
//! `intent_hash = xxhash64(canonical_intent_bytes)`
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
/// `intent_hash = xxhash64(canonical_intent_bytes)`
///
/// Uses integer qty_steps and price_ticks (not raw floats) for determinism.
/// Excludes all wall-clock timestamps (AT-343).
pub fn compute_intent_hash(input: &IntentHashInput<'_>) -> u64 {
    let canonical = canonical_intent_string_v1(input);
    xxh64(canonical.as_bytes(), 0)
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

fn canonical_intent_string_v1(input: &IntentHashInput<'_>) -> String {
    format!(
        "v1|{}|{}|{}|{}|{}|{}",
        input.instrument.to_lowercase(),
        input.side.to_lowercase(),
        input.qty_steps,
        input.price_ticks,
        input.group_id.replace('-', "").to_lowercase(),
        input.leg_idx
    )
}
