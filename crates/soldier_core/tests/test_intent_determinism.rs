//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Determinism coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_intent_determinism_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str =
    include_str!("../src/execution/pipeline_intent_determinism_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_intent_determinism_tests.rs",
        name
    );
}

#[test]
fn test_quantize_same_inputs_same_output() {
    assert_unit_test_present("test_quantize_same_inputs_same_output");
}

#[test]
fn test_full_pipeline_determinism() {
    assert_unit_test_present("test_full_pipeline_determinism");
}
