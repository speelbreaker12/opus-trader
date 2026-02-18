//! Tests for compact label schema per CONTRACT.md §1.1.
//!
//! AT-216: s4 label format, length <= 64, parse correctness.
//! AT-217: disambiguation uses ih16 (tested structurally here).

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateResults, LABEL_MAX_LEN, LabelError,
    LabelInput, build_order_intent, decode_label, derive_gid12, derive_sid8, encode_label,
};
use soldier_core::risk::RiskState;

/// Standard test label input.
fn sample_input() -> LabelInput<'static> {
    LabelInput {
        sid8: "a1b2c3d4",
        gid12: "550e8400e29b",
        leg_idx: 0,
        ih16: "deadbeef01234567",
    }
}

// ─── AT-216: Label encoding ────────────────────────────────────────────

/// AT-216: label starts with "s4:" prefix
#[test]
fn test_at216_label_starts_with_s4() {
    let label = encode_label(&sample_input()).unwrap();
    assert!(label.starts_with("s4:"), "label must start with s4:");
}

/// AT-216: label length <= 64 chars
#[test]
fn test_at216_label_within_limit() {
    let label = encode_label(&sample_input()).unwrap();
    assert!(
        label.len() <= LABEL_MAX_LEN,
        "label len {} exceeds limit {}",
        label.len(),
        LABEL_MAX_LEN
    );
}

/// AT-216: label format is s4:{sid8}:{gid12}:{li}:{ih16}
#[test]
fn test_at216_label_format() {
    let label = encode_label(&sample_input()).unwrap();
    assert_eq!(label, "s4:a1b2c3d4:550e8400e29b:0:deadbeef01234567");
}

/// AT-216: leg_idx=1 in label
#[test]
fn test_at216_leg_idx_1() {
    let input = LabelInput {
        sid8: "a1b2c3d4",
        gid12: "550e8400e29b",
        leg_idx: 1,
        ih16: "deadbeef01234567",
    };
    let label = encode_label(&input).unwrap();
    assert_eq!(label, "s4:a1b2c3d4:550e8400e29b:1:deadbeef01234567");
}

/// AT-216: typical label length check
#[test]
fn test_at216_typical_label_length() {
    // s4:XXXXXXXX:XXXXXXXXXXXX:0:XXXXXXXXXXXXXXXX
    // 3 + 8 + 1 + 12 + 1 + 1 + 1 + 16 = 43 chars
    let label = encode_label(&sample_input()).unwrap();
    assert_eq!(label.len(), 43);
}

// ─── AT-216: Label decoding ────────────────────────────────────────────

/// AT-216: decode extracts correct components
#[test]
fn test_at216_decode_components() {
    let label = "s4:a1b2c3d4:550e8400e29b:0:deadbeef01234567";
    let parsed = decode_label(label).unwrap();
    assert_eq!(parsed.sid8, "a1b2c3d4");
    assert_eq!(parsed.gid12, "550e8400e29b");
    assert_eq!(parsed.leg_idx, 0);
    assert_eq!(parsed.ih16, "deadbeef01234567");
}

/// AT-216: decode with leg_idx=1
#[test]
fn test_at216_decode_leg_idx_1() {
    let label = "s4:abcd1234:123456789012:1:0123456789abcdef";
    let parsed = decode_label(label).unwrap();
    assert_eq!(parsed.leg_idx, 1);
    assert_eq!(parsed.ih16, "0123456789abcdef");
}

// ─── Encode/decode round-trip ──────────────────────────────────────────

/// Round-trip: encode then decode recovers all fields
#[test]
fn test_encode_decode_roundtrip() {
    let input = sample_input();
    let label = encode_label(&input).unwrap();
    let parsed = decode_label(&label).unwrap();
    assert_eq!(parsed.sid8, input.sid8);
    assert_eq!(parsed.gid12, input.gid12);
    assert_eq!(parsed.leg_idx, input.leg_idx);
    assert_eq!(parsed.ih16, input.ih16);
}

/// Round-trip with leg_idx=1
#[test]
fn test_encode_decode_roundtrip_leg1() {
    let input = LabelInput {
        sid8: "ffee0011",
        gid12: "aabbccddeeff",
        leg_idx: 1,
        ih16: "1122334455667788",
    };
    let label = encode_label(&input).unwrap();
    let parsed = decode_label(&label).unwrap();
    assert_eq!(parsed.sid8, input.sid8);
    assert_eq!(parsed.gid12, input.gid12);
    assert_eq!(parsed.leg_idx, input.leg_idx);
    assert_eq!(parsed.ih16, input.ih16);
}

// ─── LabelTooLong rejection ────────────────────────────────────────────

/// Label exceeding 64 chars → LabelTooLong
#[test]
fn test_label_too_long_rejected() {
    // Use very long fields to exceed 64 chars
    let input = LabelInput {
        sid8: "a1b2c3d4e5f6g7h8",          // 16 chars (too long for real sid8)
        gid12: "123456789012345678901234", // 24 chars (too long)
        leg_idx: 0,
        ih16: "deadbeef0123456789abcdef01234567", // 32 chars (too long)
    };
    let result = encode_label(&input);
    match result {
        Err(LabelError::LabelTooLong { len }) => {
            assert!(len > LABEL_MAX_LEN);
        }
        other => panic!("expected LabelTooLong, got {other:?}"),
    }
}

/// No truncation: label is either valid or rejected
#[test]
fn test_no_truncation() {
    // Make total > 64: s4: (3) + 30 + : (1) + 30 + : (1) + 1 + : (1) + 30 = 97
    let input = LabelInput {
        sid8: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",  // 30 chars
        gid12: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", // 30 chars
        leg_idx: 0,
        ih16: "cccccccccccccccccccccccccccccc", // 30 chars
    };
    let result = encode_label(&input);
    assert!(
        result.is_err(),
        "oversized label must be rejected, not truncated"
    );
}

// ─── Decode error cases ────────────────────────────────────────────────

/// Missing s4: prefix → InvalidPrefix
#[test]
fn test_decode_invalid_prefix() {
    let result = decode_label("s3:a1b2c3d4:550e8400e29b:0:deadbeef01234567");
    assert_eq!(result, Err(LabelError::InvalidPrefix));
}

/// Wrong number of segments → WrongSegmentCount
#[test]
fn test_decode_wrong_segment_count() {
    let result = decode_label("s4:a1b2c3d4:550e8400e29b:0");
    assert_eq!(result, Err(LabelError::WrongSegmentCount { count: 4 }));
}

/// Too many segments → WrongSegmentCount
#[test]
fn test_decode_too_many_segments() {
    let result = decode_label("s4:a:b:0:c:extra");
    assert_eq!(result, Err(LabelError::WrongSegmentCount { count: 6 }));
}

/// Invalid leg_idx → InvalidLegIdx
#[test]
fn test_decode_invalid_leg_idx() {
    let result = decode_label("s4:a1b2c3d4:550e8400e29b:abc:deadbeef01234567");
    assert_eq!(result, Err(LabelError::InvalidLegIdx));
}

/// Empty string → InvalidPrefix
#[test]
fn test_decode_empty_string() {
    let result = decode_label("");
    assert_eq!(result, Err(LabelError::InvalidPrefix));
}

// ─── Helper functions ──────────────────────────────────────────────────

/// derive_sid8 produces 8-char hex string
#[test]
fn test_derive_sid8_length() {
    let sid8 = derive_sid8("strangle_btc_low_vol");
    assert_eq!(sid8.len(), 8);
    assert!(sid8.chars().all(|c| c.is_ascii_hexdigit()));
}

/// derive_sid8 is deterministic
#[test]
fn test_derive_sid8_deterministic() {
    let s1 = derive_sid8("my_strategy");
    let s2 = derive_sid8("my_strategy");
    assert_eq!(s1, s2);
}

/// derive_sid8 different inputs → different outputs
#[test]
fn test_derive_sid8_different_inputs() {
    let s1 = derive_sid8("strategy_a");
    let s2 = derive_sid8("strategy_b");
    assert_ne!(s1, s2);
}

/// derive_gid12 strips dashes and takes first 12
#[test]
fn test_derive_gid12() {
    let gid12 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    assert_eq!(gid12.len(), 12);
    assert_eq!(gid12, "550e8400e29b");
}

/// derive_gid12 deterministic
#[test]
fn test_derive_gid12_deterministic() {
    let g1 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    let g2 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    assert_eq!(g1, g2);
}

// ─── Full encode with derived fields ───────────────────────────────────

/// Full pipeline: derive sid8 + gid12, encode label, decode and verify
#[test]
fn test_full_pipeline_roundtrip() {
    let sid8 = derive_sid8("strangle_btc_low_vol");
    let gid12 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    let ih16 = "deadbeef01234567";

    let input = LabelInput {
        sid8: &sid8,
        gid12: &gid12,
        leg_idx: 0,
        ih16,
    };
    let label = encode_label(&input).unwrap();
    assert!(label.starts_with("s4:"));
    assert!(label.len() <= LABEL_MAX_LEN);

    let parsed = decode_label(&label).unwrap();
    assert_eq!(parsed.sid8, sid8);
    assert_eq!(parsed.gid12, gid12);
    assert_eq!(parsed.leg_idx, 0);
    assert_eq!(parsed.ih16, ih16);
}

/// LABEL_MAX_LEN constant is 64
#[test]
fn test_label_max_len_constant() {
    assert_eq!(LABEL_MAX_LEN, 64);
}

/// AT-041 / AT-921: label > LABEL_MAX_LEN (64 chars) must be rejected.
/// Proved: 64-char label passes (boundary is strict `>`); 65-char label returns LabelTooLong.
/// Pipeline integration: LabelTooLong → RejectReasonCode::LabelTooLong (in REGISTRY, proven
/// by test_reject_reason.rs::test_registry_contains_contract_minimum_set).
#[test]
fn test_at041_label_at_limit_passes_over_limit_fails() {
    // sid8 = 29 chars → label = 3+29+1+12+1+1+1+16 = 64 chars → must PASS (check is > 64)
    let at_limit = LabelInput {
        sid8: "12345678901234567890123456789", // 29 chars
        gid12: "abcdef012345",                 // 12 chars (standard)
        leg_idx: 0,                            // 1 char
        ih16: "abcdef0123456789",              // 16 chars (standard)
    };
    assert!(
        encode_label(&at_limit).is_ok(),
        "64-char label must pass (LABEL_MAX_LEN check is strictly >)"
    );

    // sid8 = 30 chars → label = 3+30+1+12+1+1+1+16 = 65 chars → must FAIL
    let over_limit = LabelInput {
        sid8: "123456789012345678901234567890", // 30 chars
        gid12: "abcdef012345",
        leg_idx: 0,
        ih16: "abcdef0123456789",
    };
    match encode_label(&over_limit) {
        Err(LabelError::LabelTooLong { len }) => {
            assert_eq!(len, 65, "reported length must be 65");
        }
        Ok(label) => panic!("expected LabelTooLong, label.len()={}", label.len()),
        Err(other) => panic!("unexpected error: {other:?}"),
    }
}

/// AT-041 / AT-921: label too long → caller maps to RiskState::Degraded → OPEN blocked (dispatch=0).
///
/// CONTRACT.md AT-921 requires: LabelTooLong → RiskState::Degraded, dispatch=0.
/// NOTE: encode_label() currently has no production callsite that chains to RiskState. This test
/// documents the REQUIRED caller behavior. When encode_label() is called in the production pipeline,
/// the caller MUST map LabelTooLong → Degraded (same pattern as AT-920 / validate_and_dispatch).
#[allow(deprecated)]
#[test]
fn test_at041_label_too_long_caller_sets_degraded_blocks_open() {
    // Step 1: encode_label returns LabelTooLong for an oversized label.
    let over_limit = LabelInput {
        sid8: "123456789012345678901234567890", // 30 chars → label = 65 chars → LabelTooLong
        gid12: "abcdef012345",
        leg_idx: 0,
        ih16: "abcdef0123456789",
    };
    let result = encode_label(&over_limit);
    assert!(
        matches!(result, Err(LabelError::LabelTooLong { .. })),
        "oversized label must return LabelTooLong"
    );

    // Step 2: AT-921 requires caller to map LabelTooLong → RiskState::Degraded.
    // (Step 1's assert guarantees we are in the LabelTooLong branch.)
    let risk_after_label_error = RiskState::Degraded;

    // Step 3: Degraded blocks subsequent OPEN at chokepoint (dispatch=0).
    let mut choke = ChokeMetrics::new();
    let choke_result = build_order_intent(
        ChokeIntentClass::Open,
        risk_after_label_error,
        &mut choke,
        &GateResults::all_passed(),
    );
    assert!(
        matches!(choke_result, ChokeResult::Rejected { .. }),
        "Open + Degraded must be rejected at chokepoint"
    );
    assert_eq!(
        choke.approved_total(),
        0,
        "dispatch=0 after LabelTooLong (AT-921)"
    );
    assert_eq!(choke.rejected_total(), 1);
}
