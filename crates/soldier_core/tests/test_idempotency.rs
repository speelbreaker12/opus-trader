//! Tests for intent hash computation per CONTRACT.md §1.1.1.
//!
//! AT-218: deterministic hash across codepaths.
//! AT-343: hash excludes wall-clock timestamps.

use soldier_core::idempotency::{
    IntentHashInput, compute_intent_hash, format_intent_hash, intent_hash_ih16,
};

/// Helper to build a standard test input.
fn sample_input() -> IntentHashInput<'static> {
    IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 3000,
        price_ticks: 100_000,
        group_id: "550e8400-e29b-41d4-a716-446655440000",
        leg_idx: 0,
    }
}

// ─── AT-218: Deterministic hashing ─────────────────────────────────────

/// AT-218: same inputs → same hash
#[test]
fn test_at218_deterministic_hash() {
    let input = sample_input();
    let h1 = compute_intent_hash(&input);
    let h2 = compute_intent_hash(&input);
    assert_eq!(h1, h2, "identical inputs must produce identical hashes");
}

/// AT-218: two codepaths with same fields → same hash
#[test]
fn test_at218_two_codepaths_same_hash() {
    let input_a = IntentHashInput {
        instrument: "ETH-PERPETUAL",
        side: "sell",
        qty_steps: 500,
        price_ticks: 3_500_000,
        group_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        leg_idx: 1,
    };
    // Construct independently
    let input_b = IntentHashInput {
        instrument: "ETH-PERPETUAL",
        side: "sell",
        qty_steps: 500,
        price_ticks: 3_500_000,
        group_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        leg_idx: 1,
    };
    assert_eq!(
        compute_intent_hash(&input_a),
        compute_intent_hash(&input_b),
        "independently constructed identical inputs must hash equally"
    );
}

// ─── AT-343: No wall-clock dependency ──────────────────────────────────

/// AT-343: hash does not include timestamps — same fields at different
/// "times" produce the same hash.
#[test]
fn test_at343_no_timestamp_in_hash() {
    // The IntentHashInput struct has no timestamp field at all,
    // proving timestamps cannot influence the hash.
    let input = sample_input();
    let h1 = compute_intent_hash(&input);
    // "Simulate" a different wall-clock time by just calling again
    let h2 = compute_intent_hash(&input);
    assert_eq!(
        h1, h2,
        "hash must be identical regardless of when it's computed"
    );
}

/// AT-343: IntentHashInput has no timestamp field (compile-time proof).
/// This test proves the struct cannot carry time data.
#[test]
fn test_at343_no_timestamp_field() {
    // If someone adds a timestamp field to IntentHashInput,
    // this test will fail to compile (wrong number of fields).
    let _input = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "test",
        leg_idx: 0,
    };
}

// ─── Hash uses integer values ──────────────────────────────────────────

/// Hash uses qty_steps (integer), not raw f64
#[test]
fn test_uses_integer_qty_steps() {
    let mut input = sample_input();
    input.qty_steps = 3000;
    let h1 = compute_intent_hash(&input);

    input.qty_steps = 3001;
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2, "different qty_steps must produce different hashes");
}

/// Hash uses price_ticks (integer), not raw f64
#[test]
fn test_uses_integer_price_ticks() {
    let mut input = sample_input();
    input.price_ticks = 100_000;
    let h1 = compute_intent_hash(&input);

    input.price_ticks = 100_001;
    let h2 = compute_intent_hash(&input);
    assert_ne!(
        h1, h2,
        "different price_ticks must produce different hashes"
    );
}

// ─── Field sensitivity ─────────────────────────────────────────────────

/// Different instrument → different hash
#[test]
fn test_different_instrument_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.instrument = "ETH-PERPETUAL";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different side → different hash
#[test]
fn test_different_side_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.side = "sell";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different group_id → different hash
#[test]
fn test_different_group_id_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.group_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different leg_idx → different hash
#[test]
fn test_different_leg_idx_different_hash() {
    let mut input = sample_input();
    input.leg_idx = 0;
    let h1 = compute_intent_hash(&input);

    input.leg_idx = 1;
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

// ─── Formatting ────────────────────────────────────────────────────────

/// format_intent_hash produces 16-char hex string
#[test]
fn test_format_intent_hash_length() {
    let hash = compute_intent_hash(&sample_input());
    let formatted = format_intent_hash(hash);
    assert_eq!(formatted.len(), 16, "xxhash64 hex must be 16 chars");
    assert!(
        formatted.chars().all(|c| c.is_ascii_hexdigit()),
        "must be hex"
    );
}

/// ih16 is the full 16-char hex (xxhash64 is 64 bits = 16 hex chars)
#[test]
fn test_ih16_is_full_hash_hex() {
    let hash = compute_intent_hash(&sample_input());
    let ih16 = intent_hash_ih16(hash);
    let formatted = format_intent_hash(hash);
    assert_eq!(ih16, formatted, "ih16 should be full formatted hash");
}

// ─── Non-zero hash ─────────────────────────────────────────────────────

/// Hash is non-zero for typical inputs
#[test]
fn test_hash_nonzero() {
    let hash = compute_intent_hash(&sample_input());
    assert_ne!(hash, 0, "hash should not be zero for typical inputs");
}

// ─── Field boundary safety ─────────────────────────────────────────────

/// Fields with shifted boundaries produce different hashes
/// (e.g., instrument="AB" + side="CD" vs instrument="ABC" + side="D")
#[test]
fn test_field_boundary_separation() {
    let input_a = IntentHashInput {
        instrument: "AB",
        side: "CD",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };
    let input_b = IntentHashInput {
        instrument: "ABC",
        side: "D",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };
    assert_ne!(
        compute_intent_hash(&input_a),
        compute_intent_hash(&input_b),
        "shifted field boundaries must produce different hashes"
    );
}
