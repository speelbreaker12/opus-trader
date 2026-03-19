//! Compile-time proof that intended facade symbols are reachable via
//! `crate::idempotency::{...}`.

#[allow(unused_imports)]
use crate::idempotency::{
    IntentHashInput, compute_intent_hash, format_intent_hash, intent_hash_ih16,
};

#[test]
fn facade_symbols_reachable_via_idempotency_facade() {
    let input = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 10,
        price_ticks: 50000,
        group_id: "g1",
        leg_idx: 0,
    };
    let hash = compute_intent_hash(&input);
    let _formatted = format_intent_hash(hash);
    let _short = intent_hash_ih16(hash);
}
