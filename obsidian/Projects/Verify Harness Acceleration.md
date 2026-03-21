---
status: done
priority: P1
branch: verify
base: main
pr:
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
  - plans/preflight.sh
  - plans/verify_gate_contract_check.sh
  - plans/verify_fork.sh
  - plans/verify_scope.sh
  - plans/lib/verify_env.sh
  - plans/lib/verify_scope_gates.sh
  - plans/lib/rust_gates.sh
  - plans/lib/python_gates.sh
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
---

## Current State
The verify-harness acceleration tranche is closed. `verify_fork.sh` uses the shared `verify_env` bootstrap plus shared contract/workflow scope helpers, nonblocking gates distinguish findings from broken harness execution, the Rust runner exposes reusable functions with explicit `sccache` / `nextest` controls and deterministic metadata, `verify_scope.sh` remains a non-authoritative local dispatcher, and parallel failure reporting preserves meaningful wait status plus secondary-failure context. The final closeout also fixed the stale `.claude/commands/review-stack.md` wrapper, hardened `.claude/hooks/pr-review-gate-hook.sh` against stdin-driven hangs, and removed a Bash 3.2 `set -u` empty-array failure in `plans/preflight.sh`. Authoritative `./plans/verify.sh quick` and `./plans/verify.sh full` are green from this worktree. Python-overlap concurrency is explicitly deferred: this repo state does not enter `plans/lib/python_gates.sh` during authoritative verify because there is no `pyproject.toml` or `requirements.txt`, so there is no measured Python slice to justify extra scheduling complexity.

## Commits
- `pending` — 2026-03-20 — verify harness acceleration work in progress.

## Key Files
- .claude/commands/review-stack.md
- .claude/hooks/pr-review-gate-hook.sh
- plans/preflight.sh
- plans/verify_fork.sh
- plans/verify_gate_contract_check.sh
- plans/verify_scope.sh
- plans/lib/verify_env.sh
- plans/lib/verify_scope_gates.sh
- plans/lib/rust_gates.sh
- plans/lib/python_gates.sh
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

## Log
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
