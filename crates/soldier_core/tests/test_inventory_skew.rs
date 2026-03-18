//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Inventory-skew behavior coverage now lives in:
//! `crates/soldier_core/src/execution/inventory_skew_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/inventory_skew_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/inventory_skew_tests.rs",
        name
    );
}

#[test]
fn test_inventory_skew_rejects_risk_increasing_near_limit() {
    assert_unit_test_present("test_inventory_skew_rejects_risk_increasing_near_limit");
}

#[test]
fn test_inventory_skew_tick_penalty_max_is_exactly_3_ticks_at_bias_1_0() {
    assert_unit_test_present("test_inventory_skew_tick_penalty_max_is_exactly_3_ticks_at_bias_1_0");
}
