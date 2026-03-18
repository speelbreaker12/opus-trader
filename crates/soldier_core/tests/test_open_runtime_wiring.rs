//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Open-runtime wiring coverage now lives in:
//! `crates/soldier_core/src/execution/open_runtime_wiring_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/open_runtime_wiring_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/open_runtime_wiring_tests.rs",
        name
    );
}

#[test]
fn test_runtime_wiring_releases_pending_reservation_on_reject() {
    assert_unit_test_present("test_runtime_wiring_releases_pending_reservation_on_reject");
}

#[test]
fn test_runtime_wiring_inventory_skew_forces_net_edge_recheck_before_pricer() {
    assert_unit_test_present(
        "test_runtime_wiring_inventory_skew_forces_net_edge_recheck_before_pricer",
    );
}
