use super::*;
use crate::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, build_gate_results,
    build_order_intent_with_optional_wal_gate,
};
use crate::risk::RiskState;

trait TestResultExt<T> {
    fn must(self) -> T;
}

impl<T, E: std::fmt::Debug> TestResultExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

fn sample_input() -> LabelInput<'static> {
    LabelInput {
        sid8: "a1b2c3d4",
        gid12: "550e8400e29b",
        leg_idx: 0,
        ih16: "deadbeef01234567",
    }
}

fn gate_results_all_passing() -> crate::execution::GateResults {
    build_gate_results(
        true, true, true, true, true, true, true, true, true, None, None,
    )
}

#[test]
fn test_at216_label_starts_with_s4() {
    let label = encode_label(&sample_input()).must();
    assert!(label.starts_with("s4:"), "label must start with s4:");
}

#[test]
fn test_at216_label_within_limit() {
    let label = encode_label(&sample_input()).must();
    assert!(
        label.len() <= LABEL_MAX_LEN,
        "label len {} exceeds limit {}",
        label.len(),
        LABEL_MAX_LEN
    );
}

#[test]
fn test_at216_label_format() {
    let label = encode_label(&sample_input()).must();
    assert_eq!(label, "s4:a1b2c3d4:550e8400e29b:0:deadbeef01234567");
}

#[test]
fn test_at216_leg_idx_1() {
    let input = LabelInput {
        sid8: "a1b2c3d4",
        gid12: "550e8400e29b",
        leg_idx: 1,
        ih16: "deadbeef01234567",
    };
    let label = encode_label(&input).must();
    assert_eq!(label, "s4:a1b2c3d4:550e8400e29b:1:deadbeef01234567");
}

#[test]
fn test_at216_typical_label_length() {
    let label = encode_label(&sample_input()).must();
    assert_eq!(label.len(), 43);
}

#[test]
fn test_at216_decode_components() {
    let label = "s4:a1b2c3d4:550e8400e29b:0:deadbeef01234567";
    let parsed = decode_label(label).must();
    assert_eq!(parsed.sid8, "a1b2c3d4");
    assert_eq!(parsed.gid12, "550e8400e29b");
    assert_eq!(parsed.leg_idx, 0);
    assert_eq!(parsed.ih16, "deadbeef01234567");
}

#[test]
fn test_at216_decode_leg_idx_1() {
    let label = "s4:abcd1234:123456789012:1:0123456789abcdef";
    let parsed = decode_label(label).must();
    assert_eq!(parsed.leg_idx, 1);
    assert_eq!(parsed.ih16, "0123456789abcdef");
}

#[test]
fn test_encode_decode_roundtrip() {
    let input = sample_input();
    let label = encode_label(&input).must();
    let parsed = decode_label(&label).must();
    assert_eq!(parsed.sid8, input.sid8);
    assert_eq!(parsed.gid12, input.gid12);
    assert_eq!(parsed.leg_idx, input.leg_idx);
    assert_eq!(parsed.ih16, input.ih16);
}

#[test]
fn test_encode_decode_roundtrip_leg1() {
    let input = LabelInput {
        sid8: "ffee0011",
        gid12: "aabbccddeeff",
        leg_idx: 1,
        ih16: "1122334455667788",
    };
    let label = encode_label(&input).must();
    let parsed = decode_label(&label).must();
    assert_eq!(parsed.sid8, input.sid8);
    assert_eq!(parsed.gid12, input.gid12);
    assert_eq!(parsed.leg_idx, input.leg_idx);
    assert_eq!(parsed.ih16, input.ih16);
}

#[test]
fn test_label_too_long_rejected() {
    let input = LabelInput {
        sid8: "a1b2c3d4e5f6g7h8",
        gid12: "123456789012345678901234",
        leg_idx: 0,
        ih16: "deadbeef0123456789abcdef01234567",
    };
    let result = encode_label(&input);
    match result {
        Err(LabelError::LabelTooLong { len }) => {
            assert!(len > LABEL_MAX_LEN);
        }
        other => panic!("expected LabelTooLong, got {other:?}"),
    }
}

#[test]
fn test_no_truncation() {
    let input = LabelInput {
        sid8: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        gid12: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        leg_idx: 0,
        ih16: "cccccccccccccccccccccccccccccc",
    };
    let result = encode_label(&input);
    assert!(
        result.is_err(),
        "oversized label must be rejected, not truncated"
    );
}

#[test]
fn test_decode_invalid_prefix() {
    let result = decode_label("s3:a1b2c3d4:550e8400e29b:0:deadbeef01234567");
    assert_eq!(result, Err(LabelError::InvalidPrefix));
}

#[test]
fn test_decode_wrong_segment_count() {
    let result = decode_label("s4:a1b2c3d4:550e8400e29b:0");
    assert_eq!(result, Err(LabelError::WrongSegmentCount { count: 4 }));
}

#[test]
fn test_decode_too_many_segments() {
    let result = decode_label("s4:a:b:0:c:extra");
    assert_eq!(result, Err(LabelError::WrongSegmentCount { count: 6 }));
}

#[test]
fn test_decode_invalid_leg_idx() {
    let result = decode_label("s4:a1b2c3d4:550e8400e29b:abc:deadbeef01234567");
    assert_eq!(result, Err(LabelError::InvalidLegIdx));
}

#[test]
fn test_decode_empty_string() {
    let result = decode_label("");
    assert_eq!(result, Err(LabelError::InvalidPrefix));
}

#[test]
fn test_derive_sid8_length() {
    let sid8 = derive_sid8("strangle_btc_low_vol");
    assert_eq!(sid8.len(), 8);
    assert!(sid8.chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn test_derive_sid8_deterministic() {
    let s1 = derive_sid8("my_strategy");
    let s2 = derive_sid8("my_strategy");
    assert_eq!(s1, s2);
}

#[test]
fn test_derive_sid8_different_inputs() {
    let s1 = derive_sid8("strategy_a");
    let s2 = derive_sid8("strategy_b");
    assert_ne!(s1, s2);
}

#[test]
fn test_derive_gid12() {
    let gid12 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    assert_eq!(gid12.len(), 12);
    assert_eq!(gid12, "550e8400e29b");
}

#[test]
fn test_derive_gid12_deterministic() {
    let g1 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    let g2 = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
    assert_eq!(g1, g2);
}

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
    let label = encode_label(&input).must();
    assert!(label.starts_with("s4:"));
    assert!(label.len() <= LABEL_MAX_LEN);

    let parsed = decode_label(&label).must();
    assert_eq!(parsed.sid8, sid8);
    assert_eq!(parsed.gid12, gid12);
    assert_eq!(parsed.leg_idx, 0);
    assert_eq!(parsed.ih16, ih16);
}

#[test]
fn test_label_max_len_constant() {
    assert_eq!(LABEL_MAX_LEN, 64);
}

#[test]
fn test_at041_label_at_limit_passes_over_limit_fails() {
    let at_limit = LabelInput {
        sid8: "12345678901234567890123456789",
        gid12: "abcdef012345",
        leg_idx: 0,
        ih16: "abcdef0123456789",
    };
    assert!(
        encode_label(&at_limit).is_ok(),
        "64-char label must pass (LABEL_MAX_LEN check is strictly >)"
    );

    let over_limit = LabelInput {
        sid8: "123456789012345678901234567890",
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

#[test]
fn test_at041_label_too_long_caller_sets_degraded_blocks_open() {
    let over_limit = LabelInput {
        sid8: "123456789012345678901234567890",
        gid12: "abcdef012345",
        leg_idx: 0,
        ih16: "abcdef0123456789",
    };
    let result = encode_label(&over_limit);
    assert!(
        matches!(result, Err(LabelError::LabelTooLong { .. })),
        "oversized label must return LabelTooLong"
    );

    let risk_after_label_error = RiskState::Degraded;
    let mut choke = ChokeMetrics::new();
    let choke_result = build_order_intent_with_optional_wal_gate(
        ChokeIntentClass::Open,
        risk_after_label_error,
        &mut choke,
        &gate_results_all_passing(),
        None,
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
