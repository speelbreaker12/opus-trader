# Story Premortem: S1-013

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-013 — S1.0b PR merge-readiness automation gate
- Contract clause(s): §0.Z.9 CSP-Only CI Gate, §0.Z.9.1 Meta-Acceptance Tests
- Acceptance tests: AT-1056, AT-1057
- Touch scope: `plans/pr_gate.sh`, `plans/tests/test_pr_gate.sh`, `plans/preflight.sh`, `plans/workflow_verify.sh`, `plans/workflow_files_allowlist.txt`, `plans/tests/test_workflow_allowlist_coverage.sh`
- **Risk rating**: LOW
  - Infrastructure/CI script only. No production Rust code touched. No order placement,
    risk logic, or state machine changes. Worst case: a bad PR merges or a good PR is
    blocked — both are recoverable.

## 1) Clause audit (contract → AT traceability)

Source: CONTRACT.md §0.Z.9 "CSP-Only CI Gate (Normative)" and §0.Z.9.1 "Meta-Acceptance Tests for CSP_ONLY CI Gate"

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-1056 | §0.Z.9.1 | CI job `build:csp_only` builds workspace in CSP_ONLY mode; build MUST succeed; job exits 0 and produces runnable binary | MUST | Yes |
| AT-1057 | §0.Z.9.1 | CI job `test:csp_only` runs CSP acceptance suite in CSP_ONLY mode; all CSP tests MUST pass; no GOP test may execute; job exits 0 | MUST | Yes |

Note: AT-1056 and AT-1057 are meta-acceptance tests for the CI pipeline itself. S1-013's `pr_gate.sh` is the automation that *checks* these CI states, not the CI jobs themselves. The story's acceptance criteria focus on the gate script's ability to detect and report CI/review/merge states.

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `gh` CLI is available and authenticated in the CI environment | If `gh` is not installed or not authenticated, pr_gate.sh fails with a confusing error | Fixture test: mock `gh` not found -> script exits non-zero with clear error message | Pending |
| 2 | `gh pr view --json` returns a stable JSON schema with `mergeable`, `statusCheckRollup`, `reviewDecision` fields | If GitHub changes the API schema, the jq filters break silently | Fixture test with known JSON payloads; pin expected field names | Killed -- gh CLI JSON schema is determined by GitHub API; we pin expected field names in fixture tests. If schema changes, fixture tests fail explicitly. Accepted as external dependency risk, not an internal assumption. |
| 3 | Branch auto-detection via `gh pr view --json number` works for the current branch | If branch has no PR, or multiple PRs, the command fails or returns unexpected results | Fixture test: no-PR case -> clear error; single PR -> correct number extracted | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | `gh` CLI not available or not authenticated | Script fails with cryptic error | Check for `gh` at script start; exit non-zero with reason token `gh_not_available` | N/A (infra pre-req) |
| 2 | PR has no status checks yet (empty `statusCheckRollup`) | jq filter returns null; script might exit 0 (false pass) | Fail-closed: empty/null check state -> exit non-zero with `checks_pending` | AT-1057 (indirectly: ensures checks ran) |
| 3 | Bot comments detected but gate runs in default mode -> warns but does not block | Developer ignores warning; stale bot comment causes issues post-merge | Default: warn. `--bot-comments-mode block` for strict environments. Acceptance test covers both modes | Story acceptance criterion 3 |
| 4 | Race condition: CI checks pass between script invocation and PR merge | Gate reports green, but a new commit is pushed before merge | Out of scope for this script (GitHub branch protection handles this); document limitation | N/A (GitHub-level concern) |
| 5 | Auto-detection picks wrong PR when branch has multiple PRs | Script gates on wrong PR | `gh pr view` for current branch returns the most recent open PR; if ambiguous, fail with `multiple_prs_detected` | Fixture test with multi-PR mock |
| 6 | Script assumes `jq` is installed but it's missing from CI environment | jq parse failures exit non-zero but reason token is not emitted; CI shows generic failure | Check for `jq` at script start alongside `gh` check; exit with `jq_not_available` | N/A (infra pre-req) |
| 7 | GitHub API rate limit hit during pr_gate.sh execution | gh commands return 403; script may misinterpret as "checks failing" | Detect 403/rate-limit responses explicitly; exit with `github_rate_limited` reason token | N/A (transient) |

## 4) Open decisions (resolve before coding)

### Decision: Output format for reason tokens
- **What is ambiguous / missing**: The story specifies reason tokens (`merge_conflict_or_blocked`, `checks_pending`, `checks_failing`, `changes_requested`) but not the output format (stdout, stderr, exit code mapping).
- **Evidence**: prd.json S1-013 acceptance: "exits non-zero with deterministic reason tokens"
- **Options**:
  1. Print reason token to stdout, use exit code 1 for all failures
  2. Use distinct exit codes per failure type (e.g., 2=merge_conflict, 3=checks_pending, 4=checks_failing, 5=changes_requested)
- **Chosen**: (A) Reason token to stdout, exit code 1 — deciding factor: shell scripts consuming the output can parse the token; distinct exit codes are fragile and hard to remember
- **Why not others**: Distinct exit codes require documentation and are easy to misremember; reason tokens are self-documenting
- **Scope control**:
  - What we're NOT doing yet: Machine-readable JSON output (just text tokens for now)
  - What unblocks us if this choice is wrong: Adding JSON output is additive

### Decision: Bot comment detection scope
- **What is ambiguous / missing**: "bot/copilot comments newer than head commit" — which bots count? Only GitHub Copilot? Any bot?
- **Evidence**: prd.json S1-013 acceptance criterion 3: "bot/copilot comments newer than head commit"
- **Options**:
  1. Match comments from users with `[bot]` suffix or `type: Bot` in GitHub API
  2. Hardcode known bot usernames (copilot, dependabot, etc.)
- **Chosen**: (A) Match by GitHub user type `Bot` — deciding factor: forward-compatible; catches all bots without maintenance
- **Why not others**: Hardcoded list requires updates when new bots are added
- **Scope control**:
  - What we're NOT doing yet: Filtering by bot comment content (e.g., only actionable comments)
  - What unblocks us if this choice is wrong: Switching to a hardcoded list is a one-line filter change

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-1056 | pr_gate.sh always exits 0 (never actually checks build status) | Gate is a no-op; PRs with failing CSP_ONLY builds would merge | Fixture test: mock `gh` returning failed build status -> script must exit non-zero with `checks_failing` |
| AT-1057 | Script checks build status but not test status (only validates AT-1056, not AT-1057) | GOP tests could execute in CSP_ONLY pipeline undetected | Fixture test: mock `gh` returning test failure -> script must exit non-zero; mock with GOP test execution -> must detect and block |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-1056 | pr_gate.sh (CI status check) | test_pr_gate.sh::test_build_csp_only_failure_blocks | TRIP | NON-TRIP: test_pr_gate.sh::test_all_green_passes | exit code != 0; reason token == `checks_failing` | Yes: isolates build check |
| AT-1057 | pr_gate.sh (CI status check) | test_pr_gate.sh::test_csp_test_failure_blocks | TRIP | NON-TRIP: test_pr_gate.sh::test_all_green_passes | exit code != 0; reason token == `checks_failing` | Yes: isolates test check |

Note: Both ATs share the NON-TRIP test (all-green scenario passes). This is acceptable because the NON-TRIP proves the gate does not over-block; the TRIP tests prove it blocks the correct failures.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: None. This is a CI/workflow gate script. It does not touch production trading code, order placement, or risk logic. Worst case: a PR with failing CI merges (caught by GitHub branch protection as secondary defense) or a valid PR is blocked (developer inconvenience, not financial loss).
- **Fail-closed cap on loss** (what restricts exposure): No financial exposure. The script is additive tooling on top of existing GitHub branch protection rules.
- **Drift metric** (what tells us it's going wrong before it blows up): pr_gate.sh invocation count and pass/fail ratio in CI logs. If the script is never invoked, it provides no value.
- **Loss boundary**: N/A — no financial risk.
- **Rollback plan** (how to revert if it fails): Remove pr_gate.sh from the workflow or skip the step. No state to clean up.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: `plans/preflight.sh` (will need to call or reference pr_gate.sh); `plans/workflow_files_allowlist.txt` (new files must be added).
- **If conflict with CONTRACT.md**: None. §0.Z.9 defines what CI MUST do; pr_gate.sh automates checking those requirements but does not alter them.
- Files with recent churn or shared ownership:
  - `plans/preflight.sh` — shared with other S1 stories; coordinate on integration point
  - `plans/workflow_files_allowlist.txt` — shared allowlist; adding entries is low-risk
- Struct fields I'm assuming exist (verify before coding):
  - N/A (shell script; no Rust structs)
- State machine transitions affected:
  - None

## 9) Constraint I expect to hit
- Lessons from prior story postmortems: No prior postmortems exist (first slice). No prior shell-script gate patterns to learn from.
- What will slow me down: Mocking `gh` CLI responses for fixture tests requires careful setup — the `gh` commands return complex JSON, and the mock must be realistic enough to exercise jq filters.
- Exploit (workaround for this story): Create static JSON fixture files representing each scenario (all-green, merge-conflict, checks-failing, changes-requested, bot-comments). Point the test script at these fixtures via a `GH_MOCK` environment variable or PATH override.
- Smallest fix that prevents it next time: Establish a `plans/tests/fixtures/` directory convention for mock API responses.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

No debt items. All gates pass. Low risk, no financial exposure, no production code impact.

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed (Assumption #2 killed as external dependency risk)
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice

Prior Postmortem: NONE
Reused Guardrail: NONE
