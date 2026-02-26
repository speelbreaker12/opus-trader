# Recon Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 8 verbose recon step prompts with 8 slim cards and add a PATH signal to eliminate fragile text detection in wf_step.sh.

**Architecture:** Slim cards live in `plans/step_prompts/recon/` (same filenames, replaced in place). wf_step.sh gets a new `read_cycle1_path()` function that reads `PATH: GREEN` / `PATH: YELLOW` from a canonical evidence ledger path, with backward-compatible fallback to the existing `cycle1_had_zero_findings()`. An INDEX.md carries the debrief policy once.

**Tech Stack:** Bash (wf_step.sh), Markdown (prompt cards)

**Design doc:** `docs/plans/2026-02-26-recon-simplification-design.md`

---

## Task 1: Create INDEX.md (debrief policy + card index)

**Files:**
- Create: `plans/step_prompts/recon/INDEX.md`

**Step 1: Write the file**

```markdown
# Recon Step Prompts — Index

> Read this file first. It defines policies that apply to every step.

## Debrief Policy

**GREEN path** (step completed, 0 BLOCKING findings, no code changes):
Write one line: `Step complete.`

**YELLOW or RED path** (findings found, fixes applied, or step blocked):
Write full §0–§11 ToC debrief using `plans/postmortem_template.md`.

## Card Index

| Step | File | Role |
|------|------|------|
| 0 preflight | preflight.md | Read PRD + CONTRACT + premortem → AT proof table + STOPLIGHT |
| 1 implement | implement.md | Diagnose code → classify gaps → write patch plan |
| 2 self_review | self_review.md | 6-skill stack → FIX_PLAN → apply fixes |
| 3 cycle1 | cycle1.md | External STORY_SCOPE review → evidence_ledger.md + PATH signal |
| 4 fix | fix.md | Apply BLOCKING findings from C1 |
| 5 cycle2 | cycle2.md | External FIX_DIFF review (1 or 2 dispatches based on PATH) |
| 6 resolution | resolution.md | Write review_resolution.md + postmortem if YELLOW/RED |
| 7 verify_full | verify_full.md | Run ./plans/verify.sh full |

## Receipt Command

Every step ends with:
```
plans/wf_step.sh <STORY_ID> <step_name>
```
If the step failed its gate, the script will tell you what is missing.

## Reference

For unusual situations, escalation policy, debt register rules, and verdict enum:
`reviews/premortems/RUNBOOK_PREMORTEM_RECON.md`
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/INDEX.md
```
Expected: ≤ 50 lines.

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/INDEX.md
git commit -m "recon(simplify): add INDEX.md with debrief policy and card index"
```

---

## Task 2: Replace preflight.md

**Files:**
- Modify: `plans/step_prompts/recon/preflight.md`

**Step 1: Replace the entire file**

```markdown
# Step 0: preflight

## CONTEXT
- `plans/prd.json` → story entry: `scope.touch` file list + AT references
- `specs/CONTRACT.md` → sections referenced by scope.touch files
- `artifacts/story/<ID>/premortem.md`

## ACTION
- Read each scope.touch file
- Build AT proof table: AT-ID | test file:line | verdict (PASS / FAIL / PARTIAL)
  - PASS: test exists, covers the AT, and would catch a wrong implementation
  - PARTIAL: test exists but coverage is incomplete or causal proof is weak
  - FAIL: test missing, wrong, or does not prove the AT claim
- Assign STOPLIGHT on line 1 of audit.md:
  - GREEN: all verdicts PASS
  - YELLOW: any PARTIAL, no FAIL
  - RED: any FAIL
- No code edits in this step

## OUTPUT
`artifacts/story/<ID>/preflight/audit.md`
→ Line 1: `STOPLIGHT: GREEN` (or YELLOW or RED)
→ Then: AT proof table

## RECEIPT
```
plans/wf_step.sh <ID> preflight
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/preflight.md
```
Expected: ≤ 50 lines.

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/preflight.md
git commit -m "recon(simplify): slim card — preflight"
```

---

## Task 3: Replace implement.md

**Files:**
- Modify: `plans/step_prompts/recon/implement.md`

**Step 1: Replace the entire file**

```markdown
# Step 1: implement

## CONTEXT
- `artifacts/story/<ID>/preflight/audit.md` (STOPLIGHT + AT proof table)
- scope.touch code files listed in `plans/prd.json`

## ACTION
- For each AT with FAIL or PARTIAL verdict in the proof table:
  - Read the relevant code and test
  - Trace the fail-closed path from intent to enforcement
  - Identify the gap
- Classify each gap:
  - CODE_FIX: implementation is wrong or missing
  - TEST_FIX: test doesn't prove causality (wrong impl would still pass)
  - PRD_FIX: PRD claim is incorrect
  - DEFERRED: valid gap but out of scope for this recon cycle
- Write one patch_plan entry per gap
- No code edits in this step

## OUTPUT
`artifacts/story/<ID>/implement/patch_plan.md`
→ One entry per gap: classification | AT-ID | what is wrong | proposed fix

## RECEIPT
```
plans/wf_step.sh <ID> implement
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/implement.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/implement.md
git commit -m "recon(simplify): slim card — implement"
```

---

## Task 4: Replace self_review.md

**Files:**
- Modify: `plans/step_prompts/recon/self_review.md`

**Step 1: Replace the entire file**

```markdown
# Step 2: self_review

## CONTEXT
- `artifacts/story/<ID>/implement/patch_plan.md`
- scope.touch code files listed in `plans/prd.json`

## ACTION (4 sub-phases, multi-agent)

**R5b.1 — 6 agents in parallel, each runs one skill:**
- Agent A: `/pr-review` → `FINDINGS_pr_review.md`
- Agent B: `/failure-mode-review` → `FINDINGS_failure_mode.md`
- Agent C: `/strategic-failure-review` → `FINDINGS_strategic.md`
- Agent D: `/contract-review` → `FINDINGS_contract.md`
- Agent E: `/validator-audit` → `FINDINGS_validator.md`
- Agent F: `/devils-advocate` → `FINDINGS_devils_advocate.md`

**R5b.2 — planner agent (read-only):**
- Read all 6 FINDINGS files
- Write `FIX_PLAN.md`: CODE_FIX and TEST_FIX items only (no PRD_FIX or DEFERRED)
- If no items: write `FIX_PLAN.md` with single line `PLAN: EMPTY`

**R5b.3 — fixer agent:**
- If `FIX_PLAN.md` says `PLAN: EMPTY` → skip this phase
- Else: execute every item in FIX_PLAN.md

**R5b.4 — re-runner:**
- If R5b.3 was skipped → skip this phase
- Else: re-run skills whose FINDINGS were affected by the fixes; confirm PASS

## OUTPUT
`artifacts/story/<ID>/self_review/`
→ `FINDINGS_<skill>.md` (6 files)
→ `FIX_PLAN.md`

## RECEIPT
```
plans/wf_step.sh <ID> self_review
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/self_review.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/self_review.md
git commit -m "recon(simplify): slim card — self_review"
```

---

## Task 5: Replace cycle1.md

**Files:**
- Modify: `plans/step_prompts/recon/cycle1.md`

**Step 1: Replace the entire file**

```markdown
# Step 3: cycle1

## CONTEXT
- scope.touch files listed in `plans/prd.json` story entry
- `artifacts/story/<ID>/premortem.md`

## ACTION
- Dispatch external review:
  ```
  plans/review_logged.sh --base <integration_branch> --tool <tool>
  ```
- Review basis: **STORY_SCOPE** (review the story's implementation, not git diff)
- Write `evidence_ledger.md`; **first line must be exactly one of:**
  - `PATH: GREEN` — 0 BLOCKING findings (P0 or P1)
  - `PATH: YELLOW` — any BLOCKING findings exist
- List all findings after the PATH line: severity | AT-ID | what is wrong

## OUTPUT
- `artifacts/story/<ID>/<tool>/` → review artifact from review_logged.sh
- `artifacts/story/<ID>/cycle1/evidence_ledger.md` → PATH signal + findings

## RECEIPT
```
plans/wf_step.sh <ID> cycle1
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/cycle1.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/cycle1.md
git commit -m "recon(simplify): slim card — cycle1"
```

---

## Task 6: Replace fix.md

**Files:**
- Modify: `plans/step_prompts/recon/fix.md`

**Step 1: Replace the entire file**

```markdown
# Step 4: fix

## CONTEXT
- `artifacts/story/<ID>/cycle1/evidence_ledger.md` (PATH signal + BLOCKING findings)

## ACTION
- Read line 1 of `evidence_ledger.md`
- **If `PATH: GREEN`:**
  - No code changes needed
  - Write `fix_summary.md`: first line `PATH: GREEN`, second line `code_changed: NO`
  - Done
- **If `PATH: YELLOW`:**
  - Apply every BLOCKING (P0/P1) finding listed in `evidence_ledger.md`
  - Run `./plans/verify.sh quick`; confirm it passes
  - Write `fix_summary.md`:
    - Line 1: `PATH: YELLOW`
    - Line 2: `code_changed: YES` or `code_changed: NO`
    - Then: one paragraph describing what was fixed

## OUTPUT
- Code changes (if any)
- `artifacts/story/<ID>/fix/fix_summary.md`

## RECEIPT
```
plans/wf_step.sh <ID> fix
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/fix.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/fix.md
git commit -m "recon(simplify): slim card — fix"
```

---

## Task 7: Replace cycle2.md

**Files:**
- Modify: `plans/step_prompts/recon/cycle2.md`

**Step 1: Replace the entire file**

```markdown
# Step 5: cycle2

## CONTEXT
- `artifacts/story/<ID>/fix/fix_summary.md` (lines 1-2: PATH + code_changed)
- Fix diff (`git diff <cycle1_head>..HEAD`)

## ACTION
- Read lines 1-2 of `fix_summary.md` to determine review scope:
  - `PATH: GREEN` **and** `code_changed: NO` → **1 review** (lightweight confirmation)
  - `PATH: YELLOW` **or** `code_changed: YES` → **2 reviews** (full adversarial)
- Dispatch review(s) via `plans/review_logged.sh --base <integration_branch> --tool <tool>`
- Review basis: **FIX_DIFF** (review the fix changes, not full story scope)
- Prefix all artifact filenames with `c2_` to distinguish from C1 artifacts

## OUTPUT
`artifacts/story/<ID>/<tool>/c2_*.md` → cycle2 review artifact(s)

## RECEIPT
```
plans/wf_step.sh <ID> cycle2
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/cycle2.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/cycle2.md
git commit -m "recon(simplify): slim card — cycle2"
```

---

## Task 8: Replace resolution.md

**Files:**
- Modify: `plans/step_prompts/recon/resolution.md`

**Step 1: Replace the entire file**

```markdown
# Step 6: resolution

## CONTEXT
- `artifacts/story/<ID>/cycle1/evidence_ledger.md`
- `artifacts/story/<ID>/<tool>/c2_*.md` (all cycle2 artifacts)
- `artifacts/story/<ID>/fix/fix_summary.md` (PATH signal)

## ACTION
- Write `review_resolution.md`; must contain these exact lines:
  ```
  Blocking addressed: YES
  Remaining findings: BLOCKING=0
  ```
- If PATH was YELLOW or RED at any point:
  - Write `postmortem.md` using `plans/postmortem_template.md`
  - Validate: `plans/postmortem_gate.sh <ID>`
- If PATH was GREEN throughout: no postmortem required

## OUTPUT
- `artifacts/story/<ID>/review_resolution.md`
- `artifacts/story/<ID>/postmortem.md` (YELLOW/RED only)

## RECEIPT
```
plans/wf_step.sh <ID> resolution
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/resolution.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/resolution.md
git commit -m "recon(simplify): slim card — resolution"
```

---

## Task 9: Replace verify_full.md

**Files:**
- Modify: `plans/step_prompts/recon/verify_full.md`

**Step 1: Replace the entire file**

```markdown
# Step 7: verify_full

## CONTEXT
- Current HEAD (no files to pre-read)

## ACTION
- Run: `./plans/verify.sh full`
- Confirm the output contains: `mode=full`
- Confirm no `FAILED_GATE` file exists in `artifacts/verify/<timestamp>/`
- If verify fails: read the failure output, fix the issue, re-run

## OUTPUT
`artifacts/verify/<timestamp>/` → verify artifact (created by verify.sh)

## RECEIPT
```
plans/wf_step.sh <ID> verify_full
```
```

**Step 2: Verify line count ≤ 50**

```bash
wc -l plans/step_prompts/recon/verify_full.md
```

**Step 3: Commit**

```bash
git add plans/step_prompts/recon/verify_full.md
git commit -m "recon(simplify): slim card — verify_full"
```

---

## Task 10: Add `read_cycle1_path()` to wf_step.sh

This is the only code change. Replace fragile text detection with an explicit PATH signal read.

**Files:**
- Modify: `plans/wf_step.sh`

**Step 1: Read the current `cycle1_had_zero_findings` function (line 346)**

Confirm it starts at line 346 and ends at line 383. Note the two callsites:
- Line 580: `if cycle1_had_zero_findings "$story_art"; then`
- Line 629: `if cycle1_had_zero_findings "$story_art" && [[ "$fix_code_changed" != "true" ]]; then`

**Step 2: Add `read_cycle1_path()` immediately after `cycle1_had_zero_findings()` (after line 383)**

Insert this function between line 383 and line 384:

```bash
read_cycle1_path() {
  # Reads the explicit PATH: GREEN / PATH: YELLOW signal written by the cycle1 agent.
  # Returns 0 (green/zero-findings) if PATH: GREEN, 1 otherwise.
  # Falls back to cycle1_had_zero_findings() for pre-existing artifacts without the signal.
  local art_dir="$1"
  local ledger="$art_dir/cycle1/evidence_ledger.md"
  if [[ -f "$ledger" ]]; then
    local first_line
    first_line="$(head -1 "$ledger" 2>/dev/null || true)"
    case "$first_line" in
      "PATH: GREEN")
        return 0
        ;;
      "PATH: YELLOW")
        return 1
        ;;
      *)
        # Unrecognized or missing signal — fail-closed
        echo "WF_STEP: unrecognized PATH signal in $ledger: '$first_line'" >&2
        return 1
        ;;
    esac
  fi
  # No canonical evidence ledger — fall back to legacy text detection for backward compat
  echo "WF_STEP: no cycle1/evidence_ledger.md found; falling back to legacy findings detection" >&2
  cycle1_had_zero_findings "$art_dir"
}
```

**Step 3: Replace the two callsites**

Replace line 580:
```bash
# Old
if cycle1_had_zero_findings "$story_art"; then

# New
if read_cycle1_path "$story_art"; then
```

Replace line 629:
```bash
# Old
if cycle1_had_zero_findings "$story_art" && [[ "$fix_code_changed" != "true" ]]; then

# New
if read_cycle1_path "$story_art" && [[ "$fix_code_changed" != "true" ]]; then
```

**Step 4: Verify the change looks correct**

```bash
grep -n "read_cycle1_path\|cycle1_had_zero_findings" plans/wf_step.sh
```

Expected output:
```
346:cycle1_had_zero_findings() {
384:read_cycle1_path() {
580:    if read_cycle1_path "$story_art"; then
629:      if read_cycle1_path "$story_art" && [[ "$fix_code_changed" != "true" ]]; then
```

`cycle1_had_zero_findings` should appear exactly once (its definition) — not at any callsite.

**Step 5: Smoke-test the script still parses**

```bash
bash -n plans/wf_step.sh
```
Expected: no output (syntax valid).

**Step 6: Commit**

```bash
git add plans/wf_step.sh
git commit -m "recon(simplify): add read_cycle1_path() — replace fragile text detection with PATH signal"
```

---

## Task 11: Add reference-only header to RUNBOOK

**Files:**
- Modify: `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md`

**Step 1: Read the first 5 lines of the RUNBOOK**

Confirm the file starts with a `#` heading (e.g. `# RUNBOOK: Premortem Reconciliation Process`).

**Step 2: Add the reference-only notice immediately after the first heading**

Insert after line 1:

```markdown
> **REFERENCE ONLY.** Not required for normal execution.
> For step-by-step execution prompts, use `plans/step_prompts/recon/<step>.md`.
> For the debrief policy and card index, see `plans/step_prompts/recon/INDEX.md`.
```

**Step 3: Verify the heading + notice are the first 4 lines**

```bash
head -5 reviews/premortems/RUNBOOK_PREMORTEM_RECON.md
```

Expected:
```
# RUNBOOK: ...
>
> **REFERENCE ONLY.** ...
> For step-by-step ...
> For the debrief ...
```

**Step 4: Commit**

```bash
git add reviews/premortems/RUNBOOK_PREMORTEM_RECON.md
git commit -m "recon(simplify): mark RUNBOOK as reference-only"
```

---

## Verification

After all tasks are done, confirm:

```bash
# All 8 cards ≤ 50 lines
for f in plans/step_prompts/recon/*.md; do
  count=$(wc -l < "$f")
  echo "$count  $f"
done

# wf_step.sh syntax valid
bash -n plans/wf_step.sh

# No stray callsites of old function
grep -n "cycle1_had_zero_findings" plans/wf_step.sh
# Expected: exactly 1 line (the function definition at line 346)

# INDEX.md exists
ls plans/step_prompts/recon/INDEX.md

# RUNBOOK has reference header
head -4 reviews/premortems/RUNBOOK_PREMORTEM_RECON.md
```
