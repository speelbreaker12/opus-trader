//! Property-based tests for the label encoding/decoding (CONTRACT.md §1.1).
//!
//! Properties under test:
//! - decode(encode(x)) == x roundtrip for valid inputs.
//! - Encoded label length never exceeds LABEL_MAX_LEN (64).
//! - Invalid prefix produces InvalidPrefix error.
//! - Wrong segment count produces WrongSegmentCount error.
//! - encode never panics.
//! - decode never panics.

use super::{LABEL_MAX_LEN, LabelError, LabelInput, decode_label, encode_label};
use proptest::prelude::*;

/// Strategy for hex strings of a specific length.
fn hex_string(len: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop::sample::select(
            &[
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
            ][..],
        ),
        len,
    )
    .prop_map(|chars| chars.into_iter().collect::<String>())
}

/// Strategy for valid sid8 (8 hex chars).
fn sid8_strategy() -> impl Strategy<Value = String> {
    hex_string(8)
}

/// Strategy for valid gid12 (12 hex chars).
fn gid12_strategy() -> impl Strategy<Value = String> {
    hex_string(12)
}

/// Strategy for valid ih16 (16 hex chars).
fn ih16_strategy() -> impl Strategy<Value = String> {
    hex_string(16)
}

/// Strategy for leg_idx (0 or 1 per spec, but allow broader range).
fn leg_idx_strategy() -> impl Strategy<Value = u32> {
    0..=9u32
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// Roundtrip: decode(encode(input)) reconstructs the original fields.
    #[test]
    fn encode_decode_roundtrip(
        sid8 in sid8_strategy(),
        gid12 in gid12_strategy(),
        leg_idx in leg_idx_strategy(),
        ih16 in ih16_strategy(),
    ) {
        let input = LabelInput {
            sid8: &sid8,
            gid12: &gid12,
            leg_idx,
            ih16: &ih16,
        };
        let encoded = match encode_label(&input) {
            Ok(value) => value,
            Err(err) => panic!("encode should succeed for valid short inputs: {err:?}"),
        };
        let decoded = match decode_label(&encoded) {
            Ok(value) => value,
            Err(err) => panic!("decode should succeed for valid label: {err:?}"),
        };

        prop_assert_eq!(&decoded.sid8, &sid8);
        prop_assert_eq!(&decoded.gid12, &gid12);
        prop_assert_eq!(decoded.leg_idx, leg_idx);
        prop_assert_eq!(&decoded.ih16, &ih16);
    }

    /// Encoded label length never exceeds LABEL_MAX_LEN.
    #[test]
    fn label_length_within_limit(
        sid8 in sid8_strategy(),
        gid12 in gid12_strategy(),
        leg_idx in leg_idx_strategy(),
        ih16 in ih16_strategy(),
    ) {
        let input = LabelInput {
            sid8: &sid8,
            gid12: &gid12,
            leg_idx,
            ih16: &ih16,
        };
        match encode_label(&input) {
            Ok(label) => {
                prop_assert!(
                    label.len() <= LABEL_MAX_LEN,
                    "label length {} exceeds max {}",
                    label.len(), LABEL_MAX_LEN
                );
            }
            Err(LabelError::LabelTooLong { len }) => {
                prop_assert!(
                    len > LABEL_MAX_LEN,
                    "LabelTooLong reported len={} but max={}",
                    len, LABEL_MAX_LEN
                );
            }
            Err(other) => {
                prop_assert!(false, "unexpected error: {:?}", other);
            }
        }
    }

    /// Decoding a string without "s4:" prefix produces InvalidPrefix.
    #[test]
    fn invalid_prefix_rejected(s in "[^s].*|s[^4].*|s4[^:].*") {
        // Filter out strings that accidentally start with "s4:"
        prop_assume!(!s.starts_with("s4:"));
        let result = decode_label(&s);
        prop_assert!(
            matches!(result, Err(LabelError::InvalidPrefix)),
            "expected InvalidPrefix for {:?}, got {:?}", s, result
        );
    }

    /// Decoding "s4:" with wrong segment count produces WrongSegmentCount.
    #[test]
    fn wrong_segment_count_rejected(
        extra_segments in 0..3usize,
    ) {
        // Build a label with wrong number of segments (not 5)
        let label = match extra_segments {
            0 => "s4:only_one".to_string(),
            1 => "s4:a:b".to_string(),
            2 => "s4:a:b:c".to_string(),
            _ => unreachable!(),
        };
        let result = decode_label(&label);
        prop_assert!(
            matches!(result, Err(LabelError::WrongSegmentCount { .. })),
            "expected WrongSegmentCount for {:?}, got {:?}", label, result
        );
    }

    /// encode never panics on arbitrary string inputs.
    #[test]
    fn encode_never_panics(
        sid8 in ".*",
        gid12 in ".*",
        leg_idx in proptest::num::u32::ANY,
        ih16 in ".*",
    ) {
        let input = LabelInput {
            sid8: &sid8,
            gid12: &gid12,
            leg_idx,
            ih16: &ih16,
        };
        let _ = encode_label(&input);
    }

    /// decode never panics on arbitrary strings.
    #[test]
    fn decode_never_panics(s in ".*") {
        let _ = decode_label(&s);
    }
}
