---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- 5ebf6b2d

## 0) What shipped
- Feature/behavior: Upgrade 2 now has an explicit 2A leaf / 2B orchestration boundary in the canonical checklist, `execution/quantize.rs` now exposes a crate-private `quantize_with_events(...)` seam with graybox/parity coverage, and `plans/ssot_lint.sh` now ignores test fixtures under `plans/tests/fixtures/`.
- Value (what problem it solves): This lets the leaf telemetry rollout proceed without scope games, flips another real 2A row to `PASS`, and removes a broken repo-level commit blocker from main.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The repo pre-commit hook failed before it ever reached the staged Execution Facade files; `plans/ssot_lint.sh` treated `plans/tests/fixtures/doc_sync/*.md` as canonical duplicate `IMPLEMENTATION_PLAN.md` / `POLICY.md` files; retrying `git commit` failed on a repo-wide condition unrelated to the staged scope.
- Time/token drain it caused: It forced an investigation outside the original quantize seam work, a new regression test, and a second commit attempt instead of a straight commit after verification.
- Workaround I used this session (exploit): I reproduced the bug in a synthetic repo test, then taught `ssot_lint` to filter `plans/tests/fixtures/` in both the git-backed and fallback file scans.
- Next-agent default behavior (subordinate): When a workflow guard fails on repo copies or duplicates, check whether test fixtures are being scanned before assuming the staged feature branch is wrong.
- Permanent fix proposal (elevate): Keep fixture-path filtering in `plans/ssot_lint.sh` and retain a dedicated regression test wired into `plans/verify_fork.sh`.
- Smallest increment: Keep `plans/tests/test_ssot_lint.sh` in the workflow integration test list and allowlist so future edits cannot silently drop the guard.
- Validation (proof it got better): `bash plans/ssot_lint.sh` now returns `SSOT_LINT_OK`, `bash plans/tests/test_ssot_lint.sh` passes, and the guard no longer fails on doc-sync fixture copies.

## 2) Best follow-up
- Single best next step: Convert `execution/pricer.rs` to the same crate-private event seam pattern and flip the 2A checklist row only after graybox plus wrapper parity tests exist.
- 1-3 upgrades worth considering:
- What: Convert `execution/post_only_guard.rs` after pricer. | Increment: add one `*_with_events(...)` seam and one graybox reject test. | Validation: the module's row flips from `FAIL` to `PASS` in the Upgrade 2A checklist.
- What: Convert `execution/preflight.rs` while 2A is still isolated from 2B. | Increment: extract an event sink for preflight reject visibility only. | Validation: targeted preflight tests prove no global metric lines on the graybox path.
- What: Extend `ssot_lint` fixture exclusions only if another guard proves they are non-normative. | Increment: add one more fixture-path regression only when a real false positive appears. | Validation: future fixture additions stop breaking commits without hiding true duplicate docs.

## 3) Enforceable rules
- rule: When a workflow guard reports duplicate canonical docs, exclude test fixtures only through an explicit path filter plus regression test.
  trigger: Any edit to `plans/ssot_lint.sh` or another repo-wide duplicate-doc guard.
  prevents: Commit blockers caused by fixture copies or, worse, silent guard weakening without proof.
  enforce: `plans/ssot_lint.sh` and `plans/tests/test_ssot_lint.sh`
- rule: Upgrade 2 scope edits must land first in the canonical checklist and only then in project/status notes.
  trigger: Any decision to split, defer, or close an Upgrade 2 surface.
  prevents: Narrative scope drift that disagrees with the acceptance gate.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: Flip a 2A row to `PASS` only when the module has both graybox side-effect isolation tests and wrapper parity tests.
  trigger: Any attempt to mark a leaf telemetry module complete.
  prevents: PASS claims that prove the seam exists but not that production metrics behavior was preserved.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
