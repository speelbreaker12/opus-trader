//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Liquidity gate behavior coverage now lives in:
//! `crates/soldier_core/src/execution/gate_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/gate_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/gate_tests.rs",
        name
    );
}

#[test]
fn test_at222_slippage_exceeds_max_rejected() {
    assert_unit_test_present("test_at222_slippage_exceeds_max_rejected");
}
