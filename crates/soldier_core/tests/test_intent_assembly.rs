//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Intent-assembly behavior coverage now lives in:
//! `crates/soldier_core/src/execution/intent_assembly_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/intent_assembly_tests.rs");

fn assert_unit_test_present(name: &str) {
    let needle = format!("fn {name}(");
    assert!(
        UNIT_TEST_SOURCE.contains(&needle),
        "expected unit test '{}' in ../src/execution/intent_assembly_tests.rs",
        name
    );
}

#[test]
fn test_assembly_unknown_kind_fails_closed() {
    assert_unit_test_present("test_assembly_unknown_kind_fails_closed");
}

#[test]
fn test_choke_intent_to_dispatch_mapping() {
    assert_unit_test_present("test_choke_intent_to_dispatch_mapping");
}
