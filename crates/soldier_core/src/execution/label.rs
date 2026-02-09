//! Compact label schema per CONTRACT.md §1.1.
//!
//! Canonical outbound format: `s4:{sid8}:{gid12}:{li}:{ih16}`
//!
//! - `sid8` = first 8 chars of stable strategy id hash
//! - `gid12` = first 12 chars of group_id (UUID without dashes, truncated)
//! - `li` = leg_idx (0 or 1)
//! - `ih16` = 16-hex intent hash
//!
//! Deribit constraint: label MUST be <= 64 chars.
//! If a computed label would exceed 64 chars, reject with `LabelTooLong`.
//! Truncation MUST NOT occur.

/// Maximum label length per Deribit constraint.
pub const LABEL_MAX_LEN: usize = 64;

/// Input fields for encoding an s4 label.
#[derive(Debug, Clone)]
pub struct LabelInput<'a> {
    /// First 8 chars of the strategy ID hash.
    pub sid8: &'a str,
    /// First 12 chars of the group_id (UUID without dashes).
    pub gid12: &'a str,
    /// Leg index within the group (0 or 1).
    pub leg_idx: u32,
    /// 16-hex intent hash string.
    pub ih16: &'a str,
}

/// Parsed components from a decoded s4 label.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedLabel {
    /// Strategy ID hash prefix (8 chars).
    pub sid8: String,
    /// Group ID prefix (12 chars).
    pub gid12: String,
    /// Leg index.
    pub leg_idx: u32,
    /// Intent hash prefix (16 hex chars).
    pub ih16: String,
}

/// Error returned when label encoding or decoding fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LabelError {
    /// CONTRACT.md: computed label exceeds 64 chars → reject, no truncation.
    /// Caller MUST set `RiskState::Degraded`.
    LabelTooLong {
        /// The computed label length.
        len: usize,
    },
    /// Label does not start with "s4:" prefix.
    InvalidPrefix,
    /// Label has wrong number of segments (expected 5).
    WrongSegmentCount {
        /// Actual number of segments found.
        count: usize,
    },
    /// leg_idx segment is not a valid integer.
    InvalidLegIdx,
}

/// Encode an s4 label from its components.
///
/// Format: `s4:{sid8}:{gid12}:{li}:{ih16}`
///
/// Returns `Err(LabelTooLong)` if the result exceeds 64 chars.
/// Truncation MUST NOT occur (CONTRACT.md).
pub fn encode_label(input: &LabelInput<'_>) -> Result<String, LabelError> {
    let label = format!(
        "s4:{}:{}:{}:{}",
        input.sid8, input.gid12, input.leg_idx, input.ih16
    );

    if label.len() > LABEL_MAX_LEN {
        return Err(LabelError::LabelTooLong { len: label.len() });
    }

    Ok(label)
}

/// Decode (parse) an s4 label into its components.
///
/// Expected format: `s4:{sid8}:{gid12}:{li}:{ih16}`
pub fn decode_label(label: &str) -> Result<ParsedLabel, LabelError> {
    if !label.starts_with("s4:") {
        return Err(LabelError::InvalidPrefix);
    }

    let parts: Vec<&str> = label.split(':').collect();
    // Expected: ["s4", sid8, gid12, li, ih16]
    if parts.len() != 5 {
        return Err(LabelError::WrongSegmentCount { count: parts.len() });
    }

    let leg_idx: u32 = parts[3].parse().map_err(|_| LabelError::InvalidLegIdx)?;

    Ok(ParsedLabel {
        sid8: parts[1].to_string(),
        gid12: parts[2].to_string(),
        leg_idx,
        ih16: parts[4].to_string(),
    })
}

/// Derive `sid8` from a strategy ID string.
///
/// Uses xxhash64 of the strategy ID, then takes the first 8 hex chars.
pub fn derive_sid8(strat_id: &str) -> String {
    let hash = xxhash_rust::xxh64::xxh64(strat_id.as_bytes(), 0);
    format!("{hash:016x}")[..8].to_string()
}

/// Derive `gid12` from a UUID group_id string.
///
/// Strips dashes from the UUID and takes the first 12 chars.
pub fn derive_gid12(group_id: &str) -> String {
    let no_dashes: String = group_id.chars().filter(|c| *c != '-').collect();
    no_dashes[..12.min(no_dashes.len())].to_string()
}
