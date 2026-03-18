//! Compatibility anchor for workflow/doc-sync checks.
//!
//! GI-001 property coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_prop_gi001_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/pipeline_prop_gi001_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_prop_gi001_tests.rs",
        name
    );
}

#[test]
fn gi001_open_non_healthy_rejected() {
    assert_unit_test_present("gi001_open_non_healthy_rejected");
}

#[test]
fn non_open_non_healthy_not_margin_rejected() {
    assert_unit_test_present("non_open_non_healthy_not_margin_rejected");
}
