# Reconciliation Process Simplification — Design

> **Status note (2026-03-04):** This design record is historical context.
> Current reconciliation execution authority is `reviews/reconciliations/PROTOCOL.md`
> and `reviews/reconciliations/REFERENCE.md`. The active handoff format is
> `RECON_HANDOFF_TEMPLATE.md` with "Step Log" + mandatory HANDOFF updates, and it
> supersedes the older `§0–§11` debrief framing described here.

**Date**: 2026-02-26
**Status**: Approved

## Problem

The reconciliation process has the right 9 steps. The overhead around those steps has grown into
a 3,900-line documentation machine: a 1,454-line RUNBOOK, 8 separate step prompts (40–160 lines
each), fragile text-detection for escalation logic, and §0–§11 ToC debriefs required on every
step regardless of outcome. Agents spend most of their context budget navigating documentation
rather than doing the work.

The receipts in `wf_step.sh` are correct and should be kept. The enforcement layer is not the
problem — the reading burden is.

---

## Design Principles

1. **Receipt = proof of completion.** `wf_step.sh` writes the authoritative receipt. No other
   artifact is required to prove a step happened.
2. **Explicit signals, not text detection.** Escalation decisions read a single explicit line
   from a canonical artifact, not regex searches across arbitrary review content.
3. **Cards tell agents what to DO.** The RUNBOOK tells agents what things MEAN. These are
   separate concerns and separate documents.
4. **Debriefs proportional to outcome.** Clean step → one line. Blocked step → full §0–§11.

---

## What Changes

### 1. 8 slim prompt cards replace the 8 existing step prompts

Each card: ≤50 lines, 4 sections only.

```
# Step N: <name>
## CONTEXT   — files to read before starting
## ACTION    — what to do (≤5 bullets)
## OUTPUT    — artifact path + what it contains
## RECEIPT   — exact wf_step.sh command to run
```

Files: `plans/step_prompts/recon/preflight.md` through `verify_full.md` (8 files, same names,
replaced in place).

### 2. PATH signal in evidence_ledger.md (cycle1 output)

The cycle1 agent writes one explicit line as the first line of the evidence ledger:

```
PATH: GREEN
```
or
```
PATH: YELLOW
```

GREEN = 0 BLOCKING findings. YELLOW = any BLOCKING findings exist.

This single line drives all downstream escalation (fix behavior, cycle2 min_reviews). No
downstream agent or script needs to interpret free-form review text.

### 3. One change to `wf_step.sh`

Replace `cycle1_had_zero_findings()` (regex search across review artifact content) with
`read_cycle1_path()` (reads line 1 of canonical evidence ledger):

```bash
# Old — fragile text search across arbitrary artifact files
cycle1_had_zero_findings() { ... grep/awk across content ... }

# New — explicit signal from canonical path
read_cycle1_path() {
  local ledger="artifacts/story/$STORY_ID/cycle1/evidence_ledger.md"
  head -1 "$ledger" | grep -q "^PATH: GREEN"
}
```

All callers (`fix` step, `cycle2` step) replace their `cycle1_had_zero_findings` calls with
`read_cycle1_path`. Everything else in `wf_step.sh` stays identical.

### 4. Canonical evidence ledger path

Agents produce the evidence ledger to one path:

```
artifacts/story/<ID>/cycle1/evidence_ledger.md
```

`wf_step.sh` searches this path first. The existing 6-path fallback search stays as a
compatibility fallback for any pre-existing artifacts, but new work targets the canonical path.

### 5. Debrief policy (stated once, not per card)

A single "Debrief Policy" section at the top of the slim cards index:

- **GREEN path** (no findings, no fixes): one line — `Step complete.`
- **YELLOW/RED path**: full §0–§11 ToC debrief required

Not repeated in individual cards.

### 6. RUNBOOK becomes reference-only

Add to the top of `RUNBOOK_PREMORTEM_RECON.md`:

```
> REFERENCE ONLY. Not required for normal execution.
> For step-by-step execution, use plans/step_prompts/recon/<step>.md
```

No other changes to the RUNBOOK.

---

## What Does NOT Change

| Item | Status |
|------|--------|
| `wf_step.sh` receipt format | Unchanged (5-field JSON) |
| The 9 steps and their ordering | Unchanged |
| Step prerequisite enforcement | Unchanged |
| Multi-agent R5b (6+1+1+N agents) | Unchanged |
| `verify.sh`, `prd_set_pass.sh`, `review_logged.sh` | Unchanged |
| Scope locking | Unchanged |
| Postmortem requirement on YELLOW/RED | Unchanged |
| RUNBOOK content | Unchanged (header added only) |
| All existing receipts/artifacts | Unchanged (compatible) |

---

## The 8 Slim Cards (Full Content)

### Card 0: preflight

```
## CONTEXT
- plans/prd.json → story entry + scope.touch file list
- CONTRACT.md → sections matching scope.touch files
- reviews/premortems/<ID>_premortem.md

## ACTION
- Read each scope.touch file
- Build AT proof table: AT-ID | test file:line | verdict (PASS / FAIL / PARTIAL)
- Assign STOPLIGHT: GREEN (all PASS) / YELLOW (any PARTIAL) / RED (any FAIL)
- No code edits

## OUTPUT
artifacts/story/<ID>/preflight/audit.md
  → STOPLIGHT on line 1, then AT proof table

## RECEIPT
plans/wf_step.sh <ID> preflight
```

### Card 1: implement

```
## CONTEXT
- artifacts/story/<ID>/preflight/audit.md (STOPLIGHT + AT proof table)
- scope.touch code files

## ACTION
- For each AT with FAIL or PARTIAL verdict: trace the fail-closed path in code
- Classify each gap: CODE_FIX / TEST_FIX / PRD_FIX / DEFERRED
- Write patch plan with one entry per gap
- No code edits

## OUTPUT
artifacts/story/<ID>/implement/patch_plan.md
  → classified gap list with proposed fix per item

## RECEIPT
plans/wf_step.sh <ID> implement
```

### Card 2: self_review

```
## CONTEXT
- artifacts/story/<ID>/implement/patch_plan.md
- scope.touch code files

## ACTION
- R5b.1 (parallel, 6 agents): each agent runs one skill → FINDINGS_<skill>.md
  Skills: pr-review | failure-mode-review | strategic-failure-review |
          contract-review | validator-audit | devils-advocate
- R5b.2 (planner agent): reads 6 FINDINGS files → writes FIX_PLAN.md
  (CODE_FIX and TEST_FIX items only; no PRD_FIX or DEFERRED)
- R5b.3 (fixer agent): executes FIX_PLAN.md; if plan is empty → skip
- R5b.4 (re-runner): if fixes were made → re-run affected skills; else → skip

## OUTPUT
artifacts/story/<ID>/self_review/
  FINDINGS_<skill>.md (6 files) + FIX_PLAN.md

## RECEIPT
plans/wf_step.sh <ID> self_review
```

### Card 3: cycle1

```
## CONTEXT
- scope.touch files (from prd.json story entry)
- reviews/premortems/<ID>_premortem.md

## ACTION
- Dispatch: plans/review_logged.sh --base <branch> --tool <tool>
- Review basis: STORY_SCOPE (not git diff)
- Write evidence_ledger.md; first line must be exactly: PATH: GREEN or PATH: YELLOW
  GREEN = 0 BLOCKING findings; YELLOW = any BLOCKING findings

## OUTPUT
- artifacts/story/<ID>/<tool>/  → review artifact from review_logged.sh
- artifacts/story/<ID>/cycle1/evidence_ledger.md → PATH signal + findings list

## RECEIPT
plans/wf_step.sh <ID> cycle1
```

### Card 4: fix

```
## CONTEXT
- artifacts/story/<ID>/cycle1/evidence_ledger.md (PATH signal + BLOCKING findings)

## ACTION
- If PATH: GREEN → write fix_summary.md: "PATH: GREEN — no fixes required." Done.
- If PATH: YELLOW → apply every BLOCKING finding from evidence_ledger.md
- Run ./plans/verify.sh quick; confirm it passes
- Write fix_summary.md: first line PATH: YELLOW, second line code_changed: YES or NO

## OUTPUT
- Code changes (if any)
- artifacts/story/<ID>/fix/fix_summary.md

## RECEIPT
plans/wf_step.sh <ID> fix
```

### Card 5: cycle2

```
## CONTEXT
- artifacts/story/<ID>/fix/fix_summary.md (PATH + code_changed)
- Fix diff (git diff from fix step)

## ACTION
- Read fix_summary.md lines 1-2 to determine review scope:
  PATH: GREEN + code_changed: NO → dispatch 1 review (lightweight confirmation)
  PATH: YELLOW or code_changed: YES → dispatch 2 reviews (full adversarial)
- Dispatch via plans/review_logged.sh
- Review basis: FIX_DIFF (not STORY_SCOPE)
- Prefix artifact filenames with c2_ to distinguish from C1 artifacts

## OUTPUT
artifacts/story/<ID>/<tool>/c2_*.md → cycle2 review artifact(s)

## RECEIPT
plans/wf_step.sh <ID> cycle2
```

### Card 6: resolution

```
## CONTEXT
- All review artifacts: C1 (evidence_ledger.md) + C2 (c2_*.md files)

## ACTION
- Write review_resolution.md; must contain these exact lines:
    Blocking addressed: YES
    Remaining findings: BLOCKING=0
- If YELLOW or RED path: write postmortem using plans/postmortem_template.md
  and validate with plans/postmortem_gate.sh <ID>
- If GREEN path: no postmortem required

## OUTPUT
- artifacts/story/<ID>/review_resolution.md
- artifacts/story/<ID>/postmortem.md (YELLOW/RED only)

## RECEIPT
plans/wf_step.sh <ID> resolution
```

### Card 7: verify_full

```
## CONTEXT
- Current HEAD

## ACTION
- Run: ./plans/verify.sh full
- Confirm output contains: mode=full
- Confirm no FAILED_GATE in artifacts/verify/<timestamp>/

## OUTPUT
artifacts/verify/<timestamp>/  → verify artifact

## RECEIPT
plans/wf_step.sh <ID> verify_full
```

---

## Debrief Policy

Stated once at the top of the cards index (not in individual cards):

> **GREEN path** (step completed, 0 BLOCKING findings, no code changes): write one line —
> `Step complete.`
>
> **YELLOW or RED path** (findings found, fixes applied, or blocked): write full §0–§11 ToC
> debrief using the Theory of Constraints template.

---

## Handoff Template — Per-Agent ToC Retrospective

The slice reconciliation spans multiple agent sessions (context limits prevent a single agent from completing a full slice). Each outgoing agent appends a HANDOFF block to the slice handoff doc. The ToC retrospective goes at the end of each agent's HANDOFF block — filled before handing off, read by the next agent as context.

The 3-section format:

```markdown
### §1 Constraint (ONE)
- How it manifested (2–3 concrete symptoms):
- Time/token drain it caused:
- Workaround I used (exploit):
- Next-agent default behavior (subordinate):
- Permanent fix proposal (elevate):
- Smallest increment:
- Validation (metric, fewer reruns, faster command, fewer flakes):

### §2 Follow-up
- Best follow-up:
- Upgrades worth considering: 1. … 2. …

### §3 Enforceable rules
1.
2.
```

Over time the constraint chain across sessions shows exactly where time is bleeding in the process. Stories with repeated `§1` entries pointing to the same gate are candidates for simplification.

The handoff template's Source-of-Truth table is also updated to point to `INDEX.md` as the primary execution reference (not the RUNBOOK).

---

## Implementation Scope

| File | Change |
|------|--------|
| `plans/step_prompts/recon/preflight.md` | Replace with slim card |
| `plans/step_prompts/recon/implement.md` | Replace with slim card |
| `plans/step_prompts/recon/self_review.md` | Replace with slim card |
| `plans/step_prompts/recon/cycle1.md` | Replace with slim card |
| `plans/step_prompts/recon/fix.md` | Replace with slim card |
| `plans/step_prompts/recon/cycle2.md` | Replace with slim card |
| `plans/step_prompts/recon/resolution.md` | Replace with slim card |
| `plans/step_prompts/recon/verify_full.md` | Replace with slim card |
| `plans/wf_step.sh` | Replace `cycle1_had_zero_findings()` with `read_cycle1_path()` |
| `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | Add reference-only header |
| `plans/step_prompts/recon/INDEX.md` (new) | Debrief policy + card index |
| `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` | Add §1/§2/§3 ToC to HANDOFF block; update source-of-truth table |

Total files touched: 12. New files: 1.
