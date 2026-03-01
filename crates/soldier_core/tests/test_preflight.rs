//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Preflight behavior coverage now lives in:
//! `crates/soldier_core/src/execution/preflight_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/preflight_tests.rs");

fn assert_unit_test_present(name: &str) {
    let signature = format!("fn {name}(");
    let lines: Vec<&str> = UNIT_TEST_SOURCE.lines().collect();

    for (idx, line) in lines.iter().enumerate() {
        if !line.trim_start().starts_with(&signature) {
            continue;
        }
        for prev in lines[..idx].iter().rev() {
            let trimmed = prev.trim();
            if trimmed.is_empty() || trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }
            assert_eq!(
                trimmed, "#[test]",
                "expected #[test] immediately above '{}'",
                name
            );
            return;
        }
        panic!("expected #[test] above '{}'", name);
    }
    panic!(
        "expected unit test '{}' in ../src/execution/preflight_tests.rs",
        name
    );
}

#[test]
fn test_limit_order_option_allowed() {
    assert_unit_test_present("test_limit_order_option_allowed");
}

#[test]
fn test_preflight_fail_closed_missing_input_anchor() {
    assert_unit_test_present("test_preflight_fail_closed_missing_input_anchor");
}

#[test]
fn test_preflight_reject_market_forbidden_anchor() {
    assert_unit_test_present("test_at913_market_order_reason_matches");
}

#[test]
fn test_preflight_invalid_trigger_forbidden_anchor() {
    assert_unit_test_present("test_at914_trigger_field_presence_rejected");
}
