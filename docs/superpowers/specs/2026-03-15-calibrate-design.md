# `/calibrate` Skill — Design Spec

**Date:** 2026-03-15
**Status:** Draft

---

## Purpose

Run each of the 7 review-stack skills independently as parallel subagents AND `external-review-generic` (4 LLM models) simultaneously, then analyze the gap between what each found. Identifies skill blind spots, categorizes missed findings, and optionally patches the relevant skills with generalizability-gated proposals.

**Important:** This skill does NOT invoke `/review-stack` as a unit. It runs each of the 7 skills as independent subagents to maximize parallelism. The sequencing constraints defined in `review-stack.md` (e.g., Phase 3 waits on Phase 2) do not apply here — each skill runs independently because we are collecting findings, not executing a chained review pipeline.

---

## Problem Statement

External LLM reviewers consistently catch issues that the internal 7-skill review-stack misses. Without a systematic comparison, these gaps go unnoticed and recur. `/calibrate` makes the gap visible, categorizes it (skill gap vs. noise vs. structural limitation), and provides a controlled patching loop that prevents overfitting.

---

## Invocation

```
/calibrate PR190
/calibrate '#190'
/calibrate 190
/calibrate --commit HEAD
/calibrate --base origin/main
/calibrate --files "path1 path2"
/calibrate              ← working tree diff
```

Optional: `STORY_ID=<id>` for artifact routing. Defaults to a timestamp-based run ID (`calibrate-<YYYYMMDDHHMMSS>`).

---

## Architecture

### Phase 0 — Setup

1. Resolve diff target from args (same resolution logic as `external-review-generic`)
2. Set `RUN_ID` = `STORY_ID` if provided, else `calibrate-<timestamp>`
3. Create artifact directories:
   - `artifacts/calibrate/<RUN_ID>/skills/`
   - `artifacts/calibrate/<RUN_ID>/external/`
4. Record `HEAD` sha and timestamp

### Phase 1 — Parallel Execution

Main agent starts `plans/external_review_generic.sh <target>` as a **background process** (non-blocking).

Immediately, while that script is running, main agent spins **7 subagents in parallel** — one per skill — each running at **full skill depth** (reads actual source files, not just diffs). The sequencing constraint from `review-stack.md` is waived; all 7 run simultaneously:

| Subagent | Skill | Output file |
|----------|-------|-------------|
| A | `/pr-review` | `artifacts/calibrate/<RUN_ID>/skills/pr-review.md` |
| B | `/failure-mode-review` | `artifacts/calibrate/<RUN_ID>/skills/failure-mode-review.md` |
| C | `/strategic-failure-review` | `artifacts/calibrate/<RUN_ID>/skills/strategic-failure-review.md` |
| D | `/contract-review` | `artifacts/calibrate/<RUN_ID>/skills/contract-review.md` |
| E | `/validator-audit` | `artifacts/calibrate/<RUN_ID>/skills/validator-audit.md` |
| F | `/devils-advocate` | `artifacts/calibrate/<RUN_ID>/skills/devils-advocate.md` |
| G | `/loss-risk-gate` | `artifacts/calibrate/<RUN_ID>/skills/loss-risk-gate.md` |

Each subagent has a **max wall-clock time of 10 minutes**. If a subagent times out, its output file is left empty and its skill is marked `TIMEOUT` in the gap report.

Main agent waits for all 8 (7 subagents + background script) to complete before Phase 2.

**External review script failure handling:** The script writes `artifacts/story/<RUN_ID>/external_review_generic/dispatch_status.json` and `summary.md`. After it completes:
- If the script exits non-zero, read `dispatch_status.json` to identify which of the 4 reviewers (codex, opus, kimi, gemini) succeeded vs. failed
- **Proceed** if at least 2 reviewers succeeded (note which ones failed in the gap report)
- **Abort** if fewer than 2 reviewers succeeded — surface error message listing failed tools

### Phase 2 — Gap Extraction

Read findings from:
- Skill subagent outputs: `artifacts/calibrate/<RUN_ID>/skills/<skill>.md` (7 files)
- External review output: `artifacts/story/<RUN_ID>/external_review_generic/summary.md`

Partition findings into three buckets:

| Bucket | Definition |
|--------|-----------|
| `in_both` | Found by both review-stack skills AND external review |
| `stack_only` | Found by review-stack skills, missed by external review |
| `external_only` | Found by external review, missed by all 7 skills — **the gap set** |

**Finding matching rule:** Two findings are considered the same if they reference the same `file:line` range AND identify the same defect class (e.g., both flag a missing error check at the same callsite). When uncertain whether two findings match, assign conservatively to `external_only` (do not collapse a gap unless clearly identical).

### Phase 3 — Auto-Labeling

For each finding in `external_only`, Claude assigns one label:

| Label | Meaning |
|-------|---------|
| `SKILL_GAP` | Within the declared scope of one of the 7 skills — it should have caught this. Tag which skill and section is responsible. |
| `NOISE` | Opinion, style preference, debatable, or likely false positive |
| `STRUCTURAL` | Requires running code, CI output, runtime state, or external context that skills cannot access by design |

For each `SKILL_GAP`, also record: **which skill** should have caught it (e.g., "pr-review §3", "failure-mode-review §6").

Note on `stack_only` findings: These are surfaced in the gap report for informational purposes only. No action is taken on them in this loop. They represent potential false positives from the skills but are not analyzed further.

### Phase 4 — Confirmation (Human-in-the-Loop)

Claude presents all `external_only` findings in a numbered list with Claude's proposed labels. The user responds with a **single consolidated response** using this format:
- `accept all` — accept all of Claude's labels as-is
- Individual overrides: `<N>: NOISE`, `<N>: STRUCTURAL`, `<N>: dismiss` (one per line, for any findings to reclassify)

Claude waits for the user's response before proceeding to write the gap report.

### Phase 5 — Gap Report

Write `artifacts/calibrate/<RUN_ID>/gap_report.md`:

```markdown
# Calibration Gap Report — <RUN_ID>

HEAD: <sha>
Timestamp: <utc>
Diff target: <target>
External reviewers succeeded: <list>
External reviewers failed/timed out: <list or "none">

## Summary

| Source | Total findings | Unique to source |
|--------|---------------|-----------------|
| review-stack | N | N (stack_only) |
| external-review | N | N (external_only) |
| both | N | — |

## Gap Breakdown (external_only)

| # | Finding | Label | Responsible Skill |
|---|---------|-------|------------------|
| 1 | ... | SKILL_GAP | pr-review §3 |
| 2 | ... | NOISE | — |
| 3 | ... | STRUCTURAL | — |

## Skill-Confirmed Findings (in_both)
<list>

## Stack-Only Findings (informational — potential skill false positives)
<list>
```

Then prompt: **"Enter patch loop? [y/n]"**

If there are no confirmed `SKILL_GAP` findings (all `external_only` labeled NOISE or STRUCTURAL), skip phases 6–8, write an empty patch summary noting "No SKILL_GAP findings confirmed — no patches proposed," and exit.

---

## Patch Loop (opt-in)

### Phase 6 — Generalizability Rating

For each confirmed `SKILL_GAP`, Claude rates:

| Rating | Meaning | Action |
|--------|---------|--------|
| `HIGH` | Broadly applicable across codebases and PRs | Propose skill patch |
| `MEDIUM` | Probably generalizable but has project-specific flavor | Propose skill patch with caution note |
| `LOW` | Too specific to this PR or this codebase | Suggest adding to `CLAUDE.md` instead — no skill patch |

### Phase 7 — Patch Proposals

For each HIGH/MEDIUM gap, Claude drafts:
- Which skill file to edit and which section
- The exact rule/check to add (concrete wording, not vague)
- The generalizability argument (why HIGH or MEDIUM)
- For MEDIUM: prepend a caution comment to the proposed rule text: `<!-- NOTE: Validated on opus-trader (trading risk domain); verify applicability before applying to other codebases. -->`

Proposals are presented one at a time. User approves or rejects each individually.

### Phase 8 — Apply & Verify

For each approved patch:
1. Apply the edit to the skill file directly (edit the `.md` file in `SKILLS/`)
2. Re-run **only the patched skill** as a subagent on the same diff
3. Record verdict: **CAUGHT** (patch works) or **MISSED** (needs refinement)

**Verification limitation:** Re-running on the same diff nearly guarantees CAUGHT after a targeted patch. This step confirms the patch is syntactically correct and the rule fires — it does not prove generalizability. Generalizability is controlled upstream by the Phase 6 rating and user approval.

If MISSED: Claude revises the patch and re-runs. **Max 3 attempts.** If still MISSED after 3, surface to user with explanation and mark as `UNVERIFIED` in the patch summary.

For LOW-rated gaps: propose exact `CLAUDE.md` addition text. User approves or rejects.

### Phase 9 — Patch Summary

Write `artifacts/calibrate/<RUN_ID>/patch_summary.md`:

```markdown
# Patch Summary — <RUN_ID>

## Applied Patches
| Skill file | Section | Generalizability | Verified CAUGHT? |
|------------|---------|-----------------|-----------------|
| SKILLS/pr-review.md | §3 | HIGH | Yes |

## Deferred to CLAUDE.md
| Finding | Suggested addition |
|---------|-------------------|
| ...     | ...               |

## Rejected
| Finding | Reason |
|---------|--------|

## Unverified (MISSED after 3 attempts)
| Finding | Last patch attempt |
|---------|-------------------|
```

---

## Artifact Layout

```
artifacts/calibrate/<RUN_ID>/
  skills/
    pr-review.md
    failure-mode-review.md
    strategic-failure-review.md
    contract-review.md
    validator-audit.md
    devils-advocate.md
    loss-risk-gate.md
  gap_report.md
  patch_summary.md          ← only if patch loop entered
artifacts/story/<RUN_ID>/
  external_review_generic/
    dispatch_status.json    ← written by external_review_generic.sh
    summary.md              ← written by external_review_generic.sh
```

---

## Anti-Overfitting Guardrails

1. **Generalizability gate** — LOW-rated gaps never become skill rules
2. **Explicit user approval** — every patch requires human sign-off before applying
3. **MEDIUM caution note** — project-specific flavor is flagged inline in the skill rule
4. **Verify step** — each patch is re-run on the same diff; confirms rule fires (not generalizability)
5. **Max 3 attempts** — no infinite loops on a single patch
6. **User label override** — user can demote any `SKILL_GAP` to `NOISE` during Phase 4
7. **Conservative matching** — ambiguous finding pairs default to `external_only` (not collapsed)

---

## What This Skill Does NOT Do

- Does not modify `plans/prd.json` or any workflow state
- Does not run `verify.sh` or `prd_set_pass.sh`
- Is not a workflow gate — it is a calibration and improvement tool
- Does not auto-apply patches without user approval
- Does not invoke `/review-stack` as a unit — runs 7 skills as independent subagents
