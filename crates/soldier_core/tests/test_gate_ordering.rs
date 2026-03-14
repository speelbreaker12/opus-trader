//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Full gate-ordering coverage now lives in:
//! `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str =
    include_str!("../src/execution/build_order_intent_gate_ordering_tests.rs");

fn assert_unit_test_present(name: &str) {
    let fn_needle = format!("fn {name}(");
    let fn_pos = UNIT_TEST_SOURCE.find(&fn_needle).unwrap_or_else(|| {
        panic!(
            "expected unit test '{}' in ../src/execution/build_order_intent_gate_ordering_tests.rs",
            name
        )
    });
    // Verify #[test] appears within 200 bytes before `fn name(`.
    // Uses rfind on the substring up to fn_pos to avoid char-boundary issues,
    // and accommodates stacked attributes (e.g. #[allow(...)]) between
    // #[test] and fn without requiring exact adjacency.
    let has_test_attr = UNIT_TEST_SOURCE[..fn_pos]
        .rfind("#[test]")
        .map(|attr_pos| fn_pos - attr_pos <= 200)
        .unwrap_or(false);
    assert!(
        has_test_attr,
        "expected #[test] attribute on '{}' in ../src/execution/build_order_intent_gate_ordering_tests.rs",
        name
    );
}

#[test]
fn test_at501_open_all_gates_pass_trace_order() {
    assert_unit_test_present("test_at501_open_all_gates_pass_trace_order");
}

#[test]
fn test_gate_ordering_constraints() {
    for constraint_test in [
        "test_constraint_reject_gates_before_persist",
        "test_constraint_wal_is_last_gate_open",
        "test_constraint_wal_is_last_gate_close",
        "test_constraint_wal_is_last_gate_hedge",
        "test_constraint_no_approval_with_any_gate_failed",
        "test_constraint_approval_requires_all_gates_pass",
        "test_constraint_rejected_trace_stops_at_failure",
        "test_constraint_wal_after_all_validation_gates",
    ] {
        assert_unit_test_present(constraint_test);
    }
}
