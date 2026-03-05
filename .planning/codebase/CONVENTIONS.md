# Codebase Conventions (Quality-Focused)

Analysis date: 2026-03-04

## Scope and Source Files
- This map is grounded in current implementation and gate scripts, especially `crates/soldier_core/src/lib.rs`, `crates/soldier_infra/src/lib.rs`, `plans/verify_fork.sh`, `plans/lib/verify_utils.sh`, `plans/lib/rust_gates.sh`, `plans/lib/python_gates.sh`, `dashboard/publisher/publisher.py`, and `tools/validate_status.py`.
- Workflow contract expectations are encoded in `specs/WORKFLOW_CONTRACT.md` and enforced by scripts like `plans/verify_gate_contract_check.sh`.

## Coding Style Baseline
- Rust safety posture is explicit: both crate roots set `#![forbid(unsafe_code)]` in `crates/soldier_core/src/lib.rs` and `crates/soldier_infra/src/lib.rs`.
- Rust formatting is enforced by gate, not convention text: `cargo fmt --all -- --check` in `plans/lib/rust_gates.sh`.
- Rust warnings are elevated to failures in full verification via `cargo clippy --workspace --all-targets --all-features -- -D warnings` in `plans/lib/rust_gates.sh`.
- Shell scripts follow strict mode (`set -euo pipefail`) consistently in workflow/harness entrypoints such as `plans/verify.sh`, `plans/verify_fork.sh`, `plans/preflight.sh`, and `plans/prd_set_pass.sh`.
- Python quality relies on external tools (when present): `ruff check .`, `ruff format --check .`, `pytest -q`, and optional `mypy` in `plans/lib/python_gates.sh`.

## Naming and Layout Patterns
- Rust files/modules are `snake_case` and organized by domain boundaries (`crates/soldier_core/src/execution`, `crates/soldier_core/src/risk`, `crates/soldier_infra/src/store`).
- Rust types use `PascalCase`, constants use `UPPER_SNAKE_CASE` (for example metric tokens in `crates/soldier_core/src/execution/mod.rs`).
- Test files follow `test_*.rs` / `prop_*.rs` naming under `crates/*/tests/`, with many companion in-module suites under `crates/*/src/**/*_tests.rs`.
- Python app/test modules use `snake_case` names (`dashboard/publisher/state.py`, `tests/test_publisher_contract.py`, `python/proof_graph/tests/test_rules.py`).
- Environment variables are consistently uppercase with subsystem prefixes (examples: `VERIFY_*` in `plans/verify_fork.sh`, `STATUS_PUBLISHER_*` in `dashboard/publisher/publisher.py`, `PREFLIGHT_*` in `plans/preflight.sh`).

## Implementation Patterns
- Contract-first traceability is embedded in code comments and test names (e.g., AT references in `crates/soldier_core/src/execution/gate.rs`, `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/tests/test_async_wal_writer.rs`).
- “Thin wrapper + canonical implementation” is a repeated pattern:
  - `verify.sh` delegates to `plans/verify.sh`.
  - `plans/verify.sh` delegates to `plans/verify_fork.sh`.
- API surfaces are intentionally explicit via `pub use` facades in `crates/soldier_core/src/execution/mod.rs` and `crates/soldier_infra/src/store/mod.rs`.
- Compatibility-anchor tests are used to keep workflow/doc-sync checks stable while tests move internally (example: `crates/soldier_core/tests/test_intent_pipeline.rs`).

## Error Handling Conventions
- Fail-closed defaults are standard in runtime-critical paths:
  - Config resolution rejects missing non-defaulted parameters (`crates/soldier_infra/src/config.rs`).
  - Durable bootstrapping validates absolute paths/capacities up front (`crates/soldier_infra/src/bootstrap.rs`).
  - WAL/registry paths use explicit typed error enums (`crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_infra/src/store/trade_id_registry.rs`).
- Rust code favors typed `Result<T, E>` and domain enums over opaque strings at boundaries.
- Shell gates use deterministic exits and explicit “hard fail” helpers (`fail`, `die`) in scripts like `plans/verify_fork.sh`, `plans/slice_completion_enforce.sh`, and `plans/contract_review_validate.sh`.
- Python operational code uses typed exception wrappers with stable error codes (for example `PublisherError` in `dashboard/publisher/publisher.py`).

## Logging and Diagnostics
- Runtime Rust logging uses `tracing` with structured fields (examples in `crates/soldier_infra/src/bootstrap.rs`, `crates/soldier_core/src/execution/gate.rs`).
- Verify/harness logs are artifact-backed by design: each gate writes `<gate>.log`, `<gate>.rc`, `<gate>.time`, plus `FAILED_GATE` and `verify.meta.json` under `artifacts/verify/<run_id>/` (implemented in `plans/lib/verify_utils.sh` and `plans/verify_fork.sh`).
- Python publisher logs to both file and stderr/stdout stream with unified formatting (`dashboard/publisher/publisher.py`).

## Configuration Conventions
- Safety-critical config defaults are centralized in code, not scattered env parsing (`crates/soldier_infra/src/config.rs`).
- Schema-first validation is common for status and contract artifacts (`tools/validate_status.py`, `plans/contract_review_validate.sh`).
- Feature strictness frequently uses sentinel files and env toggles (examples: `CONTRACT_COVERAGE_CI_SENTINEL`, `CROSSREF_CI_STRICT_SENTINEL` in `plans/verify_fork.sh`).

## Planning Implications
- Treat `plans/verify.sh` and `plans/verify_fork.sh` as interface/implementation pair; behavior changes belong in `plans/verify_fork.sh`, not wrapper scripts.
- For workflow/harness edits, preserve deterministic artifact behavior expected by `plans/prd_set_pass.sh` and tested in `plans/tests/test_verify_fork_guardrails.sh`.
- Preserve fail-closed semantics when introducing new config, gate, or status fields; align changes across runtime code, schema validators, and verify gates (`crates/*`, `tools/validate_status.py`, `plans/verify_fork.sh`).
- Keep contract traceability explicit by carrying AT/anchor references in tests and comments where behavior is safety-critical (`specs/CONTRACT.md` plus affected module/tests).
