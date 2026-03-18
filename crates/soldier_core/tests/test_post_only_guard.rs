//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Post-only guard behavior coverage now lives in:
//! `crates/soldier_core/src/execution/post_only_guard_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/post_only_guard_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/post_only_guard_tests.rs",
        name
    );
}

#[test]
fn test_at916_buy_crosses_at_ask_rejected() {
    assert_unit_test_present("test_at916_buy_crosses_at_ask_rejected");
}
