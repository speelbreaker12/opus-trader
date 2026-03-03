//! Compact label schema per CONTRACT.md §1.1.
//!
//! Canonical outbound format: `s4:{sid8}:{gid12}:{li}:{ih16}`
//!
//! - `sid8` = first 8 lowercase chars of RFC4648 base32 (no padding) over
//!   xxhash64(strategy_id), with the hash encoded as 8-byte big-endian.
//! - `gid12` = first 12 chars of group_id (UUID without dashes, truncated)
//! - `li` = leg_idx (0 or 1)
//! - `ih16` = 16-hex intent hash
//!
//! Deribit constraint: label MUST be <= 64 chars.
//! If a computed label would exceed 64 chars, reject with `LabelTooLong`.
//! Truncation MUST NOT occur.

/// Maximum label length per Deribit constraint.
pub const LABEL_MAX_LEN: usize = 64;
/// Canonical exchange-wire label prefix.
pub const EXCHANGE_LABEL_PREFIX: &str = "s4:";
/// Human-readable documentation prefix (must never be sent to venue).
#[allow(dead_code)] // Reserved for docs/examples; exchange path must use EXCHANGE_LABEL_PREFIX.
pub const HUMAN_LABEL_PREFIX: &str = "s4doc:";

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
        "{}{}:{}:{}:{}",
        EXCHANGE_LABEL_PREFIX, input.sid8, input.gid12, input.leg_idx, input.ih16
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
    if !label.starts_with(EXCHANGE_LABEL_PREFIX) {
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
/// CONTRACT.md §1.1:
/// first 8 lowercase chars of RFC4648 base32 (no padding) over
/// xxhash64(strategy_id) encoded as 8-byte big-endian.
pub fn derive_sid8(strat_id: &str) -> String {
    let hash = xxhash_rust::xxh64::xxh64(strat_id.as_bytes(), 0);
    let base32 = rfc4648_base32_nopad_lower(&hash.to_be_bytes());
    base32[..8].to_string()
}

/// Derive `gid12` from a UUID group_id string.
///
/// Strips dashes from the UUID and takes the first 12 chars.
pub fn derive_gid12(group_id: &str) -> String {
    let no_dashes: String = group_id.chars().filter(|c| *c != '-').collect();
    no_dashes[..12.min(no_dashes.len())].to_string()
}

fn rfc4648_base32_nopad_lower(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";
    let mut out = String::new();
    let mut bit_buffer: u32 = 0;
    let mut bit_count: u8 = 0;

    for &byte in bytes {
        bit_buffer = (bit_buffer << 8) | byte as u32;
        bit_count += 8;
        while bit_count >= 5 {
            let shift = bit_count - 5;
            let idx = ((bit_buffer >> shift) & 0x1f) as usize;
            out.push(ALPHABET[idx] as char);
            bit_count -= 5;
            bit_buffer &= (1u32 << shift) - 1;
        }
    }

    if bit_count > 0 {
        let idx = ((bit_buffer << (5 - bit_count)) & 0x1f) as usize;
        out.push(ALPHABET[idx] as char);
    }

    out
}

#[cfg(test)]
#[path = "label_tests.rs"]
mod label_tests;

#[cfg(test)]
#[path = "label_prop_tests.rs"]
mod label_prop_tests;
