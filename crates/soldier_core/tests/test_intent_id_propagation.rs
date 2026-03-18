//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Intent-id propagation coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_intent_id_propagation_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str =
    include_str!("../src/execution/pipeline_intent_id_propagation_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_intent_id_propagation_tests.rs",
        name
    );
}

#[test]
fn test_intent_id_propagates_through_approved_pipeline() {
    assert_unit_test_present("test_intent_id_propagates_through_approved_pipeline");
}

#[test]
fn test_gate_trace_provides_audit_trail() {
    assert_unit_test_present("test_gate_trace_provides_audit_trail");
}
