//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Net-edge gate behavior coverage now lives in:
//! `crates/soldier_core/src/execution/gates_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/gates_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/gates_tests.rs",
        name
    );
}

#[test]
fn test_at015_net_edge_below_min_rejected() {
    assert_unit_test_present("test_at015_net_edge_below_min_rejected");
}
