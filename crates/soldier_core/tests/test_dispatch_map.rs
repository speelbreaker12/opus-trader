//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Dispatch-map behavior coverage now lives in:
//! `crates/soldier_core/src/execution/dispatch_map_tests.rs`
//! and runs in `cargo test --lib` quick mode.

const UNIT_TEST_SOURCE: &str = include_str!("../src/execution/dispatch_map_tests.rs");

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
        "expected unit test '{}' in ../src/execution/dispatch_map_tests.rs",
        name
    );
}

#[test]
fn test_option_amount_is_qty_coin() {
    assert_unit_test_present("test_option_amount_is_qty_coin");
}

#[test]
fn test_open_haircut_mult_applies_to_open_only() {
    assert_unit_test_present("test_open_haircut_mult_applies_to_open_only");
}

#[test]
fn test_at920_consistent_contracts_passes() {
    assert_unit_test_present("test_at920_consistent_contracts_passes");
}

#[test]
fn test_at920_mismatch_rejected() {
    assert_unit_test_present("test_at920_mismatch_rejected");
}

#[test]
fn test_missing_qty_coin_error_anchor() {
    assert_unit_test_present("test_missing_qty_coin_error");
}

#[test]
fn test_missing_qty_usd_error_anchor() {
    assert_unit_test_present("test_missing_qty_usd_error");
}

#[test]
fn test_at920_no_multiplier_rejected_fail_closed_anchor() {
    assert_unit_test_present("test_at920_no_multiplier_rejected_fail_closed");
}
