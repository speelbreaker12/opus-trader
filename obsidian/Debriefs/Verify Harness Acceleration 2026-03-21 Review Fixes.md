---
project: "[[Verify Harness Acceleration]]"
date: "2026-03-21"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: closed the PR #227 review findings in the verify harness by splitting `fail_closed_coverage.sh` infra/setup exits from soft findings, adding the missing `.claude` regressions to workflow-scope verify, restoring direct-entry bootstrapping for `plans/lib/rust_gates.sh`, sharing CSP strict-mode auto-detection so `./plans/verify_scope.sh contract` matches authoritative verify, reducing `pr-review-gate-hook` runtime with single-pass payload parsing plus cached marker reads, and preserving local `quick` proof by restoring the canonical wrapper sentence in `.codex/commands/commit.md` and `.codex/commands/push-pr.md` while keeping repo-local skill lookup behavior.
- Value (what problem it solves): `./plans/verify.sh quick` no longer reports green when the fail-closed coverage gate is broken, `./plans/verify_scope.sh workflow` now validates the workflow surfaces it claims to cover, ad hoc/shared Rust-runner entrypoints work again instead of dying on an unbound artifact directory, scoped contract proof no longer silently relaxes CSP trace validation when `specs/CONTRACT.md` or `specs/TRACE.yaml` changed, the PR-review hook now satisfies the review comment without timing out in `wf_test_pr_review_gate_hook`, and local wrapper regressions stay aligned with the repo’s Codex command shims.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): quick verify masked broken `fail_closed_coverage` runs as `.warn` findings; workflow-scope verify skipped the `.claude` review regressions changed on the branch; direct `bash plans/lib/rust_gates.sh` aborted before any Rust gate with `VERIFY_ARTIFACTS_DIR: unbound variable`; and `verify_scope contract` could not auto-enable CSP strict mode because the helper lived only in `plans/verify_fork.sh`.
- Time/token drain it caused: review feedback could not be closed with confidence because the harness entrypoints were reporting partial coverage as success, forcing manual spot checks instead of trusting the named gates.
- Workaround I used this session (exploit): locked each finding behind a focused shell regression first, then patched only the affected harness surfaces, moved the CSP strict helper into the shared scope helper library, and reran both the targeted tests and the real scoped/authoritative entrypoints.
- Next-agent default behavior (subordinate): when a nonblocking quick gate is introduced, treat `rc=1` as the reserved soft-finding path and force any setup/map/tooling fault onto `rc>=2` with a regression proving the distinction.
- Permanent fix proposal (elevate): codify a shared exit-code contract for nonblocking shell gates and add a small lint that rejects gates routed through `run_logged_nonblocking_gate` unless their scripts declare the same taxonomy explicitly.
- Smallest increment: add a shell-level policy check that scans candidate nonblocking gates for `SOFT_FINDING_EXIT=1` plus `INFRA_FAILURE_EXIT>=2`, and wire it into `plans/tests/test_verify_fork_guardrails.sh` or a companion workflow fixture.
- Validation (proof it got better): `bash plans/tests/test_fail_closed_gate_map_paths.sh`, `bash plans/tests/test_verify_scope.sh`, `bash plans/tests/test_verify_accelerators.sh`, `bash plans/tests/test_pr_review_gate_hook.sh`, `bash plans/tests/test_review_command_wrappers.sh`, `bash plans/tests/test_verify_fork_guardrails.sh`, `./plans/verify_scope.sh workflow`, `./plans/verify_scope.sh contract`, and `./plans/verify.sh quick` all passed on 2026-03-21.

## 2) Best follow-up
- Single best next step: push the refreshed `verify` branch and let PR #227 CI confirm the same quick-gate truthfulness on a clean checkout now that the local review-comment fixes and wrapper compatibility patch both have authoritative proof.
- 1-3 upgrades worth considering:
  - add a shared nonblocking-gate taxonomy helper so future shell gates cannot silently drift back to ambiguous exit codes.
  - teach `verify_scope`/`workflow_verify` to emit a small executed-test manifest, making workflow-surface omissions obvious from artifacts instead of code inspection.
  - trim or parallelize the slowest workflow fixtures (`test_external_review_generic.sh`, `test_pr_review_gate_hook.sh`) if quicker local proof becomes the branch constraint again.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- rule: any shell gate routed through `run_logged_nonblocking_gate` must reserve `rc=1` for soft findings and use `rc>=2` for infra/setup faults. trigger: adding or modifying a nonblocking quick gate. prevents: broken tools/maps being downgraded into `.warn` artifacts. enforce: `plans/tests/test_fail_closed_gate_map_paths.sh` plus the `run_logged_nonblocking_gate` guardrails in `plans/tests/test_verify_fork_guardrails.sh`.
- rule: when `verify_scope.sh workflow` claims workflow-surface coverage, every changed `.claude` command or hook surface needs an explicit workflow regression in `run_workflow_scope_gates`. trigger: modifying `.claude/commands/*` or `.claude/hooks/*` on the verify branch. prevents: non-authoritative workflow scope reporting green without executing the touched surface tests. enforce: `plans/tests/test_verify_scope.sh`.
- rule: any shared gate runner kept executable as a standalone script must bootstrap `verify_env` on direct entry before touching artifact paths. trigger: extracting helpers into `plans/lib/*.sh` while retaining a `BASH_SOURCE == $0` entrypoint. prevents: unbound verify-context variables on local/manual entry. enforce: `plans/tests/test_verify_accelerators.sh`.
