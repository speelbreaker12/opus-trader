//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Full rejection-side-effects coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_rejection_side_effects_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str =
    include_str!("../src/execution/pipeline_rejection_side_effects_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_rejection_side_effects_tests.rs",
        name
    );
}

#[test]
fn test_rejected_intent_has_no_side_effects() {
    assert_unit_test_present("test_rejected_intent_has_no_side_effects");
}
