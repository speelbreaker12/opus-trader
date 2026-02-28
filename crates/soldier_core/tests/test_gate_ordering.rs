//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Full gate-ordering coverage now lives in:
//! `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str =
    include_str!("../src/execution/build_order_intent_gate_ordering_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/build_order_intent_gate_ordering_tests.rs",
        name
    );
}

#[test]
fn test_at501_open_all_gates_pass_trace_order() {
    assert_unit_test_present("test_at501_open_all_gates_pass_trace_order");
}
