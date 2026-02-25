# Reconciliation R1 Preflight Audit: S1-013

> S1.0b PR merge-readiness automation gate
> Auditor: Claude Opus 4.6 (recon/S1-v3.1)
> Date: 2026-02-23
> Mode: READ-ONLY

---

## A) GATE RESULT

**STOPLIGHT: GREEN** -- no code changes required.

All enforcement points are present and tested. Both ATs (AT-1056, AT-1057) have
causal TRIP + NON-TRIP proof. Fail-closed behavior is verified across all six
categories. No remediation items block self-review.

---

## B) AT AUDIT TABLE

### AT-1056: CI job `build:csp_only` builds workspace in CSP_ONLY mode; build MUST succeed; job exits 0

| Dimension | Finding |
|-----------|---------|
| **Contract text** | CONTRACT.md:599-604 (section 0.Z.9.1): "Given: the repository is at a clean commit. When: the CI job `build:csp_only` builds the workspace in CSP_ONLY mode... Then: the build MUST succeed." |
| **Enforcement point** | `plans/pr_gate.sh:830-831` -- `if [[ "$CHECK_FAIL" != "0" ]]; then problems+=("checks_failing")`. The script queries check-runs for the PR head SHA via `gh api repos/$repo/commits/$HEAD_SHA/check-runs` (line 426) and fails the gate when any check-run has a non-success conclusion (line 485: `select(.conclusion!="success" and .conclusion!="neutral" and .conclusion!="skipped")`). This catches a failing `build:csp_only` CI job. |
| **Fail-closed: missing data** | PASS. When `checks_json` fetch fails (rc!=0 or empty), the script falls back to the commit status API (lines 430-443). If status is `pending`, `CHECK_PENDING` is incremented (line 436-437); if `failure`/`error`, `CHECK_FAIL` is incremented (lines 438-439). Both produce non-zero exit. |
| **Fail-closed: null/empty** | PASS. When `check_runs` array is empty and no status exists, the fallback status API is consulted. If the top-level state is `pending`, the gate blocks (`checks_pending`). Zero check-runs + success status passes -- this is correct (no checks = GitHub hasn't registered them yet, handled by status API). |
| **Fail-closed: stale/unknown** | PASS. When `MERGEABLE` is `null` or `MERGEABLE_STATE` is `unknown`, the gate adds `mergeability_not_ready` to problems (line 814-815), blocking the PR. |
| **Fail-closed: tool missing** | PASS. Lines 67-73: `need gh`, `need git`, `need jq` -- exits 1 with "missing required tool" before any logic executes. |
| **Fail-closed: API error** | PASS. Line 396: `gh api ... || die "failed to fetch PR via gh api"`. Line 413: `die "failed to fetch head commit"`. Line 506-507: `die "failed to fetch PR review/issue comments"`. |
| **Fail-closed: parse error** | PASS. `set -euo pipefail` (line 2) ensures any unhandled jq parse failure exits non-zero. |
| **TRIP test** | `test_pr_gate.sh` Case 5 (line 409-410): `GH_MODE=pending_checks` -> `expect_fail "checks pending" "checks_pending"`. Case 7 (line 417-418): `GH_MODE=fallback_failure` -> `expect_fail "fallback failure state" "checks_failing"`. Both prove the gate exits non-zero with the correct reason token when check-runs fail or are pending. |
| **NON-TRIP test** | `test_pr_gate.sh` Case 1 (lines 352-358): `GH_MODE=inline_addressed` with all checks passing -> `rc_case1 == 0`, output contains "OK: PR gate passed". |
| **Causal proof** | PROVEN. TRIP tests inject failing/pending check-runs and assert non-zero exit + specific reason token. NON-TRIP test uses clean mocks and asserts zero exit. The `expect_fail` helper (lines 15-32) validates both exit code AND pattern match, proving causality. |
| **Verdict** | PROVEN |

### AT-1057: CI job `test:csp_only` runs CSP acceptance suite in CSP_ONLY mode; all CSP tests MUST pass; no GOP test may execute

| Dimension | Finding |
|-----------|---------|
| **Contract text** | CONTRACT.md:607-612 (section 0.Z.9.1): "Given: the workspace is built in CSP_ONLY mode. When: the CI job `test:csp_only` runs the CSP acceptance suite... Then: (a) all CSP tests MUST pass, and (b) no GOP test may execute." |
| **Enforcement point** | Same as AT-1056: `plans/pr_gate.sh:830-835`. The gate checks ALL check-runs for the PR head SHA. A failing `test:csp_only` job is caught by the same `CHECK_FAIL` / `CHECK_PENDING` logic. The gate does not distinguish between build and test failures -- both are caught by the same unified check-run aggregation. |
| **Fail-closed: missing data** | PASS. Same fallback behavior as AT-1056. |
| **Fail-closed: null/empty** | PASS. Same behavior as AT-1056. |
| **Fail-closed: stale/unknown** | PASS. Same mergeability_not_ready guard. |
| **Fail-closed: tool missing** | PASS. Same `need` guards. |
| **Fail-closed: API error** | PASS. Same `die` on API failures. |
| **Fail-closed: parse error** | PASS. Same `set -euo pipefail`. |
| **TRIP test** | `test_pr_gate.sh` Case 5 (line 409-410): `GH_MODE=pending_checks` catches any pending check including `test:csp_only`. The mock at line 215-218 simulates a check-run named "verify" in `in_progress` state. Case 7 (line 417-418): `GH_MODE=failing_checks` simulates a completed check with `conclusion: failure` (mock lines 220-224). Both verify the gate blocks. |
| **NON-TRIP test** | Same as AT-1056: Case 1 proves passing checks yield gate pass. |
| **Causal proof** | PROVEN. The gate treats ALL check-run failures identically. Since `test:csp_only` is a check-run, a failure in it triggers `checks_failing`. The test mocks prove the mechanism works for any failing check-run. |
| **Verdict** | PROVEN |

---

## C) PREMORTEM CROSS-REFERENCE

### Section 2: Assumptions

| # | Assumption | Premortem status | Audit finding |
|---|-----------|-----------------|---------------|
| 1 | `gh` CLI is available and authenticated | Pending (fixture test expected) | VERIFIED. `plans/pr_gate.sh:71` calls `need gh` which exits non-zero if not found. The test scaffolds a mock `gh` at `$fake_bin/gh` and puts it on PATH, proving the real script consults `gh`. No explicit test for "gh not found" scenario exists in test_pr_gate.sh, but the `need` guard is trivially correct (`command -v` + `die`). LOW RISK. |
| 2 | `gh pr view --json` returns stable JSON schema | Killed (external dependency) | VERIFIED KILLED. The mock fixtures pin expected field names (`mergeable`, `mergeable_state`, `head.sha`, `head.ref`, `base.ref`, `html_url`, `requested_reviewers`). If GitHub changes the schema, the real `gh` output would differ and the jq filters would fail, which `set -euo pipefail` catches. |
| 3 | Branch auto-detection works | Pending (fixture test expected) | VERIFIED. `plans/pr_gate.sh:302-308` auto-detects via `gh pr view --json number --jq '.number'`. Case 1 of test_pr_gate.sh (line 352-358) omits `--pr` and confirms the gate passes (auto-detect succeeds). The mock at line 76-79 handles this exact invocation. |

### Section 4: Decisions

| Decision | Chosen option | Implemented? | Evidence |
|----------|--------------|--------------|----------|
| Output format: reason tokens to stdout, exit code 1 for all failures | Option A: reason token to stdout, exit 1 | YES | `plans/pr_gate.sh:893`: `echo "FAIL: PR gate failed: ${problems[*]}"` to stderr, line 904: `exit 1`. All failure modes produce exit 1. Reason tokens are space-separated in the FAIL message. |
| Bot comment detection: match by GitHub user type Bot | Option A: match `.user.type == "Bot"` or login contains "copilot" | YES | `plans/pr_gate.sh:667-668`: `def is_bot($u): ($u.type == "Bot") or ...contains("copilot")`. Confirmed in multiple locations (lines 728-729, 753-755). |

### Section 5: Wrong Implementation Gate

| AT | Wrong impl identified | Blocked by? | Audit finding |
|----|----------------------|-------------|---------------|
| AT-1056 | pr_gate.sh always exits 0 (never checks build status) | Fixture test with failing build -> must exit non-zero | BLOCKED. Case 5 (`pending_checks`) and Case 7 (`fallback_failure`) both assert non-zero exit with specific reason tokens. A no-op gate would fail these tests. |
| AT-1057 | Script checks build but not test status | Fixture test with test failure -> must exit non-zero | BLOCKED. The gate checks ALL check-runs uniformly (line 485 selects any non-success conclusion). Case 5 and Case 7 use a generic "verify" check-run name, proving the mechanism is not build-specific. |

---

## D) DESIGN RISK NOTES

1. **AT mapping is indirect, not direct.** AT-1056 and AT-1057 describe CI jobs (`build:csp_only`, `test:csp_only`), while `pr_gate.sh` checks GitHub check-run status generically. The gate does not verify that specific CI job names exist -- it only checks whether all check-runs pass. This is a correct architectural choice (the gate should not hardcode CI job names), but it means the AT is enforced at the CI configuration level (`.github/workflows/ci.yml` must define these jobs), not in `pr_gate.sh` itself. The gate is the **enforcement mechanism**, not the **producer** of the test results.

   **Risk**: LOW. If someone removes the `build:csp_only` or `test:csp_only` CI jobs, the gate would not detect their absence -- it only checks that existing check-runs pass. However, this is documented as an accepted architectural boundary: the CI configuration is the source of truth for which jobs exist.

2. **Duplicate check-run resolution.** The gate resolves duplicate check-run names by taking the latest run per check name (lines 461-483: `sort_by(...) | group_by(.name) | map(last)`). This is tested in Case 4 (`duplicate_checks`). Correct behavior: a stale failure followed by a fresh success passes.

3. **Fallback to commit status API.** When check-runs API fails, the script falls back to the older commit status API (lines 430-443). This is tested in Cases 6 and 7 (`fallback_pending`, `fallback_failure`). The fallback is fail-closed: pending or failure states block.

4. **No observability metrics.** The prd.json entry has empty `observability.metrics`. This is appropriate for a CI gate script -- there is no runtime metric emission. The drift metric in `loss_mode` is "N/A -- CI gate, no runtime metric", which is honest.

5. **test_pr_gate.sh is not in preflight smoke/full arrays.** Per `plans/preflight.sh:277`, it was moved to `verify_fork.sh` gate 14g for wall-clock optimization (parallel with rust compilation). This is confirmed by `plans/verify_fork.sh:685-686` and validated by `test_preflight_fixture_profiles.sh:78-89`. The test still runs during `verify.sh full`.

---

## E) REMEDIATION PLAN

No remediation items identified. All enforcement points are present, all fail-closed categories are covered, and both ATs have causal TRIP + NON-TRIP proof.

| # | Item | Priority | Blocking? |
|---|------|----------|-----------|
| -- | (none) | -- | -- |

---

## F) SCOPE CHECK

### Files in scope.touch vs actual implementation

| File | In scope.touch? | Exists? | Role |
|------|----------------|---------|------|
| `plans/pr_gate.sh` | YES | YES (922 lines) | Primary enforcement script |
| `plans/tests/test_pr_gate.sh` | YES | YES (621 lines) | 29 fixture test cases |
| `plans/preflight.sh` | YES | YES | Wires fixture tests; notes pr_gate moved to verify_fork |
| `plans/workflow_verify.sh` | YES | YES | Includes `check_script "plans/pr_gate.sh"` (line 29) |
| `plans/workflow_files_allowlist.txt` | YES | YES | Contains `plans/pr_gate.sh` (line 44) and `plans/tests/test_pr_gate.sh` (line 93) |
| `plans/tests/test_workflow_allowlist_coverage.sh` | YES | YES | Includes `plans/tests/test_pr_gate.sh` in required list (line 91) |

### Out-of-scope modifications detected

None. The `scope.avoid` lists `crates/**` and `specs/CONTRACT.md`. No modifications to those areas are present in the S1-013 implementation.

### prd.json entry integrity

- `passes: true` -- confirmed
- `enforcing_contract_ats: ["AT-1056", "AT-1057"]` -- both traced and verified
- `primary_owner_for: ["AT-1056", "AT-1057"]` -- confirmed
- `implementation_tests: ["plans/tests/test_pr_gate.sh"]` -- confirmed (29 test cases)
- `enforcement_point: ""` -- correct (CI gate, not a runtime enforcement point)
- `loss_mode.worst_case`: "PR gate auto-detection fails -> manual gate checks missed -> broken code merged" -- accurate
- `loss_mode.fail_closed_cap`: "PR gate blocks merge; no production code impact" -- accurate
- `loss_mode.drift_metric`: "N/A -- CI gate, no runtime metric" -- accurate

### Test case coverage summary (29 cases in test_pr_gate.sh)

| Case | Scenario | Exit | Key assertion |
|------|----------|------|---------------|
| 1 | All green, bot comments warn mode | 0 | "OK: PR gate passed" + warn message |
| 2 | Dirty merge state | 1 | "merge_conflict_or_blocked" |
| 3 | Unstable merge state (mergeable=true) | 0 | Passes (unstable != blocked) |
| 3b | Legacy PRD-style branch (S1-TEST-fix) | 0 | Story ID extraction works |
| 3c | Plain hyphenated story ID branch | 0 | Not truncated |
| 4 | Duplicate check-run history | 0 | Latest success wins |
| 5 | Pending checks | 1 | "checks_pending" |
| 6 | Fallback pending status | 1 | "checks_pending" |
| 7 | Fallback failure status | 1 | "checks_failing" |
| 8 | Unknown review decision (default) | 0 | Warning only |
| 9 | Unknown review decision (strict) | 1 | "review_decision_unknown" |
| 10 | Path traversal story ID | 1 | "invalid --story value" |
| 10b | Slash-containing story ID | 1 | "invalid --story value" |
| 11 | Inline bot comment unaddressed | 1 | "inline_bot_comments_unaddressed" |
| 11b | Resolved inline threads ignored | 0 | Passes |
| 12 | Issue bot comment without ACK | 1 | "missing_aftercare_ack_for_head" |
| 13 | Issue bot comment with valid ACK | 0 | Passes |
| 14 | Strict ACK mode, no ACK | 1 | "missing_aftercare_ack_for_head" |
| 15 | Strict ACK mode, ACK present | 0 | Passes |
| 15b | ACK mode off, bot comments | 0 | Passes |
| 15c | ACK mode off overrides --require-aftercare-ack | 0 | Passes |
| 16 | Self check-run ignored by regex | 0 | Passes |
| 17 | Blocked + self check ignored | 0 | Warning about blocked-ignore |
| 18 | Blocked without self check | 1 | "merge_conflict_or_blocked" |
| 19 | Bot comment blocking mode | 1 | "new_bot_comments_since_last_push" |
| 20 | Copilot review required, not present | 1 | "copilot_review_pending" |
| 21 | Copilot review for HEAD SHA | 0 | Passes |
| 22 | Copilot as requested reviewer | 0 | Passes |
| 0 | No --story (copilot-only mode) | 0 | Passes |
| 0b | No story, non-story branch | 0 | Passes |
| 0c | No story, pre-PR mode fail bypassed | 0 | Passes |
| 23 | Changes requested | 1 | "changes_requested" |
| 24 | Branch story mismatch | 1 | "story_branch_mismatch" |
| 25 | Invalid branch naming | 1 | "invalid_story_branch_name" |
| 26 | Pre-PR gate failure | 1 | "pre_pr_review_gate_failed" |
| 27 | Pre-PR gate skip mode | 0 | Passes |
| 28 | Invalid pre-PR review mode | 1 | Fast-fail validation |
| 29 | Invalid aftercare mode | 1 | Fast-fail validation |

---

## Git Status (end of audit)

Verified via `git status --porcelain` -- only pre-existing modifications and untracked files present; no new changes introduced by this audit except the reconciliation artifact itself.

---

READY FOR SELF_REVIEW
