# Testing Map (Quality-Focused)

Analysis date: 2026-03-04

## Canonical Test Entrypoints
- Primary verification entrypoint is `plans/verify.sh` (thin wrapper) delegating to `plans/verify_fork.sh`.
- Root `verify.sh` is also a thin wrapper to `plans/verify.sh`.
- Iteration mode: `./plans/verify.sh quick`.
- Completion mode: `./plans/verify.sh full`.
- Fast preflight (before full verify chain) is `plans/preflight.sh`.

## Framework and Runner Matrix
- Rust:
  - `cargo test` for unit/integration/property tests (`plans/lib/rust_gates.sh`).
  - `proptest` is used for property testing (`crates/soldier_core/Cargo.toml`, `crates/soldier_core/src/execution/quantize_prop_tests.rs`).
- Python:
  - `pytest` is the runner in verify (`plans/lib/python_gates.sh`).
  - `unittest` style suites run under pytest collection in `python/proof_graph/tests/test_rules.py`, `python/proof_graph/tests/test_schema.py`, and `python/proof_graph/tests/test_validate.py`.
  - JSON schema checks use `jsonschema` (`tools/validate_status.py`, `tests/test_publisher_contract.py`).
- Bash harness:
  - Workflow/gate tests are shell scripts in `plans/tests/` (invoked in preflight and workflow maintenance scripts).
- TypeScript/Node:
  - Probe-style testing path uses `tsx` via `npx -y tsx tests/probes/status_contract_probe.ts` in `tests/test_status_contract_model.py`.

## Test Layout and Ownership by Area
- Core Rust behavior:
  - In-module suites in `crates/soldier_core/src/execution/*_tests.rs` and related modules.
  - Integration/facade suites in `crates/soldier_core/tests/`.
- Infra Rust behavior:
  - Integration/runtime suites in `crates/soldier_infra/tests/` (WAL, bootstrap, phase0 runtime, replay, config defaults).
- Repo-level Python and contract tests:
  - Top-level tests in `tests/` with fixtures under `tests/fixtures/`.
- Proof-graph validator subsystem:
  - Tests under `python/proof_graph/tests/` with dedicated fixtures in `python/proof_graph/tests/fixtures/`.
- Workflow/harness safety checks:
  - Shell test suite under `plans/tests/` plus smoke runner `plans/test_verify_fork_smoke.sh`.

## Current Test Inventory Signal (Snapshot)
- Rust test-related files in `crates/`: 84 (`find crates ...`).
- Top-level `tests/` test assets (`test_*.py`, `*.ts`, `*.md`): 14.
- Harness test scripts in `plans/tests/test_*.sh`: 62.
- These are volume signals only; they are not coverage percentages.

## Test Types in Active Use
- Unit tests:
  - Rust module-level tests (example: `crates/soldier_core/src/execution/tlsm_tests.rs`).
- Integration tests:
  - Rust crate integration tests (example: `crates/soldier_infra/tests/test_phase0_runtime.rs`).
  - Python subprocess/integration tests (example: `tests/test_status_contract_model.py`).
- Property tests:
  - Proptest-based randomized checks in Rust (example: `crates/soldier_core/src/execution/quantize_prop_tests.rs`).
- Contract/schema conformance tests:
  - Status schema and semantics checks (`tools/validate_status.py`, `tests/test_validate_status_semantics_versioning.py`).
  - Contract/profile/crossref gate scripts wired in `plans/verify_fork.sh`.
- Harness/meta tests:
  - Guardrails around verify behavior and workflow contracts (`plans/tests/test_verify_fork_guardrails.sh`, `plans/tests/test_contract_profile_parity.sh`, `plans/tests/test_prd_set_pass.sh`).
- Adversarial completeness checks:
  - Coverage accounting and semantic assertion checks in `plans/lib/adversarial_gate.sh`.

## Fixtures, Mocks, and Test Data Patterns
- Heavy fixture usage through committed JSON/Markdown artifacts:
  - `tests/fixtures/status/`, `tests/fixtures/runtime_state/`, `tests/fixtures/status_semantics/`, `python/proof_graph/tests/fixtures/`.
- Temporary filesystem/state fixtures are common in Rust and Python:
  - Examples in `crates/soldier_infra/tests/test_async_wal_writer.rs` and `tests/test_publisher_contract.py` (`tmp_path`).
- Network behavior is simulated with local test servers and monkeypatching in Python (`tests/test_publisher_contract.py`).
- Mocking libraries are not a dominant pattern; tests mostly use concrete objects + fixture data.

## Verification Gates and Scripts
- `plans/preflight.sh` performs fast checks (tools/files/shell parse/schema checks + fixture test profile).
- `plans/verify_fork.sh` orchestrates gate flow and artifacts for quick/full modes.
- Language gates are split into dedicated scripts:
  - Rust: `plans/lib/rust_gates.sh`
  - Python: `plans/lib/python_gates.sh`
  - Node/TS: `plans/lib/node_gates.sh`
- Verify artifact contract is implemented in `plans/lib/verify_utils.sh` and consumed by pass flip gate `plans/prd_set_pass.sh`.

## Coverage Signals and Gaps
- Strong signals present:
  - Contract/profile traceability reports via `tools/at_coverage_report.py` and `plans/contract_coverage_matrix.py` in `plans/verify_fork.sh`.
  - Full-pass evidence requires gate RC artifacts, including `fail_closed_coverage.rc`, in `plans/prd_set_pass.sh`.
  - Adversarial report generation (`adversarial_report.json`) is enforced by `plans/lib/adversarial_gate.sh`.
- Gaps/limits currently visible:
  - No repository-wide line/branch coverage threshold tool is enforced (no `pytest-cov`, `tarpaulin`, `grcov`, or similar gate observed).
  - Node gate steps are script-dependent and can be effectively no-op in `dashboard/package.json` because only `convex:*` scripts are defined.
  - Quick mode intentionally reduces depth (e.g., Rust `--lib` + smoke tests, optional quick pytest expression fallback).

## Planning Implications
- Any change to workflow/harness scripts should add or update a matching shell gate test in `plans/tests/` plus verify wiring in `plans/verify_fork.sh`.
- If adding new test suites, ensure they are reachable from quick/full verify paths instead of relying on ad hoc local commands.
- If hard coverage requirements are needed, add explicit measurable gates (tool + threshold + artifact) and integrate with `plans/prd_set_pass.sh` expectations.
- Preserve fixture determinism and fail-closed behavior when extending status/contract validators (`tools/validate_status.py`, `plans/lib/status_reason_codegen_gate.sh`, `plans/preflight.sh`).
