---
project: "[[PR Review Gate Hook Fix]]"
date: "2026-03-21"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Restored fail-closed `gh pr create` review-stack enforcement in `.claude/hooks/pr-review-gate-hook.sh` and aligned `/review-stack` marker docs/tests to the canonical `${SAFE_BRANCH}.json` path, while keeping backward-compatible support for legacy `.review-stack.json` markers.
- Value (what problem it solves): Removes the baseline fail-open path that allowed PR creation without current review proof and prevents legacy markers from bypassing an invalid canonical marker.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Fresh `main` reproduced `plans/tests/test_pr_review_gate_hook.sh` failing because the hook warned and exited `0` on missing review proof; local long-running shell fixtures were also noisy because unrelated background harnesses in other worktrees kept re-spawning the same hook tests.
- Time/token drain it caused: Re-running the full shell fixture directly in this session produced misleading hangs/timeouts and extra process-noise debugging before the actual hook logic could be isolated.
- Workaround I used this session (exploit): Reduced verification to direct sanitized hook invocations against temp repos, plus syntax/diff checks, so the changed decision paths could be proven without relying on the noisy long-running wrapper.
- Next-agent default behavior (subordinate): Reuse the direct-hook proof commands first when this hook/test area is noisy locally, then rerun the full `plans/tests/test_pr_review_gate_hook.sh` once the concurrent background harnesses are quiet.
- Permanent fix proposal (elevate): Isolate or kill inherited/background shell harnesses before running this workflow test locally, or give the repo a deterministic dedicated wrapper for hook-test runs that sanitizes ambient shell state and refuses concurrent duplicates.
- Smallest increment: Keep this branch scoped to the hook/doc/test fix and capture the exact direct-hook proofs in project notes and `plans/progress.txt`.
- Validation (proof it got better): Direct sanitized hook calls now show `rc=2` with `No review-stack result` when the canonical marker is missing, `rc=0` when only a legacy `.review-stack.json` pass marker exists, and `rc=2` when a canonical `FAIL` marker coexists with a legacy pass marker.

## 2) Best follow-up
- Single best next step: Stage only the in-scope workflow files plus Obsidian/progress updates, commit this branch, and let CI or a quiet local session run the full workflow fixture cleanly.
- 1-3 upgrades worth considering:
  - Add a tiny dedicated local runner for PR-review hook tests that sanitizes shell environment and rejects duplicate concurrent runs.
  - If this hook area keeps regressing, add a smaller focused fixture script for canonical-vs-legacy marker precedence so that behavior can be proven without the full shell suite.
  - Coordinate with the separate workflow-timeout lane if `wf_test_pr_review_gate_hook` still dominates `workflow_verify` runtime after this correctness fix lands.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: If `${SAFE_BRANCH}.json` exists anywhere the hook would resolve it, treat it as authoritative and do not fall back to `.review-stack.json`. Trigger: touching `.claude/hooks/pr-review-gate-hook.sh` marker-selection logic. Prevents: legacy-pass markers fail-opening around canonical invalid markers. Enforce: `plans/tests/test_pr_review_gate_hook.sh`.
- Rule: `/review-stack` docs must emit `artifacts/pr-review-gate/${SAFE_BRANCH}.json`, not `.review-stack.json`. Trigger: editing `.claude/commands/review-stack.md`. Prevents: producer/consumer marker-path drift. Enforce: `plans/tests/test_pr_review_gate_hook.sh`.
- Rule: Missing, malformed, or stale review-stack proof must block `gh pr create` with exit `2`. Trigger: editing `.claude/hooks/pr-review-gate-hook.sh`. Prevents: PR publication without current review evidence. Enforce: `plans/tests/test_pr_review_gate_hook.sh` and direct hook smoke proofs.
