# PRD Story Workflow — Complete Reference

> Single document covering the full lifecycle of a PRD story from premortem through postmortem.
> For a reviewer: read this end-to-end to understand how stories are implemented and verified.

---

## Overview

Every PRD story follows 9 steps, enforced by 8 progressive receipts and 1 final pass gate. No shortcuts.

**Receipt tracking (`plans/wf_step.sh`)**: Steps 1-8 each validate prerequisites and write a JSON receipt to `.wf/receipts/<STORY_ID>/`. Step 9 is validation-only (no receipt). An agent can't skip to Step 7 and backfill — each step refuses to start without its prerequisites.

**Enforcement**:
1. **Receipt tracking** (`wf_step.sh`): Ordering + step-specific input validation
2. **Final chokepoint** (`prd_set_pass.sh`): Receipts + verify artifacts + review evidence + contract review + proof graph

**Step numbering**: Human-readable steps are 1-indexed (Step 1 to 9). Receipt filenames are 0-indexed (`00_preflight.json` to `07_verify_full.json`). The `step_index` field in receipt JSON matches the 0-based filename prefix.

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
  3.1: Fix issues and rerun reviews (convention — no separate receipt)
  ↓ receipt: 02_self_review.json (artifacts in self_review/)

Step 4: CYCLE 1 REVIEW
  External review via review_logged.sh --tool codex --base <branch>
  ↓ receipt: 03_cycle1.json (at least 1 review artifact in codex/ or opus/)

Step 5: FIX
  Address P0/P1/P2 findings + verify.sh quick
  ↓ receipt: 04_fix.json (non-artifact code changed, or 0 findings detected)

Step 6: CYCLE 2 REVIEW
  Adversarial review on fixed code (sequential, not parallel)
  6.1: Code review expert + thinking expert audit (convention — no separate receipt)
  ↓ receipt: 05_cycle2.json (at least 2 review artifacts total)

Step 7: RESOLUTION
  review_resolution.md with finding disposition table
  7.1: Postmortem — TOC constraint analysis (plans/postmortem_template.md)
  ↓ receipt: 06_resolution.json (BLOCKING=0, all findings dispositioned)

Step 8: VERIFY FULL
  verify.sh full (generates verify.meta.json automatically)
  ↓ receipt: 07_verify_full.json (mode=full + HEAD match in verify.meta.json)

Step 9: PASS (no receipt — final gate only)
  prd_set_pass.sh flips passes=true
  ↓ validates: all 8 receipts + verify artifacts + review for HEAD
    + contract review PASS + fail-closed coverage + loss_mode fields
    + proof_graph.json validation (--strict) or exempt-list bypass
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

**Note on BASE_HEAD**: The preflight receipt's `head_sha` field serves as `BASE_HEAD` — the baseline for all subsequent diffs. The code reads it via `get_base_head()` which extracts `head_sha` from `00_preflight.json`. No separate `base_head` field is needed because only the preflight step records the baseline; all other steps record their own HEAD at completion time.

### Ordering enforcement

Each step validates:
1. All previous receipts exist (progressive chokepoint)
2. Step-specific inputs are ready (artifact existence, code changes, etc.)

If any check fails, the step is **blocked immediately** — not deferred to pass-flip time.

### Commands

```bash
# Execute a step (validates prerequisites, writes receipt)
plans/wf_step.sh <STORY_ID> <step>

# Check chain status
plans/wf_step.sh <STORY_ID> --status

# Reset chain (deletes receipts only — does NOT touch artifacts or prd.json)
plans/wf_step.sh <STORY_ID> --reset --yes

# Dry run (validate without writing)
plans/wf_step.sh <STORY_ID> <step> --dry-run
```

**Failure recovery**: If a step fails mid-execution, fix the issue and re-run the same step. `--reset --yes` deletes all receipt files in `.wf/receipts/<STORY_ID>/` — it does NOT delete review artifacts, verify artifacts, or modify `prd.json`. After reset, you must re-run all steps from preflight.

---

## Glossary

| Term | Definition |
|------|-----------|
| **TRIP test** | Test where the safety gate fires (rejects/blocks). Proves the gate catches the bad case. |
| **NON-TRIP test** | Test where the safety gate allows passage. Proves the gate doesn't over-block. |
| **Fail-closed** | Default to the safe/restrictive state when uncertain. Unknown TradingMode → ReduceOnly. Missing config → reject. NaN/Inf → reject. |
| **STOPLIGHT** | Premortem readiness signal. GREEN = ready to implement. YELLOW = proceed with debt register. RED = stop, resolve blockers first. |
| **Golden vectors** | Table-driven tests with 10-30 input rows. Each row catches a specific wrong implementation. |
| **BASE_HEAD** | The HEAD SHA recorded during preflight. All diffs use `BASE_HEAD..HEAD` to show the full story change. |
| **Skills** (`/pr-review`, `/failure-mode-review`, etc.) | Claude Code skill commands defined in the `SKILLS/` directory. Invoked by typing the slash command in a Claude Code session. |

### Severity mapping

Review skills output P0-P3 severity. The resolution template uses BLOCKING/MAJOR/MEDIUM. The mapping:

| Review severity | Resolution severity | Rule |
|----------------|-------------------|------|
| **P0** (Critical) | **BLOCKING** | Must fix before Step 5 (Fix). Blocks merge. |
| **P1** (High) | **MAJOR** | Must fix before Step 7 (Resolution). |
| **P2** (Medium) | **MEDIUM** | Must fix or defer to Debt Register with justification. |
| **P3** (Low) | **MINOR** | Informational. Fix optional. |

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

Run the full 5-skill review stack on your implementation (these are Claude Code slash commands defined in `SKILLS/`):

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

**Note:** Step 3.1 is convention-based guidance, not a separate receipt-tracked step. The receipt for Step 3 validates that self-review artifacts exist; the fix-and-rerun loop is the builder's responsibility.

---

## Step 4: Cycle 1 Review

**Receipt:** `03_cycle1.json`
**Command:** `plans/wf_step.sh <STORY-ID> cycle1`
**Validates:** At least 1 review artifact in `codex/` or `opus/`

External review of current code. Use `--base` against integration branch for diffs, not `--commit HEAD`.

**Command:**
```bash
plans/review_logged.sh <STORY-ID> --tool codex --base <integration_branch>
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
- Exception: if cycle1 had 0 findings, fix step passes with empty diff (no deadlock on perfect reviews). This is **programmatically enforced** — `wf_step.sh` scans review artifacts for patterns like "0 findings", "no issues", "P0: 0.*P1: 0" using word-boundary-aware regex.
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

**Note:** Step 6.1 is convention-based guidance, not a separate receipt-tracked step. The receipt for Step 6 validates artifact count; the expert audit is the builder's responsibility.

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
| F-1 | P1/MAJOR | file.rs:42 | Description | FIXED | commit sha |
```

### Step 7.1: Write postmortem

TOC-style constraint-first postmortem while the story is fresh. The next story's premortem §9 reads the carry-forward note (section 8). Use the template at `plans/postmortem_template.md`.

**Artifact:** `artifacts/story/<STORY-ID>/postmortem.md`

**Gate:** `plans/postmortem_gate.sh <STORY-ID> [--head <sha>]`

**Sections (9 total — keep to ~1 page):**

| # | Section | Purpose |
|---|---------|---------|
| 1 | Constraint Summary | ONE bottleneck + Constraint Class + loss lens |
| 2 | TOC Five Focusing Steps | Identify → Exploit → Subordinate → Elevate → Repeat |
| 3 | Causal Chain | Trigger → Propagation → Outcome → Detection |
| 4 | Proof and Evidence | Contract/AT refs, test names, artifact paths |
| 5 | What Was Missing | Missing proofs + Wrong-Implementation Risk |
| 6 | Rule Updates | **The point** — permanent layer/change/why/owner table |
| 7 | Residual Risk | YELLOW debt only (YES/NO + containment) |
| 8 | Next-Story Startup Note | Carry-forward constraint for next premortem §9 |
| 9 | Completion Checklist | Self-check quality gate |

**Required for:** YELLOW/RED stories and any story touching gates, TradingMode, RiskState, WAL, or replay.

---

## Step 8: Verify Full

**Receipt:** `07_verify_full.json`
**Command:** `plans/wf_step.sh <STORY-ID> verify_full`
**Validates:** `verify.meta.json` exists with `mode=full` and matching HEAD

```bash
./plans/verify.sh full
```

Must produce `VERIFY OK (mode=full)`. Run after all reviews and fixes are complete.

`verify.sh` automatically generates `verify.meta.json` in `artifacts/verify/<run_id>/`:

```json
{
  "mode": "full",
  "head_sha": "abc123...",
  "timestamp_utc": "2026-02-19T17:00:00Z"
}
```

---

## Step 9: Pass (final gate)

**Command:** `plans/wf_step.sh <STORY-ID> pass` → `plans/prd_set_pass.sh <STORY-ID> true`
**No receipt written** — validation-only step that flips `passes=true` in `plans/prd.json`

### Required artifact: `contract_review.json`

Generated during or after verify.sh full, placed in the verify artifacts directory:
`artifacts/verify/<run_id>/contract_review.json`

```json
{ "decision": "PASS" }
```

`verify.sh full` now auto-seeds this artifact with a fail-closed baseline (`decision=BLOCKED`).
Before pass flip, replace or update it with human/supervisor judgment and ensure `decision=PASS`.

### Gate checks (all must pass)

| Gate | What it checks | Exit code | Meaning |
|------|---------------|-----------|---------|
| **Receipts** | All 8 receipts exist (steps 1-8) | 4 | Process incomplete — missing workflow step |
| **Verify output** | `verify.sh full` passed, HEAD match | 4 | Code quality gate failed or HEAD drifted |
| **Contract review** | `contract_review.json` with `decision=PASS` | 4 | Contract alignment not confirmed |
| **Review evidence** | At least one review artifact for current HEAD | 4 | No review covers the final code |
| **AT ownership** | `enforcing_contract_ats` non-empty | 6 | Story metadata incomplete — no AT claims |
| **Enforcement point** | `enforcement_point` populated | 6 | Story metadata incomplete — no enforcement point |
| **Fail-closed coverage** | TRIP + NON-TRIP name patterns in test files | 8 | Test naming conventions not met |
| **Loss mode** | `worst_case`, `fail_closed_cap`, `drift_metric` populated | 9 | Risk fields unpopulated in PRD |
| **Proof graph** | `proof_graph.json` validates with `--strict`, or ID in `plans/proof_graph_exempt.txt` | 10 | Proof graph missing/invalid and not legacy-exempt |

---

## Quick Reference: Commands

```bash
# Execute a step
plans/wf_step.sh <ID> <step>

# Check chain status
plans/wf_step.sh <ID> --status

# Reset chain (deletes receipts only, requires confirmation)
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

**Postmortem Chain**: Story N postmortem section 8 (Next-Story Startup Note) feeds story N+1 premortem §9. Prior constraint becomes current prevention.

---

## Reconciliation Mode

Reconciliation mode uses the **same 9-step workflow** to retroactively audit stories that already have `passes=true`. Same receipts, same gates, different prompts (reframed for audit rather than fresh implementation).

### Activation

```bash
# Preferred orchestration
/reconcil

# Preferred mechanical receipt execution
WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> <step>
```

### Guards

- **Recon only for `passes=true` stories** — preflight in recon mode verifies the story already passes in `plans/prd.json`. Stories with `passes=false` are blocked (exit 3).
- **`WF_RECON_MODE` must be `0` or `1`** — any other value is rejected (exit 2).

### Step Differences

| Step | Normal Mode | Reconciliation Mode |
|------|------------|-------------------|
| **Preflight** | Write premortem + cargo check | **Blind premortem** from PRD+CONTRACT only (no code reading) |
| **Implement** | Code must change since BASE_HEAD | **Compare premortem vs reality** (diff check bypassed) |
| **Self-Review** | 5-skill stack on new code | 5-skill stack as **retroactive audit** + LSP verification |
| **Cycle 1** | Diff-based external review | **scope.touch file review** (not diff-based) |
| **Fix** | Address findings | Same (or 0-findings pass) |
| **Cycle 2** | ≥2 review artifacts required | GREEN: ≥1 artifact / YELLOW: ≥2 artifacts |
| **Resolution** | Standard | Standard + reconciliation context |
| **Verify Full** | Standard | Standard |
| **Pass** | Flip `passes=true` | GREEN: no flip needed / YELLOW: re-run `prd_set_pass.sh` |

### GREEN vs YELLOW Escalation

After Cycle 1 review, reconciliation stories are classified:

- **GREEN** (0 findings, no code changes needed): Lighter requirements for remaining steps. Cycle 2 only needs 1 review artifact. No `prd_set_pass.sh` re-run needed. Receipt chain + resolution + postmortem = proof.

- **YELLOW/RED** (findings exist, code changes made): Automatically escalates to full normal workflow requirements. Cycle 2 needs 2 review artifacts. Must re-run `prd_set_pass.sh` at new HEAD.

The escalation is **automatic** — the supervisor detects HEAD changes since the cycle1 receipt.

### Receipt Schema

Reconciliation receipts include extra fields for audit trail:

```json
{
  "story_id": "S1-001",
  "step_name": "implement",
  "step_index": 1,
  "head_sha": "abc123...",
  "timestamp_utc": "2026-02-20T10:00:00Z",
  "recon_mode": true,
  "recon_relaxation": "implement_diff_check_skipped"
}
```

- `recon_mode`: `true` for reconciliation, `false` for normal workflow
- `recon_relaxation`: describes which check was relaxed (only present when a relaxation was applied)

### Recommended Queue Order

Reconcile in **risk-first** order, not chronological:

1. Stories affecting allow/reject/block (PolicyGuard, intent classification)
2. Stories affecting TradingMode / RiskState transitions
3. Stories affecting WAL / restart / idempotency
4. Stories affecting dispatch chokepoint / execution pipeline
5. Everything else (docs, metadata, low-risk infra)

### Step Counting

The standard workflow has 9 receipt-tracked steps (Steps 1-9). Reconciliation adds a Step 0 preamble (convention — no receipt) for reading prior postmortems and creating the worktree. Total: 10 steps (0-9), with 8 producing receipts (Steps 1-8).

### Worktree Convention

```bash
# Configurable base path (default: sibling directory)
RECON_WORKTREE_BASE="${RECON_WORKTREE_BASE:-$(dirname "$(git rev-parse --show-toplevel)")/recon_worktrees}"
mkdir -p "$RECON_WORKTREE_BASE"

# Create reconciliation worktree
git worktree add "$RECON_WORKTREE_BASE/wt_<STORY_ID>" -b recon/<STORY_ID> <integration_branch>

# After reconciliation, merge back
# Note: --ff-only will fail if integration branch advanced.
# Rebase first if needed (then re-run verify.sh full for HEAD consistency).
git checkout <integration_branch>
git merge --no-ff recon/<STORY_ID> -m "recon(<STORY_ID>): reconciliation audit"
git worktree remove "$RECON_WORKTREE_BASE/wt_<STORY_ID>"
```
