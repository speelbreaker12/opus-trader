//! Recovery primitives: label matching, reconciliation.

pub mod label_match;

pub use label_match::{IntentRecord, LabelMatchMetrics, MatchQuery, MatchResult, match_label};
