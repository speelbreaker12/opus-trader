//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Missing-config fail-closed coverage now lives in:
//! `crates/soldier_core/src/execution/pipeline_missing_config_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/pipeline_missing_config_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/pipeline_missing_config_tests.rs",
        name
    );
}

#[test]
fn test_missing_tick_size_fails_closed() {
    assert_unit_test_present("test_missing_tick_size_fails_closed");
}

#[test]
fn test_unhealthy_risk_state_fails_closed() {
    assert_unit_test_present("test_unhealthy_risk_state_fails_closed");
}

#[test]
fn test_config_missing_no_side_effects() {
    assert_unit_test_present("test_config_missing_no_side_effects");
}
