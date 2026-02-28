//! Compatibility anchor for workflow/doc-sync checks.
//!
//! Label behavior coverage now lives in:
//! `crates/soldier_core/src/execution/label_tests.rs`
//! and runs in `cargo test --lib` quick mode.

use soldier_core::execution::{LabelInput, encode_label};

trait TestResultExt<T> {
    fn must(self) -> T;
}

impl<T, E: std::fmt::Debug> TestResultExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

#[test]
fn test_at216_label_starts_with_s4() {
    let label = encode_label(&LabelInput {
        sid8: "a1b2c3d4",
        gid12: "550e8400e29b",
        leg_idx: 0,
        ih16: "deadbeef01234567",
    })
    .must();
    assert!(label.starts_with("s4:"));
}
