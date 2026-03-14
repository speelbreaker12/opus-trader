# SKILL: /post-impl-audit (Post-Implementation Breaker Audit)

## Purpose
Invalidate paper compliance and catch what the implementer missed. Audit-only — no production code changes.
Run after `/slice-execute`, before review cycles and merge.

## When to use
- After implementing a PRD story (between slice-execute and codex reviews)
- As a focused single-pass alternative to running `/pr-review` + `/failure-mode-review` + `/devils-advocate` separately
- When you want the AT status table with PROVEN/CLAIMED-NOT-PROVEN classification

## Inputs (must open)
- `reviews/premortems/<STORY-ID>_premortem.md` — the binding pre-implementation plan
- `specs/CONTRACT.md`
- `plans/prd.json` — the target story
- `git diff` for this story (use `--base` against integration branch, not `--commit HEAD`)
- All touched files under `scope.touch`

## Hard Gate (audit must fail-closed)

If any claimed AT lacks causal proof → downgrade STOPLIGHT and list as blocker. No exceptions.

## Task

### 1) Premortem compliance (did they follow the plan?)

Read STOPLIGHT in the premortem (§10). Verify:
- Every item that was MISSING in the premortem is either fixed in the patch or explicitly DEFERRED with owner + rationale
- Implementer did not expand scope beyond `scope.touch` without justification
- All hard gates (§1, §4, §5, §6, §8) were respected

Output: `Premortem adherence: PASS/FAIL` with reasons.

### 2) PRD truth check (no paper compliance)

For each PRD item in the story:
- `passes=true` implies: enforcement exists in code, tests exist and pass, evidence paths exist
- Claimed AT-IDs exist in CONTRACT.md (not phantom)
- Flag any of:
  - **MISOWNED** — wrong story claims the AT
  - **CLAIMED-NOT-PROVEN** — test exists but doesn't prove causality
  - **INVALID-REF** — AT not in contract
  - **PASS-WITHOUT-PROOF** — `passes=true` with no proving test

### 3) AT-by-AT causal proof audit (the core)

For every AT claimed by this story:
1. Extract AT pass criteria from CONTRACT.md
2. Locate enforcement point in code
3. Verify tests assert the criteria causally

Classify each AT:
- **PROVEN** — test asserts pass criteria directly (dispatch_count, reject_reason, latch_reason)
- **PROVEN-BY-CROSS-TEST** — criteria split across tests (acceptable only if documented)
- **CLAIMED-NOT-PROVEN** — string match or test exists but no causal assertion
- **DEFERRED** — explicitly deferred with owner + rationale
- **INVALID-REF** — AT not in contract

**TRIP/NON-TRIP rule** (mandatory for safety ATs):
If the AT can block OPEN / change mode / latch permission:
- TRIP test exists?
- NON-TRIP test exists?
If missing → mark CLAIMED-NOT-PROVEN at minimum.

**Isolation check**: Does removing the enforcement point fail exactly this AT? If not, flag as BROAD (multiple clauses) or REDUNDANT (another AT covers it).

### 4) Fail-closed check

Search for any path where required inputs are missing/invalid/NaN/Inf and the system:
- Warns and continues
- Defaults silently
- Allows OPEN risk

Any fail-open behavior is a **blocker** unless CONTRACT.md explicitly permits it.

### 5) Wrong-implementation test quality audit

For each new/modified test, answer: "What wrong implementation would still pass this test?"

If a plausible wrong design would pass, mark the test **TOO-COARSE** and recommend:
- Add boundary row (golden vector)
- Add property test
- Split test into isolated assertions

### 5b) Mechanical verification

Run `./plans/verify_mechanical.sh` and paste output. Any FAIL = downgrade STOPLIGHT.

### 6) Regression + scope check

- Changes are localized to `scope.touch`
- No unrelated behavior changes
- No risky refactors not required by the story

## Required Output

### A) STOPLIGHT
**STOPLIGHT: GREEN / YELLOW / RED** — 3-6 bullet rationale.

### B) Blockers (if any)
Each blocker with: AT/Clause, why it's failing, exact file:line references.

### C) AT Status Table

| AT-ID | PRD owner | Status | Enforcement point | Proof test(s) | TRIP? | NON-TRIP? | Isolated? | Notes |
|-------|-----------|--------|-------------------|---------------|-------|-----------|-----------|-------|

### D) Paper Compliance Findings
- `passes=true` without proof
- Misowned ATs
- Invalid refs
- Missing evidence

### E) Test Quality Findings
Tests marked TOO-COARSE with the "wrong implementation that would pass" explanation and recommended tightening.

### F) Next Actions (smallest-first)
- If RED: actions required to reach YELLOW/GREEN
- If YELLOW: debt register with owner slice + target + rationale
- If GREEN: optional hardening only

## Constraints
- **No production code edits.** This is audit-only.
- **No guessing.** If you can't find proof, it's not proven.
- Prefer small, surgical recommendations.
- Use `--base` against integration branch for diffs, not `--commit HEAD`.

## Integration with story loop

This skill fits between steps 2 (slice-execute) and 3 (self-review) of the story loop:
1. Fill premortem → `/slice-execute` → **`/post-impl-audit`** → `/pr-review` + `/failure-mode-review` → verify.sh → codex reviews → merge

It can also replace the combination of `/pr-review` + `/failure-mode-review` + `/devils-advocate` as a single focused pass when the priority is contract compliance over general code quality.
