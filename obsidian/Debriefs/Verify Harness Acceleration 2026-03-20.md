---
project: "[[Verify Harness Acceleration]]"
date: "2026-03-20"
---

## Commits
- `7061f36e` — verify: finish harness acceleration tranche

## 0) What shipped
- Feature/behavior: Landed the verify-harness truthfulness hardening, shared verify bootstrap and scope runners, non-authoritative focused verify entrypoints, explicit Rust accelerators, and the late closeout fixes for the review-stack wrapper, PR-review hook stdin handling, and Bash 3.2 preflight array handling. Python overlap was explicitly deferred because the current authoritative repo path does not run a Python gate tranche.
- Value (what problem it solves): Local harness iteration is faster and more truthful without weakening `./plans/verify.sh quick|full` as the only authoritative verify surface, the surrounding workflow surfaces no longer block or hang the branch spuriously, and the work is now up on PR #227.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The harness core was green, but authoritative verify still failed or stalled in adjacent workflow control surfaces: the stale `.claude/commands/review-stack.md` wrapper broke `plans/tests/test_review_command_wrappers.sh`, `.claude/hooks/pr-review-gate-hook.sh` could hang under the piped hook test harness, and `plans/preflight.sh` tripped a Bash 3.2 empty-array `set -u` edge case in full mode.
- Time/token drain it caused: Each issue forced another slow authoritative rerun after the previous blocker was cleared, which stretched a mostly-finished harness change into multiple extra diagnostic cycles.
- Workaround I used this session (exploit): I kept the shared-runner and truthfulness work intact, fixed each adjacent failure at its ownership boundary, and revalidated with the targeted shell tests before rerunning authoritative verify.
- Next-agent default behavior (subordinate): When authoritative verify fails late in a workflow-adjacent surface, fix that surface directly if it is now in project scope; do not dilute the harness contract or skip the failing test.
- Permanent fix proposal (elevate): Keep wrapper docs thin, detach hook scripts from stdin before invoking subprocess-heavy logic, and guard Bash 3.2 empty arrays anywhere `set -u` is active in shared workflow scripts.
- Smallest increment: Preserve the new regressions around wrapper contracts, hook behavior, and preflight fixture profiles whenever those files move again.
- Validation (proof it got better): `bash plans/tests/test_review_command_wrappers.sh`, `bash plans/tests/test_pr_review_gate_hook.sh`, and `bash plans/tests/test_preflight_fixture_profiles.sh` now pass, and authoritative `./plans/verify.sh quick` plus `./plans/verify.sh full` are green from this worktree.

## 2) Best follow-up
- Single best next step: If the team wants a durable benchmark artifact, archive a short before/after timing summary from the existing verify artifacts; no Python-overlap patch is warranted for the current repo shape.
- 1-3 upgrades worth considering:
  - If the team still wants Python overlap, collect comparable timing samples first and only land concurrency if the wall-clock delta is real.
  - Add a lightweight regression around hook stdin detachment if `.claude/hooks/pr-review-gate-hook.sh` grows again.
  - If `nextest` is adopted broadly, add a focused runtime test with fake `cargo-nextest` / `sccache` shims so accelerator behavior stays covered without relying on local installs.

## 3) Enforceable rules
- If a workflow-facing script is added or refactored, update `plans/workflow_files_allowlist.txt`, `plans/workflow_verify.sh`, and the matching workflow regression tests in the same tranche.
- If Rust-runner behavior moves across files, update both `test_verify_timeout_policy.sh` and `verify_gate_contract_check.sh` to reflect the new ownership boundary before rerunning authoritative verify.
- If a shell hook or wrapper reads stdin implicitly, detach it or make the reader explicit before invoking subprocesses that may also touch stdin.
