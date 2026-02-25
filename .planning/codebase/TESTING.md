# Testing Patterns

**Analysis Date:** 2026-02-25

## Test Framework

**Runner:**
- `cargo test` (Rust).
- `pytest` (Python).
- Verify-time harness: Rust and Python gates are orchestrated in `plans/lib/rust_gates.sh` and `plans/lib/python_gates.sh`.

**Assertion Library:**
- Rust: built-in `assert!`, `assert_eq!`, `assert_ne!`.
- Python: `unittest` assertions (`self.assertEqual`, `self.assertTrue`, etc.) executed via pytest.

**Run Commands:**
```bash
cargo test --workspace --lib --locked
cargo test --workspace --all-features --locked
cargo test -p soldier_core --test test_quantize
cargo test -p soldier_infra --test test_fee_cache
pytest -q
pytest -q -m "not integration and not slow"
pytest -q -m "not integration and not slow"  # quick fallback path in verify
```

## Test File Organization

**Location:**
- Rust: `crates/soldier_core/tests/*.rs`, `crates/soldier_infra/tests/*.rs`, and in-module `#[cfg(test)] mod tests` blocks.
- Python: `python/proof_graph/tests/*.py` with JSON fixtures in `python/proof_graph/tests/fixtures/`.
- Dashboard/frontend tests are not detected in the inspected surface.

**Naming:**
- Unit/integration style Rust file names mirror subject (`test_quantize.rs`, `test_config_defaults.rs`, `test_fee_cache.rs`).
- Python tests follow `test_*.py`.

**Structure:**
```text
crates/
  soldier_core/
    src/
      quantize.rs
      order_size.rs
    tests/
      test_quantize.rs
      test_order_size.rs
  soldier_infra/
    tests/
      test_fee_cache.rs
      test_dispatch_durability.rs
python/
  proof_graph/
    tests/
      test_rules.py
      fixtures/
```

## Test Structure

**Suite Organization:**
```rust
#[test]
fn test_quantize_success() {
    // arrange
    let mut metrics = QuantizeMetrics::new();

    // act
    let result = quantize(...);

    // assert
    assert!(result.is_ok());
}
```

**Patterns:**
- Direct Arrange/Act/Assert style.
- Boundary/error-case coverage and explicit `assert_eq!` on concrete outputs/errors.
- Heavy use of helper constructors and focused case-per-test functions.

## Mocking

**Framework:**
- Not detected.

**Patterns:**
- No dedicated mocking libraries are visible in inspected Rust or Python tests.
- Tests usually rely on concrete in-memory objects and fixtures.

**What to Mock:**
- Not detected as a repo-wide pattern.

**What NOT to Mock:**
- Not detected.

## Fixtures and Factories

**Test Data:**
```rust
fn intent(hash: &str) -> IntentRecord { ... }
```

**Location:**
- Rust: helper constructors inside tests or shared helper modules (for example `crates/soldier_core/tests/common/mod.rs`).
- Python: static JSON fixtures in `python/proof_graph/tests/fixtures/`.

## Coverage

**Requirements:**
- Not detected: explicit minimum coverage thresholds in the repository commands/docs sampled here.

**Configuration:**
- Not detected.

**View Coverage:**
- Not detected.

## Test Types

**Unit Tests:**
- Core logic and edge-case validation in Rust and Python.

**Integration Tests:**
- Rust integration test binaries in `crates/*/tests/*.rs` (e.g., `--test test_dispatch_map`, `--test test_fee_cache`).

**E2E Tests:**
- Not detected in the inspected codebase surface.

## Common Patterns

**Async Testing:**
- Not detected as a dominant pattern in sampled tests.

**Error Testing:**
```rust
let result = quantize(...);
assert_eq!(
    result,
    Err(QuantizeError::InstrumentMetadataMissing { field: "tick_size" })
);
```

**Snapshot Testing:**
- Not detected.

*Testing analysis: 2026-02-25*
*Update when test patterns change*
