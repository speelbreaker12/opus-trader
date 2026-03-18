//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Order size behavior coverage now lives in:
//! `crates/soldier_core/src/execution/order_size_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/order_size_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/order_size_tests.rs",
        name
    );
}

#[test]
fn test_at277_option_sizing() {
    assert_unit_test_present("test_at277_option_sizing");
}
