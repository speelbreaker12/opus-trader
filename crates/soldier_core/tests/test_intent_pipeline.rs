//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Intent-pipeline integration coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_integration_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/pipeline_integration_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_integration_tests.rs",
        name
    );
}

#[test]
fn test_pipeline_open_happy_path_approved() {
    assert_unit_test_present("test_pipeline_open_happy_path_approved");
}

#[test]
fn test_pipeline_open_degraded_skips_preflight_side_effects() {
    assert_unit_test_present("test_pipeline_open_degraded_skips_preflight_side_effects");
}

#[test]
fn test_pipeline_open_not_healthy_fail_closed_anchor() {
    assert_unit_test_present("test_at104_degraded_blocks_open_at_chokepoint");
}

#[test]
fn test_pipeline_open_missing_dispatch_consistency_fail_closed_anchor() {
    assert_unit_test_present("test_at920_pipeline_dispatch_consistency_failure_rejected");
}
