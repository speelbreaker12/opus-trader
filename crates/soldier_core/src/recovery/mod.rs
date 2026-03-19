//! Recovery subsystem.
//!
//! Owns: label-match disambiguation.
//!
//! **Public:** intent record, match query/result, label match metrics,
//! and `match_label`.
//!
//! **Private:** `label_match`.
//!
//! **Tests:** facade completeness in `facade_completeness_contract_tests.rs`;
//! integration tests under `tests/` covering the public recovery surface.

mod label_match;

#[cfg(test)]
mod facade_completeness_contract_tests;

pub use label_match::{IntentRecord, LabelMatchMetrics, MatchQuery, MatchResult, match_label};
