# PRD Story Workflow — Complete Reference

> Single document covering the full lifecycle of a PRD story from premortem through postmortem.
> For a reviewer: read this end-to-end to understand how stories are implemented and verified.

---

## Overview

Every PRD story follows 9 receipt-tracked steps. No shortcuts.

**Receipt tracking (`plans/wf_step.sh`)**: Each step validates that prior steps completed, checks step-specific inputs, and writes a JSON receipt to `.wf/receipts/<STORY_ID>/`. An agent can't skip to Step 7 and backfill — each step refuses to start without its prerequisites.

**Enforcement**:
1. **Receipt tracking** (`wf_step.sh`): Ordering + step-specific input validation
2. **Final chokepoint** (`prd_set_pass.sh`): Receipts + verify artifacts + review evidence + contract review

```
Step 1: PREFLIGHT
  Premortem (§0-§10) + verify.sh quick
  ↓ receipt: 00_preflight.json (records BASE_HEAD as diff baseline)

Step 2: IMPLEMENT
  /slice-execute — enforcement code + TRIP/NON-TRIP tests + golden vectors
  ↓ receipt: 01_implement.json (code must change since BASE_HEAD)

Step 3: SELF-REVIEW
  5-skill review stack: /pr-review → /failure-mode-review →
    /strategic-failure-review → /contract-review → /devils-advocate
  3.1: Fix issues and rerun reviews
  ↓ receipt: 02_self_review.json (artifacts in self_review/)

Step 4: CYCLE 1 REVIEW
  External review via review_logged.sh --tool codex --base <branch>
  ↓ receipt: 03_cycle1.json (at least 1 review artifact in codex/ or opus/)

Step 5: FIX
  Address P0/P1/P2 findings + verify.sh quick
  ↓ receipt: 04_fix.json (non-artifact code changed, or 0 findings)

Step 6: CYCLE 2 REVIEW
  Adversarial review on fixed code (sequential, not parallel)
  6.1: Code review expert + thinking expert comprehensive audit
  ↓ receipt: 05_cycle2.json (at least 2 review artifacts total)

Step 7: RESOLUTION
  review_resolution.md with finding disposition table
  7.1: Postmortem — constraint, follow-up, rules (plans/postmortem_template.md)
  ↓ receipt: 06_resolution.json (BLOCKING=0, all findings dispositioned)

Step 8: VERIFY FULL
  verify.sh full
  ↓ receipt: 07_verify_full.json (mode=full + HEAD match in verify.meta.json)

Step 9: PASS
  prd_set_pass.sh flips passes=true
  ↓ no receipt — all 8 receipts + verify artifacts + review for HEAD
    + contract review PASS + fail-closed coverage + loss_mode fields
```

---

## Receipt Tracking

### Receipt format

Each receipt is a JSON file in `.wf/receipts/<STORY_ID>/`:

```json
{
  "story_id": "S6-001",
  "step_name": "implement",
  "step_index": 1,
  "head_sha": "abc123...",
  "timestamp_utc": "2026-02-19T16:00:00Z"
}
```

### BASE_HEAD principle

The `preflight` step records HEAD as the baseline for all subsequent diffs. Every diff uses `BASE_HEAD..HEAD` (the full story change), never `HEAD~1..HEAD` (single commit). This prevents hiding risky changes behind cosmetic follow-up commits.

### Ordering enforcement

Each step validates:
1. All previous receipts exist (progressive chokepoint)
2. Step-specific inputs are ready

If any check fails, the step is **blocked immediately** — not deferred to pass-flip time.

### Commands

```bash
# Execute a step (validates prerequisites, writes receipt)
plans/wf_step.sh <STORY_ID> <step>

# Check chain status
plans/wf_step.sh <STORY_ID> --status

# Reset chain (start over — requires confirmation)
plans/wf_step.sh <STORY_ID> --reset --yes

# Dry run (validate without writing)
plans/wf_step.sh <STORY_ID> <step> --dry-run
```

---

## Step 1: Preflight (before any code)

**Receipt:** `00_preflight.json`
**Command:** `plans/wf_step.sh <STORY-ID> preflight`

This step records HEAD as BASE_HEAD and validates premortem/planning is complete.

### Premortem template (§0-§10)

#### §0 — What we're building
```
- Story: <story ref>
- Contract clause(s): §X.Y
- Acceptance tests: AT-XXX
- Touch scope: (files/crates)
- Risk rating: LOW / MED / HIGH
  HIGH if touching: persistence/replay/idempotency, order placement/funds movement,
  risk limits, auth/keys, or anything that can silently weaken gates.
```

#### §1 — Clause audit (contract → AT traceability) [HARD GATE]

For each `enforcing_contract_ats` claimed by this story, find the AT in CONTRACT.md,
extract the normative clause, and classify. Skip informational clauses.

```
| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
```

#### §2 — Assumptions (each must become a test or get killed)
```
| # | Assumption | How it breaks | Test that proves it | Validated? |
```

#### §3 — Top 5 failure modes [REQUIRED for HIGH/MED risk]
```
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
```

#### §4 — Open decisions (resolve before coding) [HARD GATE]

```
### Decision: <short title>
- What is ambiguous / missing:
- Options:
  1. Option A — Why it works; blast radius; verification
  2. Option B — Why it works; blast radius; verification
- Chosen: (A/B) — deciding factor:
- Why not others:
```

#### §5 — Wrong implementation gate [HARD GATE]

For EACH AT claimed by this story:

```
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
```

#### §6 — Proof plan (AT → enforcement → tests) [HARD GATE]

```
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
```

#### §7 — Economic risk (loss_mode) [REQUIRED for HIGH/MED risk]
```
- If this fails in prod, worst financial outcome:
- Fail-closed cap on loss:
- Drift metric:
- Rollback plan:
```

#### §8 — Conflict scan & hot zones [HARD GATE]
```
- Invariants/gates impacted:
- If conflict with CONTRACT.md: STOP
- Struct fields I'm assuming exist (verify before coding):
```

#### §9 — Constraint I expect to hit
```
- Lessons from prior story postmortems:
- What will slow me down:
- Exploit (workaround):
```

#### §10 — STOPLIGHT + Exit criteria
```
STOPLIGHT: GREEN / YELLOW / RED

Debt Register (required if YELLOW):
| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
```

---

## Step 2: Implement

**Receipt:** `01_implement.json`
**Command:** `plans/wf_step.sh <STORY-ID> implement`
**Validates:** Code changed since BASE_HEAD (full story diff, not single commit)

### Implementation steps

1. **Implement enforcement** — for each AT, follow the proof plan. Fail-closed: uncertain → ReduceOnly, unknown intent → OPEN (most restrictive), latch on bad event.

2. **Add TRIP / NON-TRIP tests** — each safety-critical AT gets both. Each proves causality via `dispatch_count`, `reject_reason`, `latch_reason`, or `cortex_override`.

3. **Fix PRD mapping** — update `implementation_tests[]`, verify `enforcing_contract_ats[]`.

4. **Golden vectors for critical gates** — table-driven test with 10-30 input cases.

5. **Resolve ambiguity with behavioral ATs** — add golden vector rows that distinguish correct from wrong.

6. **Add observability** — structured log with `tracing`, reason code on reject paths.

### Self-check
- [ ] Enforcement point exists in code?
- [ ] Proving test proves causality (dispatch count OR reason code)?
- [ ] TRIP + NON-TRIP tests exist (if safety-critical)?
- [ ] No `unwrap()` in production paths?
- [ ] Fail-closed on error paths?

---

## Step 3: Self-Review (5-skill review stack)

**Receipt:** `02_self_review.json`
**Command:** `plans/wf_step.sh <STORY-ID> self_review`
**Validates:** Self-review artifacts exist in `artifacts/story/<ID>/self_review/`

Run the full 5-skill review stack on your implementation:

1. `/pr-review` — SOLID, architecture, removal candidates, security
2. `/failure-mode-review` — interface crossings, state transitions, what-if analysis
3. `/strategic-failure-review` — hidden assumptions, complexity-to-benefit, simpler alternatives
4. `/contract-review` — fail-open hazard filter, CONTRACT.md alignment
5. `/devils-advocate` — mutation testing, simpler-than-correct gate

**Artifacts:**
- `artifacts/story/<STORY-ID>/self_review/pr_review.md`
- `artifacts/story/<STORY-ID>/self_review/failure_mode_review.md`
- `artifacts/story/<STORY-ID>/self_review/strategic_failure_review.md`
- `artifacts/story/<STORY-ID>/self_review/contract_review.md`
- `artifacts/story/<STORY-ID>/self_review/devils_advocate.md`

### Step 3.1: Fix issues and rerun reviews

Address all P0/P1/P2 findings from the 5-skill stack, then rerun reviews on the fixed code to confirm resolution. Iterate until clean.

---

## Step 4: Cycle 1 Review

**Receipt:** `03_cycle1.json`
**Command:** `plans/wf_step.sh <STORY-ID> cycle1`
**Validates:** At least 1 review artifact in `codex/` or `opus/`

External review of current code. Use `--base` against integration branch for diffs, not `--commit HEAD`.

**Commands:**
```bash
plans/review_logged.sh <STORY-ID> --tool codex --base <integration_branch>
plans/codex_review_logged.sh <STORY-ID> --base <integration_branch>
```

**Artifact:** `artifacts/story/<STORY-ID>/codex/<timestamp>_review.md`

---

## Step 5: Fix

**Receipt:** `04_fix.json`
**Command:** `plans/wf_step.sh <STORY-ID> fix`
**Validates:** Non-artifact code changed since cycle1 receipt (or cycle1 had 0 findings)

Address all actionable findings (P0/P1/P2) from cycle 1 review.

**Safeguards:**
- Must change at least one non-artifact file (excludes `artifacts/`, `.wf/`, `plans/prd.json`, `plans/progress*`)
- Exception: if cycle1 had 0 findings, fix step passes with empty diff (no deadlock on perfect reviews)
- Run `verify.sh quick` after fixes

---

## Step 6: Cycle 2 Review (adversarial)

**Receipt:** `05_cycle2.json`
**Command:** `plans/wf_step.sh <STORY-ID> cycle2`
**Validates:** At least 2 review artifacts total

Adversarial review of FIXED code — stress/edge cases. Must be sequential (not parallel with cycle 1).

**Artifact:** `artifacts/story/<STORY-ID>/codex/<timestamp>_review.md`

### Step 6.1: Code review expert + thinking expert audit

After the external adversarial review, run a comprehensive audit using the code review expert and thinking expert skills on the implementation. This catches structural and reasoning-level issues that tool-based reviews may miss.

---

## Step 7: Resolution

**Receipt:** `06_resolution.json`
**Command:** `plans/wf_step.sh <STORY-ID> resolution`
**Validates:** `review_resolution.md` exists with `Blocking addressed: YES` and `BLOCKING=0`

**Artifact:** `artifacts/story/<STORY-ID>/review_resolution.md`

Required fields:
```
Story: <ID>
HEAD: <sha>
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
```

### Finding Disposition Table

```
| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | file.rs:42 | Description | FIXED | commit sha |
```

### Step 7.1: Write postmortem

Constraint-first postmortem while the story is fresh. The next story's premortem §9 reads this. Use the template at `plans/postmortem_template.md`.

**Artifact:** `reviews/postmortems/<STORY-ID>_postmortem.md`

**Sections:**

| # | Section | Purpose |
|---|---------|---------|
| 0 | What shipped | One-line outcome + value declaration |
| 1 | Constraint | THE bottleneck: symptoms, exploit, subordinate, elevate |
| 2 | Follow-up | Best next story + 1-3 upgrades with validation |
| 3 | Rules | 1-3 enforceable rules so next agent doesn't repeat the pain |

---

## Step 8: Verify Full

**Receipt:** `07_verify_full.json`
**Command:** `plans/wf_step.sh <STORY-ID> verify_full`
**Validates:** `verify.meta.json` exists with `mode=full` and matching HEAD

```bash
./plans/verify.sh full
```

Must produce `VERIFY OK (mode=full)`. Run after all reviews and fixes are complete.

---

## Step 9: Pass (final gate)

**Command:** `plans/wf_step.sh <STORY-ID> pass` → `plans/prd_set_pass.sh <STORY-ID> true`
**No receipt written** — flips `passes=true` in `plans/prd.json`

### Gate checks (all must pass)

| Gate | What it checks | Exit code |
|------|---------------|-----------|
| **Receipts** | All 8 receipts exist | 4 |
| **Verify output** | `verify.sh full` passed, HEAD match | 4 |
| **Contract review** | `contract_review.json` with `decision=PASS` | 4 |
| **Review evidence** | At least one review artifact for current HEAD | 4 |
| **AT ownership** | `enforcing_contract_ats` non-empty | 6 |
| **Fail-closed coverage** | TRIP + NON-TRIP name patterns in test files | 8 |
| **Loss mode** | `worst_case`, `fail_closed_cap`, `drift_metric` populated | 9 |

---

## Quick Reference: Commands

```bash
# Execute a step
plans/wf_step.sh <ID> <step>

# Check chain status
plans/wf_step.sh <ID> --status

# Reset chain (requires confirmation)
plans/wf_step.sh <ID> --reset --yes

# Dry run (validate without writing)
plans/wf_step.sh <ID> <step> --dry-run

# Final pass-flip
plans/prd_set_pass.sh <ID> true
```

---

## Supporting Reference Documents

| Document | Purpose | When to read |
|----------|---------|-------------|
| `specs/CONTRACT.md` | Source of truth for behavioral invariants | Every step |
| `specs/WORKFLOW_CONTRACT.md` | Full workflow contract + receipt tracking spec | Steps 1, 9 |
| `specs/DESIGN_PATTERNS.md` | How to build (gate shape, fail-closed, naming) | Step 2 |
| `specs/QUALITY_GATES.md` | How to prove (scorecard, AT taxonomy, golden vectors) | Steps 1, 3 |
| `plans/prd.json` | PRD with story metadata, ATs, test mappings | Steps 1-9 |

## Key Concepts

**AT Taxonomy**: Every normative, testable clause needs both AT-SCOPE (proves ownership) and AT-BEHAVIOR (proves correctness).

**Clause-Level AT Isolation**: Each AT isolates one clause. Remove enforcement → exactly this AT fails.

**Golden Vectors**: 10-30 row table-driven tests. Every row justifies itself ("catches [wrong impl]").

**Wrong-Implementation Gate**: For every AT: "What wrong implementation would pass?" If one exists → tighten.

**Fail-Closed Defaults**: Unknown TradingMode → ReduceOnly. Missing config → reject. NaN/Inf → reject.

**Real Quantities, Not Proxies**: Compare actual values vs thresholds, not proxy indicators.

**Idempotency**: Anything that can be retried must be safe to run twice. Use stable IDs and replace semantics.

**No Paper Compliance**: `passes=true` requires enforcement in code, proving tests, evidence artifacts, and valid receipts. If a wrong implementation would pass the tests, the tests are insufficient.

**Postmortem Chain**: Story N postmortem feeds story N+1 premortem §9. Prior pain becomes current prevention.
