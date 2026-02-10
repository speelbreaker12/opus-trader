//! Idempotency primitives: intent hashing and deduplication.

pub mod hash;

pub use hash::{IntentHashInput, compute_intent_hash, format_intent_hash, intent_hash_ih16};
