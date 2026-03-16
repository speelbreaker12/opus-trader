# SKILL: /premortem (Pre-Implementation Safety Analysis)

## Purpose
Fill out the Story Premortem Template (`reviews/premortems/STORY_PREMORTEM_TEMPLATE.md`) for a
given PRD story. This is a structured pre-implementation analysis that must be completed before
any coding begins on safety-critical trading stories. No production code in this step.

## When to use
- Before implementing any PRD story (mandatory first step in the story loop)
- When `plans/prd.json` has a pending story with `passes=false`
- Called by `/slice-execute` as a prerequisite (STOPLIGHT must be GREEN or YELLOW-addressed)

## Inputs (must be provided)
- **Story context**: story ID, description, risk rating, scope (files/crates touched)
- **Contract clauses**: which `specs/CONTRACT.md` sections apply
- **Acceptance tests**: which AT-XXX identifiers are claimed
- **Enforcement point(s)**: where in the pipeline the enforcement lives

## Inputs (must open and read)
- `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` — the canonical template
- `specs/CONTRACT.md` — to trace AT clauses and verify normative text
- `specs/DESIGN_PATTERNS.md` §0 — principles that apply to every section
- `plans/prd.json` — the story entry for metadata

## Task

### 0) Scope Challenge (before touching the template)

Read the story entry from `plans/prd.json`. Then answer these three questions internally:

1. **What existing code already partially solves this?** Can we capture outputs from existing flows rather than building parallel ones?
2. **What is the minimum set of changes that achieves the stated goal?** Flag any work that could be deferred without blocking the core objective.
3. **Complexity check:** Does this touch more than 3 files or introduce more than 2 new types/structs? If yes, treat that as a smell.

Present your finding to the user and ask them to choose:

> **A) SCOPE REDUCTION** — the story as written is over-specified. Propose a minimal version that achieves the contract goal, then proceed with that.
> **B) FULL SCOPE** — proceed as specified in the PRD story.
> **C) SMALL CHANGE** — compressed scope: one primary enforcement path, minimum new code, defer secondary hardening to a follow-on story.

**Hard rule:** Once the user picks a scope, commit to it fully. Do not re-argue for a smaller scope during S0–S10. If the user chose FULL SCOPE, your job is to make that scope succeed — not to keep lobbying for less work.

Only after the user responds, proceed to step 1.

---

### 1) Copy the template
Copy `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` to
`reviews/premortems/<STORY-ID>_premortem.md`. Fill in the story ID in the header.

### 2) Fill ALL sections (S0 through S10)

Every section must be filled. Empty sections are not acceptable.

**S0 — What we're building**: Story ID, contract clauses, ATs, touch scope, risk rating.
Apply the risk rating rules: HIGH if touching persistence/replay/idempotency, order
placement/funds movement, risk limits, auth/keys, or anything that can silently weaken gates.

**Trading Risk Hard Gate**: Answer all 7 questions with YES / NO / UNKNOWN using a Markdown table with columns `| # | Question | Answer | Justification | Proof Reference | Gap ID |`. Each answer requires a one-sentence justification and a concrete proof reference (contract clause, file path, test name). If any answer is NO or UNKNOWN, provide a Gap ID.

**S1 — Clause audit**: For each claimed AT, look up the actual text in CONTRACT.md. Extract
the normative clause, classify as MUST/SHOULD/MAY, and confirm testability. Flag any AT
whose contract clause is ambiguous, missing, or informational-only.

**S2 — Assumptions**: List every assumption the implementation depends on. For each, state
how it breaks and which test proves it. If no test exists, the assumption must be killed or
a test planned.

**S3 — Top 5 failure modes**: Run the 6-category fail-closed sweep (Missing/None, NaN/Inf,
Negative, Out-of-domain, Corrupt/garbage, Narrowing casts) against each enforcement input.
Minimum 5 entries for HIGH risk, 3 for MED, 2 for LOW.

**S4 — Open decisions**: Document every ambiguity or design choice. Each decision needs
evidence (file + line), options with blast radius, chosen option with rationale, and scope
control. If ambiguity cannot be resolved, set `needs_human_decision=true` and STOP.

**S5 — Wrong implementation gate**: For EACH claimed AT, identify at least one wrong
implementation that would still pass the existing tests. State whether the wrong impl is
easier than the correct one. Propose a tightening test or golden vector to block it.

**S6 — Proof plan**: Map each AT to its enforcement point, proving tests, TRIP/NON-TRIP
coverage, causality proof method, and isolation check. Safety-critical ATs MUST have both
TRIP and NON-TRIP tests. Note interactions between ATs.

**S7 — Economic risk**: State the worst financial outcome if this fails in prod, the
fail-closed cap on loss, the drift metric name, the loss boundary, and the rollback plan.
For observability-only stories (no enforcement changes, no ATs), state explicitly: "no capital
impact — this change cannot cause financial loss or block profit."

**S8 — Conflict scan**: Check for invariant/gate conflicts, CONTRACT.md conflicts, struct
field assumptions, and state machine transitions affected. If touching CONTRACT.md, run the
contract change ledger check.

**S9 — Constraint**: Read the prior postmortem (if any) section 8 startup note. State the
expected constraint, exploit, and smallest fix.

**S10 — STOPLIGHT + Exit criteria**: Assign GREEN / YELLOW / RED using these strict rules:
- **GREEN**: ALL 7 Hard Gate answers are YES with proof — no exceptions.
- **YELLOW**: No answer is NO; at least one UNKNOWN has a gap_id and a containment plan.
- **RED or NO-GO**: ANY answer is NO — even if a gap_id exists. A NO answer is a known design
  violation; a gap_id documents it but does not cure it. NO always means RED.
Use the exact format: `**STOPLIGHT**: GREEN` — bold only the word STOPLIGHT, value after the
colon outside the bold markers (not `**STOPLIGHT: GREEN**`).
For YELLOW and RED outputs, include a `**Debt Register**` section (use that exact heading) with
a table containing gap_id, severity, owner, and target slice. This is required for both colors:
YELLOW debt register documents UNKNOWN gaps that need containment; RED debt register documents NO
violations that block implementation.
Verify all exit criteria checkboxes.

### 3) Quality rules (non-negotiable)

- **Fail-closed throughout**: When uncertain about any answer, choose the restrictive option
  (NO or UNKNOWN, not YES). When uncertain about risk rating, choose HIGH.
- **Concrete proof references**: Every Hard Gate answer, every clause audit entry, and every
  proof plan row must cite a specific file, contract section, or test name. Prose without
  proof = not answered.
- **No optimistic defaults**: Do not assume safety. Prove it. If proof is missing, the
  answer is UNKNOWN or NO with a Gap ID.
- **gap_id format**: `GAP-<STORY-ID>-<SEQ>` for story-specific (e.g., `GAP-S5-003-1`, `GAP-S4-007-2`), `GAP-SYSTEMIC-<SEQ>` for cross-story debt — use the exact story ID including its dash.
- **STOPLIGHT color rule**: GREEN = all YES. YELLOW = no NO, at least one UNKNOWN (contained).
  RED = any NO. A gap_id on a NO answer documents the violation but STOPLIGHT stays RED.
- **Q6 (contract clauses MUST-level)**: YES for stories with no enforcement changes and no ATs
  — no normative enforcement clause is being relied upon. Mark UNKNOWN only if the story
  claims an AT whose contract clause level you cannot verify from the provided fixture.
- **Q7 (AT coverage causal sufficiency)**: Q7 asks whether the CLAIMED ATs causally prove the
  CLAIMED contract paths — not whether every fail-closed branch has a dedicated AT. Answer YES
  when the named ATs (AT-XXX) cover TRIP+NON-TRIP for the primary enforcement path they claim
  to cover. Secondary fail-closed branches described as design requirements (stale state
  handling, NaN guarding, missing snapshot handling) are implementation best practices; their
  absence from the AT list does NOT make Q7 UNKNOWN unless the story specifically introduces a
  NEW LOGIC PATH not covered by any existing AT (e.g., a new cache-miss default that the ATs
  provably cannot trigger). Example: S4-007 AT-050/AT-051 prove spread threshold TRIP/NON-TRIP
  → Q7=YES even though there are no dedicated stale/NaN ATs, because those are implementation
  detail paths, not the primary contract path being claimed.
- **Wrong impl gate must be adversarial**: Think like an attacker. The wrong impl should be
  something a lazy or confused implementer might actually write — not a strawman.
- **Proportional depth**: Keep total output proportional to risk. LOW risk stories with no ATs
  and no enforcement changes should be under 1500 words total — mark §5 and §6 "N/A — no ATs
  claimed" and keep each remaining section to 1-3 sentences or a small table.

## Output
The filled premortem document at `reviews/premortems/<STORY-ID>_premortem.md`.

## Hard Constraints
- Do NOT write production code — this is analysis only
- Do NOT skip sections — every section must be filled
- Do NOT mark GREEN unless all 7 Hard Gate questions are YES with concrete proof
- Do NOT leave claimed ATs without clause audit entries
- Do NOT leave safety-critical ATs without TRIP + NON-TRIP in the proof plan
- If any Hard Gate answer is NO, STOPLIGHT must be RED or NO-GO
