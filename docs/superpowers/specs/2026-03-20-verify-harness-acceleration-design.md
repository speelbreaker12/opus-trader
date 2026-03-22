# Verify Harness Acceleration Design

## Goal

Reduce local verify iteration time without changing the public verify contract or making runs host-dependent.

The public contract remains `./plans/verify.sh quick|full`. Any focused entrypoint is a local iteration tool only and must not be treated as equivalent to authoritative verify evidence. The portable baseline remains unchanged.

## Constraints

- `plans/verify.sh` must remain a thin wrapper.
- Workflow changes must be deterministic and artifact-backed.
- Explicit accelerator intent must not silently degrade into host-specific fallback behavior.
- CI defaults stay portable: no accelerator required unless explicitly requested.

## Decisions

### 1. Freeze verify authority first

- `./plans/verify.sh quick|full` remains the only pass/merge truth.
- `plans/verify.sh` stays a thin wrapper.
- `plans/verify_fork.sh` stays the canonical orchestration path.
- Any new focused entrypoint must identify itself as non-authoritative in both output and artifacts.

### 2. Fix harness truthfulness before adding new surface area

- Fix the current nonblocking-gate ambiguity first.
- A real soft-gate finding may stay nonblocking and artifact-backed.
- A broken gate runner, missing script, or exec failure must fail clearly as infrastructure breakage.
- Do not keep the current shape where both conditions collapse into the same warn-only outcome.
- Use an explicit convention for nonblocking gates:
  - `exit 1` = legitimate soft finding
  - `exit 2+` = infrastructure failure
  - `124`, `126`, `127` remain timeout / exec failure classes and are always treated as infrastructure failure

### 3. Refactor shared runners before adding speed knobs

- Add a shared setup helper in `plans/lib/verify_env.sh` for environment/bootstrap state currently owned by `verify_fork.sh`.
- Extract reusable Rust runner units from `plans/lib/rust_gates.sh` for:
  - format
  - clippy
  - tests
  - smoke/facade lints
- Reuse those same units from both full verify and any focused local dispatcher.
- Only extract shared contract/workflow runners where the refactor is genuinely needed.
- This is a small entry-point extraction from a compact file, not a large monolith breakup.

### 4. Add one focused dispatcher, not a family of wrappers

- Add a single `plans/verify_scope.sh` dispatcher.
- Initial supported surfaces:
  - `./plans/verify_scope.sh contract`
  - `./plans/verify_scope.sh workflow`
  - `./plans/verify_scope.sh rust clippy`
  - `./plans/verify_scope.sh rust tests`
- Keep the surface small and reuse shared runners.
- This is the biggest total local-iteration win because skipping irrelevant gates beats making irrelevant gates faster.
- Scoped runs must not share the authoritative artifact root:
  - authoritative runs: `artifacts/verify/<run_id>/`
  - scoped runs: `artifacts/verify_scope/<run_id>/`
- Scoped `verify.meta.json` must include at least:
  - `"authoritative": false`
  - `"scope": "<selected-slice>"`
  - `"run_root": "verify_scope"`

### 5. `sccache` and test-runner selection are explicit

- Add `VERIFY_USE_SCCACHE=0|1`.
- Add `VERIFY_TEST_RUNNER=cargo|nextest`.
- Default is `VERIFY_USE_SCCACHE=0` and `VERIFY_TEST_RUNNER=cargo`.
- Requested but missing accelerator = hard fail.
- Unsupported `nextest` path = deterministic fallback to `cargo test` with explicit logged evidence.
- `sccache` is expected to be the biggest repeated Rust win and should land before `nextest`.
- `nextest` is useful but not treated as a blind drop-in replacement; it must preserve the current test-selection semantics.

### 6. Harden parallel diagnostics before adding more parallelism

- Preserve the actual `wait` result for crashed parallel subprocesses when `.rc` is missing.
- Improve first-failure reporting so secondary failures remain visible.
- Keep slot-reclaim behavior unchanged; the operational change is in crash diagnosis and reporting, not queue control.
- This is diagnostics hardening, not the primary throughput constraint, so it should not delay the shared-runner refactor, scoped dispatcher, or Rust accelerators.
- It should land before any new Python overlap work, because extra parallelism makes weak diagnostics more painful.

### 7. Python overlap is conditional and separate

- Do not bundle Python overlap into the same patch unless timings prove it matters.
- Measure after the runner refactor, accelerator work, and parallel diagnostics hardening.
- Only overlap Python with Rust/workflow if the median Python slice time exceeds 20% of total authoritative quick-run wall-clock time across 3 comparable same-machine runs.

### 8. Operator tuning stays out of the harness contract

- `VERIFY_PARALLEL_JOBS` is an operator tuning knob, not a design pillar.
- custom `CARGO_TARGET_DIR` or `/tmp` target-dir experiments are workstation-local tweaks
- these may be documented later, but they should not be baked into default repo behavior

## Artifact Contract

Each authoritative verify run should make accelerator state auditable:

- whether `sccache` was requested and active
- which Rust test runner was requested
- whether any Rust test command fell back from `nextest` to `cargo test`
- whether Python overlap was enabled

Each focused scoped run should also make its non-authoritative status auditable.

Required isolation/identity:
- authoritative runs live under `artifacts/verify/<run_id>/`
- scoped runs live under `artifacts/verify_scope/<run_id>/`
- scoped metadata must include `authoritative=false` and `scope=<slice>`

This can live in `verify.meta.json` or a sibling artifact, but it must be deterministic and easy to inspect from CI or local artifacts.

## Files

- `plans/verify_fork.sh`
  - own the top-level verify mode and artifact metadata
  - decide whether Python overlap is enabled
- `plans/lib/rust_gates.sh`
  - own `sccache` and Rust test-runner selection
  - emit deterministic metadata for any runner fallback
- `plans/lib/verify_env.sh`
  - own shared environment/bootstrap setup used by both authoritative and scoped entrypoints
- `plans/verify_scope.sh`
  - own the focused local iteration dispatcher
- `plans/lib/python_gates.sh`
  - only changes if Python overlap is proven and added
- `plans/tests/test_verify_accelerators.sh`
  - cover explicit accelerator requests, failure mode, artifact metadata, and any nextest fallback path
- `plans/tests/test_verify_scope.sh`
  - cover dispatcher routing and non-authoritative signaling

## Rollout

### Phase 1

- freeze verify authority
- TDD nonblocking-gate truthfulness hardening
- TDD shared Rust runners
- TDD `verify_scope.sh`
- keep Python sequencing unchanged
- choose the scoped artifact root and metadata contract up front

### Phase 2

- TDD explicit `sccache` support
- TDD explicit `nextest` support
- run workflow verification and repo quick verify

### Phase 3

- TDD parallel diagnostics hardening for existing parallel batches
- run workflow verification and repo quick verify

### Phase 4

- gather timing evidence from Phase 3
- if evidence supports it, TDD Python overlap
- rerun workflow verification and repo quick verify/full as appropriate

### Phase 5

- optionally document local-only tuning for operators
- do not change default harness behavior for `VERIFY_PARALLEL_JOBS` or target-dir placement
