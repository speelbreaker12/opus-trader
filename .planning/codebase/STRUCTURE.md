# Structure Map

**Analysis date:** 2026-03-04  
**Scope:** repository layout, naming/organization conventions, and concern ownership.

## 1) Top-level directory layout
- `crates/` — Rust workspace runtime code (`soldier_core`, `soldier_infra`).
- `plans/` — verification + workflow harness scripts, schemas, and harness tests.
- `specs/` — behavioral contract, workflow contract, flow/state-machine specs.
- `scripts/` — contract/spec validators and support scripts.
- `tools/` — status validation, profile checks, coverage/meta checks.
- `dashboard/` — status storage/query backend (Convex TS) and publisher sidecar (Python).
- `python/` — MCP server and proof-graph tooling libraries.
- `tests/` — repository-level tests/fixtures/probes not bound to one Rust crate.
- `docs/` — architecture/codebase/process documentation.
- `artifacts/` — generated verify/story outputs; persistent evidence directories.

## 2) Runtime code organization

### 2.1 Workspace and crate split
- Workspace membership is declared in `Cargo.toml`.
- `crates/soldier_core/` contains domain safety/decision logic.
- `crates/soldier_infra/` contains infra/persistence/adapters and depends on `soldier_core` (`crates/soldier_infra/Cargo.toml`).

### 2.2 `soldier_core` layout
- Module roots in `crates/soldier_core/src/lib.rs`.
- Execution subsystem under `crates/soldier_core/src/execution/`.
- Risk subsystem under `crates/soldier_core/src/risk/`.
- Venue/capability/lifecycle subsystem under `crates/soldier_core/src/venue/`.
- Idempotency primitives under `crates/soldier_core/src/idempotency/`.
- Recovery utilities under `crates/soldier_core/src/recovery/`.
- Integration tests live in `crates/soldier_core/tests/` and are mostly `test_*.rs` / `prop_*.rs`.

### 2.3 `soldier_infra` layout
- Public crate surface in `crates/soldier_infra/src/lib.rs`.
- Bootstrap/config in `crates/soldier_infra/src/bootstrap.rs` and `crates/soldier_infra/src/config.rs`.
- Durable storage in `crates/soldier_infra/src/store/` (`ledger.rs`, `trade_id_registry.rs`, `mod.rs`).
- WAL adapter in `crates/soldier_infra/src/wal.rs`.
- Venue-specific DTO/mapping in `crates/soldier_infra/src/deribit/` and `crates/soldier_infra/src/deribit/public/`.
- Infra tests in `crates/soldier_infra/tests/` with `test_*.rs` naming.

## 3) Workflow and verification organization
- Canonical verify entrypoint: `plans/verify.sh` (wrapper).
- Canonical implementation: `plans/verify_fork.sh`.
- Shared shell helpers: `plans/lib/verify_utils.sh`.
- Language gate executors: `plans/lib/rust_gates.sh`, `plans/lib/python_gates.sh`, `plans/lib/node_gates.sh`.
- PRD/workflow state files: `plans/prd.json`, `plans/progress.txt`, `plans/ideas.md`, `plans/pause.md`.
- Pass flip enforcement: `plans/prd_set_pass.sh`.
- Workflow step/receipt control: `plans/wf_step.sh` and `.wf/receipts/<story>/`.
- Harness tests are shell-first in `plans/tests/test_*.sh`; fixture assets live in `plans/tests/fixtures/`.

## 4) Spec, validation, and policy file organization
- Runtime behavioral source of truth: `specs/CONTRACT.md`.
- Workflow source of truth: `specs/WORKFLOW_CONTRACT.md`.
- Flow-level specs in `specs/flows/*.yaml|*.md`.
- State-machine specs in `specs/state_machines/*.yaml`.
- Status registry/spec files in `specs/status/*`.
- Validator scripts for these specs in `scripts/check_*.py`.
- Additional policy/meta validation in `tools/*.py` and `tools/ci/*.py`.

## 5) Status/dashboard structure
- Convex backend files in `dashboard/convex/` (`schema.ts`, `status.ts`, `status_contract.ts`, `validators.ts`, `http.ts`).
- Publisher sidecar files in `dashboard/publisher/` (`publisher.py`, `transform.py`, `spool.py`, `state.py`).
- Contract/status schemas used by validators in `python/schemas/*.json`.
- Runtime status fixture sets in `tests/fixtures/status/` and `tests/fixtures/status_semantics/`.

## 6) Naming and file-pattern conventions
- Rust modules use `snake_case.rs` and explicit `mod.rs` boundaries (for example `crates/soldier_core/src/execution/mod.rs`).
- Co-located Rust tests often use `*_tests.rs`; crate integration tests use `test_*.rs` and property tests use `prop_*.rs`.
- Shell harness scripts use action-oriented names: `verify*.sh`, `*_gate.sh`, `*_check.sh`, `*_logged.sh`.
- Python validators follow `check_*.py` / `validate_*.py` conventions (`scripts/check_contract_crossrefs.py`, `tools/validate_status.py`).
- Planning and process docs are uppercase or descriptive markdown (`AGENTS.md`, `ENTRYPOINTS.md`, `REPO_MAP.md`, `plans/README.md`).

## 7) Where key concerns live
- Dispatch gating and reject semantics: `crates/soldier_core/src/execution/*`.
- Risk thresholds and exposure models: `crates/soldier_core/src/risk/*` + defaults in `crates/soldier_infra/src/config.rs`.
- Idempotency hash and trade dedup: `crates/soldier_core/src/idempotency/hash.rs`, `crates/soldier_infra/src/store/trade_id_registry.rs`.
- WAL durability/replay: `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_infra/src/bootstrap.rs`.
- Workflow contract enforcement: `plans/verify_fork.sh`, `plans/workflow_contract_gate.sh`, `plans/verify_gate_contract_check.sh`.
- Status shape enforcement: `dashboard/convex/status_contract.ts`, `tools/validate_status.py`, `python/schemas/status_*.schema.json`.

## 8) Mutable/generated areas (planning caution)
- Verify artifacts are written to `artifacts/verify/<run_id>/` (`*.log`, `*.rc`, `*.time`, `FAILED_GATE`, `verify.meta.json`).
- Story review/proof artifacts are under `artifacts/story/<story_id>/`.
- Workflow receipts and locks are under `.wf/receipts/` and `.wf/recon_scope_lock/`.
- Build outputs and caches include `target/`, `.pytest_cache/`, `.ruff_cache/`, and `__pycache__/` directories.

## 9) Practical extension points
- New runtime gates usually land in `crates/soldier_core/src/execution/` and then wire into `base_gates.rs`, `pipeline.rs`, or `open_runtime.rs`.
- New durable fields generally require coordinated updates across `store/ledger.rs`, replay/bootstrap paths, and `specs/CONTRACT.md`.
- New verification checks should be added to `plans/verify_fork.sh` and, if language-specific, to `plans/lib/*_gates.sh` with artifact-backed logging behavior preserved.
