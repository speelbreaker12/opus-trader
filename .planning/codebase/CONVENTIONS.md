# Coding Conventions

**Analysis Date:** 2026-02-25

## Naming Patterns

**Files:**
- Rust source uses snake_case file names (`order_size.rs`, `quantize.rs`, `ledger.rs`).
- Rust test files are mainly split into module-level and crate-level suites under `crates/soldier_core/tests/*.rs`, `crates/soldier_infra/tests/*.rs`, and in-module `#[cfg(test)]` blocks in `crates/*/src/*.rs`.
- Python uses snake_case test module names (`test_rules.py`, `test_init.py`) under `python/proof_graph/tests/`.
- Dashboard TS file names and source layout are not fully represented; dashboard package is mostly metadata (`dashboard/package.json`, `dashboard/tsconfig.json`).

**Functions:**
- Rust and Python functions are `snake_case` (e.g., `resolve_config_value`, `build_order_size`, `test_at908_too_small_rejected`).
- No special async naming prefix is used.
- Test function naming is `test_<scenario>` in Rust.
- Not detected: specific handler naming convention like `handleX`.

**Variables:**
- `snake_case` for local variables and function parameters (`gate_results_all_passing`, `raw_qty`).
- `UPPER_SNAKE_CASE` for constants in Rust (`EXPECTED_PARAM_COUNT`, `PROPTEST_CASES`, `BOUNDARY_EPS`).
- No underscore-private naming convention is enforced; private items usually use normal `snake_case`.

**Types:**
- Rust structs/enums/types are `PascalCase` (`GateConfig`, `QuantizeError`, `IntentSize`).
- Python typed classes in tests and modules follow `PascalCase` (`ValidationContext`, `ProofGraph`, `Input`).
- No interface/type-alias naming anomalies detected.

## Code Style

**Formatting:**
- Rust formatting is enforced through `cargo fmt --all -- --check` in verify.
- No local Rust formatter config file detected (`rustfmt.toml` not detected).
- Python/JS formatter config not detected for this map scope.
- Indentation is 4 spaces in Rust and Python.
- Semicolons are required by Rust compiler/language.
- Line length appears unconstrained by repo config; observed style keeps lines moderate rather than tightly enforced.

**Linting:**
- Rust: `cargo clippy` in full verify mode (`cargo clippy --workspace --all-targets --all-features -- -D warnings`).
- Python: lint/format via `ruff check .` and `ruff format --check .` when `ruff` is available.
- No repository-wide JS linter is guaranteed; scripts are optional by package lockfile detection.

## Import Organization

**Order:**
1. Standard library imports.
2. External crate imports.
3. Internal crate/module imports (`crate::`, `super::`, `use soldier_core::...`, `use soldier_infra::...`).

**Grouping:**
- Imports are grouped with blank lines and sorted to keep logical clusters.
- Type-only imports are generally mixed with other uses (not separated).

**Path Aliases:**
- Not detected (no consistent path alias usage in the inspected files).

## Error Handling

**Patterns:**
- Fail-closed by default for invalid/incomplete input (`Result::Err` paths dominate invalid metadata, invalid values, and boundary conditions).
- Custom error enums and structs are used extensively (`QuantizeError`, `MissingConfigError`).
- `?` is used for propagation; `match` blocks are used to convert/attach context.
- Return early on guard failures is common.

**Error Types:**
- Fail with structured domain errors for business-rule violations and validation failures.
- Convert to user-facing `io::Error` with explicit context when crossing module boundaries.
- Parse/contract violations are surfaced via explicit custom reasons/messages.

**Logging:**
- Structured logs via `tracing` in Rust (e.g., `tracing::warn!(...)`, `tracing::debug!(...)`) with named fields.
- Not detected: centralized Python logging standardization.

## Logging

**Framework:**
- Rust: `tracing` crate.

**Patterns:**
- Use structured key/value logs for warning/error paths.
- Logs are placed at validation and edge-condition points rather than every line of flow.
- Avoids ad-hoc `println!` in tested logic where tracing is used.

## Comments

**When to Comment:**
- Document contract mapping, invariants, and safety rationale with doc comments (`//!`, `///`) before public/critical items.
- Comments explain non-obvious behavior and boundary conditions.

**JSDoc/TSDoc:**
- Rust doc comments are heavily used.
- Not detected: language-specific JSDoc/TSDoc usage (dashboard JS surface is minimal).

**TODO Comments:**
- `TODO(...)` format observed, often with migration/scope tags (e.g., `TODO(slice-N): ...`).
- No single mandatory issue-number format policy was detected beyond that pattern.

## Function Design

**Size:**
- Functions are usually decomposed into small, single-responsibility units.
- Long functions are avoided where practical.

**Parameters:**
- Prefer small parameter structs for grouped inputs (`OrderSizeInput`, `QuantizeConstraints`, `IntentPipelineInput`).
- Prefer simple value params for small constructors.

**Return Values:**
- Explicit return values are preferred.
- Validation and conversion functions return `Result<T, E>` when failure is possible.
- Error variants are handled before side effects.

## Module Design

**Exports:**
- Rust favors explicit `pub mod` plus `pub use` re-exports.
- Public modules are grouped under crate roots (`src/lib.rs`, `crates/*/src/lib.rs`).

**Barrel Files:**
- Barrel-like re-export pattern is standard in Rust (`pub mod ...`, `pub use ...`).
- Preserve separation between core and infra crate boundaries.
- No broad namespace wildcards in re-exports observed in sampled files.

*Convention analysis: 2026-02-25*
*Update when patterns change*
