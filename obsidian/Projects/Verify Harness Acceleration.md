---
status: in-progress
priority: P1
branch: verify
base: main
pr: 227
started: "2026-03-20"
aliases: []
keywords:
  - verify
  - workflow
  - verify-scope
  - verify-env
  - sccache
  - nextest
scope_paths:
  - .claude/commands/review-stack.md
  - .claude/hooks/pr-review-gate-hook.sh
  - .codex/commands/commit.md
  - .codex/commands/push-pr.md
  - plans/preflight.sh
  - plans/fail_closed_coverage.sh
  - plans/verify_gate_contract_check.sh
  - plans/verify_fork.sh
  - plans/verify_scope.sh
  - plans/lib/verify_env.sh
  - plans/lib/verify_scope_gates.sh
  - plans/lib/rust_gates.sh
  - plans/lib/python_gates.sh
  - plans/tests/test_fail_closed_gate_map_paths.sh
  - plans/tests/test_preflight_fixture_profiles.sh
  - plans/tests/test_verify_accelerators.sh
  - plans/tests/test_verify_gate_contract_check_batching.sh
  - plans/tests/test_verify_timeout_policy.sh
  - plans/tests/test_rust_gates_quick_clippy.sh
  - plans/tests/test_rust_gates_smoke_targets.sh
  - plans/tests/test_verify_fork_guardrails.sh
  - plans/tests/test_workflow_allowlist_coverage.sh
  - plans/tests/test_verify_scope.sh
  - plans/workflow_files_allowlist.txt
  - plans/workflow_verify.sh
  - docs/superpowers/specs/2026-03-20-verify-harness-acceleration-design.md
  - docs/superpowers/plans/2026-03-20-verify-harness-acceleration.md
  - obsidian/Projects/Verify Harness Acceleration.md
  - obsidian/Debriefs/Verify Harness Acceleration 2026-03-20.md
  - obsidian/Debriefs/Verify Harness Acceleration 2026-03-21 Review Fixes.md
  - obsidian/Debriefs/Verify Harness Acceleration 2026-03-21 Handoff.md
---

## Current State
PR #227 is active on `verify` against `main`. The original acceleration tranche is in branch history, and the current follow-up review-fix slice is ready locally. `fail_closed_coverage.sh` now reserves `rc=1` for real coverage findings and uses `rc=2` for setup/infra faults, `verify_scope.sh workflow` now executes the `.claude` PR-review/wrapper regressions it previously skipped, direct `bash plans/lib/rust_gates.sh` execution now bootstraps the shared verify environment before writing runner metadata, and `verify_scope.sh contract` now shares the authoritative CSP strict-mode auto-detection helper instead of silently relaxing when `specs/CONTRACT.md` or `specs/TRACE.yaml` changed. The 2026-03-21 review-fix scope also now includes `.codex/commands/commit.md` and `.codex/commands/push-pr.md` so local workflow-wrapper checks remain compatible with the repo-provided Codex command wrappers while the PR comment fixes are verified. Fresh local evidence is green again after the hook parser/cache reduction and Codex wrapper compatibility patch: `bash plans/tests/test_pr_review_gate_hook.sh`, `bash plans/tests/test_review_command_wrappers.sh`, and `./plans/verify.sh quick` all passed on 2026-03-21.

## Commits
- `37e64685` — 2026-03-21 — close PR #227 review findings: fail_closed coverage infra exit taxonomy, workflow-scope `.claude` regressions, direct rust_gates bootstrap, PR-review hook/runtime fixes, and contract-scope CSP strict parity.
- `7061f36e` — 2026-03-20 — verify harness acceleration tranche landed with fresh authoritative quick/full proof.

## Key Files
- .claude/commands/review-stack.md
- .claude/hooks/pr-review-gate-hook.sh
- .codex/commands/commit.md
- .codex/commands/push-pr.md
- plans/preflight.sh
- plans/fail_closed_coverage.sh
- plans/verify_fork.sh
- plans/verify_gate_contract_check.sh
- plans/verify_scope.sh
- plans/lib/verify_env.sh
- plans/lib/verify_scope_gates.sh
- plans/lib/rust_gates.sh
- plans/lib/python_gates.sh
- plans/tests/test_fail_closed_gate_map_paths.sh
- plans/tests/test_preflight_fixture_profiles.sh
- plans/tests/test_verify_accelerators.sh
- plans/tests/test_verify_gate_contract_check_batching.sh
- plans/tests/test_verify_timeout_policy.sh
- plans/tests/test_rust_gates_quick_clippy.sh
- plans/tests/test_rust_gates_smoke_targets.sh
- plans/tests/test_verify_fork_guardrails.sh
- plans/tests/test_workflow_allowlist_coverage.sh
- plans/tests/test_verify_scope.sh
- plans/workflow_files_allowlist.txt
- plans/workflow_verify.sh
- docs/superpowers/specs/2026-03-20-verify-harness-acceleration-design.md
- docs/superpowers/plans/2026-03-20-verify-harness-acceleration.md

## Debriefs
- [[Verify Harness Acceleration 2026-03-20]]
- [[Verify Harness Acceleration 2026-03-21 Review Fixes]]

## Handoffs
- [[Verify Harness Acceleration 2026-03-21 Handoff]]

## Log
### 2026-03-21
- Fixed the `fail_closed_coverage.sh` exit taxonomy so quick verify only soft-warns on true coverage findings while missing `jq`, missing gate-map state, and other setup faults fail the gate with `rc=2`.
- Expanded the review-fix slice scope to `.codex/commands/commit.md` and `.codex/commands/push-pr.md`, restoring the canonical wrapper sentence expected by `plans/tests/test_review_command_wrappers.sh` while preserving the repo-local skill resolution logic in those Codex command files.
- Reworked `.claude/hooks/pr-review-gate-hook.sh` so the PR-create parser reads the tool payload in a single Python pass, lazily resolves repo roots for relative `env -C/--chdir`, caches marker JSON reads, and keeps the single-quoted heredoc form required by the review comment without regressing `wf_test_pr_review_gate_hook` runtime.
- Added regression coverage for the new fail-closed taxonomy (`plans/tests/test_fail_closed_gate_map_paths.sh`), workflow-scope inclusion of the `.claude` PR-review/wrapper tests (`plans/tests/test_verify_scope.sh`), and standalone `plans/lib/rust_gates.sh` bootstrap behavior (`plans/tests/test_verify_accelerators.sh`).
- Extended `plans/lib/verify_scope_gates.sh` so `./plans/verify_scope.sh workflow` now runs `plans/tests/test_pr_review_gate_hook.sh` and `plans/tests/test_review_command_wrappers.sh` instead of reporting green without those surfaces.
- Sourced `plans/lib/verify_env.sh` from `plans/lib/rust_gates.sh`, added a direct-entry bootstrap via `init_verify_env`, and kept sourced-callers fail-closed with an explicit `VERIFY_ARTIFACTS_DIR` requirement.
- Shared `compute_csp_strict_changed_files` / `should_enable_csp_strict` into `plans/lib/verify_scope_gates.sh`, removed the silent `declare -F` fallback in `build_csp_trace_cmd auto`, and restored contract-scope CSP strict-mode parity with authoritative verify.
- Added a red/green regression in `plans/tests/test_verify_scope.sh` that proves contract-scope auto strict mode adds `--strict` for `specs/CONTRACT.md` / `specs/TRACE.yaml` diffs, and updated `plans/tests/test_verify_fork_guardrails.sh` to source the shared helper location.
- Verified the slice with `bash plans/tests/test_fail_closed_gate_map_paths.sh`, `bash plans/tests/test_verify_scope.sh`, `bash plans/tests/test_verify_accelerators.sh`, `bash plans/tests/test_pr_review_gate_hook.sh`, `bash plans/tests/test_review_command_wrappers.sh`, `bash plans/tests/test_verify_fork_guardrails.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, `bash plans/tests/test_rust_gates_quick_clippy.sh`, `./plans/verify_scope.sh workflow`, `./plans/verify_scope.sh contract`, and `./plans/verify.sh quick`.
- Updated the Obsidian handoff note to reflect that the contract-scope CSP strict-mode blocker is resolved and the next step is push/CI verification.

### 2026-03-20
- Captured the approved design: portable baseline by default, explicit accelerator requests must be deterministic and fail clearly when missing.
- Split the rollout into two phases: `sccache` and `nextest` first; Python overlap only if timing evidence proves it reduces wall-clock time without destabilizing the harness.
- Tightened the plan after review: `./plans/verify.sh quick|full` remains the only pass/merge truth, shared runners come before accelerators, `verify_scope.sh` is the single focused-entrypoint dispatcher, and Python overlap is explicitly phase-later work.
- Tightened sequencing again after harness review: `R2` truthfulness hardening now comes first, while `C1/C2` move into a dedicated diagnostics tranche that lands before any new Python overlap work but does not block entrypoints or Rust accelerators.
- Clarified optimization ranking: focused entrypoints are the biggest overall iteration win, `sccache` is the biggest repeated Rust win, `nextest` follows `sccache`, and operator tuning like `VERIFY_PARALLEL_JOBS` or target-dir placement remains out-of-scope for the default harness patch series.
- Incorporated plan-review fixes: chose scoped artifact isolation (`artifacts/verify_scope/<run_id>/` plus `authoritative=false` metadata), added the shared `verify_env` setup layer to the intended file set, chose the nonblocking exit-code convention, clarified that parallel wait preservation is a diagnostics/reporting change rather than queue-control change, and made the Python-overlap threshold mechanical.
- Implemented Chunk 1 truthfulness hardening and Chunk 2 shared-runner extraction: `verify_fork.sh` now sources `verify_env.sh`, Rust gates are reusable functions, and workflow control-surface checks cover the new helper.
- Implemented Chunk 3 and Chunk 4: `verify_scope.sh` now dispatches `contract`, `workflow`, `rust clippy`, and `rust tests` with non-authoritative metadata; the Rust runner supports explicit `VERIFY_USE_SCCACHE` and `VERIFY_TEST_RUNNER=cargo|nextest`, writes `rust_runner.meta.json`, and logs smoke-suite cargo fallbacks deterministically.
- Implemented Chunk 5 diagnostics hardening: parallel batches now preserve missing-`.rc` wait status, write `parallel_failures.summary.log`, and surface secondary failures instead of hiding them behind the first failure only.
- Fixed refactor fallouts in `test_verify_timeout_policy.sh`, `verify_gate_contract_check.sh`, and `test_verify_gate_contract_check_batching.sh`, and removed the stale `test_contract_at_wording_drift.sh` workflow entry.
- Verified focused harness regressions with `bash plans/tests/test_verify_accelerators.sh`, `bash plans/tests/test_verify_scope.sh`, `bash plans/tests/test_verify_timeout_policy.sh`, `bash plans/tests/test_verify_gate_contract_check_batching.sh`, `bash plans/tests/test_verify_fork_guardrails.sh`, `bash plans/tests/test_workflow_allowlist_coverage.sh`, `bash plans/tests/test_rust_gates_quick_clippy.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, and `./plans/verify_scope.sh workflow`.
- Closed the authoritative blocker by restoring `.claude/commands/review-stack.md` to the thin-wrapper contract expected by `plans/tests/test_review_command_wrappers.sh`.
- Hardened `.claude/hooks/pr-review-gate-hook.sh` by detaching the hook from stdin and replacing the heredoc-based marker reader, which removed the `gh pr create --title ready` hang in `plans/tests/test_pr_review_gate_hook.sh`.
- Fixed shared workflow gate naming drift in `plans/lib/verify_scope_gates.sh` so direct and parallel workflow runs emit the same gate names.
- Fixed the Bash 3.2 `set -u` empty-array failure in `plans/preflight.sh` and locked it down in `plans/tests/test_preflight_fixture_profiles.sh`.
- Refreshed the project note scope to include the auxiliary `.claude`, preflight, and shared-helper files that were required to close the branch cleanly.
- Recorded Python overlap as intentionally deferred because authoritative verify in this repo state has no Python gate tranche to overlap.
- Pushed `verify` to `origin` and opened PR #227 against `main`.
- Re-ran `bash plans/tests/test_pr_review_gate_hook.sh`, `bash plans/tests/test_review_command_wrappers.sh`, and authoritative `./plans/verify.sh quick` after the review-comment fixes plus the approved local scope expansion for Codex wrapper compatibility; all passed.
