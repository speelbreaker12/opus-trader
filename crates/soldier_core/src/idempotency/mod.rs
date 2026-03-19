//! Idempotency subsystem.
//!
//! Owns: intent hash computation and deduplication.
//!
//! **Public:** intent hash input, computation, formatting, and ih16 extraction.
//!
//! **Private:** `hash`.
//!
//! **Tests:** facade completeness in `facade_completeness_contract_tests.rs`;
//! integration tests under `tests/` covering the public idempotency surface.

mod hash;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use hash::{IntentHashInput, compute_intent_hash, format_intent_hash, intent_hash_ih16};
