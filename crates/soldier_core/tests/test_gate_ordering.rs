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
    // Bound the #[test] search to the attribute block immediately preceding this
    // function.  Find the last closing brace (`\n}`) before fn_pos — any #[test]
    // after that boundary belongs to this function, not a prior one.  This is
    // robust to arbitrarily many stacked attributes and arbitrary function body size.
    let search_start = UNIT_TEST_SOURCE[..fn_pos]
        .rfind("\n}")
        .map(|p| p + 2) // skip past the `\n}` itself
        .unwrap_or(0);
    let has_test_attr = UNIT_TEST_SOURCE[search_start..fn_pos].contains("#[test]");
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
fn test_assert_unit_test_present_rejects_fn_without_test_attr() {
    // Mutation-B5 guard: a wrong impl that reverts to the old `contains(fn_needle)`
    // check (without verifying `#[test]` attribute presence) would pass for
    // `gate_results_all_passing`, which exists in the source WITHOUT `#[test]`.
    // This test proves the attribute check is present and active.
    let result = std::panic::catch_unwind(|| {
        assert_unit_test_present("gate_results_all_passing");
    });
    assert!(
        result.is_err(),
        "assert_unit_test_present must panic for a fn that exists without #[test]"
    );
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
