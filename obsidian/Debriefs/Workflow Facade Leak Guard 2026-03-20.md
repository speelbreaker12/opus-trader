---
project: "[[Workflow Facade Leak Guard]]"
date: "2026-03-20"
---

## Commits
- `0c944689` — workflow: add facade leak guard
- pending — project-note refresh for dedicated branch/worktree and PR-boundary readiness

## 0) What shipped
- Feature/behavior: Added a repo-wide facade public-module leak guard, wired it into live verification, and covered semicolon, attribute-prefixed, multiline-attribute, and inline-block `pub mod` forms with regression fixtures.
- Value (what problem it solves): Prevents internal module visibility leaks from silently re-entering the public API surface and makes the architecture rule fail closed in normal verification.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The first implementation was only fixture-tested and missed live rust-gates wiring; subsequent verification exposed stale workflow references and syntax edge cases (`#[cfg] pub mod`, multiline attributes, inline `pub mod foo {}`) that would have left false negatives in the new gate.
- Time/token drain it caused: Repeated review-fix-verify loops and multiple full workflow quick passes were required before the new rule was actually trustworthy.
- Workaround I used this session (exploit): Tightened the guard incrementally with failing regression fixtures first, then reran targeted harness checks before each quick verify.
- Next-agent default behavior (subordinate): For new workflow guards, verify both fixture coverage and the live gate wiring in `plans/lib/rust_gates.sh`/`plans/verify_fork.sh` before claiming the rule exists.
- Permanent fix proposal (elevate): Add a deterministic workflow fixture that asserts every newly introduced lint script is both allowlisted and executed by a live verify gate, not only referenced by another test.
- Smallest increment: Extend the existing rust-gates/workflow-fixture coverage to assert new lint gate names whenever `plans/workflow_files_allowlist.txt` grows.
- Validation (proof it got better): `bash plans/tests/test_lint_facade_public_modules.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, and `./plans/verify.sh quick` all passed after the hardening and live-wire fixes.

## 2) Best follow-up
- Single best next step: Push the dedicated branch `project/workflow-facade-leak-guard` and open the PR now that `./plans/verify.sh full` has passed and the workspace is correctly attached.
- 1-3 upgrades worth considering:
  - Add a fixture that fails if a workflow integration test listed in `verify_fork.sh` does not exist on disk.
  - Add a fixture that compares new lint scripts under `plans/` against the live rust/workflow gate wiring.
  - Consider moving machine-local runtime snapshots out of tracked files if they continue to churn during verification.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- When adding a workflow lint, add a direct fixture for the lint and a second fixture that proves a live verify gate executes it.
- If `./plans/verify.sh quick` rewrites tracked runtime snapshots, restore checked-in metadata before committing.
- Treat parser edge cases as required regressions for syntax-based guards: same-line attributes, multiline attributes, and inline block bodies must all have explicit tests.
