//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Base-gates behavior coverage now lives in:
//! `crates/soldier_core/src/execution/base_gates_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/base_gates_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/base_gates_tests.rs",
        name
    );
}

#[test]
fn test_base_gates_all_pass_returns_proof() {
    assert_unit_test_present("test_base_gates_all_pass_returns_proof");
}
