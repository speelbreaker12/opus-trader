# Reconciliation Process — Complete Reference

> Retroactive audit of already-passing PRD stories using the same 9-step workflow.
> Same receipts, same gates, different prompts (reframed for audit, not fresh implementation).

---

## Why Reconciliation Exists

Phase 1 stories were implemented before the full workflow existed. Many have `passes=true` but were never audited with the current review stack, postmortem format, or gate enforcement. Reconciliation closes that gap without re-implementing anything — it audits what shipped and forces corrections where needed.

The operating principle: **if a story can't survive the same workflow it would face today, it doesn't deserve `passes=true`.**

---

## Prerequisites

Before starting reconciliation for any story:

1. The story MUST have `passes=true` in `plans/prd.json` — recon is blocked otherwise (exit 3).
2. The integration branch must be clean and up to date.
3. `plans/verify.sh quick` should pass on the integration branch.

---

## Activation

### Via supervisor (recommended)

```bash
# Print the next step's prompt
STEP_SUPERVISOR_BASE_BRANCH=feature/slice4-cherry-pick \
  plans/step_supervisor.sh <STORY_ID> prompt --recon

# Validate a completed step
STEP_SUPERVISOR_BASE_BRANCH=feature/slice4-cherry-pick \
  plans/step_supervisor.sh <STORY_ID> validate --recon

# Check status
plans/step_supervisor.sh <STORY_ID> status --recon
```

### Via loop scripts

```bash
# For-loop (walks all 8 steps, pauses for builder between each)
STEP_SUPERVISOR_BASE_BRANCH=feature/slice4-cherry-pick \
  plans/step_pod_loop.sh <STORY_ID> --recon

# While-loop (uses next/prompt/validate cycle)
STEP_SUPERVISOR_BASE_BRANCH=feature/slice4-cherry-pick \
  plans/step_loop.sh <STORY_ID> --recon
```

### Via wf_step.sh directly

```bash
WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> <step>
```

---

## Worktree Setup

Reconciliation work happens in a dedicated worktree branched from the integration branch.

```bash
# Set base path (default: sibling directory)
RECON_WORKTREE_BASE="${RECON_WORKTREE_BASE:-$(dirname "$(git rev-parse --show-toplevel)")/recon_worktrees}"
mkdir -p "$RECON_WORKTREE_BASE"

# Create reconciliation worktree
git worktree add "$RECON_WORKTREE_BASE/wt_<STORY_ID>" -b recon/<STORY_ID> <integration_branch>

# Work inside it
cd "$RECON_WORKTREE_BASE/wt_<STORY_ID>"
```

After reconciliation:

```bash
# Merge back (rebase first if integration branch advanced)
git checkout <integration_branch>
git merge --no-ff recon/<STORY_ID> -m "recon(<STORY_ID>): reconciliation audit"
git worktree remove "$RECON_WORKTREE_BASE/wt_<STORY_ID>"
```

---

## The 9-Step Workflow (Recon Mode)

Each step has a dedicated recon prompt at `plans/step_prompts/recon/<step>.md`. The supervisor prepends `plans/step_prompts/builder_preamble.md` and substitutes `${STORY_ID}`, `${BASE_BRANCH}`, `${HEAD}`, and `${PRIOR_POSTMORTEM_PATH}` into each prompt.

Receipts are written to `.wf/receipts/<STORY_ID>/` — same location as normal mode.

### Step 1: Preflight (audit scope, not fresh planning)

**Receipt:** `00_preflight.json`
**Prompt:** `plans/step_prompts/recon/preflight.md`

What the builder does:
1. Reads the PRD entry and referenced CONTRACT.md clauses/ATs.
2. Reads the prior postmortem (path injected by supervisor as `${PRIOR_POSTMORTEM_PATH}`).
3. For each AT in `enforcing_contract_ats`:
   - Locates the proving test file and function.
   - Checks if proof is CAUSAL (reject reason, dispatch_count, latch), not just existence.
   - Classifies: PROVEN / WEAK / MISSING / DEFERRED.
4. Verifies all `scope.touch` files exist.
5. Runs `cargo check --workspace`.
6. Produces an AT proof audit table and STOPLIGHT verdict.

**Gate enforcement:** `wf_step.sh` verifies:
- Story has `passes=true` in `plans/prd.json` (recon guard).
- Premortem contains `Prior Postmortem:` and `Reused Guardrail:` lines (carry-forward enforcement).

**Output ends with:** `READY FOR IMPLEMENT`

### Step 2: Implement (read-only implementation audit)

**Receipt:** `01_implement.json`
**Prompt:** `plans/step_prompts/recon/implement.md`

**Key principle:** In recon mode, Step 2 is diagnosis. Step 5 is treatment. The builder must NOT edit code here — only inspect and categorize.

**Hard gate:** Reads the recon preflight STOPLIGHT from Step 1.
- RED → STOP. Fix preflight gaps first.
- YELLOW → Proceed only if every gap is marked DEFERRED or FIX_IN_STEP_5.
- GREEN → Proceed.

What the builder does — for each AT in `enforcing_contract_ats[]`:

1. **Locate enforcement point** — file + function + branch/guard. If missing or only implied by tests/docs, mark `CLAIMED_NOT_PROVEN`.
2. **Verify fail-closed path** — missing/stale/invalid/NaN/contradictory inputs must reject/degrade/halt, not warn-and-continue. If warn-and-continue found, mark `FAIL_OPEN_RISK`.
3. **Verify causal proof** — identify proving test(s) by name. Confirm they prove causality via `dispatch_count`, `reject_reason`, `latch_reason`, or `cortex_override`. If test only proves "something happened," mark `WEAK_PROOF`.
4. **Check design-pattern conformance** — real quantity vs proxy, idempotency, local blast radius, observability on reject paths.
5. **Build remediation list (NO EDITS)** — categorize each finding:
   - `CODE_FIX` — code change needed (Step 5)
   - `TEST_FIX` — test change needed (Step 5)
   - `PRD_FIX` — PRD mapping drift (Step 5)
   - `DEFERRED` — future slice (with owner + rationale)

**Design discovery rule:** If a better design is found, do NOT silently redesign. Record as:
- `BLOCKING` — must fix now (loss/safety risk)
- `HARDENING` — defer (improves robustness but does not violate contract)

**Output:**
- AT Audit Table: `| AT | Enforcement Point | Proving Test | Causal? | Fail-Closed? | Verdict |`
- Design Risks (if any)
- Step 5 Patch Plan (ordered smallest-first): `| # | Category | File | What to change | Why |`

**Gate enforcement:** `wf_step.sh` bypasses the diff requirement in recon mode (no code change needed).

**Receipt extra:** `recon_relaxation: "implement_diff_check_skipped"`

**Output ends with:** `READY FOR SELF_REVIEW`

### Step 3: Self-Review (retroactive audit)

**Receipt:** `02_self_review.json`
**Prompt:** `plans/step_prompts/recon/self_review.md`

What the builder does:
1. Runs the internal review stack as a retroactive audit:
   - `/pr-review`
   - `/failure-mode-review`
   - `/strategic-failure-review`
   - `/contract-review`
2. Creates self-review artifact at `artifacts/story/<ID>/self_review/<timestamp>_self_review.md`.
3. Artifact MUST include exact lines:
   ```
   Story: <ID>
   HEAD: <sha>
   Decision: PASS
   - Failure-Mode Review: DONE
   - Strategic Failure Review: DONE
   ```

**Gate enforcement:** `wf_step.sh` checks self-review artifacts exist in `artifacts/story/<ID>/self_review/`.

**Output ends with:** `READY FOR CYCLE1 REVIEW`

### Step 4: Cycle 1 Review (external review)

**Receipt:** `03_cycle1.json`
**Prompt:** `plans/step_prompts/recon/cycle1.md`

What the builder does:
1. Runs logged review scripts (does NOT hand-write reviews):
   ```bash
   ./plans/review_logged.sh <ID> --tool codex --base <integration_branch>
   ```
2. Optionally also runs opus review.
3. Waits for artifacts to generate under `artifacts/story/<ID>/codex/` and `artifacts/story/<ID>/opus/`.

**Gate enforcement:** `wf_step.sh` checks at least 1 review artifact exists in `codex/` or `opus/`.

**This step determines the GREEN/YELLOW path for the rest of the workflow.**

**Output ends with:** `READY FOR FIX`

### Step 5: Fix (apply Step 2 patch plan + cycle 1 findings)

**Receipt:** `04_fix.json`
**Prompt:** `plans/step_prompts/recon/fix.md`

**Key principle:** This is the treatment step. Step 2 diagnosed, Step 5 fixes. The builder works from two sources: the Step 2 Patch Plan and the Cycle 1 review findings.

**GREEN PATH (0 findings from BOTH Step 2 audit AND Cycle 1 review):**
- No code changes needed.
- Builder confirms: "0 findings — no fixes needed."
- Fix step passes with empty diff (programmatically enforced by `wf_step.sh`).

**YELLOW/RED PATH (findings exist):**
1. Work through the Step 2 Patch Plan, ordered smallest-first:
   - `CODE_FIX`: fix enforcement, fail-closed paths, proof gaps
   - `TEST_FIX`: add/fix TRIP/NON-TRIP tests, golden vectors, causal proof
   - `PRD_FIX`: update `implementation_tests[]`, `enforcing_contract_ats[]`, `loss_mode`
2. Address all BLOCKING and MAJOR findings from Cycle 1 review.
3. For `HARDENING` items from Step 2: defer unless they address a contract violation.
4. Run `./plans/verify.sh quick`.

**Critical rule:** Fixing code ESCALATES remaining steps to full review requirements.

**Output:** Patch plan disposition table: `| # | Category | Verdict (FIXED/DEFERRED) | Evidence |`

**Gate enforcement:** `wf_step.sh` checks non-artifact code changed since cycle1 receipt, OR cycle1 had 0 findings (auto-detected by scanning review artifacts for zero-finding patterns).

**Output ends with:** `READY FOR CYCLE2 REVIEW`

### Step 6: Cycle 2 Review (adversarial re-check)

**Receipt:** `05_cycle2.json`
**Prompt:** `plans/step_prompts/recon/cycle2.md`

**GREEN PATH (no code changes in fix step):**
- Abbreviated validation — only 1 review artifact required.
- Confirms audit completeness.

**YELLOW/RED PATH (code changed in fix step):**
- Full adversarial review — 2 review artifacts required (same as normal mode).
- Runs logged review scripts.
- Confirms BLOCKING=0 and no new bypasses.

**Gate enforcement:** `wf_step.sh` checks review artifact count:
- Recon + cycle1 had 0 findings → min 1 artifact (relaxed).
- Otherwise → min 2 artifacts (full).

**Receipt extra (GREEN path):** `recon_relaxation: "min_reviews_relaxed_to_1"`

**Output ends with:** `READY FOR RESOLUTION`

### Step 7: Resolution (close the review loop)

**Receipt:** `06_resolution.json`
**Prompt:** `plans/step_prompts/recon/resolution.md`

What the builder does:
1. Creates `artifacts/story/<ID>/review_resolution.md` with required exact lines:
   ```
   Story: <ID>
   HEAD: <sha>
   Blocking addressed: YES
   Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
   ```
2. References actual review files with real paths.
3. Includes Finding Disposition section:
   - GREEN: "Reconciliation audit: no findings."
   - YELLOW/RED: Disposition every finding (FIXED or DEFERRED with rationale).
4. Writes TOC postmortem at `artifacts/story/<ID>/postmortem.md`:
   - Required for YELLOW/RED stories and safety-critical stories.
   - 9 sections. Key: Constraint Summary, Wrong-Implementation Risk, Rule Updates table, Next-Story Startup Note.
   - Validate with: `./plans/postmortem_gate.sh <ID> --head <sha>`

**Gate enforcement:** `wf_step.sh` checks `review_resolution.md` exists with `Blocking addressed: YES` and `BLOCKING=0`.

**Output ends with:** `READY FOR VERIFY_FULL`

### Step 8: Verify Full (final proof)

**Receipt:** `07_verify_full.json`
**Prompt:** `plans/step_prompts/recon/verify_full.md`

What the builder does:
1. Runs `./plans/verify.sh full`.
2. Confirms `verify.meta.json` has `mode=full` and `head_sha` matches current HEAD.
3. Summarizes warnings.

**Gate enforcement:** `wf_step.sh` checks `verify.meta.json` exists with `mode=full` and matching HEAD.

**Output ends with:** `READY FOR PASS_FLIP`

### Step 9: Pass (supervisor only)

**No receipt** — validation-only step.

**GREEN PATH:** No pass-flip needed. Story already has `passes=true`. The receipt chain + resolution + postmortem = proof of audit.

**YELLOW/RED PATH:** Must re-run `plans/prd_set_pass.sh <ID> true` because HEAD changed during fixes. All 8 receipts + verify artifacts + review evidence + contract review must pass.

---

## GREEN vs YELLOW Escalation

The escalation is **automatic** — `wf_step.sh` detects it based on whether cycle1 had findings and whether code changed.

```
Cycle 1 Review
     │
     ├── 0 findings ──────────────────► GREEN PATH
     │   No code changes                 │
     │   Fix step passes automatically   │
     │   Cycle 2: 1 review artifact      │
     │   Resolution: "no findings"       │
     │   Pass: no re-flip needed         │
     │                                   │
     └── Findings exist ─────────────► YELLOW/RED PATH
         Code changes in fix step        │
         Fix step requires diff          │
         Cycle 2: 2 review artifacts     │
         Resolution: full disposition    │
         Pass: re-run prd_set_pass.sh    │
```

**How `wf_step.sh` detects it:**
- **Cycle 2 gate:** Calls `cycle1_had_zero_findings()` which scans review artifacts for patterns like "0 findings", "no issues", "P0: 0.*P1: 0".
- **Fix gate:** Checks whether non-artifact code changed since cycle1 receipt. If cycle1 had 0 findings, the fix step passes with empty diff.

---

## Receipt Schema (Recon Extras)

Recon receipts include additional fields:

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

| Field | Values | When present |
|-------|--------|-------------|
| `recon_mode` | `true` / `false` | Always |
| `recon_relaxation` | `implement_diff_check_skipped` | Implement step (diff bypassed) |
| `recon_relaxation` | `min_reviews_relaxed_to_1` | Cycle 2 step (GREEN path) |

---

## Carry-Forward Enforcement

The postmortem-to-premortem feedback loop is enforced, not just recommended.

### How it works

1. **Supervisor** runs `find_prior_postmortem()` — finds the most recently modified `artifacts/story/*/postmortem.md` excluding the current story.
2. **Supervisor** injects the path as `${PRIOR_POSTMORTEM_PATH}` into the preflight prompt (resolves to a real path or `NONE`).
3. **Preflight prompt** instructs the builder to read section 8 (Next-Story Startup Note) and include two exact lines in the premortem.
4. **`wf_step.sh` preflight** greps the premortem for:
   ```
   Prior Postmortem: <path or NONE>
   Reused Guardrail: <one concrete rule carried forward>
   ```
   Blocks with exit 3 if either line is missing.

### What gets carried forward

The postmortem template section 8:
```markdown
## 8) Next-Story Startup Note (for Step 0)

> **Carry-forward constraint:** <one line>
>
> Watch for: <specific failure pattern>
>
> Required proof before pass-flip: <AT/test/gate requirement>
```

This feeds directly into the next story's premortem §9.

---

## Pod Model (Fresh Builder Contexts)

Steps are grouped into 4 pods. A fresh builder agent context is used at each pod boundary to prevent context rot and finish-line bias.

| Pod | Steps | Agent role |
|-----|-------|-----------|
| A | Preflight + Implement | Auditor — scope the work, inspect code |
| B | Self-Review + Cycle 1 | Reviewer — internal + external review |
| C | Fix + Cycle 2 | Fixer + Verifier — address findings, re-review |
| D | Resolution + Verify Full | Closer — resolution doc, postmortem, final verify |

Step 9 (Pass) is supervisor-only — never delegated to a builder.

---

## Gate Summary

| Step | Gate script | What it checks |
|------|-----------|---------------|
| Preflight | `wf_step.sh` | `passes=true` in PRD (recon guard), premortem carry-forward lines |
| Implement | `wf_step.sh` | Bypassed in recon (no diff required) |
| Self-Review | `wf_step.sh` | Artifacts exist in `self_review/` |
| Cycle 1 | `wf_step.sh` | At least 1 review artifact in `codex/` or `opus/` |
| Fix | `wf_step.sh` | Non-artifact code changed, or cycle1 had 0 findings |
| Cycle 2 | `wf_step.sh` | GREEN: 1 artifact / YELLOW: 2 artifacts |
| Resolution | `wf_step.sh` | `review_resolution.md` with `Blocking addressed: YES`, `BLOCKING=0` |
| Resolution | `postmortem_gate.sh` | TOC postmortem sections, constraint, rule updates, no placeholders |
| Verify Full | `wf_step.sh` | `verify.meta.json` with `mode=full` + HEAD match |
| Pass | `prd_set_pass.sh` | All 8 receipts + verify + review + contract + loss_mode |

---

## Recommended Queue Order

Reconcile in **risk-first** order, not chronological:

1. Stories affecting allow/reject/block (PolicyGuard, intent classification)
2. Stories affecting TradingMode / RiskState transitions
3. Stories affecting WAL / restart / idempotency
4. Stories affecting dispatch chokepoint / execution pipeline
5. Everything else (docs, metadata, low-risk infra)

---

## Quick Reference: Commands

```bash
# Full loop (pauses between steps for builder)
STEP_SUPERVISOR_BASE_BRANCH=<branch> plans/step_pod_loop.sh <ID> --recon

# Individual step control
plans/step_supervisor.sh <ID> next --recon              # What's next?
plans/step_supervisor.sh <ID> prompt --recon             # Print prompt
plans/step_supervisor.sh <ID> validate --recon           # Validate step
plans/step_supervisor.sh <ID> status --recon             # Show progress

# Machine-readable
plans/step_supervisor.sh <ID> next --recon --machine     # PENDING|<step> or DONE|-
plans/step_supervisor.sh <ID> status --recon --machine   # STATUS|story=X|current=Y|...

# Receipt management
WF_RECON_MODE=1 plans/wf_step.sh <ID> --status          # Receipt chain
WF_RECON_MODE=1 plans/wf_step.sh <ID> --reset --yes     # Start over
WF_RECON_MODE=1 plans/wf_step.sh <ID> <step> --dry-run  # Validate without writing

# Postmortem validation
plans/postmortem_gate.sh <ID> --head <sha>               # Validate postmortem artifact

# Final pass (YELLOW path only)
plans/prd_set_pass.sh <ID> true
```

---

## File Inventory

| File | Purpose |
|------|---------|
| `plans/step_supervisor.sh` | Orchestration: next/prompt/validate/status/reset + `find_prior_postmortem()` |
| `plans/step_pod_loop.sh` | For-loop wrapper with `${PRIOR_POSTMORTEM_PATH}` injection |
| `plans/step_loop.sh` | While-loop wrapper using next/validate cycle |
| `plans/wf_step.sh` | Receipt writer + gate enforcement (recon guards, carry-forward check) |
| `plans/step_prompts/recon/*.md` | 8 recon-specific builder prompts |
| `plans/step_prompts/builder_preamble.md` | Agent preamble prepended to every prompt |
| `plans/postmortem_template.md` | 9-section TOC postmortem template |
| `plans/postmortem_gate.sh` | Postmortem artifact validator |
| `plans/scaffold_postmortem.sh` | Scaffolds postmortem from template |
| `plans/prd_set_pass.sh` | Final pass-flip gate (YELLOW path only) |
| `.wf/receipts/<ID>/` | Receipt chain (JSON files, 8 steps) |
| `artifacts/story/<ID>/` | All story artifacts (reviews, resolution, postmortem) |

---

## Appendix A: Recon Prompts (verbatim)

These are the exact prompts the supervisor injects into builder agents. Variables (`${STORY_ID}`, `${BASE_BRANCH}`, `${HEAD}`, `${PRIOR_POSTMORTEM_PATH}`, `${RECON_MODE}`) are substituted at runtime by the supervisor.

### Builder Preamble (`plans/step_prompts/builder_preamble.md`)

Prepended to every prompt, every step.

```
Success is not "story marked done."
Success is: proof-backed, fail-closed, review-clean, and verifiably compliant.

Never optimize for speed over safety.
Never skip sequence.
If a required artifact/test/proof is missing, stop and report it.

Required Decision Output (if this step changes code or PRD):
  Chosen design | Alternative considered | Why chosen is safer | What can still fail | How failure is detected
```

### Step 1: Preflight (`plans/step_prompts/recon/preflight.md`)

```
ROLE
You are the Builder performing RECONCILIATION PREFLIGHT for ${STORY_ID}.
This is an audit step. Do NOT write production code in this step.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Read the PRD entry for ${STORY_ID} in plans/prd.json.
2) Read the referenced contract clauses / ATs in specs/CONTRACT.md.
3) Read the prior postmortem: ${PRIOR_POSTMORTEM_PATH}
   - If not NONE: read section "## 8) Next-Story Startup Note" for carry-forward constraints.
   - If NONE: no prior postmortem exists.
4) For each AT in enforcing_contract_ats:
   - identify the proving test file and test function (or mark missing)
   - check if proof is CAUSAL (reject reason, dispatch_count, latch/mode/result), not just existence
   - note proof quality: PROVEN / WEAK / MISSING / DEFERRED
5) Verify all scope.touch files exist.
6) Run: cargo check --workspace
7) Produce an AT proof audit table and a STOPLIGHT verdict for this story.

OUTPUT
- AT Proof Audit table: | AT | Test file:line | Causal? | Status | Notes |
- scope.touch file existence summary
- Contract alignment notes (including any paper-compliance risk)
- STOPLIGHT: GREEN / YELLOW / RED
- End with exact line: READY FOR IMPLEMENT

PROHIBITED
- Do NOT edit production code
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT hand-wave missing tests as "covered elsewhere" without naming exact test files
```

### Step 2: Implement — Read-Only Audit (`plans/step_prompts/recon/implement.md`)

```
ROLE
You are the Builder performing a READ-ONLY implementation audit for ${STORY_ID}.
This is reconciliation mode — diagnosis only. No code edits in this step.
Fixes belong in Step 5 (Fix), not here.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

READS
- Recon preflight artifact (Step 1 output — AT proof audit table + STOPLIGHT)
- Prior postmortem: ${PRIOR_POSTMORTEM_PATH}
- specs/CONTRACT.md (referenced ATs)
- specs/DESIGN_PATTERNS.md §0 (principles)
- plans/prd.json (story entry)
- scope.touch files (existing implementation)

HARD GATE
Read the recon preflight STOPLIGHT from Step 1.
- RED → STOP. Do not proceed. Fix preflight gaps first.
- YELLOW → Proceed only if every gap is explicitly marked:
    DEFERRED (future slice) or FIX_IN_STEP_5
- GREEN → Proceed.

TASK (read-only — no edits)
For each AT in enforcing_contract_ats[]:

  1) Locate enforcement point
     - File + function + branch/guard
     - If missing or only implied by tests/docs, mark: CLAIMED_NOT_PROVEN

  2) Verify fail-closed path
     - Missing / stale / invalid / NaN / contradictory inputs
     - Confirm: reject / degrade / halt (NOT warn-and-continue)
     - If warn-and-continue found, mark: FAIL_OPEN_RISK

  3) Verify causal proof
     - Identify proving test(s) by name
     - Confirm test proves causality via: dispatch_count, reject_reason,
       latch_reason, cortex_override, or mode assertion
     - If test only proves "something happened" (no reason code, no dispatch
       count), mark: WEAK_PROOF

  4) Check design-pattern conformance
     - Real quantity vs proxy (actual edge vs multiplier proxy)
     - Idempotency where retries are possible
     - Local blast radius (failure stays contained)
     - Observability present on reject paths (structured log + reason code)

  5) Build remediation list (NO EDITS — list only)
     Categorize each finding:
     - CODE_FIX — code change needed (Step 5)
     - TEST_FIX — test change needed (Step 5)
     - PRD_FIX — PRD mapping drift (Step 5)
     - DEFERRED — future slice (with owner + rationale)

DESIGN DISCOVERY RULE
If a better design is found during audit, do NOT silently redesign.
Record it as:
- BLOCKING — must fix now if it creates loss/safety risk
- HARDENING — defer if it improves robustness but does not violate contract
This prevents scope drift disguised as cleanup.

EMERGENCY STOP RULE
If you discover a live-risk fail-open path (P0 severity):
- Output NO-GO with the blocker description
- Do NOT continue to self-review
- The path must be fixed before the audit can proceed

OUTPUT (all sections required)

A) Gate Result
   - GO or NO-GO
   - One-line reason

B) Implementation Audit Summary (5-10 bullets)
   - What is actually implemented
   - What is contract-aligned
   - What is risky / ambiguous

C) AT Proof Status Table
   | AT | Enforcement Point | Proving Test(s) | Causal? | Fail-Closed? | Verdict |
   Verdict: PROVEN / WEAK_PROOF / CLAIMED_NOT_PROVEN / MISSING / FAIL_OPEN_RISK

D) Fail-Closed Findings
   - List any fail-open or ambiguous error paths
   - Include severity (P0/P1/P2/P3)

E) Step 5 Patch Plan (ordered smallest-first)
   | # | Category | File | What to change | Why | Test to add/update |

F) Decision Notes (for non-obvious issues only)
   - Chosen patch direction
   - Alternative considered
   - Why chosen is safer
   - What could still go wrong
   - How it would be detected

G) End with exact line: READY FOR SELF_REVIEW

PROHIBITED
- Do NOT edit production code or tests
- Do NOT edit plans/prd.json
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT write review artifacts manually
- Do NOT silently redesign — record findings, don't fix them
- Do NOT mark an AT as PROVEN unless the test is causal
- Do NOT fabricate proof from test names alone — read the test body
```

### Step 3: Self-Review (`plans/step_prompts/recon/self_review.md`)

```
ROLE
You are the Builder doing SELF-REVIEW for ${STORY_ID} (reconciliation mode).
No new feature work. Audit and document only.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Run the internal review stack against the current code (retroactive audit framing):
   - /pr-review
   - /failure-mode-review
   - /strategic-failure-review
   - /contract-review
2) Create the self-review artifact under:
   artifacts/story/${STORY_ID}/self_review/<TIMESTAMP>_self_review.md
3) The artifact MUST include these exact lines:
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Decision: PASS
   - Failure-Mode Review: DONE
   - Strategic Failure Review: DONE
4) Summarize key findings and whether fixes are needed before external review.

OUTPUT
- Print the path to the self-review artifact
- Short summary of findings (or "none")
- End with exact line: READY FOR CYCLE1 REVIEW

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT fabricate external review artifacts (codex/opus)
- Do NOT skip exact required strings in the self-review file
```

### Step 4: Cycle 1 Review (`plans/step_prompts/recon/cycle1.md`)

```
ROLE
You are the Reviewer requesting EXTERNAL REVIEWS for ${STORY_ID} (cycle 1).
You do NOT write review markdown by hand. You run the logged review scripts.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
Run the logged review scripts so gate-compliant artifacts are generated:
1) ./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}
   (or: ./plans/codex_review_logged.sh ${STORY_ID} --base ${BASE_BRANCH})
2) Optionally also: ./plans/review_logged.sh ${STORY_ID} --tool opus --base ${BASE_BRANCH}
   (or: ./plans/opus_review_logged.sh ${STORY_ID} --base ${BASE_BRANCH})

Wait for scripts to generate artifacts under:
- artifacts/story/${STORY_ID}/codex/
- artifacts/story/${STORY_ID}/opus/ (if run)

OUTPUT
- List all generated review artifact file paths
- Count of BLOCKING/MAJOR/MEDIUM findings across cycle 1
- End with exact line: READY FOR FIX

PROHIBITED
- Do NOT hand-write review artifacts
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT edit any source code — review only
```

### Step 5: Fix (`plans/step_prompts/recon/fix.md`)

```
ROLE
You are the Builder fixing findings for ${STORY_ID} (reconciliation mode).
This is the only step where code/PRD/evidence edits are expected.
Work from the Step 2 Patch Plan and Cycle 1 review findings.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

READS
- Step 2 output (AT Audit Table + Step 5 Patch Plan)
- Cycle 1 review artifacts in artifacts/story/${STORY_ID}/codex/ or opus/

TASK
GREEN PATH (0 findings from both Step 2 audit AND Cycle 1 review):
- If Step 2 patch plan is empty AND cycle 1 found 0 actionable findings,
  this step passes automatically.
- Confirm: "0 findings — no fixes needed."

YELLOW/RED PATH (findings exist):
1) Work through the Step 2 Patch Plan, ordered smallest-first:
   - CODE_FIX items: fix enforcement, fail-closed paths, proof gaps
   - TEST_FIX items: add/fix TRIP/NON-TRIP tests, golden vectors, causal proof
   - PRD_FIX items: update implementation_tests[], enforcing_contract_ats[], loss_mode
2) Address all BLOCKING and MAJOR findings from Cycle 1 review.
3) For HARDENING items from Step 2: defer unless they address a contract violation.
   Document: why deferred, risk impact, owner story/slice.
4) Run: ./plans/verify.sh quick
5) Note: fixing code ESCALATES remaining steps to full review requirements.

OUTPUT
- Patch plan disposition: | # | Category | Verdict (FIXED/DEFERRED) | Evidence |
- Summary of changes made (files touched)
- verify.sh quick result (if fixes were made)
- End with exact line: READY FOR CYCLE2 REVIEW

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT mark deferred findings as fixed
- Do NOT introduce fail-open behavior to "make tests pass"
- Do NOT widen scope beyond this story unless required for correctness
```

### Step 6: Cycle 2 Review (`plans/step_prompts/recon/cycle2.md`)

```
ROLE
You are the Reviewer running cycle-2 review for ${STORY_ID} (adversarial re-check).
This step proves the fixes, not just the intent.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
GREEN PATH (no code changes in fix step):
- Abbreviated validation of the reconciliation audit.
- Produce at least 1 review artifact confirming audit completeness.

YELLOW/RED PATH (code changed in fix step):
- Full adversarial review of the fixed code.
- Run: ./plans/review_logged.sh ${STORY_ID} --tool codex --base ${BASE_BRANCH}
  (or: ./plans/codex_review_logged.sh ${STORY_ID} --base ${BASE_BRANCH})
- Confirm BLOCKING=0 and no new bypasses introduced by fixes.

OUTPUT
- Path(s) to cycle-2 review artifact(s)
- New BLOCKING/MAJOR/MEDIUM findings count (should be 0)
- End with exact line: READY FOR RESOLUTION

PROHIBITED
- Do NOT hand-write review artifacts
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT edit any source code — review only
```

### Step 7: Resolution (`plans/step_prompts/recon/resolution.md`)

```
ROLE
You are the Builder closing the review loop for ${STORY_ID}.
You must create a gate-compliant review resolution artifact.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Read and use the template: plans/review_resolution_template.md
2) Create: artifacts/story/${STORY_ID}/review_resolution.md
3) The document MUST contain these exact lines:
   Story: ${STORY_ID}
   HEAD: ${HEAD}
   Blocking addressed: YES
   Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
4) The document MUST reference the actual review files with real paths:
   - Codex cycle 1 review file: <path>
   - Codex cycle 2 review file: <path>
   - Self-review file: <path>
5) Include a "## Finding Disposition" section.
   - For GREEN reconciliation (0 findings): "Reconciliation audit: no findings."
   - Otherwise: disposition every finding (FIXED or DEFERRED with rationale).
6) Write postmortem using plans/postmortem_template.md:
   - Save to: artifacts/story/${STORY_ID}/postmortem.md
   - Required for YELLOW/RED stories and any story touching gates, TradingMode,
     RiskState, WAL, or replay.
   - Fill all 9 sections. Key requirements:
     - Section 1: Name ONE constraint in a single sentence + Constraint Class
     - Section 5: Describe a wrong implementation that could have passed before
     - Section 6: Rule Updates table — at least one permanent change (this is the point)
     - Section 8: Next-Story Startup Note (carry-forward constraint)
     - Section 9: Complete the checklist (all boxes checked)
   - Keep it to ~1 page. If you can't name the constraint in one sentence, it's fluff.

OUTPUT
- Print the path to review_resolution.md
- Postmortem path (if written)
- Paste the final resolution contents
- End with exact line: READY FOR VERIFY_FULL

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT omit the exact required lines
- Do NOT leave placeholders (<TODO>, TBD, etc.)
```

### Step 8: Verify Full (`plans/step_prompts/recon/verify_full.md`)

```
ROLE
You are the Builder running full verification for ${STORY_ID}.
This is the final proof step before any pass-flip.

STORY
- Story ID: ${STORY_ID}
- Base branch: ${BASE_BRANCH}
- Current HEAD: ${HEAD}

TASK
1) Run full verification: ./plans/verify.sh full
2) Confirm the run completed successfully.
3) Confirm the verification artifact (verify.meta.json) has mode=full and
   head_sha == current HEAD.
4) Summarize any warnings and whether they are informational or blocking.

OUTPUT
- Verification command result (PASS/FAIL)
- Path to verify metadata artifact
- Current HEAD used for verification
- End with exact line: READY FOR PASS_FLIP

PROHIBITED
- Do NOT run plans/wf_step.sh or plans/prd_set_pass.sh
- Do NOT claim PASS if full verify failed
- Do NOT skip reporting the HEAD used for verification
```

---

## Appendix B: Referenced Scripts (verbatim)

All shell scripts and templates referenced in the process. Pasted verbatim for offline review.

### `plans/step_supervisor.sh` — Orchestration Wrapper

```bash
#!/usr/bin/env bash
set -euo pipefail

# step_supervisor.sh — thin orchestration wrapper around wf_step.sh
#
# All validation lives in wf_step.sh. This script only does:
#   next → prompt → (builder works) → validate → next
#
# Usage:
#   step_supervisor.sh <STORY_ID> next [--machine] [--recon]
#   step_supervisor.sh <STORY_ID> prompt [<step>] [--recon]
#   step_supervisor.sh <STORY_ID> validate|run [<step>] [--recon]
#   step_supervisor.sh <STORY_ID> status [--machine] [--recon]
#   step_supervisor.sh <STORY_ID> reset

STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)
WF_STEP="./plans/wf_step.sh"
PROMPTS_DIR="plans/step_prompts"
PREAMBLE="$PROMPTS_DIR/builder_preamble.md"

usage() {
  cat >&2 <<'EOF'
Usage: step_supervisor.sh <STORY_ID> <cmd> [<step>] [--recon] [--machine]

Commands:
  next          Print the next required step (or "done").
  prompt        Print the builder prompt for the next step.
  validate|run  Validate the next step via wf_step.sh + write receipt.
  status        Show receipt chain.
  reset         Delete all receipts for story.

Options:
  --recon     Reconciliation mode (audit already-passing stories)
  --machine   Machine-readable output (pipe-delimited)

Environment:
  STEP_SUPERVISOR_BASE_BRANCH  Base branch for review diffs
EOF
  exit 2
}

# ── Arg parsing ─────────────────────────────────────────────────────
[[ $# -ge 2 ]] || usage
STORY="$1"; shift
CMD="$1"; shift

RECON_MODE=0
MACHINE=0
BASE_BRANCH="${STEP_SUPERVISOR_BASE_BRANCH:-}"
STEP_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recon)   RECON_MODE=1 ;;
    --machine) MACHINE=1 ;;
    -h|--help) usage ;;
    -*)        echo "Unknown option: $1" >&2; usage ;;
    *)
      if [[ -z "$STEP_ARG" ]]; then
        STEP_ARG="$1"
      else
        echo "Unexpected arg: $1" >&2; usage
      fi
      ;;
  esac
  shift
done

# Security: prevent path traversal
[[ "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "Invalid STORY_ID: $STORY" >&2; exit 2; }

# ── Paths ───────────────────────────────────────────────────────────
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"

# ── Helpers ─────────────────────────────────────────────────────────

receipt_file() {
  local step="$1" i
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$step" ]] && { printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$i" "$step"; return; }
  done
  return 1
}

first_missing_step() {
  local step f
  for step in "${STEPS[@]}"; do
    f="$(receipt_file "$step")"
    [[ -f "$f" ]] || { echo "$step"; return; }
  done
  echo "done"
}

prompt_file_for_step() {
  local step="$1"
  if [[ "$RECON_MODE" -eq 1 ]]; then
    echo "$ROOT/$PROMPTS_DIR/recon/$step.md"
  else
    echo "$ROOT/$PROMPTS_DIR/$step.md"
  fi
}

run_wf_step() {
  local step="$1"
  if [[ "$RECON_MODE" -eq 1 ]]; then
    WF_RECON_MODE=1 "$WF_STEP" "$STORY" "$step"
  else
    "$WF_STEP" "$STORY" "$step"
  fi
}

find_prior_postmortem() {
  # Find the most recently modified postmortem in artifacts/story/*/postmortem.md
  # excluding the current story.
  local pm
  pm="$(find "$ROOT/artifacts/story" -maxdepth 2 -name 'postmortem.md' -not -path "*/$STORY/*" 2>/dev/null \
    | xargs ls -t 2>/dev/null | head -1 || true)"
  echo "${pm:-NONE}"
}

# ── Resolve pending step ────────────────────────────────────────────
pending="$(first_missing_step)"
step="${STEP_ARG:-$pending}"

# ── Commands ────────────────────────────────────────────────────────
case "$CMD" in
  next)
    if [[ "$MACHINE" -eq 1 ]]; then
      [[ "$pending" == "done" ]] && echo "DONE|-" || echo "PENDING|$pending"
    else
      echo "$pending"
    fi
    ;;

  prompt)
    [[ "$pending" != "done" ]] || { echo "All steps complete."; exit 0; }

    # Skip guard
    if [[ -n "$STEP_ARG" && "$step" != "$pending" ]]; then
      echo "Refusing prompt for '$step' — next required step is '$pending'" >&2
      exit 3
    fi

    pf="$(prompt_file_for_step "$step")"
    [[ -f "$pf" ]] || { echo "Missing prompt: $pf" >&2; exit 1; }

    HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    PRIOR_PM="$(find_prior_postmortem)"

    # Preamble
    [[ -f "$ROOT/$PREAMBLE" ]] && { cat "$ROOT/$PREAMBLE"; echo; echo "---"; echo; }

    # Render with variable substitution
    sed \
      -e "s|\${STORY_ID}|$STORY|g" \
      -e "s|\${BASE_BRANCH}|${BASE_BRANCH:-main}|g" \
      -e "s|\${HEAD}|$HEAD_SHA|g" \
      -e "s|\${RECON_MODE}|$RECON_MODE|g" \
      -e "s|\${PRIOR_POSTMORTEM_PATH}|$PRIOR_PM|g" \
      "$pf"
    ;;

  validate|run)
    [[ "$pending" != "done" ]] || { echo "All steps complete."; exit 0; }

    # Skip guard
    if [[ -n "$STEP_ARG" && "$step" != "$pending" ]]; then
      echo "Refusing '$step' — next required step is '$pending'" >&2
      exit 3
    fi

    rc=0
    run_wf_step "$step" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      case "$rc" in
        1) echo "Hint: prerequisite receipt missing." >&2 ;;
        3) echo "Hint: required artifacts not found or format wrong." >&2 ;;
        5) echo "Hint: HEAD drift or receipt mismatch." >&2 ;;
      esac
      exit "$rc"
    fi
    echo "Validated: $step"
    ;;

  status)
    if [[ "$MACHINE" -eq 1 ]]; then
      done_count=0; current="-"
      for s in "${STEPS[@]}"; do
        [[ -f "$(receipt_file "$s")" ]] && { done_count=$((done_count + 1)); current="$s"; }
      done
      echo "STATUS|story=${STORY}|current=${current}|next=${pending}|receipts=${done_count}/8|recon=${RECON_MODE}"
    else
      echo "Story: $STORY"
      echo "Mode: $([[ "$RECON_MODE" -eq 1 ]] && echo recon || echo normal)"
      echo "Next: $pending"
      echo "Receipts:"
      for s in "${STEPS[@]}"; do
        if [[ -f "$(receipt_file "$s")" ]]; then
          echo "  [x] $s"
        else
          echo "  [ ] $s"
        fi
      done
    fi
    ;;

  reset)
    "$WF_STEP" "$STORY" --reset --yes
    ;;

  *)
    usage
    ;;
esac
```

### `plans/step_pod_loop.sh` — For-Loop Wrapper

```bash
#!/usr/bin/env bash
set -euo pipefail

# step_pod_loop.sh — minimal supervisor loop
#
# Walks the step array, prints each prompt, waits for the builder,
# then validates via wf_step.sh. That's it.
#
# Usage:
#   STEP_SUPERVISOR_BASE_BRANCH=<branch> ./plans/step_pod_loop.sh <STORY_ID> [--recon]

ID="${1:?usage: step_pod_loop.sh STORY_ID [--recon]}"
RECON="${2:-}"
BASE_BRANCH="${STEP_SUPERVISOR_BASE_BRANCH:-main}"
PROMPT_ROOT="plans/step_prompts"
PREAMBLE="$PROMPT_ROOT/builder_preamble.md"
[[ "$RECON" == "--recon" ]] && PROMPT_ROOT="$PROMPT_ROOT/recon"

steps=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)

# Find the most recent postmortem from a different story (for preflight carry-forward)
find_prior_postmortem() {
  local pm
  pm="$(find "$(git rev-parse --show-toplevel)/artifacts/story" -maxdepth 2 -name 'postmortem.md' \
    -not -path "*/$ID/*" 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)"
  echo "${pm:-NONE}"
}

PRIOR_PM="$(find_prior_postmortem)"

for step in "${steps[@]}"; do
  echo "=================================================="
  echo "STEP: $step  STORY: $ID"
  echo "=================================================="

  prompt_file="$PROMPT_ROOT/${step}.md"
  [[ -f "$prompt_file" ]] || { echo "Missing prompt: $prompt_file" >&2; exit 2; }

  HEAD="$(git rev-parse HEAD)"

  echo
  echo "----- PROMPT TO GIVE BUILDER -----"
  [[ -f "$PREAMBLE" ]] && { cat "$PREAMBLE"; echo; echo "---"; echo; }
  sed \
    -e "s|\${STORY_ID}|$ID|g" \
    -e "s|\${BASE_BRANCH}|$BASE_BRANCH|g" \
    -e "s|\${HEAD}|$HEAD|g" \
    -e "s|\${RECON_MODE}|$([[ "$RECON" == "--recon" ]] && echo 1 || echo 0)|g" \
    -e "s|\${PRIOR_POSTMORTEM_PATH}|$PRIOR_PM|g" \
    "$prompt_file"
  echo "----- END PROMPT -----"
  echo

  read -r -p "Press ENTER after builder completes step '$step'..."

  if [[ "$RECON" == "--recon" ]]; then
    WF_RECON_MODE=1 plans/wf_step.sh "$ID" "$step"
  else
    plans/wf_step.sh "$ID" "$step"
  fi

  echo "VALIDATED: $step"
done

echo
echo "All 8 steps validated. Final pass flip is a separate command:"
echo "  plans/prd_set_pass.sh $ID true"
```

### `plans/step_loop.sh` — While-Loop Wrapper

```bash
#!/usr/bin/env bash
set -euo pipefail

# step_loop.sh — thin supervisor loop
#
# Does NOT duplicate any validation. All checks live in wf_step.sh.
# This script only does: next → prompt → (builder works) → validate → next
#
# Usage:
#   STEP_SUPERVISOR_BASE_BRANCH=<branch> ./plans/step_loop.sh <STORY_ID> [--recon]

STORY_ID="${1:?usage: step_loop.sh <STORY_ID> [--recon]}"
RECON_FLAG="${2:-}"
SUP="./plans/step_supervisor.sh"

while true; do
  step="$("$SUP" "$STORY_ID" next ${RECON_FLAG:+$RECON_FLAG})"

  if [[ "$step" == "done" ]]; then
    echo "All steps complete for $STORY_ID."
    break
  fi

  echo
  echo "=== STEP: $step ==="
  "$SUP" "$STORY_ID" prompt ${RECON_FLAG:+$RECON_FLAG}
  echo
  read -r -p "Press Enter after builder finishes '$step'..."

  if ! "$SUP" "$STORY_ID" validate ${RECON_FLAG:+$RECON_FLAG}; then
    echo "Step '$step' failed validation. Fix and re-run." >&2
    "$SUP" "$STORY_ID" status ${RECON_FLAG:+$RECON_FLAG} || true
    exit 1
  fi

  echo "Validated: $step"
  "$SUP" "$STORY_ID" status ${RECON_FLAG:+$RECON_FLAG} || true
done

exit 0
```

### `plans/wf_step.sh` — Receipt Writer + Gate Enforcement

```bash
#!/usr/bin/env bash
set -euo pipefail

# Workflow step progress tracker.
#
# Tracks which steps are done, enforces ordering, writes simple JSON receipts.
#
# Usage: plans/wf_step.sh <STORY_ID> <step> [options]
#
# Steps (in order — each requires the previous receipt):
#   preflight      — record HEAD as baseline
#   implement      — validate code changed since preflight
#   self_review    — validate self-review artifacts exist
#   cycle1         — validate cycle 1 review artifact exists
#   fix            — validate fixes applied (code changed since cycle1)
#   cycle2         — validate cycle 2 review artifact exists
#   resolution     — validate review resolution exists
#   verify_full    — validate verify.sh full passed with matching HEAD
#   pass           — final gate (all 8 preceding receipts must exist)
#
# Options:
#   --check-only   Exit 0 if step receipt exists, non-zero if not (no validation, no writing)
#   --dry-run      Validate prerequisites but don't write receipt
#   --status       Show current receipt chain status
#   --reset        Delete all receipts for this story (requires --yes)
#
# Receipt location: .wf/receipts/<STORY_ID>/<NN>_<step>.json
#
# Exit codes:
#   0 — step completed, receipt written
#   1 — prerequisite missing (run the required step first)
#   2 — usage/setup error
#   3 — step validation failed (inputs not ready)
#   5 — HEAD mismatch

STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full pass)

usage() {
  cat <<'EOF'
Usage: plans/wf_step.sh <STORY_ID> <step> [--dry-run|--status|--reset]

Steps (in order):
  preflight      Record HEAD as baseline
  implement      Validate code changed since preflight
  self_review    Validate self-review artifacts exist
  cycle1         Validate cycle 1 review artifact exists
  fix            Validate fixes applied since cycle1
  cycle2         Validate cycle 2 review artifact exists
  resolution     Validate review resolution exists
  verify_full    Validate verify.sh full passed
  pass           Final gate (all 8 receipts required)

Options:
  --check-only   Check if step receipt exists (exit 0=yes, 1=no)
  --dry-run      Validate only, don't write receipt
  --status       Show receipt chain status
  --reset        Delete all receipts for story (requires --yes)
EOF
}

die()  { echo "WF_STEP ERROR: $*" >&2; exit 2; }
fail() { echo "WF_STEP BLOCKED: $*" >&2; exit 1; }

# ── Parse args ──────────────────────────────────────────────────────

STORY="${1:-}"
CHECK_ONLY=0
DRY_RUN=0
STATUS_MODE=0
RESET_MODE=0
YES=0
STEP=""

shift $(( $# >= 1 ? 1 : 0 ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)   CHECK_ONLY=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --status)       STATUS_MODE=1 ;;
    --reset)        RESET_MODE=1 ;;
    --yes)          YES=1 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1" ;;
    *)
      if [[ -z "$STEP" ]]; then
        STEP="$1"
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[[ -n "$STORY" ]] || { usage >&2; exit 2; }

# Security: STORY_ID validation (prevent path traversal)
if [[ ! "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  die "invalid STORY_ID '$STORY' — must match ^[A-Za-z0-9][A-Za-z0-9_-]*\$"
fi

# Close stdin to prevent any commands from blocking on input
exec < /dev/null

# ── Reconciliation mode ──────────────────────────────────────────────
WF_RECON_MODE="${WF_RECON_MODE:-0}"
if [[ "$WF_RECON_MODE" != "0" && "$WF_RECON_MODE" != "1" ]]; then
  die "WF_RECON_MODE must be 0 or 1, got: $WF_RECON_MODE"
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$ROOT"

RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"
mkdir -p "$RECEIPT_DIR"

art_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"
if [[ "$art_root" != /* ]]; then art_root="$ROOT/$art_root"; fi
story_art="$art_root/$STORY"

# ── Step index helpers ──────────────────────────────────────────────

step_index() {
  local s="$1"
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$s" ]] && { echo "$i"; return 0; }
  done
  return 1
}

step_is_valid() {
  step_index "$1" >/dev/null 2>&1
}

receipt_file() {
  local s="$1"
  local idx
  idx="$(step_index "$s")"
  printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$idx" "$s"
}

# ── Status mode ─────────────────────────────────────────────────────

if [[ "$STATUS_MODE" -eq 1 ]]; then
  echo "Receipt chain for $STORY:"
  echo "─────────────────────────────"
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo '?')"
  for s in "${STEPS[@]}"; do
    f="$(receipt_file "$s")"
    if [[ -f "$f" ]]; then
      r_head="$(jq -r '.head_sha // "?"' "$f" 2>/dev/null || echo '?')"
      r_ts="$(jq -r '.timestamp_utc // "?"' "$f" 2>/dev/null || echo '?')"
      head_match=""
      [[ "$r_head" != "$head_sha" ]] && head_match=" (HEAD MISMATCH!)"
      printf '  [DONE] %-15s  %s  %s%s\n' "$s" "$r_ts" "$r_head" "$head_match"
    else
      printf '  [    ] %-15s\n' "$s"
    fi
  done
  echo "─────────────────────────────"
  echo "Current HEAD: $head_sha"
  exit 0
fi

# ── Reset mode ──────────────────────────────────────────────────────

if [[ "$RESET_MODE" -eq 1 ]]; then
  count="$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$count" -eq 0 ]]; then
    echo "No receipts to reset for $STORY"
    exit 0
  fi
  if [[ "$YES" -ne 1 ]]; then
    echo "WF_STEP: reset will delete $count receipt(s) for $STORY" >&2
    echo "  Add --yes to confirm: plans/wf_step.sh $STORY --reset --yes" >&2
    exit 2
  fi
  echo "Deleting $count receipt(s) for $STORY in $RECEIPT_DIR"
  rm -f "$RECEIPT_DIR"/*.json
  echo "Reset complete."
  exit 0
fi

# ── Check-only mode (receipt probe, no validation/writing) ─────────

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
  f="$(receipt_file "$STEP")"
  if [[ -f "$f" ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ── Validate step name (not required for --status/--reset) ──────────

if [[ "$STATUS_MODE" -eq 0 && "$RESET_MODE" -eq 0 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
fi

HEAD_SHA="$(git rev-parse HEAD)"
STEP_IDX="$(step_index "$STEP")"

# ── Validate prerequisites (previous receipts must exist) ───────────

if [[ "$STEP_IDX" -gt 0 ]]; then
  for i in $(seq 0 $((STEP_IDX - 1))); do
    local_step="${STEPS[$i]}"
    f="$(receipt_file "$local_step")"
    if [[ ! -f "$f" ]]; then
      fail "missing receipt for step '$local_step' — run: plans/wf_step.sh $STORY $local_step"
    fi
  done
fi

# ── Step-specific input validation ──────────────────────────────────

get_base_head() {
  local pf
  pf="$(receipt_file preflight)"
  if [[ ! -f "$pf" ]]; then
    die "no preflight receipt — cannot determine BASE_HEAD"
  fi
  jq -r '.head_sha' "$pf" 2>/dev/null || die "cannot read head_sha from preflight receipt"
}

require_code_change_since_base() {
  local base_head="$1"
  local diff_output
  diff_output="$(git diff --name-only "$base_head"..HEAD 2>/dev/null || true)"
  [[ -n "$diff_output" ]]
}

cycle1_had_zero_findings() {
  # Shared detection: returns 0 if cycle1 review had 0 high-severity findings.
  # Used by both fix and cycle2 steps. Do NOT duplicate this logic.
  # NOTE: Relies on free-text regex matching review output. If review format
  # changes, update the pattern. Long-term: replace with structured metadata.
  local art_dir="$1"
  for d in "$art_dir/codex" "$art_dir/opus"; do
    if [[ -d "$d" ]]; then
      while IFS= read -r rf; do
        [[ -f "$rf" ]] || continue
        if grep -qiE '(\b0 findings|no findings|no issues|\b0 P0.*\b0 P1|P0: 0.*P1: 0)' "$rf" 2>/dev/null; then
          return 0
        fi
      done < <(find "$d" -maxdepth 1 -type f -name '*_review.md' 2>/dev/null | LC_ALL=C sort)
    fi
  done
  return 1
}

case "$STEP" in
  preflight)
    # First step — record HEAD as BASE_HEAD.
    if [[ "$WF_RECON_MODE" -eq 1 ]]; then
      # Recon mode: verify story already has passes=true in PRD (fail-closed)
      prd_file="${PRD_FILE:-$ROOT/plans/prd.json}"
      if [[ ! -f "$prd_file" ]]; then
        echo "WF_STEP: recon mode blocked — PRD file not found at $prd_file" >&2
        exit 3
      fi
      story_passes="$(jq -r --arg id "$STORY" '.items[] | select(.id==$id) | .passes // false' "$prd_file" 2>/dev/null || echo "false")"
      if [[ "$story_passes" != "true" ]]; then
        echo "WF_STEP: recon mode blocked — story $STORY does not have passes=true" >&2
        echo "  Reconciliation is only for already-passing stories" >&2
        exit 3
      fi
    fi

    # Validate premortem carry-forward lines exist
    premortem_file="$ROOT/reviews/premortems/${STORY}_premortem.md"
    if [[ -f "$premortem_file" ]]; then
      if ! grep -q '^Prior Postmortem: ' "$premortem_file"; then
        echo "WF_STEP: premortem missing required line: 'Prior Postmortem: <path or NONE>'" >&2
        echo "  Add this line to section §9 of $premortem_file" >&2
        exit 3
      fi
      if ! grep -q '^Reused Guardrail: ' "$premortem_file"; then
        echo "WF_STEP: premortem missing required line: 'Reused Guardrail: <rule or NONE>'" >&2
        echo "  Add this line to section §9 of $premortem_file" >&2
        exit 3
      fi
    fi
    ;;

  implement)
    if [[ "$WF_RECON_MODE" -eq 1 ]]; then
      echo "WF_STEP: reconciliation mode — bypassing diff requirement" >&2
    else
      base_head="$(get_base_head)"
      if ! require_code_change_since_base "$base_head"; then
        echo "WF_STEP: no code changes since preflight base ($base_head)" >&2
        exit 3
      fi
    fi
    ;;

  self_review)
    sr_dir="$story_art/self_review"
    if [[ ! -d "$sr_dir" ]]; then
      echo "WF_STEP: no self_review directory at $sr_dir" >&2
      exit 3
    fi
    sr_count="$(find "$sr_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "$sr_count" -lt 1 ]]; then
      echo "WF_STEP: no self-review artifacts found in $sr_dir" >&2
      exit 3
    fi
    ;;

  cycle1)
    review_count=0
    for d in "$story_art/codex" "$story_art/opus"; do
      if [[ -d "$d" ]]; then
        c="$(find "$d" -maxdepth 1 -type f -name '*_review.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
        review_count=$((review_count + c))
      fi
    done
    if [[ "$review_count" -lt 1 ]]; then
      echo "WF_STEP: no cycle 1 review artifact found in $story_art/codex/ or $story_art/opus/" >&2
      exit 3
    fi
    ;;

  fix)
    cycle1_file="$(receipt_file cycle1)"
    cycle1_head="$(jq -r '.head_sha' "$cycle1_file" 2>/dev/null || echo '')"
    if [[ -z "$cycle1_head" ]]; then
      die "cannot read head_sha from cycle1 receipt"
    fi

    # Determine code_changed for receipt (deterministic, used by cycle2 escalation)
    FIX_CODE_CHANGED="false"
    if cycle1_had_zero_findings "$story_art"; then
      echo "WF_STEP: cycle1 had 0 findings — fix step passes with no code changes" >&2
    else
      changed_files="$(git diff --name-only "$cycle1_head"..HEAD 2>/dev/null || true)"
      if [[ -z "$changed_files" ]]; then
        changed_files="$(git diff --name-only 2>/dev/null || true)"
        changed_files+="$(git diff --cached --name-only 2>/dev/null || true)"
      fi
      non_artifact_changes="$(echo "$changed_files" | grep -vE '^(artifacts/|\.wf/|plans/prd\.json$|plans/progress)' || true)"

      if [[ -z "$non_artifact_changes" ]]; then
        echo "WF_STEP: no non-artifact code changes since cycle1 receipt (HEAD=$cycle1_head)" >&2
        echo "  Only artifact/metadata files changed. Fix the actual code." >&2
        exit 3
      fi
      FIX_CODE_CHANGED="true"
    fi
    ;;

  cycle2)
    min_reviews=2
    # GREEN path: recon mode + cycle1 clean → abbreviated Cycle 2 (1 review sufficient)
    # YELLOW/RED path: recon mode + fixes made → full Cycle 2 (same as normal)
    if [[ "$WF_RECON_MODE" -eq 1 ]] && cycle1_had_zero_findings "$story_art"; then
      min_reviews=1
      echo "WF_STEP: recon GREEN path — abbreviated cycle2 (min_reviews=1)" >&2
    fi
    review_count=0
    for d in "$story_art/codex" "$story_art/opus"; do
      if [[ -d "$d" ]]; then
        c="$(find "$d" -maxdepth 1 -type f -name '*_review.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
        review_count=$((review_count + c))
      fi
    done
    if [[ "$review_count" -lt "$min_reviews" ]]; then
      echo "WF_STEP: need at least $min_reviews review artifacts in $story_art/codex/ or $story_art/opus/" >&2
      exit 3
    fi
    ;;

  resolution)
    res_file="$story_art/review_resolution.md"
    if [[ ! -f "$res_file" ]]; then
      echo "WF_STEP: no review_resolution.md at $res_file" >&2
      exit 3
    fi
    if ! grep -q 'Blocking addressed: YES' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Blocking addressed: YES'" >&2
      exit 3
    fi
    if ! grep -q 'Remaining findings: BLOCKING=0' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Remaining findings: BLOCKING=0'" >&2
      exit 3
    fi
    ;;

  verify_full)
    latest_verify="$(ls -dt "$ROOT"/artifacts/verify/*/ 2>/dev/null | head -1 || true)"
    if [[ -z "$latest_verify" ]]; then
      echo "WF_STEP: no verify artifacts found in artifacts/verify/" >&2
      exit 3
    fi
    meta_file="${latest_verify%/}/verify.meta.json"
    if [[ ! -f "$meta_file" ]]; then
      echo "WF_STEP: no verify.meta.json in $latest_verify" >&2
      exit 3
    fi
    verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_mode" != "full" ]]; then
      echo "WF_STEP: verify was mode=$verify_mode, need mode=full" >&2
      exit 3
    fi
    verify_head="$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_head" != "$HEAD_SHA" ]]; then
      echo "WF_STEP: verify HEAD mismatch (verify=$verify_head current=$HEAD_SHA)" >&2
      exit 5
    fi
    if [[ -f "${latest_verify%/}/FAILED_GATE" ]]; then
      echo "WF_STEP: FAILED_GATE present in $latest_verify" >&2
      exit 3
    fi
    ;;

  pass)
    # Final gate — validate all 8 preceding receipts exist.
    for i in $(seq 0 7); do
      s="${STEPS[$i]}"
      f="$(receipt_file "$s")"
      if [[ ! -f "$f" ]]; then
        fail "missing receipt for step '$s' — run: plans/wf_step.sh $STORY $s"
      fi
    done
    echo "WF_STEP: all 8 receipts present for $STORY"
    echo "WF_STEP: ready for prd_set_pass.sh"
    exit 0
    ;;
esac

# ── Dry run ─────────────────────────────────────────────────────────

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "WF_STEP DRY RUN: step '$STEP' prerequisites OK, would write receipt"
  echo "  HEAD: $HEAD_SHA"
  exit 0
fi

# ── Write receipt ───────────────────────────────────────────────────

receipt_path="$(receipt_file "$STEP")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build relaxation note for recon mode (empty string for normal mode).
recon_note=""
if [[ "$WF_RECON_MODE" -eq 1 ]]; then
  case "$STEP" in
    implement) recon_note="implement_diff_check_skipped" ;;
    cycle2)    recon_note="min_reviews_relaxed_to_1" ;;
    *)         recon_note="" ;;
  esac
fi

# Build step-specific extra fields
fix_code_changed="${FIX_CODE_CHANGED:-}"

jq -n \
  --arg story_id "$STORY" \
  --arg step_name "$STEP" \
  --argjson step_index "$STEP_IDX" \
  --arg head_sha "$HEAD_SHA" \
  --arg timestamp_utc "$ts" \
  --argjson recon_mode "$WF_RECON_MODE" \
  --arg recon_relaxation "$recon_note" \
  --arg fix_code_changed "$fix_code_changed" \
  '{
    story_id: $story_id,
    step_name: $step_name,
    step_index: $step_index,
    head_sha: $head_sha,
    timestamp_utc: $timestamp_utc,
    recon_mode: ($recon_mode == 1)
  }
  + (if $recon_relaxation != "" then {recon_relaxation: $recon_relaxation} else {} end)
  + (if $fix_code_changed != "" then {code_changed: ($fix_code_changed == "true")} else {} end)' > "$receipt_path"

echo "WF_STEP: [$STEP] receipt written → $receipt_path"
echo "  HEAD: $HEAD_SHA"
```

### `plans/postmortem_gate.sh` — Postmortem Artifact Validator

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/postmortem_gate.sh <STORY_ID> [--head <sha>] [--artifacts-root <path>]

Purpose:
  Fail-closed gate for TOC-style postmortem artifacts.
  Exit 0 only if all checks pass.

Exit codes:
  0 = pass
  1 = validation failure
  2 = usage error
USAGE
}

die() { echo "FAIL: $*" >&2; exit 1; }

require_fixed_line() {
  local file="$1" expected="$2" message="$3"
  grep -Fxq -- "$expected" "$file" || die "$message"
}

require_heading() {
  local file="$1" heading="$2"
  grep -Fxq -- "$heading" "$file" || die "missing required heading: $heading"
}

# Extract section content between a heading and the next ## heading (or EOF)
section_content() {
  local file="$1" heading="$2"
  sed -n "/^${heading}/,/^## [0-9]/{/^## /d; p;}" "$file" | grep -v '^[[:space:]]*$' || true
}

# --- args ---
story_id="${1:-}"
[[ -n "$story_id" ]] || { usage >&2; exit 2; }
shift

head_sha=""
artifacts_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)       head_sha="${2:?missing sha}"; shift 2 ;;
    --artifacts-root) artifacts_root="${2:?missing path}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

[[ -z "$head_sha" ]] && head_sha="$(git rev-parse HEAD 2>/dev/null)" || true
[[ "$artifacts_root" != /* ]] && artifacts_root="$repo_root/$artifacts_root"

# --- artifact exists ---
pm="$artifacts_root/$story_id/postmortem.md"
[[ -f "$pm" ]] || die "postmortem artifact not found: $pm"

# --- fixed lines ---
require_fixed_line "$pm" "Story: $story_id" "Story ID line missing or wrong"

if [[ -n "$head_sha" ]]; then
  require_fixed_line "$pm" "HEAD: $head_sha" "HEAD line missing or does not match $head_sha"
fi

# --- STOPLIGHT ---
grep -Eq '^STOPLIGHT: (GREEN|YELLOW|RED)$' "$pm" || die "missing or invalid STOPLIGHT line"

# --- Constraint Class ---
grep -Eq '^(\*\*)?Constraint Class:(\*\*)? .+' "$pm" || die "missing Constraint Class line"

# --- required section headings ---
require_heading "$pm" "## 1) Constraint Summary"
require_heading "$pm" "## 2) TOC Five Focusing Steps"
require_heading "$pm" "## 3) Causal Chain (show the failure path)"
require_heading "$pm" "## 5) What Was Missing (be explicit)"
require_heading "$pm" "## 6) Rule Updates (what changes permanently)"
require_heading "$pm" "## 9) Completion Checklist (postmortem quality gate)"

# --- no placeholder markers ---
for marker in '<TODO>' 'TBD' 'FILL_ME'; do
  if grep -Fq -- "$marker" "$pm"; then
    die "placeholder marker found: $marker"
  fi
done

# --- constraint summary non-empty (section 1) ---
s1=$(section_content "$pm" "## 1) Constraint Summary")
if [[ -z "$s1" ]]; then
  die "section 1 (Constraint Summary) is empty"
fi
char_count=$(echo "$s1" | tr -d '[:space:]' | wc -c | tr -d ' ')
if [[ "$char_count" -lt 15 ]]; then
  die "section 1 (Constraint Summary) too short ($char_count chars, need >=15)"
fi

# --- wrong-implementation risk in section 5 ---
s5=$(section_content "$pm" "## 5) What Was Missing")
echo "$s5" | grep -Fq "Wrong-Implementation Risk" || die "section 5 missing 'Wrong-Implementation Risk' subsection"

# --- rule updates table has content (section 6) ---
s6=$(section_content "$pm" "## 6) Rule Updates")
if [[ -z "$s6" ]]; then
  die "section 6 (Rule Updates) is empty"
fi
# Must contain at least one concrete file path or layer reference
has_path=0
for token in 'plans/' 'SKILLS/' 'docs/' 'crates/' 'CLAUDE.md' 'specs/' 'python/' 'Contract' 'PRD' 'Tests' 'Gate' 'Prompt' 'Pattern'; do
  if echo "$s6" | grep -Fq -- "$token"; then
    has_path=1
    break
  fi
done
[[ "$has_path" -eq 1 ]] || die "section 6 (Rule Updates) must reference concrete layers or file paths"

# --- next-story startup note (section 8) ---
s8=$(section_content "$pm" "## 8) Next-Story Startup Note")
if [[ -z "$s8" ]]; then
  die "section 8 (Next-Story Startup Note) is empty"
fi

# --- completion checklist (section 9) ---
s9=$(section_content "$pm" "## 9) Completion Checklist")
echo "$s9" | grep -Fq "Constraint named clearly" || die "section 9 missing checklist item: 'Constraint named clearly'"
echo "$s9" | grep -Fq "Wrong implementation risk" || die "section 9 missing checklist item: 'Wrong implementation risk'"
echo "$s9" | grep -Fq "Permanent rule/gate/test" || die "section 9 missing checklist item: 'Permanent rule/gate/test'"

# --- pass ---
echo "OK: postmortem gate passed for $story_id"
echo "  artifact: $pm"
echo "  stoplight: $(grep -oE 'STOPLIGHT: (GREEN|YELLOW|RED)' "$pm")"
```

### `plans/postmortem_template.md` — 9-Section TOC Template

```markdown
# Postmortem (TOC) — ${STORY_ID}

Story: ${STORY_ID}
Slice: <SLICE_ID>
HEAD: ${HEAD}
Date: <YYYY-MM-DD>
Mode: <implementation|reconciliation>
STOPLIGHT: <GREEN|YELLOW|RED>

## 1) Constraint Summary

**Constraint (single sentence):**
<What bottleneck or weakness actually limited correctness/safety/proof?>

**Constraint Class:** <Spec Gap | Test Gap | Gate Gap | Workflow Gap | Design Gap | Observability Gap>

**Why it matters (loss lens):**
<How this could cause capital loss, missed profit, duplicate dispatch, stale state, fail-open behavior, or hidden drift>

---

## 2) TOC Five Focusing Steps

### Step 1 — Identify the Constraint
- **Primary constraint:** <one clear bottleneck>
- **Symptoms observed:**
  - <symptom 1>
  - <symptom 2>
- **Where it appeared:** <file(s), step(s), gate(s), test(s)>

### Step 2 — Exploit the Constraint (use what exists better)
- **Immediate actions taken (no major redesign):**
  - <tightened AT>
  - <added missing proof>
  - <used existing gate correctly>
- **What we stopped doing:**
  - <paper compliance / broad test / manual shortcut / etc.>

### Step 3 — Subordinate Everything Else
- **What changed so the workflow supports the constraint fix:**
  - <prompt change>
  - <review requirement>
  - <receipt/order rule>
  - <naming requirement>
- **What remains intentionally unchanged (to avoid scope creep):**
  - <list>

### Step 4 — Elevate the Constraint
- **Structural fix (higher leverage):**
  - <new gate / pattern canon / AT addition / config model / integration test>
- **Owner / target slice:** <owner> / <slice or story id>
- **Effort:** <S|M|L>

### Step 5 — Repeat (next likely constraint)
- **Next constraint likely to break us:**
  - <next bottleneck>
- **Early warning signal:**
  - <metric / test gap / review pattern / repeated finding>

---

## 3) Causal Chain (show the failure path)

**Trigger → Propagation → Outcome → Detection**

1. **Trigger:** <what started it>
2. **Propagation:** <how it moved through code/workflow>
3. **Outcome:** <unsafe behavior / missing proof / blocked gate / drift>
4. **Detection:** <which test/review/gate caught it>
5. **Why not caught earlier:** <missing AT / coarse test / no gate / unclear pattern>

---

## 4) Proof and Evidence

### Contract / PRD / Test Proof
- **Contract clauses / ATs affected:** <AT-xxx, section x.y>
- **PRD story refs:** <story refs>
- **Tests proving final behavior:**
  - <test file :: test name>
  - <test file :: test name>

### Artifacts (must be real paths)
- Preflight: <path>
- Reviews: <path(s)>
- Resolution: <path>
- Verify output: <path>

---

## 5) What Was Missing (be explicit)

### Missing Proofs
- <AT / behavior> — <why proof was missing or too weak>

### Wrong-Implementation Risk (critical)
- **A wrong implementation that could have passed before:**
  <describe the bad implementation>
- **What now prevents it:**
  <new AT / gate / prompt rule / pattern>

---

## 6) Rule Updates (what changes permanently)

| Layer | Change | Why | Owner | Target |
|---|---|---|---|---|
| Contract | <change or "none"> | <reason> | <owner> | <target> |
| PRD / AT | <new/updated AT> | <reason> | <owner> | <target> |
| Tests | <new test / rename / split> | <reason> | <owner> | <target> |
| Gate | <new check> | <reason> | <owner> | <target> |
| Prompt / Workflow | <prompt rule> | <reason> | <owner> | <target> |
| Pattern Canon | <pattern added/updated> | <reason> | <owner> | <target> |

---

## 7) Residual Risk (YELLOW debt only)

**Residual risk exists:** <YES|NO>

If YES:
- **Risk:** <what remains>
- **Why deferred:** <scope / dependency / future slice>
- **Safe containment:** <feature flag / non-live path / no-open-risk>
- **Owner / target slice:** <owner> / <target>

---

## 8) Next-Story Startup Note (for Step 0)

> **Carry-forward constraint:** <one line>
>
> Watch for: <specific failure pattern>
>
> Required proof before pass-flip: <AT/test/gate requirement>

---

## 9) Completion Checklist (postmortem quality gate)

- [ ] Constraint named clearly (not vague)
- [ ] Loss/profit impact stated
- [ ] Wrong implementation risk described
- [ ] Permanent rule/gate/test update listed
- [ ] Residual risk either closed or explicitly deferred
- [ ] Next-story startup note written
- [ ] All evidence paths are real
```

### `plans/scaffold_postmortem.sh` — Postmortem Scaffolder

```bash
#!/usr/bin/env bash
set -euo pipefail

# Scaffold a new story postmortem entry.
# Usage: ./plans/scaffold_postmortem.sh <STORY-ID>
# Creates: artifacts/story/<STORY-ID>/postmortem.md

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/plans/postmortem_template.md"
OUT_DIR="$ROOT/artifacts/story"

usage() {
  echo "Usage: $0 <STORY-ID>" >&2
  echo "Creates: artifacts/story/<STORY-ID>/postmortem.md" >&2
  echo "Example: $0 S7-001" >&2
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
fi

story_id="$1"

# Validate story ID format (e.g., S7-001, PX-1)
if [[ ! "$story_id" =~ ^[A-Z]+[0-9]*-[0-9]+$ ]]; then
  echo "ERROR: invalid story ID format: $story_id (expected e.g., S7-001, PX-1)" >&2
  usage
fi

target_dir="$OUT_DIR/$story_id"
target="$target_dir/postmortem.md"

if [[ -f "$target" ]]; then
  echo "ERROR: already exists: $target" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template missing: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$target_dir"

# Copy template and substitute story ID + HEAD
head_sha="$(git rev-parse HEAD 2>/dev/null || echo '<HEAD>')"
sed -e "s/\${STORY_ID}/${story_id}/g" \
    -e "s/\${HEAD}/${head_sha}/g" \
    "$TEMPLATE" > "$target"

echo "$target"
```

### `plans/review_logged.sh` — Review Artifact Logger

```bash
#!/usr/bin/env bash
set -euo pipefail

# Unified review artifact logger.
#
# Dispatches to codex or opus review tools, captures transcript with
# provenance header and SHA256, writes to standard artifact path.
#
# Usage:
#   plans/review_logged.sh STORY_ID --tool codex [--commit REF | --base REF | --uncommitted] [--title TITLE]
#   plans/review_logged.sh STORY_ID --tool opus  [--base REF] [--title TITLE]

usage() {
  cat <<'EOF'
Usage:
  plans/review_logged.sh STORY_ID --tool <codex|opus> [options] [-- <extra tool args>]

Options:
  --tool TOOL      Required: codex or opus
  --commit REF     Review a specific commit (default: HEAD)
  --base REF       Review diff from base to HEAD
  --uncommitted    Review uncommitted changes
  --files LIST     Review specific files (space/comma-separated paths; for recon audits)
  --title TITLE    Review title (default: "<STORY_ID>: <TOOL> review")
  --out-root PATH  Override artifact root (default: artifacts/story)

Artifacts:
  - artifacts/story/<ID>/<tool>/<STAMP>_review.md

Examples:
  plans/review_logged.sh S1-004 --tool codex --base run/slice1-clean
  plans/review_logged.sh S1-004 --tool opus --base run/slice1-clean
  plans/review_logged.sh S1-004 --tool codex --commit HEAD -- --c model="o3"
  plans/review_logged.sh S1-004 --tool opus --files "crates/soldier_core/src/gate.rs crates/soldier_core/src/risk.rs"
EOF
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

# Portable uppercase-first (zsh lacks ${var^})
ucfirst() { echo "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }

# Portable lowercase (zsh lacks ${var,,})
lcase() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

story="${1:-}"
if [[ -z "$story" || "$story" == "-h" || "$story" == "--help" ]]; then
  usage
  exit 2
fi
shift

tool=""
mode="commit"
commit="HEAD"
base=""
files_list=""
title=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      tool="${2:?missing tool name}"
      shift 2
      ;;
    --commit)
      mode="commit"
      commit="${2:?missing ref}"
      shift 2
      ;;
    --base)
      mode="base"
      base="${2:?missing ref}"
      shift 2
      ;;
    --uncommitted)
      mode="uncommitted"
      shift 1
      ;;
    --files)
      mode="files"
      files_list="${2:?missing files list}"
      shift 2
      ;;
    --title)
      title="${2:?missing title}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    *)
      extra+=("$1")
      shift 1
      ;;
  esac
done

[[ -n "$tool" ]] || { echo "ERROR: --tool is required (codex or opus)" >&2; exit 2; }
case "$tool" in
  codex|opus) ;;
  *) echo "ERROR: unknown tool '$tool' (expected: codex or opus)" >&2; exit 2 ;;
esac

if [[ -z "$title" ]]; then
  title="$story: $(ucfirst "$tool") review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$root"

# Verify tool is available
case "$tool" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found in PATH" >&2; exit 2; }
    ;;
  opus)
    command -v claude >/dev/null 2>&1 || { echo "ERROR: claude CLI not found in PATH" >&2; exit 2; }
    ;;
esac

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/$tool"
else
  outdir="$root/$out_root/$story/$tool"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
stamp="${ts}_$$_${RANDOM}"
outfile="$outdir/${stamp}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

# ── Build tool-specific command ─────────────────────────────────────

cmd=()
prompt_tmp=""

# ── Build file contents for --files mode ────────────────────────────
files_context=""
if [[ "$mode" == "files" && -n "$files_list" ]]; then
  # Normalize: replace commas with spaces
  normalized_files="${files_list//,/ }"
  for f in $normalized_files; do
    if [[ -f "$f" ]]; then
      files_context+="
=== FILE: $f ===
$(cat "$f")
"
    else
      files_context+="
=== FILE: $f === (NOT FOUND)
"
    fi
  done
fi

case "$tool" in
  codex)
    cmd=("codex" "review" "--title" "$title")
    case "$mode" in
      commit)      cmd+=("--commit" "$commit") ;;
      base)        cmd+=("--base" "$base") ;;
      uncommitted) cmd+=("--uncommitted") ;;
      files)
        echo "ERROR: --files mode is not supported with codex (use --tool opus instead)" >&2
        exit 2
        ;;
    esac
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;

  opus)
    # Build diff context for the review prompt
    diff_context=""
    case "$mode" in
      commit)
        resolved="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
          if git rev-parse "${resolved}^" >/dev/null 2>&1; then
            diff_context="$(git diff "${resolved}^..${resolved}" 2>/dev/null || true)"
          else
            diff_context="$(git show --format= "${resolved}" 2>/dev/null || true)"
          fi
        fi
        ;;
      base)
        diff_context="$(git diff "${base}...HEAD" 2>/dev/null || true)"
        ;;
      uncommitted)
        diff_context="$(git diff HEAD 2>/dev/null || true)"
        ;;
      files)
        diff_context="$files_context"
        ;;
    esac

    review_context_label="Diff"
    [[ "$mode" == "files" ]] && review_context_label="Files to review"

    review_prompt="You are a senior code reviewer for story $story on branch $branch (HEAD: $head_sha).

Review the following $(lcase "$review_context_label") and provide findings ordered by severity (P0-Critical, P1-High, P2-Medium, P3-Low).

Focus on:
- Correctness bugs and logic errors
- Safety violations (unwrap in production, silent error drops, fail-open paths)
- Missing or inadequate tests
- Contract violations (specs/CONTRACT.md)
- Security issues (injection, auth gaps, race conditions)
- Performance regressions

For each finding, include:
- File path and line number
- Severity level (P0-P3)
- Description of the issue
- Suggested fix

Title: $title

${review_context_label}:
\`\`\`
${diff_context:-(no content available)}
\`\`\`"

    prompt_tmp="$(mktemp)"
    printf '%s' "$review_prompt" > "$prompt_tmp"

    cmd=("claude" "--model" "claude-opus-4-6" "--print" "--verbose")
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;
esac

# ── Run review command ──────────────────────────────────────────────

transcript_tmp="$(mktemp)"
cleanup() {
  rm -f "$transcript_tmp" ${prompt_tmp:+"$prompt_tmp"} ${files_tmp:+"$files_tmp"}
}
trap cleanup EXIT

start_epoch="$(date +%s)"
set +e
if [[ "$tool" == "opus" && -n "$prompt_tmp" ]]; then
  "${cmd[@]}" < "$prompt_tmp" 2>&1 | tee "$transcript_tmp"
else
  "${cmd[@]}" 2>&1 | tee "$transcript_tmp"
fi
rc="${PIPESTATUS[0]}"
set -e
end_epoch="$(date +%s)"
duration_seconds="$((end_epoch - start_epoch))"

printf '\n' >> "$transcript_tmp"
transcript_hash="$(sha256_file "$transcript_tmp")"
transcript_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"

# ── Write artifact with provenance header ───────────────────────────

{
  echo "# $(ucfirst "$tool") review"
  echo
  echo "- Story: $story"
  echo "- Timestamp (UTC): $ts"
  echo "- Branch: $branch"
  echo "- HEAD: $head_sha"
  echo "- Mode: $mode"
  if [[ "$mode" == "commit" ]]; then
    echo "- Commit ref: $commit"
  fi
  if [[ "$mode" == "base" ]]; then
    echo "- Base ref: $base"
  fi
  if [[ "$mode" == "files" ]]; then
    echo "- Files: $files_list"
  fi
  if [[ "$tool" == "opus" ]]; then
    echo "- Model: claude-opus-4-6"
  fi
  echo "- Command: ${cmd[*]}"
  echo "- Artifact Provenance: logger-v1"
  echo "- Generator Script: plans/review_logged.sh"
  echo "- Command Exit Code: $rc"
  echo "- Transcript SHA256: $transcript_hash"
  echo "- Transcript Bytes: $transcript_bytes"
  echo "- Duration Seconds: $duration_seconds"
  echo
  echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
} > "$outfile"
cat "$transcript_tmp" >> "$outfile"
echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"

# Run codex digest if available (codex only)
if [[ "$tool" == "codex" ]]; then
  digest_script="$root/plans/codex_review_digest.sh"
  if [[ -x "$digest_script" ]]; then
    if ! "$digest_script" "$outfile" >&2; then
      echo "WARN: failed to generate digest for $outfile" >&2
    fi
  fi
fi

echo "Saved $(ucfirst "$tool") review: $outfile" >&2
exit "$rc"
```

### `plans/review_resolution_template.md` — Resolution Template

```markdown
# Review Resolution Template

Copy this into `artifacts/story/<STORY_ID>/review_resolution.md` and replace placeholders.

Story: <STORY_ID>
HEAD: <HEAD_SHA>
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Cycle 1 review file: codex/<TIMESTAMP>_review.md
Cycle 2 review file: codex/<TIMESTAMP>_review.md

## Finding Disposition

Cycle 1 review: codex/<CYCLE1_TIMESTAMP>_review.md
Cycle 1 high-severity count: <N>

<!-- List EVERY P0/P1 finding from cycle 1. Each line must follow this exact format: -->
<!-- F-<N> | <P0|P1|P2> | <file:line> | <description> | <FIXED|DEFERRED|WONTFIX> | <evidence> -->
<!-- Gate requires: P0 cannot be DEFERRED or WONTFIX. DEFERRED must reference a debt item. -->
<!-- If cycle 1 had 0 high-severity findings, write: "No high-severity findings in cycle 1." -->

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | file.rs:42 | Brief description of finding | FIXED | commit abc1234 |
| F-2 | P2 | file.rs:55 | Brief description of finding | DEFERRED | debt D-001 target slice N |

Cycle 2 review: codex/<CYCLE2_TIMESTAMP>_review.md
Cycle 2 high-severity count: <N>
Cycle 2 new P0/P1 findings: 0
```

### `plans/prd_set_pass.sh` — Final Pass-Flip Gate

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./plans/prd_set_pass.sh <task_id> <true|false> [--artifacts-dir <dir>] [--contract-review <file>]

If --artifacts-dir is omitted, the latest artifacts/verify/<run_id>/ directory is used.

Rules for passes=true:
  - verify.meta.json must exist and report mode=full
  - verify.meta.json head_sha must equal current HEAD
  - FAILED_GATE must be absent in artifacts dir
  - all *.rc files in artifacts dir must be 0
  - contract review file must exist and contain decision=PASS
  - at least one review artifact must exist for current HEAD (codex/ or opus/)
  - wf_step.sh receipt chain must have all 8 receipts
  - enforcing_contract_ats must be non-empty (exit 6) — exempt: policy/certification categories
  - enforcement_point must be non-empty (exit 6) — exempt: policy/certification categories
  - loss_mode.worst_case, .fail_closed_cap, .drift_metric must all be non-empty (exit 9) — exempt: policy/certification
USAGE
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ID="${1:-}"
STATUS="${2:-}"
shift $(( $# >= 2 ? 2 : $# ))

PRD_FILE="${PRD_FILE:-plans/prd.json}"
ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-}"
CONTRACT_REVIEW_FILE=""

if [[ -z "$ARTIFACTS_DIR" ]]; then
  ARTIFACTS_DIR="$(ls -dt "$ROOT"/artifacts/verify/*/ 2>/dev/null | head -n 1 || true)"
fi
ARTIFACTS_DIR="${ARTIFACTS_DIR%/}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts-dir)
      ARTIFACTS_DIR="${2:-}"
      shift 2
      ;;
    --contract-review)
      CONTRACT_REVIEW_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$ID" && -n "$STATUS" ]] || { usage >&2; exit 2; }
[[ "$STATUS" == "true" || "$STATUS" == "false" ]] || { echo "ERROR: status must be true or false" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[[ -f "$PRD_FILE" ]] || { echo "ERROR: missing PRD file: $PRD_FILE" >&2; exit 1; }

lock_file="${PRD_FILE}.lock"
lock_dir="${lock_file}.d"
tmp=""
lock_dir_acquired=0

cleanup() {
  if [[ -n "$tmp" && -f "$tmp" ]]; then
    rm -f "$tmp" 2>/dev/null || true
  fi
  if [[ "$lock_dir_acquired" == "1" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

trap cleanup EXIT

if command -v flock >/dev/null 2>&1; then
  exec 200>"$lock_file"
  if ! flock -n 200; then
    echo "ERROR: PRD is locked by another process" >&2
    exit 7
  fi
else
  if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "ERROR: PRD is locked by another process" >&2
    exit 7
  fi
  lock_dir_acquired=1
fi

if ! jq -e . "$PRD_FILE" >/dev/null 2>&1; then
  echo "ERROR: PRD is invalid JSON: $PRD_FILE" >&2
  exit 1
fi

exists="$(jq --arg id "$ID" 'any(.items[]; .id==$id)' "$PRD_FILE")"
if [[ "$exists" != "true" ]]; then
  echo "ERROR: task id not found in PRD: $ID" >&2
  exit 3
fi

if [[ "$STATUS" == "true" ]]; then
  # ── PRD field validation ──────────────────────────────────────────
  story_category="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.category // "")' "$PRD_FILE")"
  if [[ "$story_category" != "policy" && "$story_category" != "certification" ]]; then
    eca_count="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.enforcing_contract_ats // []) | if type == "array" then length else 0 end' "$PRD_FILE")"
    if [[ "$eca_count" -eq 0 ]]; then
      echo "ERROR: cannot set passes=true for $ID: enforcing_contract_ats is empty (PASS requires AT ownership)" >&2
      exit 6
    fi
    enf_point="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.enforcement_point // "")' "$PRD_FILE")"
    if [[ -z "$enf_point" ]]; then
      echo "ERROR: cannot set passes=true for $ID: enforcement_point is missing/empty (PASS requires a named enforcement point)" >&2
      exit 6
    fi
  fi

  # ── loss_mode gate ──
  if [[ "$story_category" != "policy" && "$story_category" != "certification" ]]; then
    loss_ok=$(jq -r --arg id "$ID" '
      .items[] | select(.id == $id) |
      (.loss_mode // {}) | if type == "object" then . else {} end |
      ((.worst_case // "") | length > 0) and
      ((.fail_closed_cap // "") | length > 0) and
      ((.drift_metric // "") | length > 0)
    ' "$PRD_FILE")
    if [[ "$loss_ok" != "true" ]]; then
      echo "ERROR: loss_mode incomplete for $ID (worst_case, fail_closed_cap, drift_metric required)" >&2
      exit 9
    fi
  fi

  # ── Verify artifacts ──────────────────────────────────────────────
  [[ -d "$ARTIFACTS_DIR" ]] || { echo "ERROR: missing artifacts dir: $ARTIFACTS_DIR" >&2; exit 4; }

  meta_file="$ARTIFACTS_DIR/verify.meta.json"
  [[ -f "$meta_file" ]] || { echo "ERROR: missing verify metadata artifact: $meta_file" >&2; exit 4; }
  verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
  if [[ "$verify_mode" != "full" ]]; then
    echo "ERROR: verify artifacts are not from full mode (mode=${verify_mode:-<missing>}) in $meta_file" >&2
    exit 4
  fi
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read current HEAD" >&2; exit 4; }
  [[ -n "$HEAD_SHA" ]] || { echo "ERROR: HEAD_SHA is empty" >&2; exit 4; }
  verify_head_sha="$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null || true)"
  if [[ -z "$verify_head_sha" ]]; then
    echo "ERROR: verify metadata missing head_sha in $meta_file" >&2
    exit 4
  fi
  if [[ "$verify_head_sha" != "$HEAD_SHA" ]]; then
    echo "ERROR: verify metadata HEAD mismatch (verify=$verify_head_sha current=$HEAD_SHA)" >&2
    exit 4
  fi

  if [[ -f "$ARTIFACTS_DIR/FAILED_GATE" ]]; then
    echo "ERROR: FAILED_GATE present in $ARTIFACTS_DIR" >&2
    exit 4
  fi

  rc_count=0
  bad_rc=0
  while IFS= read -r rc_file; do
    rc_count=$((rc_count + 1))
    rc_val="$(tr -d '[:space:]' < "$rc_file" 2>/dev/null || true)"
    if [[ "$rc_val" != "0" ]]; then
      echo "ERROR: non-zero gate rc in $rc_file: ${rc_val:-<empty>}" >&2
      bad_rc=1
    fi
  done < <(find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name '*.rc' | sort)

  if [[ "$rc_count" -eq 0 ]]; then
    echo "ERROR: no *.rc gate artifacts found in $ARTIFACTS_DIR" >&2
    exit 4
  fi
  if [[ "$bad_rc" -ne 0 ]]; then
    exit 4
  fi

  # ── Contract review ───────────────────────────────────────────────
  if [[ -z "$CONTRACT_REVIEW_FILE" ]]; then
    CONTRACT_REVIEW_FILE="$ARTIFACTS_DIR/contract_review.json"
  fi
  [[ -f "$CONTRACT_REVIEW_FILE" ]] || { echo "ERROR: missing contract review artifact: $CONTRACT_REVIEW_FILE" >&2; exit 4; }

  if ! jq -e '.decision == "PASS"' "$CONTRACT_REVIEW_FILE" >/dev/null 2>&1; then
    echo "ERROR: contract review decision is not PASS in $CONTRACT_REVIEW_FILE" >&2
    exit 4
  fi

  # ── Inline review check ──────────────────────────────────────────
  review_found=0
  art_root="${STORY_ARTIFACTS_ROOT:-$ROOT/artifacts/story}"
  for dir in "$art_root/$ID/codex" "$art_root/$ID/opus"; do
    [[ -d "$dir" ]] || continue
    if grep -rlF "$HEAD_SHA" "$dir"/ 2>/dev/null | head -1 | grep -q .; then
      review_found=1; break
    fi
  done
  if [[ "$review_found" -eq 1 ]]; then
    echo "OK: review gate passed for $ID @ $HEAD_SHA"
  else
    echo "ERROR: no review artifact for HEAD=$HEAD_SHA in $art_root/$ID/{codex,opus}" >&2
    exit 4
  fi

  # ── Fail-closed coverage ──────────────────────────────────────────
  if [[ -x "./plans/fail_closed_coverage.sh" ]]; then
    if ! ./plans/fail_closed_coverage.sh; then
      echo "ERROR: fail-closed test coverage minimum not met" >&2
      exit 8
    fi
  fi

  # ── Receipt chain (all 8 receipts must exist) ─────────────────────
  WF_STEP="${WF_STEP:-./plans/wf_step.sh}"
  if [[ -x "$WF_STEP" ]]; then
    if ! "$WF_STEP" "$ID" pass; then
      echo "ERROR: receipt chain validation failed for $ID" >&2
      echo "  Run: plans/wf_step.sh $ID --status  to see missing steps" >&2
      exit 4
    fi
  fi
fi

tmp="$(mktemp)"
jq --arg id "$ID" --argjson status "$STATUS" '
  .items = (.items | map(if .id == $id then .passes = $status else . end))
' "$PRD_FILE" > "$tmp"
if [[ "$STATUS" == "true" ]]; then
  final_head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to re-read current HEAD before pass flip" >&2; rm -f "$tmp"; exit 4; }
  if [[ "$final_head_sha" != "$HEAD_SHA" ]]; then
    echo "ERROR: HEAD changed during pass flip validation (initial=$HEAD_SHA current=$final_head_sha)" >&2
    rm -f "$tmp"
    exit 4
  fi
fi
mv "$tmp" "$PRD_FILE"

echo "Updated task $ID: passes=$STATUS"
```

