# PRD Story Workflow — Complete Reference

> Single document covering the full lifecycle of a PRD story from premortem through postmortem.
> For a reviewer: read this end-to-end to understand how stories are implemented and verified.

---

## Overview

Every PRD story follows 9 receipt-gated steps. No shortcuts.

**Receipt chain (`plans/wf_step.sh`)**: Each step validates that prior steps completed, checks step-specific inputs, and writes a hash-chained JSON receipt to `.wf/receipts/<STORY_ID>/`. An agent can't skip to Step 7 and backfill — each step refuses to start without its prerequisites AND a valid hash chain.

**3-layer enforcement**:
1. **Layer 1 — Receipt chain** (`wf_step.sh`): Ordering + structural integrity + BASE_HEAD diffs
2. **Layer 2 — Anti-fabrication gates** (`story_review_gate.sh`): Transcript quality, timing, diff cross-reference, provenance hashing
3. **Layer 3 — Final chokepoint** (`prd_set_pass.sh`): Everything from layers 1+2 plus contract review, verify artifacts, HMAC signatures

```
Step 1: PREFLIGHT (premortem + verify quick)
  ↓ receipt: 00_preflight.json (records BASE_HEAD)
Step 2: IMPLEMENT (/slice-execute)
  ↓ receipt: 01_implement.json (validates code changed since BASE_HEAD)
Step 3: SELF-REVIEW (/pr-review → /failure-mode-review → /contract-review)
  ↓ receipt: 02_self_review.json
Step 4: CYCLE 1 REVIEW (external reviewer)
  ↓ receipt: 03_cycle1.json (hashes ALL review artifacts)
Step 5: FIX (address review findings)
  ↓ receipt: 04_fix.json (requires non-artifact code changes, or 0-finding cycle1)
Step 6: CYCLE 2 REVIEW (adversarial, on fixed code)
  ↓ receipt: 05_cycle2.json (hashes ALL review artifacts)
Step 7: RESOLUTION (review_resolution.md with disposition table)
  ↓ receipt: 06_resolution.json
Step 8: VERIFY FULL (verify.sh full → artifacts)
  ↓ receipt: 07_verify_full.json (validates mode=full + HEAD match)
Step 9: PASS (prd_set_pass.sh — full chain validation)
  ↓ no receipt — flips passes=true in prd.json
```

---

## Receipt Chain Architecture

### Receipt format

Each receipt is a JSON file in `.wf/receipts/<STORY_ID>/`:

```json
{
  "story_id": "S6-001",
  "step_name": "implement",
  "step_index": 1,
  "head_sha": "abc123...",
  "timestamp_utc": "2026-02-19T16:00:00Z",
  "inputs_hash": "sha256-of-step-specific-evidence",
  "prev_receipt_hash": "sha256-of-previous-receipt-or-GENESIS",
  "receipt_hash": "sha256-of-this-receipt",
  "tainted": false,
  "signature": "hmac-sha256-if-WF_HMAC_KEY-set"
}
```

### BASE_HEAD principle

The `preflight` step records HEAD as the baseline for all subsequent diffs. Every diff uses `BASE_HEAD..HEAD` (the full story change), never `HEAD~1..HEAD` (single commit). This prevents hiding risky changes behind cosmetic follow-up commits.

### Ordering enforcement

Each step validates:
1. All previous receipts exist (progressive chokepoint)
2. The hash chain is valid (`prev_receipt_hash` matches actual hash of previous receipt)
3. Step-specific inputs are ready

If any check fails, the step is **blocked immediately** — not deferred to pass-flip time.

### HMAC signing (optional, recommended for CI)

If `WF_HMAC_KEY` is set, each receipt includes an HMAC-SHA256 signature. Only processes with the key can produce valid signatures — agents can't forge receipts.

### Safety controls

- `--force` skips prerequisites but **taints** the receipt → `pass` step hard-fails (exit 4)
- `--reset` requires `--yes` confirmation (prevents accidental chain deletion)
- `--dry-run` validates without writing
- `--verify-sigs` checks HMAC signatures on all receipts

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

## Step 3: Self-Review

**Receipt:** `02_self_review.json`
**Command:** `plans/wf_step.sh <STORY-ID> self_review`
**Validates:** Self-review artifacts exist in `artifacts/story/<ID>/self_review/`

**Skills (always):** `/pr-review` → `/failure-mode-review` → `/contract-review`
**Skills (conditional):** + `/strategic-failure-review` for multi-crate or infrastructure changes

**Artifacts:**
- `artifacts/story/<STORY-ID>/self_review/pr_review.md`
- `artifacts/story/<STORY-ID>/self_review/failure_mode_review.md`
- `artifacts/story/<STORY-ID>/self_review/contract_review.md`
- `artifacts/story/<STORY-ID>/self_review/strategic_failure_review.md` (if applicable)

Fix any P0/P1 findings before proceeding.

---

## Step 4: Cycle 1 Review

**Receipt:** `03_cycle1.json`
**Command:** `plans/wf_step.sh <STORY-ID> cycle1`
**Validates:** At least 1 review artifact in `codex/` or `opus/`; hashes ALL artifacts (sorted)

External review of current code. Use `--base` against integration branch for diffs, not `--commit HEAD`.

**Artifact:** `artifacts/story/<STORY-ID>/codex/<timestamp>_cycle1_review.md`

### Anti-fabrication checks enforced by `story_review_gate.sh`:
- `Duration Seconds` field **required** (missing = hard fail)
- Transcript minimum byte threshold (≥500 bytes default)
- File path references (≥2 required)
- Severity markers present
- Diff cross-reference: transcript must mention files from BASE_HEAD..HEAD diff
- Transcript SHA256 hash integrity

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
**Validates:** At least 2 review artifacts total; hashes ALL artifacts (sorted)

Adversarial review of FIXED code — stress/edge cases. Must be sequential (not parallel with cycle 1).

**Artifact:** `artifacts/story/<STORY-ID>/codex/<timestamp>_cycle2_review.md`

Same anti-fabrication checks as cycle 1.

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
Kimi final review file: <path>
Codex final review file: <path>
Codex second review file: <path>
Code-review-expert final review file: <path>
```

### Finding Disposition Table

```
| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | file.rs:42 | Description | FIXED | commit sha |
```

- Whitespace-tolerant regex matching (handles LLM formatting inconsistencies)
- P0 findings cannot be DEFERRED
- DEFERRED dispositions must reference a debt item with owner + target slice
- Disposition count must match cycle1 high-severity finding count

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
| **Receipt chain** | All 8 receipts exist, hash chain intact, no tainted receipts | 4 |
| **Tainted receipts** | Any `tainted=true` → hard fail | 4 |
| **HMAC signatures** | If `WF_HMAC_KEY` set, all signatures valid | 4 |
| **Verify output** | `verify.sh full` passed, HEAD match | 4 |
| **Contract review** | `contract_review.json` with `decision=PASS` | 4 |
| **Story review gate** | Self-review + Kimi + 2 Codex + code-review-expert + resolution (all matching HEAD, provenance hashed, timing enforced) | 4 |
| **Self-review artifacts** | `pr_review.md` + `failure_mode_review.md` exist | 5 |
| **Codex reviews** | 2 review cycles exist | 5 |
| **AT ownership** | `enforcing_contract_ats` non-empty | 6 |
| **Fail-closed coverage** | TRIP + NON-TRIP name patterns in test files | 8 |

### CI guard (`plans/wf_ci_guard.sh`)

Detects `passes=true` flips in `prd.json` diffs and validates receipt chains. Catches direct PRD edits that bypass `prd_set_pass.sh`.

```bash
# In CI pipeline
plans/wf_ci_guard.sh

# With HMAC verification
WF_HMAC_KEY="$SECRET" plans/wf_ci_guard.sh --require-sigs
```

---

## Postmortem (after story passes)

5-10 bullets. The next story's premortem §9 reads this.

**Artifact:** `reviews/postmortems/<STORY-ID>_postmortem.md`

```
## What surprised me
## What the premortem got wrong
## What slowed me down
## What the next story should watch for
```

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

# Force (skip prereqs, taints receipt — recovery only)
plans/wf_step.sh <ID> <step> --force

# Sign receipts with HMAC
WF_HMAC_KEY="<secret>" plans/wf_step.sh <ID> <step>

# Verify HMAC signatures
WF_HMAC_KEY="<secret>" plans/wf_step.sh <ID> --verify-sigs

# Final pass-flip
plans/prd_set_pass.sh <ID> true
```

---

## Supporting Reference Documents

| Document | Purpose | When to read |
|----------|---------|-------------|
| `specs/CONTRACT.md` | Source of truth for behavioral invariants | Every step |
| `specs/WORKFLOW_CONTRACT.md` | Full workflow contract + receipt chain spec | Steps 1, 9 |
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

**No Paper Compliance**: `passes=true` requires enforcement in code, proving tests, evidence artifacts, and a valid receipt chain. If a wrong implementation would pass the tests, the tests are insufficient.

**Postmortem Chain**: Story N postmortem feeds story N+1 premortem §9. Prior pain becomes current prevention.
