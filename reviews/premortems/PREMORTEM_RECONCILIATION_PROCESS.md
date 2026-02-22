# Premortem and Implementation Reconciliation Process

> Multi-agent workflows for (A) producing high-quality story premortems and (B) retroactively auditing existing code against those premortems.
> Designed and validated during Slice 1 (13 stories, 4 agent teams, 3 review rounds).
>
> **Version**: 1.7 (2026-02-21) — v1.7: machine-verifiable proof graphs V1 (`python/proof_graph/`) — per-story `proof_graph.json` with stdlib-only Python validator (18 rules, `--strict` enforcement at pass-flip), scaffolder (`scaffold.py`), deny-unknown-fields schema, `schema_version: 1`, legacy exemption list (`plans/proof_graph_exempt.txt`), `prd_set_pass.sh` gate integration (exit 10). Appendix C roadmap item marked DONE (V1). v1.6: anti-patterns #12-#15 (workflow bypass vectors: fake citation pass-through, diff-only review gaming, DECISION_DIVERGENCE escape hatch, silent debt deferral), enforceable Cycle 1 pre-existing-code gate, DECISION_DIVERGENCE auto-escalation for rejected options, debt register JSON schema + R7f validation, R7c call-graph reachability (entry-point assertion replaces single-caller check), codebase audit anchors (`#[audit_anchor]`), future roadmap (proof graphs, post-rejection blast-radius audit). v1.5: GAP-P0-01 separated proof verdicts from runtime-enforcement gate (PROVEN-INTEGRATED required for pass-eligibility on safety-critical ATs; proof verdict stays clean), GAP-P0-02 machine mutation testing via `cargo mutants` with fast/deep path scoping (mental analysis demoted to pre-filter, scope extended to full proving suite for gapped ATs), GAP-P0-03 structured R5b skill receipts with head_commit validation (replaces mtime checks, SELF_REVIEW_UNPROVEN blocker), GAP-P0-04 OPERATIONAL_ESCALATION_REQUIRED flag for live-system unwired guards. GAP-P1-01 decentralized R4 synthesis (scripted JSON aggregation, lead resolves conflicts only), GAP-P1-02 WEAK_PROOF on MED/HIGH loss_mode ATs escalated to CLAIMED_NOT_PROVEN, GAP-P1-03 STOPLIGHT re-evaluation in Phase R6 verify. v1.2: review scope rules, Phase R5b, story proof scope, Review Basis, Evidence Index, minimum evidence pack, positive/negative evidence. v1.3: PARTIAL verdict, R7 sub-phase breakdown, R7d-R7e escalation, MISSING_ARTIFACT/FALLBACK priority, emergency escalation, Review Basis enforcement, prd_set_pass.sh cross-reference, Simpler-Than-Correct Gate dual-application. v1.4: expanded fail-closed check (5-category input validation), input-boundary mutations in R7e, anti-patterns #10 (recusal blind spot) and #11 (saturating arithmetic ≠ input validation). Root cause: Kimi K2.5 external review surfaced 2 gaps missed by all prior review layers.

## Glossary (Normative)

| Term | Definition |
|------|------------|
| AT | Acceptance Test — a contract clause translated into a verifiable behavior. |
| TRIP Test | A test that triggers a safety guard and proves causality (e.g., asserts `dispatch_count == 0` AND `reject_reason == X`). |
| NON-TRIP Test | A test that verifies the absence of a guard trigger under valid conditions (pass-through proof). |
| STOPLIGHT | Premortem readiness status: RED (blockers exist, do not implement), YELLOW (deferred debt accepted), GREEN (ready to implement). |
| Enforcement Point | Specific `file:line::function` where a contract clause is enforced (guard, check, or validation). |
| Wrong Impl | An easier/cheaper implementation that satisfies naive tests but violates the contract. |
| Tightening Test | A test specifically designed to distinguish the correct implementation from a predicted wrong implementation. |
| Fail-Closed | Error/edge-case handling that defaults to rejection/degradation (not warn-and-continue). |
| Golden Vector | A table-driven test with 10-30 input cases covering boundary, NaN/Inf/missing, and §5 wrong-impl scenarios. |
| Evidence Ledger | Per-story document produced during reconciliation with file:line citations for every audit check. |
| Simpler-Than-Correct Gate | A meta-check applied to each implementation under test: "Is there any implementation SIMPLER than the correct one that passes the entire test suite?" If yes, the suite has a mutation gap. Applied twice: first in Phase R5b self-review (preliminary, builder catches own gaps) and definitively in Phase R7e devils advocate (independent auditor). The R5b application is defense-in-depth — it reduces the load on R7e but does not replace it. |
| Proof Graph | Per-story `proof_graph.json` — structured JSON mapping each AT to enforcement point, tests, wiring status, observability, and verdict. Validated by `python/proof_graph/validate.py` with 18 rules. Replaces markdown evidence ledger tables for machine-checkable invariant enforcement at pass-flip time. Schema version 1. |
| Story Proof Scope | The minimum context needed to audit a story's contract compliance: PRD item, `enforcing_contract_ats[]`, premortem (especially §2/§4/§5), recon preflight, `scope.touch` files, proving test files from `implementation_tests[]`, relevant CONTRACT.md sections, and direct integration surfaces for causality. This is the default review unit — not the diff, not the whole slice. The framing is "contract-proof audit," not "code review." |
| Review Basis | An explicit label every reviewer must include in their output: `STORY_SCOPE (Cycle 1)` or `FIX_DIFF + AT_REGRESSION (Cycle 2)`. Removes ambiguity about what was actually reviewed. |

**Verdict systems**: This document uses three verdict levels that operate at different scopes:
- **Per-AT verdicts** (used in evidence ledgers, Phase R1): `PROVEN`, `WEAK_PROOF`, `CLAIMED_NOT_PROVEN`, `UNTESTED_ENFORCEMENT`, `WRONG_IMPL_UNBLOCKED`, `DEFERRED`. **Safety-critical escalation (v1.5)**: `WEAK_PROOF` on a MED/HIGH `loss_mode` AT is treated as `CLAIMED_NOT_PROVEN` and blocks `RECONCILED`. Asserting `result.is_err()` without verifying which guard caused the rejection is insufficient for safety-critical ATs. **PROVEN requires cause-specific assertions**: at least one of `reject_reason`, `dispatch_count`, `latch_reason`, or `mode_transition` — plus `PROVEN-INTEGRATED` wiring status for safety-critical ATs (see runtime-enforcement gate). **LOW risk tolerance (v1.6)**: `WEAK_PROOF` on a LOW `loss_mode` AT may be accepted as `RECONCILED-WITH-DEBT` — but only with a debt register entry (`DEBT_REGISTER.json`) specifying `owner` and `target_slice` for the proof upgrade. `WEAK_PROOF` without a debt entry is treated as `CLAIMED_NOT_PROVEN` regardless of risk level.
- **Evidence ledger intermediate verdict** (used in Phase R1-R4, before final assignment): `PARTIAL` — at least one AT has gaps requiring remediation. Replaced by a final verdict in Phase R6.
- **Story-level verdicts** (used in Phase R6 final summary): `RECONCILED`, `RECONCILED-WITH-DEBT`, `NOT RECONCILED`
- **Wiring qualifiers** (added in Phase R7c): `PROVEN-INTEGRATED` (function works AND has production callers), `PROVEN-UNIT` (function works but has zero production callers — island guard)

A story's final verdict is derived from its per-AT verdicts: any `CLAIMED_NOT_PROVEN` or `WRONG_IMPL_UNBLOCKED` on a safety-critical AT produces `NOT RECONCILED`. Phase R7c wiring status does **not** change the proof verdict — `RECONCILED` means "unit correctness proven," which remains true regardless of wiring.

**Runtime-enforcement gate (separate from proof verdict)**: `prd_set_pass.sh` requires that every safety-critical AT is `PROVEN-INTEGRATED` (not just `PROVEN-UNIT`). A story can be `RECONCILED` (proof is valid) but still blocked from passing because its guards aren't wired. This separation preserves spec-driven truth (the unit proof is still true) while eliminating false signals at the capital-risk layer.

- `PROVEN-INTEGRATED` on all safety-critical ATs → pass-eligible
- `PROVEN-UNIT` on any safety-critical AT → blocked; requires integration story
- `PROVEN-UNIT` on non-safety-critical ATs (observability, metrics) → pass-eligible; track as debt

**Phase numbering**: Part A uses Phases 1–7. Part B uses Phases R1–R7 (the "R" prefix distinguishes reconciliation phases from authoring phases).

**Review rounds vs. phases**: A "review round" is a phase where an agent evaluates existing artifacts without modifying them. Part A has 3 review rounds (Phase 2, Phase 4, Phase 7). Part B has 5 review rounds: Cycle 1 (R2 lead eval, R3 cross-review), self-review (R5b), and Cycle 2 (R6 verify, R7 post-reconciliation). Patch phases (3, 6, R5) are not review rounds.

---

# Part A: Premortem Authoring Process

## Why This Process Exists

A single agent writing premortems sequentially produces consistent but blind-spotted output. The agent's own biases (enforcement point labeling, assumption rigor, economic risk calibration) propagate uniformly across all documents. No single-pass self-review catches systemic patterns because the same agent that introduced the pattern evaluates it.

This process uses **adversarial cross-review** to surface issues that the original author cannot see, then **targeted patching** to fix them without rewriting from scratch.

## Process Overview

```
Phase 1: Parallel Write     (4 agents, grouped by domain)
Phase 2: Lead Evaluation    (1 lead rates all outputs)
Phase 3: Targeted Patch     (4 agents fix Phase 2 findings)
Phase 4: Cross-Review       (each agent reviews ALL other agents' work)
Phase 5: Synthesis          (lead compiles cross-review, identifies net-new findings)
Phase 6: Final Patch        (4 agents fix Phase 5 findings)
Phase 7: Verify             (lead confirms all fixes applied)
```

Total: 7 phases, 3 review rounds (Phase 2 lead eval, Phase 4 cross-review, Phase 7 final verify).

---

## Phase 1: Parallel Write

### Setup

1. **Create a worktree** on a dedicated branch to isolate premortem work from implementation:
   ```bash
   git worktree add ../wt_<name> -b premortem/<slice> main
   ```

2. **Gather context** for agents:
   - `plans/prd.json` — story definitions, ATs, scope, dependencies, loss_mode
   - `specs/CONTRACT.md` — AT anchors, normative clauses, MUST/SHOULD/MAY
   - `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` — the template (§0 through §10, eleven sections total)

3. **Create agent team** with 4 writers grouped by domain affinity:
   - Stories that share files, ATs, or subsystems go to the same writer
   - This ensures each writer understands the cross-story dependencies within their batch

### Grouping Strategy

Group stories so that:
- **Shared file ownership** stays in one batch (e.g., stories touching `execution/dispatch_map.rs` together)
- **Dependency chains** stay in one batch (e.g., S1-011 structs -> S1-002 derivation -> S1-003 cache)
- **Batch sizes are balanced** by estimated complexity, not just story count — a batch of 2 complex stories may take longer than a batch of 4 simple ones

Example grouping for Slice 1 (13 stories):

| Agent | Domain | Stories |
|-------|--------|---------|
| writer-infra | Scaffolding, config, QA | S1-001, S1-008, S1-009, S1-010 |
| writer-instrument | Venue types, cache, observability | S1-002, S1-011, S1-003, S1-006 |
| writer-dispatch | Order sizing, dispatch mapping | S1-004, S1-005, S1-007 |
| writer-expiry | Lifecycle, CI gates | S1-012, S1-013 |

### Agent Instructions

Each writer agent receives the context files and the explicit instruction: **write as if code does not exist yet** — no peeking at implementation. The agent writes one `<STORY-ID>_premortem.md` per story, filling all sections §0-§10.

### Output

- One premortem file per story in `reviews/premortems/`
- All agents run in parallel; wall-clock time = slowest agent

---

## Phase 2: Lead Evaluation

### What the lead does

The lead (human or coordinator agent) reads every premortem and evaluates each agent's batch on these criteria:

| Criterion | What it measures |
|-----------|-----------------|
| Template adherence | All sections present, tables formatted, checklists filled |
| Clause audit quality | ATs traced to normative clauses, no informational-only ATs |
| Failure mode depth | Non-obvious modes identified, not just happy-path inversions |
| Wrong-impl gate | Wrong impls that are *easier* than correct, with tightenings |
| Economic risk calibration | Quantified worst case, not generic "financial loss" |
| Cross-story awareness | Hot zones, shared files, dependency risks identified |
| Factual accuracy | Contract citations correct, formula references match CONTRACT.md |

### Scoring

Rate each agent's batch on a four-level scale:

| Rating | Meaning |
|--------|---------|
| **PASS** | No significant issues; minor formatting only |
| **PASS-WITH-ISSUES** | Content is sound but specific gaps need patching |
| **NEEDS-PATCH** | Multiple issues; batch requires targeted fixes before cross-review |
| **REJECT** | Fundamental problems (wrong ATs, fabricated citations); batch must be rewritten |

Identify **specific** issues per file (not vague "could be better"). Categorize each issue as:
- **Factual error** — wrong formula, wrong AT reference, wrong file path
- **Logic gap** — contradiction between sections, missing TRIP/NON-TRIP
- **Depth gap** — section is present but superficial
- **Formatting** — template deviations, symbol errors

Flag any story where two reviewers disagree by more than one level (e.g., PASS vs NEEDS-PATCH) for investigation.

### Output

A rated list of agents with per-file issue descriptions. This becomes the input to Phase 3.

---

## Phase 3: Targeted Patch (Round 1)

### What happens

Each writer agent receives **only the issues identified for their batch** and applies surgical fixes:

- Factual errors: correct the specific value/reference
- Logic gaps: add missing reasoning or resolve contradictions
- Depth gaps: add the specific analysis that was missing
- Formatting: fix symbols, table formatting, template deviations

### Rules

- **Do not rewrite sections** — fix only what was flagged
- **Use Edit tool** with exact old_string/new_string replacements
- **Verify after edit** — re-read the file to confirm the fix didn't break surrounding content
- **Escalation rule**: If fixing an issue requires changing more than ~30% of a section's content, stop and escalate to the lead. A section that needs that much change was fundamentally wrong — the lead must decide whether to rewrite or restructure.

### Output

Updated premortem files with Phase 2 issues resolved.

---

## Phase 4: Cross-Review

This is the critical phase that catches what the lead evaluation missed.

### Design Principle

Each reviewer evaluates **ALL premortems they did NOT write**. This is essential:
- A reviewer who only sees one other batch cannot detect systemic patterns
- Cross-batch visibility reveals enforcement point mislabeling, AT ownership conflicts, and assumption rigor inconsistencies that only appear when you compare 10+ documents side by side

### Setup

4 reviewer agents, each assigned the complement of their original writing batch:

| Reviewer | Wrote | Reviews (count) |
|----------|-------|-----------------|
| reviewer-A (was writer-instrument) | S1-002, 011, 003, 006 | All 9 others |
| reviewer-B (was writer-dispatch) | S1-004, 005, 007 | All 10 others |
| reviewer-C (was writer-expiry) | S1-012, 013 | All 11 others |
| reviewer-D (was writer-infra) | S1-001, 008, 009, 010 | All 9 others |

(Note: Review counts differ because each agent wrote a different number of stories. This is expected.)

### Scoring Dimensions

Each reviewer scores every premortem on the same 7 criteria used in Phase 2, producing a per-criterion assessment and an overall rating.

### Required Output Format

Each reviewer writes `CROSS_REVIEW_by_<X>.md` containing:
1. Per-premortem assessment table (7 criteria + overall rating)
2. **Strengths** (2-3 specific observations with section references)
3. **Weaknesses** (2-3 specific observations with section references)
4. **Suggestion** (one concrete, actionable fix per premortem)
5. Batch summary table (all ratings in one table)
6. Overall assessment identifying systemic patterns across all reviewed premortems

### What Cross-Review Catches That Lead Evaluation Misses

From the Slice 1 pilot, cross-reviewers found 8 issues the lead missed:

| Finding | Why Lead Missed It |
|---------|--------------------|
| AT-104 dual ownership (S1-003 + S1-006) | Lead evaluated each file independently, didn't cross-reference AT claims |
| Enforcement point mislabeling across 5 stories | Lead normalized "DispatcherChokepoint" as acceptable; reviewers who wrote different labels noticed the inconsistency |
| Pending assumptions marked GREEN in 5 stories | Lead focused on content quality, not checklist honesty |
| Missing metric ownership in S1-007 | Lead checked the metric name was present, not whether any story owned its registration |
| S1-003 contract citation listed as assumption | Lead treated assumptions at face value; reviewer recognized it as a known CONTRACT.md clause |
| S1-012 assumption vs. decision contradiction | Lead read each section forward; reviewer compared assumption #3 against decision #4.2 |
| S1-011 wrong serde mitigation | Lead accepted `deny_unknown_fields` as plausible; reviewer knew it rejects extra fields, not missing ones |
| S1-008 mark_price vs index_price | Lead caught a different error in S1-008 (wrong downstream stories) and didn't double-check the formula |

### Key Insight

Cross-review works because **different writers bring different blind spots**. The writer-dispatch agent, having deeply studied tolerance formulas and dispatch mechanics, naturally caught enforcement point errors in stories about data structs. The writer-expiry agent, having dealt with complex state machine interactions, caught assumption-vs-decision contradictions in other stories.

**Single-reviewer evaluation has diminishing returns; multi-reviewer cross-evaluation has compounding returns.**

---

## Phase 5: Synthesis

### What the lead does

1. Read all 4 `CROSS_REVIEW_by_<X>.md` files
2. Compile a **consensus assessment table** — aggregate each story's rating across all reviewers. Flag any story where reviewers disagreed by more than one level (e.g., PASS vs NEEDS-PATCH) for investigation.
3. Identify **net-new findings** — issues raised by cross-reviewers that the lead's Phase 2 evaluation missed
4. Categorize findings by priority:
   - **Must fix before implementation** — factual errors, contradictions, checklist dishonesty
   - **Should fix** — enforcement point labels, AT ownership clarification
   - **Nice to have** — depth improvements, additional test suggestions

### Output

A prioritized list of fixes grouped by file, ready for Phase 6 agents.

---

## Phase 6: Final Patch (Round 2)

### What happens

4 patch agents (same batch grouping as Phase 1) receive the synthesized fix list and apply surgical edits.
The same ~30% escalation rule from Phase 3 applies.

### Fix Categories from Slice 1

| Category | Example | Fix Pattern |
|----------|---------|-------------|
| Factual error | `mark_price` -> `index_price` | Direct string replacement |
| Enforcement point mislabel | "DispatcherChokepoint" -> "ConfigLoader (soldier_infra::config)" | Replace in §6 table |
| STOPLIGHT dishonesty | GREEN with pending assumptions | Change to YELLOW, add debt register |
| AT ownership conflict | Two stories claim same AT | Narrow one story's claim to side-conditions |
| Section contradiction | Assumption says X, Decision says Y | Reconcile with evidence, update both |
| Wrong mitigation | `deny_unknown_fields` for missing fields | Replace with correct technique |
| Missing ownership | Metric referenced but no story owns it | Add ownership declaration in §8 |
| Assumption misclassification | Contract citation listed as assumption | Change to validated citation with evidence |

---

## Phase 7: Verify

The lead confirms:
- [ ] All flagged fixes were applied
- [ ] No new issues introduced by patches
- [ ] STOPLIGHT ratings are honest (no GREEN with pending assumptions)
- [ ] AT ownership is unambiguous (no two stories claim the same AT as primary enforcement)
- [ ] Enforcement points match the actual module, not a downstream consumer

---

## Abbreviated Process (Single High-Risk Story)

For a single story with MED or HIGH loss_mode, the full 4-agent process has more overhead than value. Use this variant:

| Full Process Phase | Abbreviated Equivalent |
|-------------------|----------------------|
| Phase 1: Parallel Write | 1 writer agent |
| Phase 2: Lead Evaluation | Lead evaluates the single premortem |
| Phase 3: Targeted Patch | Writer applies lead's fixes |
| Phase 4: Cross-Review | 2 cross-reviewers (each reviews the single premortem) |
| Phase 5: Synthesis | Lead reads both cross-reviews, identifies net-new findings |
| Phase 6: Final Patch | Writer applies synthesis findings |
| Phase 7: Verify | Lead confirms |

The abbreviated process preserves adversarial review (2 independent reviewers) while eliminating the parallel-write overhead. Do not abbreviate further for MED/HIGH stories — single-reviewer evaluation on safety-critical premortems is insufficient.

For **LOW risk** single stories: 1 writer + lead evaluation is sufficient. Skip cross-review.

## Metrics from Slice 1 Pilot

| Metric | Value |
|--------|-------|
| Stories | 13 |
| Writer agents | 4 |
| Reviewer agents | 4 |
| Phases | 7 |
| Total review rounds | 3 (lead eval + cross-review + final verify) |
| Issues found by lead (Phase 2) | ~15 across 13 files |
| Issues found by cross-review (Phase 4) | 8 net-new systemic issues |
| Cross-review lift | +53% more issues found vs lead-only evaluation |
| Score range before patching | 78-90 (per-agent batch average) |
| Score range after all patching | 84-93 (per-story cross-review average) |
| Consensus top 3 | S1-012 (93.3), S1-007 (93.0), S1-003 (92.7) |
| Wall-clock time | ~15 min per parallel phase |

### Part B Metrics (Implementation Reconciliation, Slice 1)

| Metric | Value |
|--------|-------|
| Stories reconciled | 13 |
| Reconcile agents | 4 (same domain batches as Part A) |
| Cross-review agents | 4 |
| Phases | R1-R7 (8 phases, including R5b self-review) |
| Total review rounds | 5 (Cycle 1: R2 + R3, Self-review: R5b, Cycle 2: R6 + R7) |
| Gaps found (Phase R4) | 1 P0, 3 P1, 12 P2, 6 DEFERRED, 1 SYSTEMIC |
| Tests before remediation | 890 |
| Tests after all R7 fixes | 899 (+9 net new) |
| R7a contract review findings | 1 (invalid enforcement_point enum) |
| R7b strategic review findings | 1 critical ("island of guards"), 3 secondary |
| R7c wiring audit | 11 WIRED (42%), 15 NOT-WIRED (58%) |
| R7d code review findings | 1 P1, 4 P2 (all fixed) |
| R7e devils advocate gaps | 5 actionable (all closed on recheck), 1 structural (accepted) |
| Final verdicts | 8 RECONCILED, 5 RECONCILED-WITH-DEBT, 0 NOT RECONCILED |
| Highest-value finding | R7b+R7c: most guards tested in isolation but not wired into production |

## When to Use This Process

| Scenario | Use which variant? |
|----------|-------------------|
| New slice with 5+ stories | Full process |
| Single high-risk story (MED/HIGH) | Abbreviated (see above) |
| Single low-risk story (LOW) | 1 writer + lead eval only |
| Retroactive audit of existing premortems | Phase 4-7 only (cross-review + patch) |
| Code exists, no premortems | Part A (write premortems), then Part B (reconcile) |

## Anti-Patterns

1. **Each reviewer only reviews one other batch** — Defeats the purpose. Systemic patterns only emerge when a reviewer sees 9+ documents from different authors. The first attempt at cross-review in Slice 1 used per-batch reviews and had to be restarted.

2. **Reviewer reviews their own work** — Self-review has near-zero marginal value after the writing phase. Assign complements only.

3. **Patches rewrite entire sections** — Rewrites introduce new errors. Surgical edits are verifiable. If a section needs full rewrite, it's a signal the original was fundamentally wrong — escalate to the lead via the ~30% rule.

4. **Skipping Phase 5 synthesis** — Without the lead comparing cross-review findings against their own Phase 2 evaluation, net-new findings are invisible. The whole point is to identify what the lead missed.

5. **Treating scores as absolute** — Ratings are calibration signals, not grades. A story rated PASS-WITH-ISSUES by all reviewers is fine. A story rated PASS by one reviewer and NEEDS-PATCH by another has a disagreement worth investigating.

6. **Skipping Phase R7c wiring audit** — The most dangerous false sense of security is a RECONCILED verdict on a guard that has zero production callers. Without the wiring audit, you can report "all 13 stories reconciled" while only 3 are actually enforced at runtime. This was the single highest-value finding in the Slice 1 pilot.

7. **Conflating proof verdicts with deployment readiness** — `RECONCILED` means "unit correctness proven" — this is a spec-driven truth that remains valid regardless of wiring. ~~(v1.3 and earlier: this was confused with deployment eligibility.)~~ As of v1.5: the proof verdict stays clean (`RECONCILED`), but `prd_set_pass.sh` enforces a **separate runtime-enforcement gate**: every safety-critical AT must be `PROVEN-INTEGRATED`. A story can be honestly `RECONCILED` and still blocked from passing because its guards aren't wired into production. The fix is an integration story, not a verdict change.

8. **Diff-only review in Cycle 1** — In reconciliation, the bug may already exist in old code. If the recon diff is zero (or tiny), a diff-scoped review reviews nothing. Cycle 1 reviewers must audit the full story proof scope, not just the changes.

9. **Skipping Phase R5b self-review** — Sending known-broken code to external review wastes the constraint (reviewer attention). The builder should run the 5-skill stack, fix P0/P1/P2 blockers, and produce a gate artifact before Cycle 2 begins. Without self-review, external reviewers rediscover issues the builder already saw.

10. **Cross-review recusal without secondary coverage** — When a reviewer recuses from their own batch (correct — self-review has near-zero marginal value), no one may be assigned as secondary reviewer for that batch's domain-specific edge cases. In Slice 1, the EXPIRY reviewer correctly recused from S1-012, but no other reviewer had the domain context to catch timestamp input-boundary gaps. **Fix**: When a reviewer recuses, assign a secondary reviewer from a different batch, or add a checklist item: "For recused stories, verify boundary inputs were tested by another reviewer."

11. **Treating saturating/checked arithmetic as sufficient input validation** — `saturating_sub` and `checked_mul` protect computation from overflow but do not validate that inputs are sane. In Slice 1, reviewers saw `saturating_sub` in the expiry guard and concluded "overflow-safe" without asking "what if `expiration_ms = u64::MAX` from a corrupt feed?" Saturating arithmetic is a defense layer, not input validation. Always ask: "Are the inputs themselves bounded?"

12. **Fake citation pass-through** — Agent cites a real file:line but the line is blank, a comment, or a helper function — not the actual enforcement gate. Spot-checks in Phase R3 catch some cases, but probabilistic spot-checking is insufficient for safety-critical ATs. **Fix**: (a) Automated AST/grep validation of all file:line citations — verify the cited line contains a function call or guard expression, not whitespace. (b) Introduce **Codebase Audit Anchors** (see below) — `#[audit_anchor(AT-920)]` attributes in Rust code that CI validates against `prd.json` AT lists. A citation that references a function without an audit anchor on a safety-critical AT produces a `CITATION_UNANCHORED` warning.

13. **Diff-only review gaming in Cycle 1** — Agent ignores the "Story Proof Scope" directive, reviews only the git diff (which may be empty for retro-audits), and marks PROVEN. Anti-pattern #8 warns against this in prose, but prose warnings are not enforceable. **Fix**: Require Cycle 1 reviewers to cite at least one observation from pre-existing code (not the recon diff). If every cited file:line in the review artifact also appears in `git diff`, the review is auto-rejected with `DIFF_ONLY_REVIEW_REJECTED`. This is enforced by `review_logged.sh` post-validation.

14. **DECISION_DIVERGENCE escape hatch** — Agent finds code doesn't match the premortem §4 decision. To avoid the work of writing a gap ticket + remediation plan, they mark it `INFO: Code is better` without evidence. **Fix**: Any divergence toward a **previously rejected option** in the premortem is automatically P1. The premortem already evaluated and dismissed that option — silently re-adopting it is suspicious, not "better." Only the lead can downgrade a rejected-option divergence from P1 to INFO, and the downgrade must include a written justification recorded in the evidence ledger.

15. **Silent debt deferral** — Agent marks a gap `DEFERRED` without creating a debt register entry, or sets `target_slice` to "TBD." The gap effectively disappears. **Fix**: Debt register must follow a strict JSON schema (see Phase R4). Phase R7f validation script checks that every `DEFERRED` gap in the evidence ledgers has a corresponding entry in the debt register with a valid `target_slice` (not "TBD"), `owner`, and `created_at`. Overdue debt (target_slice already passed) blocks the current slice's `prd_set_pass.sh`.

---
---

# Part B: Implementation Reconciliation Process (`/slice-reconcile`)

> Retroactive audit of existing code against premortems. Agents evaluate — they do not rewrite code in Phases R1-R4.
> Replaces `/slice-execute` when code already exists.

## Why This Exists

The standard workflow is: premortem first, then implement. But when stories were implemented before premortems were written (or when auditing a prior slice retroactively), the code already exists. Running `/slice-execute` would have agents re-implement what's already there — wasting effort and risking destructive rewrites.

Part B inverts the direction: instead of "implement what the premortem requires," agents **locate existing implementations and evaluate them against premortem requirements**. The output is an evidence ledger with verdicts, not code.

## Process Overview

```
Phase R1:  Parallel Reconcile       (4 agents, same domain batches as Part A)
Phase R2:  Lead Evaluation          (1 lead reviews all evidence ledgers)
Phase R3:  Cross-Review             (Cycle 1: story-scope audit, not diff-only)
Phase R4:  Synthesis + Gap List     (lead compiles gaps into actionable fix tickets)
Phase R5:  Remediation              (agents fix ONLY the gaps — no wholesale rewrites)
Phase R5b: Self-Review              (5-skill stack → fix blockers → gate artifact)
Phase R6:  Verify                   (lead confirms gaps closed, tests pass)
Phase R7:  Post-Reconciliation      (Cycle 2: fix-diff + AT regression)
  R7a:  Contract Review             (fail-open hazard scan on R5 diff)
  R7b:  Strategic Failure Review    (systemic risks across all stories)
  R7c:  Production Wiring Audit     (WIRED vs NOT-WIRED classification)
  R7d:  Code Review Expert          (SOLID, security, quality on full diff)
  R7e:  Devils Advocate             (mutation analysis on new/modified tests)
  R7f:  Debt Register Validation   (schema check on all DEFERRED gaps)
```

Total: 13 phases across Part B. R7a-R7c run in parallel; R7d-R7e run after R7a-R7c fixes are applied; R7f runs last (validates debt register completeness).

---

## Review Scope in Reconciliation

> The fundamental difference between implementation and reconciliation: in implementation, the diff IS the work. In reconciliation, the bug may already exist in old code and the recon diff may be zero. Reviewing only the diff reviews nothing.

### Two Review Cycles

| Cycle | When | Scope | Mental model |
|-------|------|-------|--------------|
| **Cycle 1** | After Phase R1 (initial audit) | Full story-scope implementation — the current code, not just what changed | "I inherited this code and I'm trying to break its proof" |
| **Cycle 2** | After Phase R5/R5b (remediation + self-review) | Fix diff + AT regression spot-check on affected proofs | "Did the fixes close the gaps without opening new ones?" |

### Story Proof Scope (Default Review Unit)

The default review scope is the **story proof scope** — not the diff, not the whole slice:

1. PRD item for the story (`jq '.stories["<ID>"]' plans/prd.json`)
2. `enforcing_contract_ats[]` — which ATs this story claims to enforce
3. Premortem (`reviews/premortems/<ID>_premortem.md`) — especially §4 decisions, §5 wrong-impls, §2 assumptions
4. Recon preflight artifact (AT proof audit from Step 1)
5. `scope.touch` files — the actual implementation source code
6. Proving test files from `implementation_tests[]`
7. Relevant CONTRACT.md sections only (not the whole contract)
8. Direct integration surfaces only if needed (e.g., PolicyGuard/WAL/TLSM) to validate causality

This is the right granularity: big enough to catch pre-existing bugs in old code, small enough to not drown the reviewer in unrelated files.

**The framing matters**: do not ask the reviewer to "review the code." Ask them to **perform a contract-proof audit** — prove or disprove that each claimed AT is actually enforced with causal proof.

### Escalation to Wider Slice Review

Escalate beyond story-scope only when:

| Trigger | Why | Action |
|---------|-----|--------|
| Story touches a shared primitive (PolicyGuard, TradingMode, WAL, dispatch gate) | Changes to shared primitives affect all consumers | Review all stories that depend on the primitive |
| Reviewer finds a pattern bug likely repeated elsewhere | Systemic issue, not isolated | Spot-check 2-3 other stories for the same pattern |
| Modified module is used by multiple stories (blast radius) | One fix can break siblings | Review affected siblings' AT proofs |

Default to story-scope. Reviewing the entire slice every time burns reviewer bandwidth on unchanged code and produces noise that hides real findings.

### TOC Principle: Protect Reviewer Attention

The constraint in the review process is **reviewer attention** — it is finite, expensive, and non-renewable within a review cycle. The highest-throughput setup:

1. **Self-review (R5b) should be heavy** — the builder does the evidence assembly, builds the proof table, runs 5 skills, fixes blockers
2. **Cycle 1 external review can be lighter** if self-review is high quality — the reviewer stress-tests and catches what slipped, rather than starting from scratch
3. **Cycle 2 is narrowly scoped** — only the fixes, only the affected AT proofs

Spend reviewer attention where it changes outcomes. Don't burn it on issues the builder already knows about (hence R5b fix-before-external) or on unchanged code that was already audited in Cycle 1.

### Review Basis Line (Hard Rule)

Every review artifact — self-review and external review — must include this line:

```
Review basis: STORY_SCOPE (Cycle 1)
```
or
```
Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)
```

This removes ambiguity and prevents agents from silently doing a shallow diff review when they should be auditing the full implementation.

**Enforcement**: Review artifact validation scripts (e.g., `review_logged.sh`, `postmortem_gate.sh`) should grep for the Review Basis line and warn if absent. A missing Review Basis line does not block the review but produces a `REVIEW_BASIS_MISSING` warning that the lead must acknowledge.

### Pre-Existing Code Citation Gate (Cycle 1 — Hard Rule)

Cycle 1 reviews must demonstrate engagement with the existing codebase, not just the reconciliation diff. This prevents the diff-only review gaming described in Anti-pattern #13.

**Rule**: A Cycle 1 review artifact must cite at least one **pre-existing enforcement point** (file:line of a guard/gate function) AND at least one **pre-existing proving test** (file:line of a test function) from the story proof scope — neither of which appears in the `git diff`. If every cited file:line in the review also appears in the diff, the review is auto-rejected with `DIFF_ONLY_REVIEW_REJECTED`.

This is stricter than "any pre-existing code observation." Citing a random utility function doesn't prove the reviewer engaged with the story's contract proof. Citing the actual enforcement point and its test does.

**Enforcement**: `review_logged.sh` post-validation:
1. Extracts all file:line citations from the review artifact.
2. Compares against `git diff --unified=0`.
3. Checks that at least one citation is tagged `enforcement` and at least one is tagged `test` (reviewers must label their citations).
4. Rejects if all citations are diff-only, or if enforcement/test citations are missing.

**Why this matters**: In reconciliation mode, the diff may be empty (zero code changes). A diff-only reviewer would review nothing and mark PROVEN. Requiring enforcement + test citations forces the reviewer to actually locate and evaluate the story's contract proof in the existing codebase — even when the result is "no issue found."

---

## Hard Gate: Premortem §10 STOPLIGHT

Before reconciliation begins, check each story's premortem STOPLIGHT:

| STOPLIGHT | Action |
|-----------|--------|
| RED | STOP — premortem has unresolved blockers. Fix premortem first. |
| YELLOW | Proceed — but all deferred items must appear in the evidence ledger's gap list. |
| GREEN | Proceed. |

If no premortem exists for a story, write one first (Part A). Reconciliation without a premortem is just ad-hoc code review — it misses the structured failure mode analysis that makes this process valuable.

---

## Phase R1: Parallel Reconcile

This phase is **read-only**. Agents do not write or modify any file.

**EMERGENCY ESCALATION**: If a read-only audit discovers a pre-existing critical vulnerability (e.g., fail-open path reachable in normal operation on a safety-critical gate), do not wait for Phase R5 remediation. Flag it immediately as `EMERGENCY-P0` in the output and notify the lead. The lead may authorize an out-of-band hotfix before the reconciliation process continues. The hotfix must still be tracked as a gap (GAP-XXX-E) and verified in Phase R6.

### Agent Prompt

Each reconcile agent receives the **reconciliation audit prompt** (see [Appendix A](#appendix-a-phase-r1-agent-prompt)). The prompt is also maintained as a standalone file at `plans/prompts/slice_reconcile_implement.md` for agent dispatch.

The prompt defines:
- READ FIRST checklist (premortem, contract, PRD, scope files)
- HARD GATE (premortem §10 STOPLIGHT check)
- MISSING ARTIFACT rule (NO-GO if required inputs are absent)
- PREMORTEM FALLBACK rule (use recon preflight as surrogate if no premortem exists)
- READ-ONLY INTEGRITY CHECK (`git status --porcelain` at start and end)
- 9 audit tasks (locate enforcement, verify fail-closed, verify causal proof, verify §5 wrong impls, verify §4 decisions, verify §2 assumptions, check observability, check design patterns, build remediation list)
- Required output format (Sections A-F)
- PROHIBITED actions list
- QUALITY BAR definition

The prompt is parameterized with `${STORY_ID}`, `${BASE_BRANCH}`, and `${HEAD}`.

> **SCOPE WARNING**: The agent prompt governs Phase R1 only. It is a STRICTLY READ-ONLY audit step.
> Phase R5 (remediation) uses a separate prompt.

### Per-AT Verdict Definitions

| Verdict | Meaning |
|---------|---------|
| **PROVEN** | Enforcement exists, test proves causality, fail-closed confirmed |
| **CLAIMED_NOT_PROVEN** | No enforcement found, or enforcement exists but no causal test |
| **WEAK_PROOF** | Test exists but checks "something happened," not which guard caused it |
| **UNTESTED_ENFORCEMENT** | Enforcement point and test both exist but are disconnected |
| **WRONG_IMPL_UNBLOCKED** | A §5 wrong impl has no tightening test to distinguish it from correct |
| **DEFERRED** | AT not yet implemented; tracked in debt register |

### Per-AT Evidence Checklist

For every AT claimed by the story's premortem, the agent fills this evidence row:

| Check | Expected Verdicts | Evidence Required |
|-------|-------------------|-------------------|
| Enforcement point exists in code? | PROVEN / CLAIMED_NOT_PROVEN | file:line — function/method name |
| Proving test exists? | PROVEN / CLAIMED_NOT_PROVEN | test file:line — test function name |
| Test proves causality? | PROVEN / WEAK_PROOF / UNTESTED_ENFORCEMENT | mechanism: dispatch_count / reject_reason / latch_reason |
| TRIP test exists? (if safety-critical) | PROVEN / CLAIMED_NOT_PROVEN | test name + what it trips |
| NON-TRIP test exists? (if safety-critical) | PROVEN / CLAIMED_NOT_PROVEN | test name + what it doesn't trip |
| Golden vector table exists? | PROVEN / MISSING_GOLDEN_VECTOR | test name + row count |
| Premortem §5 wrong impls blocked? | PROVEN / WRONG_IMPL_UNBLOCKED | which wrong impls have tightened tests, which don't |
| Fail-closed on error paths? | PROVEN / FAIL_OPEN | file:line — what happens on NaN/None/error |
| No unwrap() in production path? | PROVEN / UNWRAP_IN_PROD | rg "unwrap()" result for enforcement file |
| Observability on reject path? | PROVEN / SILENT_REJECT | structured log / metric / reason code at file:line |

### Per-Section Reconciliation

Beyond the per-AT checklist, the agent audits each premortem section against reality:

| Premortem § | What the agent checks | Evidence required |
|-------------|----------------------|-------------------|
| §0 Touch scope | Do the files listed in touch scope actually exist and contain the relevant code? | List actual files touched with line ranges |
| §1 Clause audit | Does the implementation enforce the correct contract clauses? | AT -> enforcement point mapping with file:line |
| §2 Assumptions | Were assumptions validated or killed? Do the predicted tests exist? | For each assumption: test name or "not tested" |
| §3 Failure modes | Are the predicted failure modes mitigated in code? | For each mode: mitigation location or "unmitigated" |
| §4 Open decisions | Was the chosen option actually implemented (not an alternative)? | Code evidence matching the decision |
| §5 Wrong-impl gate | Are the wrong impls blocked by tightened tests? | Test name per wrong impl, or "no tightening test" |
| §6 Proof plan | Does the actual test suite match the planned tests? | Planned test name -> actual test name mapping |
| §7 Economic risk | Does the drift metric exist and increment correctly? | Metric name at file:line |
| §8 Conflict scan | Were predicted hot-zone conflicts resolved? | Merge status / file ownership |

### Output Per Story

Each agent produces one evidence ledger per story as `<STORY-ID>_reconciliation.md`.

Worked example (S1-007):

```markdown
# Reconciliation Evidence: S1-007

## Summary
| Metric | Value |
|--------|-------|
| ATs checked | 1 (AT-920) |
| Checks passed | 8/10 |
| Checks failed | 2/10 |
| Verdict | PARTIAL |

## AT-920: Contracts/Amount Mismatch Rejection

| Check | Status | Evidence |
|-------|--------|----------|
| Enforcement point exists? | PROVEN | `dispatch_map.rs:142` — `validate_contracts_amount_match()` |
| Proving test exists? | PROVEN | `test_dispatch_map.rs:89` — `test_mismatch_beyond_tolerance_rejects` |
| Causality proof? | PROVEN | dispatch_count == 0, reject_reason == ContractsAmountMismatch |
| TRIP test? | PROVEN | `test_mismatch_beyond_tolerance_rejects` — mismatch > 0.001 triggers rejection |
| NON-TRIP test? | PROVEN | `test_within_tolerance_passes` — mismatch <= 0.001 passes through |
| Golden vector table? | WRONG_IMPL_UNBLOCKED | 8 rows present, but no absolute-vs-relative tolerance row from §5 |
| §5 wrong impls blocked? | WRONG_IMPL_UNBLOCKED | NaN guard present (line 156), but no test for absolute tolerance wrong impl |
| Fail-closed on error? | PROVEN | `if delta.is_nan() { return Err(ContractsAmountMismatch) }` at line 156 |
| No unwrap()? | PROVEN | `rg "unwrap()" dispatch_map.rs` — 0 matches |
| Observability? | SILENT_REJECT | Metric incremented but no `tracing::warn!` with diagnostic fields on rejection |

## §2 Assumptions Validated?

| # | Assumption | Premortem prediction | Actual status |
|---|-----------|---------------------|---------------|
| 1 | contract_multiplier > 0 | Test for multiplier=0 | PROVEN — `test_zero_multiplier_rejects` exists |
| 2 | Relative error formula | Verify at different scales | PROVEN — golden vectors include $1 and $100K scales |
| 3 | epsilon prevents div-by-zero | Test amount=0 | PROVEN — `test_zero_amount_mismatch` at line 134 |
| 4 | Degraded set atomically | Assert both in same response | PROVEN — test asserts reject + Degraded together |
| 5 | Check runs before dispatch | dispatch_count == 0 | PROVEN — causality proof in TRIP test |

## §4 Decisions — Implemented as Chosen?

| Decision | Chosen option | Implemented? | Evidence |
|----------|--------------|-------------|----------|
| Tolerance formula precision | Option A (f64 arithmetic) | YES | No decimal crate dependency; f64 at line 148 |
| Behavior when one field missing | Option A (skip check) | YES | Guard `if contracts.is_some() && amount.is_some()` at line 140 |
| NaN handling | Option A (fail-closed) | YES | `delta.is_nan()` guard at line 156 |

## §5 Wrong Impls — Blocked?

| Wrong impl | Blocked? | Evidence |
|-----------|---------|----------|
| Absolute tolerance instead of relative | NO | No golden vector testing large amounts where absolute != relative |
| Forget RiskState::Degraded | YES | TRIP test asserts both reject reason AND Degraded |
| Dispatch despite rejection | YES | TRIP test asserts dispatch_count == 0 |
| Wrong reject reason variant | YES | Test asserts exact `ContractsAmountMismatch` string |

## Gaps Found

1. **[P1][TEST_FIX] GAP-007-1**: Missing golden vector for absolute-vs-relative tolerance (§5 row 1). Need a test row with contracts=10, multiplier=10_000, amount=100_001 that distinguishes relative from absolute tolerance.
2. **[P1][CODE_FIX] GAP-007-2**: Missing structured log on rejection path. Metric increments but no `tracing::warn!` with `intent_id`, `computed_delta`, `tolerance` fields for operator debugging.

## Verdict: PARTIAL — 2 gaps require remediation
```

---

## Phase R2: Lead Evaluation

### What the lead checks

The lead reads every evidence ledger and evaluates:

1. **Citation accuracy** — Are citations real? Does `file:line` actually contain what's claimed?
2. **Verdict accuracy** — Is a PROVEN verdict justified, or did the agent give credit too easily?
3. **Gap completeness** — Did the agent miss gaps that should have been flagged?
4. **Cross-story consistency** — Are the same standards applied across all stories?

### Red Flags

- **PROVEN with no file:line** — Agent claimed something exists but didn't cite where
- **PROVEN on §5 wrong-impl with no tightening test** — Wrong impl is "blocked" but no test name given
- **WEAK_PROOF accepted as PROVEN** — A test exists, but it only checks that an error occurred, not which guard caused it
- **Gaps that are actually blockers** — A "gap" in a safety-critical gate is P0, not P1

---

## Phase R3: Cross-Review (Evidence Ledgers) — Cycle 1

Same cross-review structure as Part A Phase 4, but applied to evidence ledgers instead of premortems.

> **Scope**: This is a **Cycle 1** review. Reviewers audit the current story implementation (the story proof scope), not just the evidence ledger text or the reconciliation diff. The evidence ledger is the reviewer's guide, but the actual code is what gets reviewed.
>
> **External review prompt**: `plans/step_prompts/recon/cycle1.md` — frames the review as a contract-proof audit against the story proof scope.

### Why Cross-Review of Evidence Ledgers Is Distinct

Evidence ledger cross-review has failure modes that don't exist in premortem cross-review:

- **Familiarity bias**: An agent reconciling its own domain knows where the code lives and may accept "close enough" evidence. A cross-reviewer from a different domain will question whether the cited test actually proves causality, not just existence.
- **Citation accuracy**: Premortems contain predictions; evidence ledgers contain citations to real code. A cross-reviewer can spot-check whether `dispatch_map.rs:142` actually contains `validate_contracts_amount_match()`.
- **Verdict calibration drift**: An agent may apply a lenient standard to its own domain ("this is close enough to a TRIP test") that a cross-reviewer would reject. Calibration drift is invisible from within a single batch — it only shows when you compare verdicts across batches.

### What Cross-Review of Evidence Ledgers Catches

Examples of what cross-reviewers find that lead evaluation misses:

| Finding | Why Lead Missed It |
|---------|--------------------|
| Cited test doesn't exercise the enforcement point | Lead verified the test name existed; didn't check whether it called the enforcement function |
| PROVEN verdict where the "causality proof" only checks `result.is_err()` | Lead accepted the test as sufficient; cross-reviewer recognized it as WEAK_PROOF |
| §5 wrong impl marked "blocked" by a test that doesn't distinguish correct from wrong | Lead checked a test was cited; cross-reviewer read the test and found it would pass either impl |
| Enforcement point citation is to a helper function, not the actual gate | Lead accepted the citation; cross-reviewer traced the call graph and found the real gate upstream |

### What Reviewers Check

Each reviewer reads ALL evidence ledgers they did not write and evaluates:

| Dimension | What to look for |
|-----------|-----------------|
| Citation accuracy | Does the cited file:line actually contain the enforcement/test? Spot-check 2-3 per story. |
| Verdict calibration | Would you give the same per-AT verdict? Flag disagreements with reasoning. |
| Gap completeness | Did the agent miss something the premortem required but the code lacks? |
| §5 wrong-impl coverage | For each wrong impl marked "blocked" — does the cited test actually distinguish correct from wrong? |
| Consistency | Same standard across stories? PROVEN in one story shouldn't be WEAK_PROOF-equivalent in another. |

### Cycle 1 Reviewer Checklist

Reviewers must check each story against its story proof scope:

| Check | What to look for |
|-------|-----------------|
| **AT causal proof** | Does each claimed AT have a real proving test? Does it prove causality (dispatch count, reject reason, latch reason), not just existence? |
| **Premortem §4 decisions** | Implemented as chosen? If diverged, is it justified or a silent drift? |
| **Premortem §5 wrong impls** | Blocked by tightening tests? Would the wrong impl pass the current suite? |
| **Premortem §2 assumptions** | Turned into tests? Or explicitly killed with evidence? |
| **Fail-closed behavior** | For EACH input: (1) Missing/None → reject? (2) NaN/Inf → reject? (3) Negative where unsigned → reject? (4) Out-of-domain (type::MAX, % > 1.0, timestamp beyond sane range) → reject? (5) Corrupt/garbage → reject or degrade? "Invalid" means all five — not just NaN. No warn-and-continue? No silent fallback? |
| **Pattern conformance** | Gates use real quantities, state transitions explicit, small blast radius, idempotent where retries happen? |
| **Paper compliance** | PRD claims match reality? `implementation_tests[]` points to real proving tests? No fake "passes" logic? |

### Output

Each reviewer writes `RECONCILE_REVIEW_by_<X>.md` with:
1. **Review basis line**: `Review basis: STORY_SCOPE (Cycle 1)`
2. Per-story evaluation (verdict agreement or disagreement with reasoning)
3. Citation spot-checks (which citations were verified, what was found)
4. Missed gaps (gaps the original agent didn't flag)
5. Systemic patterns across all reviewed ledgers

---

## Phase R4: Synthesis + Gap List

### What the lead produces

**Aggregation method (v1.5)**: Do not rely on a single LLM agent to synthesize gaps across all stories — context window dilution causes silent finding drops. Instead:
1. Each Phase R3 cross-reviewer outputs structured gap findings in JSON format (one JSON array per story reviewed).
2. A deterministic script (`plans/aggregate_gaps.py` or equivalent) merges all JSON gap arrays into a unified list, deduplicating by AT + gap description.
3. The lead resolves conflicts (disagreements on priority, overlapping gap descriptions) and assigns final priorities — but does not perform the initial aggregation.

This separates mechanical aggregation (must be lossless) from judgment calls (appropriate for the lead).

**Structured "no gaps found" declarations (v1.6)**: "No findings" is also a claim that must be proven. When a cross-reviewer reports zero gaps for a story, they must output a structured checklist proving they checked all dimensions — not just an empty gap array:

```json
{
  "story_id": "S1-007",
  "reviewer": "reviewer-B",
  "gaps": [],
  "coverage_proof": {
    "at_causality_checked": true,
    "fail_closed_checked": true,
    "section_4_decisions_checked": true,
    "section_5_wrong_impls_checked": true,
    "observability_checked": true,
    "citation_spot_checks": ["dispatch_map.rs:142", "test_dispatch_map.rs:89"]
  }
}
```

The aggregation script validates that every story reviewed has either gaps or a complete `coverage_proof`. A story with an empty gap array and no coverage proof produces `UNCHECKED_CLEAN_REVIEW` — the lead must investigate whether the reviewer actually engaged with the story or skipped it.

A unified gap list across all stories, prioritized by severity. Cross-story systemic gaps (the same issue appearing in multiple stories) get a `GAP-SYSTEMIC-<N>` ID.

**Gap ID Format**:
- Story-specific gap: `GAP-<STORY-ID>-<SEQUENCE>` (e.g., `GAP-007-1`)
- Cross-story systemic gap: `GAP-SYSTEMIC-<SEQUENCE>` (e.g., `GAP-SYSTEMIC-1`)

| Priority | Criteria | Action |
|----------|----------|--------|
| **P0 — Blocker** | Safety-critical AT has no enforcement or no TRIP test | Must fix before story can be marked reconciled |
| **P1 — Gap** | Enforcement exists but wrong-impl tightening is missing, or observability absent | Should fix in current slice |
| **P2 — Debt** | Minor: test naming doesn't match premortem, enforcement point is in a slightly different location than predicted | Track in debt register, fix opportunistically |

### Debt Register Schema (Normative)

Every `DEFERRED` gap must have a corresponding entry in `reviews/reconciliations/<slice>/DEBT_REGISTER.json`. Entries without valid `target_slice` or `owner` block the current slice via Phase R7f validation.

```json
{
  "debt_items": [
    {
      "gap_id": "GAP-007-3",
      "story_id": "S1-007",
      "at_id": "AT-920",
      "description": "Observability: structured log on rejection path",
      "priority": "P2",
      "owner": "reconcile-dispatch",
      "target_slice": "S2",
      "created_at": "2026-02-21T15:00:00Z",
      "status": "open"
    }
  ]
}
```

**Required fields**: `gap_id`, `story_id`, `description`, `priority`, `owner` (not empty), `target_slice` (valid slice ID — not "TBD"), `created_at`, `status` (`open` | `resolved`).

**Phase R7f validation**: A deterministic script validates the debt register after Phase R7e:
1. Every `DEFERRED` gap in evidence ledgers has a matching `gap_id` in the debt register.
2. No entry has `target_slice: "TBD"` or empty `owner`.
3. Any debt item whose `target_slice` has already passed (i.e., that slice is complete) produces `OVERDUE_DEBT` — this blocks `prd_set_pass.sh` for the current slice until the item is re-targeted or resolved.

### Gap Entry Format

```markdown
### [P1][TEST_FIX] GAP-007-1: Missing absolute-vs-relative tolerance golden vector

- **Story**: S1-007
- **AT**: AT-920
- **Premortem §**: §5 wrong-impl row 1
- **What's missing**: Golden vector row that distinguishes absolute from relative tolerance
- **Proposed fix**: Add test row: `contracts=10, multiplier=10_000, amount=100_001` (0.001% off, relative tolerance passes, absolute tolerance rejects)
- **Owner**: reconcile-dispatch agent
```

---

## Phase R5: Remediation

### What happens

Agents fix ONLY the gaps from Phase R4. This is the only phase where agents modify code.

### Rules

1. **Fix only what's in the gap list** — No refactoring, no "while I'm here" improvements
2. **Each fix must cite the gap ID** — Commit messages reference GAP-XXX-Y
3. **New tests must follow premortem §6 proof plan** — TRIP/NON-TRIP, causality proof, isolation
4. **Golden vector rows must justify themselves** — "This row catches [wrong implementation from §5]"
5. **No `unwrap()` in production paths** — enforced by post-fix grep check
6. **Run existing tests before and after** — No regressions

### Fix Categories

| Gap type | Fix pattern |
|----------|------------|
| Missing enforcement | Implement the guard per premortem §6, fail-closed |
| Missing TRIP test | Add test that triggers the guard and asserts causality |
| Missing NON-TRIP test | Add test that doesn't trigger the guard and asserts pass-through |
| Missing golden vector row | Add row to existing table-driven test |
| Missing observability | Add `tracing::warn!` / `tracing::info!` with structured fields |
| Missing metric | Register counter/gauge, wire to code path |
| Wrong decision implemented | Rewrite to match premortem §4 chosen option (flag to lead if ambiguous) |

### Output

- Code changes (enforcement, tests, observability)
- Updated evidence ledger rows (GAP -> FIXED with new file:line citations)
- Test run output proving the fix works

---

## Phase R5b: Self-Review (Pre-External)

> In reconciliation mode, self-review is NOT "reviewing what I just wrote." It is a retroactive internal audit: "I inherited this code and I'm trying to break its proof." The builder uses the premortem as the checklist, not the diff.
>
> **Prompt**: `plans/step_prompts/recon/self_review.md` — parameterized with `${STORY_ID}`, `${BASE_BRANCH}`, `${HEAD}`.

### Why This Matters

Without structured self-review, known-broken code reaches external review, wasting Cycle 2 reviewer bandwidth on issues the builder could have caught. Self-review also produces a gate artifact that makes external review stronger — the reviewer can see what was already checked and focus on what wasn't.

### Step 3A: Run 5-Skill Stack (Audit Framing)

Run these on the **current story code** (story proof scope), not just the R5 diff:

| Skill | What it checks | Reconciliation focus |
|-------|---------------|---------------------|
| `/pr-review` | Implementation quality, SOLID, security | Code quality of enforcement points |
| `/failure-mode-review` | Failure paths, error handling | Fail-closed behavior on edge cases |
| `/strategic-failure-review` | Systemic risks, hidden assumptions | Cross-story interaction risks |
| `/contract-review` | Contract-vs-code alignment | AT proof alignment, fail-open hazards |
| `/devils-advocate` | Mutation resistance of tests | Simpler-Than-Correct Gate on all proving tests |

The premortem is the primary checklist. Walk each skill through:
- **§2 assumptions** — were they turned into tests or killed?
- **§4 decisions** — implemented as chosen?
- **§5 wrong-impl traps** — blocked by tightening tests?
- **§6 proof plan** — do actual tests match planned tests?
- **§10 STOPLIGHT gate** — still honest after remediation?

### Step 3B: Fix Obvious Blockers Immediately

If self-review finds P0/P1/P2:
1. Fix them now (in the same R5 branch)
2. Rerun the relevant skill(s) that found the issue
3. Then proceed to Phase R6 / Cycle 2 external review

**Do not send known-broken code to external review.** It wastes the constraint (reviewer attention) on issues you already know about.

### Step 3C: Write a Gate-Compliant Self-Review Artifact

**Machine-verifiable skill receipts (v1.5)**: Each skill in the 5-skill stack must produce a structured receipt. The self-review markdown alone is not a gate — it is a summary. The gate is the existence, integrity, and consistency of the receipt files.

**Receipt location**: `reviews/reconciliations/<slice>/receipts/r5b_<skill>.json`

**Receipt schema** (required fields):
```json
{
  "skill_name": "/pr-review",
  "story_id": "S1-007",
  "head_commit": "abc123f",
  "started_at": "2026-02-21T14:30:00Z",
  "ended_at": "2026-02-21T14:32:15Z",
  "exit_status": "completed",
  "artifact_paths": ["artifacts/story/S1-007/self_review/pr_review.md"],
  "finding_counts": { "P0": 0, "P1": 1, "P2": 3 }
}
```

| Skill | Receipt filename |
|-------|-----------------|
| `/pr-review` | `r5b_pr_review.json` |
| `/failure-mode-review` | `r5b_failure_mode_review.json` |
| `/strategic-failure-review` | `r5b_strategic_review.json` |
| `/contract-review` | `r5b_contract_review.json` |
| `/devils-advocate` | `r5b_devils_advocate.json` |

**Phase R6 gate check**: Before allowing Cycle 2 to begin, `step_supervisor.sh` (or the lead) must programmatically verify:
1. All 5 receipt files exist at `reviews/reconciliations/<slice>/receipts/`
2. Each receipt's `head_commit` matches the current HEAD (prevents stale receipts from a prior run)
3. Each receipt's `started_at`/`ended_at` timestamps are plausible and within the R5b window
4. Each receipt's `exit_status` is `"completed"` (not `"skipped"` or `"failed"`)
5. Each receipt's `artifact_paths[]` reference files that exist on disk

If any check fails, Cycle 2 is blocked with `SELF_REVIEW_UNPROVEN: <reason>`. This prevents agents from ticking markdown checkboxes without running the skills.

Output a `SELF_REVIEW_R5b.md` in `reviews/reconciliations/<slice>/` with:

```markdown
# Self-Review: Phase R5b

Review basis: STORY_SCOPE (Cycle 1) + FIX_DIFF (pre-Cycle 2)
HEAD: <commit hash>

## Skills Run
- [ ] /pr-review: <pass/findings>
- [ ] /failure-mode-review: <pass/findings>
- [ ] /strategic-failure-review: <pass/findings>
- [ ] /contract-review: <pass/findings>
- [ ] /devils-advocate: <pass/findings>

## Findings by Severity
| ID | Severity | Classification | Description | Status |
|----|----------|----------------|-------------|--------|

## Premortem Cross-Check
| § | Check | Status |
|---|-------|--------|
| §2 | Assumptions validated or killed? | |
| §4 | Decisions implemented as chosen? | |
| §5 | Wrong impls blocked? | |
| §6 | Proof plan matches actual tests? | |
| §10 | STOPLIGHT still honest? | |

## AT Proof Gaps
| AT | Gap | Status |
|----|-----|--------|

## Simpler-Than-Correct Gate
| Implementation | Pass? | Notes |
|---------------|-------|-------|

## Evidence Index

### Commands Run
| Command | Purpose | Result |
|---------|---------|--------|

### Test Outputs Cited
| Test | File:Line | AT Proved | Causal Mechanism |
|------|-----------|-----------|-----------------|

### File:Line References
| File:Line | What's There | Why It Matters |
|-----------|-------------|---------------|
```

The Evidence Index makes the self-review auditable — it documents what was actually inspected and how, preventing hand-waving ("covered elsewhere" without proof).

**Evidence must be both positive and negative.** In reconciliation, absence claims are half the audit.

- **Positive evidence** (proof something exists/works): `cargo test` PASS, file:line for enforcement point, file:line for proving test, review artifact path, `verify.meta.json` showing mode/head match
- **Negative evidence** (proof something is absent / no issue found): `rg "unwrap()" → 0 hits`, `git diff --name-only → only allowed files changed`, review summary `BLOCKING=0`, explicit note `NO_CODE_CHANGE_AUDIT_ONLY` with proof checks run

Without negative evidence, "no issues found" is opinion, not proof.

This artifact makes Phase R6 and Cycle 2 external review stronger — reviewers see what was checked and can focus on what wasn't.

---

## Phase R6: Verify

### What the lead confirms

1. **All P0 gaps closed** — no safety-critical AT without enforcement + TRIP test
2. **All P1 gaps closed or explicitly deferred** — with debt register entry if deferred
3. **No WEAK_PROOF on MED/HIGH loss_mode ATs** — escalated to CLAIMED_NOT_PROVEN if still present
4. **Tests pass** — `cargo test` / `./plans/verify.sh quick` green
5. **Evidence ledgers updated** — GAP entries now show FIXED status with citations
6. **No regressions** — diff review confirms fixes are additive, not destructive
7. **STOPLIGHT delta recheck (R6.5)** — Remediation is not neutral. Fixes introduce new dependencies, new assumptions, new failure modes, and new observability needs. Re-check premortem STOPLIGHT against the remediation diff by walking these sections:

   | Section | What to check against R5 diff | Downgrade trigger |
   |---------|-------------------------------|-------------------|
   | §2 Assumptions | Did R5 introduce new assumptions not in the original premortem? | New untested assumption → YELLOW |
   | §4 Decisions | Did R5 diverge from the premortem's chosen design option? | Silent divergence toward rejected option → YELLOW (investigate) |
   | §5 Wrong-impl table | Did R5 create a new bypass path not covered by existing tightening tests? | New unblocked wrong-impl → YELLOW |
   | Fail-closed behavior | Did any R5 fix introduce warn-and-continue, silent fallback, or unwrap()? | New fail-open path on safety-critical gate → RED (stop) |

   **Rules**: New untested assumption → downgrade to YELLOW. New unresolved safety risk → RED (stop, escalate to lead). If STOPLIGHT changes, all new deferred items must appear in the debt register. A stale GREEN is dishonest — this check prevents post-remediation false confidence.

8. **R5b skill receipts verified** — all 5 receipts exist, `head_commit` matches, timestamps plausible (see Phase R5b)

### Final Verdicts

Each story gets a final reconciliation verdict:

| Verdict | Meaning | What happens next |
|---------|---------|-------------------|
| **RECONCILED** | All premortem requirements verified in code. All P0/P1 gaps fixed. Unit correctness proven. | Proof complete; pass eligibility depends on runtime-enforcement gate (see below) |
| **RECONCILED-WITH-DEBT** | Requirements verified but P2 items deferred. Debt register populated. | Proof complete with tracked debt; pass eligibility depends on runtime-enforcement gate |
| **NOT RECONCILED** | P0 gaps remain open. Enforcement missing or tests absent. | Story blocked until remediation complete |

**`prd_set_pass.sh` gate requirements** (two independent gates):

1. **Proof gate**: Story verdict must be `RECONCILED` or `RECONCILED-WITH-DEBT`. A `NOT RECONCILED` story is always blocked.
2. **Runtime-enforcement gate**: Every safety-critical AT must be `PROVEN-INTEGRATED` (wired into production). `PROVEN-UNIT` on a safety-critical AT blocks the story — the guard provides zero runtime protection regardless of proof status. `PROVEN-UNIT` on non-safety-critical ATs (observability, metrics) does not block.
3. **Mechanical checks**: (a) all 8 workflow receipts present, (b) `verify.sh` passed, (c) `contract_review.json` contains `"decision": "PASS"`, (d) `loss_mode` fields are populated, (e) R5b skill receipts verified (see Phase R5b).
4. **Proof graph gate** (v1.7): `proof_graph.json` must exist at `artifacts/story/<ID>/proof_graph.json` and pass `python/proof_graph/validate.py --strict` (all 18 rules, WARNs promoted to ERRORs). Stories without a proof graph are blocked unless listed in `plans/proof_graph_exempt.txt` (legacy grandfathering). Exit code 10 on failure. Generate skeleton: `python3 python/proof_graph/scaffold.py <ID>`.

See `specs/WORKFLOW_CONTRACT.md` for the full gate checklist.

---

## Reconciliation vs. Implementation: Decision Matrix

| Situation | Use which process? |
|-----------|-------------------|
| Story not yet implemented, premortem exists | `/slice-execute` (implement from premortem) |
| Story already implemented, premortem exists | `/slice-reconcile` (audit code against premortem) — Part B |
| Story already implemented, no premortem | Part A (write premortem) then Part B (reconcile) |
| Story not yet implemented, no premortem | Part A (write premortem) then `/slice-execute` (implement) |
| Retroactive audit of entire slice | Part A (batch premortems) then Part B (batch reconcile) |

---

## Evidence Ledger Template

```markdown
# Reconciliation Evidence: <STORY-ID>

## Summary
| Metric | Value |
|--------|-------|
| ATs checked | N |
| Checks passed | X/Y |
| Checks failed | Z/Y |
| AT verdicts | AT-XXX: PROVEN / WEAK_PROOF / etc. |
| Story verdict | RECONCILED / PARTIAL / NOT RECONCILED |

## AT-XXX: <AT Title>

| Check | Status | Evidence |
|-------|--------|----------|
| Enforcement point exists? | | file:line |
| Proving test exists? | | test file:line |
| Causality proof? | | mechanism |
| TRIP test? | | test name |
| NON-TRIP test? | | test name |
| Golden vector table? | | test name + row count |
| §5 wrong impls blocked? | | which blocked, which not |
| Fail-closed on error? | | file:line |
| No unwrap()? | | grep result |
| Observability? | | file:line |

## §2 Assumptions Validated?

| # | Assumption | Premortem prediction | Actual status |
|---|-----------|---------------------|---------------|
| 1 | ... | ... | PROVEN/ASSUMPTION_UNTESTED — evidence |

## §4 Decisions — Implemented as Chosen?

| Decision | Chosen option | Implemented? | Evidence |
|----------|--------------|-------------|----------|
| ... | ... | YES/NO/DECISION_DIVERGENCE | file:line |

## §5 Wrong Impls — Blocked?

| Wrong impl | Blocked? | Evidence |
|-----------|---------|----------|
| ... | YES/WRONG_IMPL_UNBLOCKED | test name or "no tightening test" |

## Gaps Found

1. **[P0][CODE_FIX] GAP-XXX-1**: Description.
2. **[P1][TEST_FIX] GAP-XXX-2**: Description.
3. ...

## Verdict: RECONCILED / PARTIAL / NOT RECONCILED
```

---

## Minimum Evidence Pack (per Recon Story)

Every reconciled story must produce this set of artifacts. Missing items block the `RECONCILED` verdict.

| # | Artifact | Phase | What it proves |
|---|----------|-------|---------------|
| 1 | **Preflight artifact** (AT proof audit table) | R1 | Each AT has an enforcement point + proving test (or explicit gap) |
| 2a | **Self-review artifact** (with premortem cross-check + Evidence Index) | R5b | Builder tried to break the proof; §2/§4/§5 walked; 5-skill stack run |
| 2b | **Skill receipts** (5 JSON files in `reviews/reconciliations/<slice>/receipts/`) | R5b | Machine-verifiable proof that each skill was executed (`head_commit` matches, timestamps plausible, artifacts exist) |
| 3 | **Cycle 1 external review artifact(s)** (logged via `review_logged.sh`) | R3 | Independent auditor confirmed contract compliance on story proof scope |
| 4 | **Cycle 2 external review artifact(s)** (logged, or `RECON-CLEAN` exception — see below) | R7 | Fix diff verified; Cycle 1 findings closed; no regressions |
| 5 | **Review resolution artifact** | R6 | All BLOCKING findings closed; verdicts assigned with evidence |
| 6 | **Verify output** + `verify.meta.json` | R8 | `verify.sh` passed with correct mode/head; test count matches |
| 7a | **Test output + diff summary** *(if code changed)* | R5/R5b | Fixes compile, tests pass, diff is additive |
| 7b | **`NO_CODE_CHANGE_AUDIT_ONLY` section** *(if no code changed)* | R5b | Negative evidence: `git diff → 0`, proof checks still run, no fixes needed |
| 8 | **`proof_graph.json`** (v1.7) | R6 | Machine-verifiable proof graph: per-AT enforcement, tests, wiring, verdicts; validated by `validate.py --strict` at pass-flip |

**`RECON-CLEAN` exception (item 4)**: If the Cycle 1 review and self-review found zero BLOCKING findings and the story required no code changes, the Cycle 2 review may be replaced by an abbreviated `RECON-CLEAN` note in the resolution artifact. The note must include:
- Confirmation that preflight + self-review + Cycle 1 found `BLOCKING=0`
- `git diff → 0` proof (no code changed)
- Explicit statement: "Cycle 2 abbreviated: no fix diff to review"

This exception prevents spending reviewer attention on empty diffs while maintaining traceability.

---

## Phase R7: Post-Reconciliation Validation — Cycle 2

> Added after Slice 1 pilot. These checks caught critical issues that Phases R1-R6 missed.
>
> **Scope**: This is a **Cycle 2** review. R7a-R7c audit the fix diff for contract alignment, systemic risks, and wiring status. R7d-R7e audit the fix diff + run AT regression spot-checks (mutation analysis on affected tests). Reviewers must include `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)` in their output.
>
> **External review prompt**: `plans/step_prompts/recon/cycle2.md` — frames the review as closure verification + regression check.

After Phase R6 verdicts are assigned, run five validation passes. R7a-R7c are independent and can run in parallel. R7d-R7e run after R7a-R7c fixes are applied (they review the complete diff including R7 fixes).

**Cycle 2 scope for R7d-R7e**: The reviewer audits the remediation diff (R5 + R5b + R7a-c changes) plus a targeted re-check of AT proofs affected by those changes. If a fix modified a test for AT-960, the reviewer re-runs mutation analysis on AT-960's full proof chain — not just the changed lines. This catches fixes that close one gap but open another (the classic Cycle 2 failure mode).

### R7a: Contract Review on Remediation Diff

Run `/contract-review` (see `SKILLS/contract-review.md`) scoped to the Phase R5 diff.

**What it catches**: Fail-open hazards, invalid enum values, contract-vs-code drift introduced by remediation itself.

**How to run**:
1. Generate the diff: `git diff <pre-R5-commit>..HEAD`
2. Launch a contract review agent with the diff as input
3. The agent checks each change against CONTRACT.md for fail-open patterns

**Example finding from Slice 1**: S1-013 `enforcement_point` was changed to "CIGate" during remediation — but "CIGate" is not in the valid enum (`PolicyGuard|EvidenceGuard|DispatcherChokepoint|WAL|AtomicGroupExecutor|StatusEndpoint`). The contract review caught this; Phases R1-R6 did not.

**Output**: `reviews/reconciliations/<slice>/CONTRACT_REVIEW_R5.md`

### R7b: Strategic Failure Review

Run `/strategic-failure-review` (see `SKILLS/strategic-failure-review.md`) on the entire reconciliation output.

**What it catches**: Systemic risks that are invisible at the per-story level — emergent failures that only appear when you consider all stories together as a system.

**How to run**:
1. Launch a strategic failure review agent with access to all evidence ledgers, the gap list, and the final verdicts
2. The agent evaluates 22 dimensions including: hidden assumptions, cascading failures, human factors, operational readiness

**Example finding from Slice 1**: The "island of guards" problem — Slice 1 builds individual guards tested in isolation, but only S1-012's expiry guard is actually wired into the production pipeline. The remaining guards (dispatch validation, open permission, instrument cache TTL) have zero production callers. Per-story RECONCILED verdicts are honest at the function level but misleading at the system level.

**Output**: `reviews/reconciliations/<slice>/STRATEGIC_REVIEW_R5.md`

### R7c: Production Wiring Audit (Call Chain Check)

For each enforcement function marked PROVEN in Phase R1, verify it is reachable from a known entry point in the production call graph — not just that it has "at least one caller."

**What it catches**: The gap between "function works correctly when called" (PROVEN-UNIT) and "function is actually reachable at runtime" (PROVEN-INTEGRATED). Without this check, a reconciliation can report RECONCILED on a guard that is never executed in production. A single-caller check is necessary but not sufficient — the caller itself may be dead code (an intermediate function with no callers of its own).

**How to run**:
1. Extract the list of enforcement functions from all evidence ledgers
2. Define **entry points**: the known production entry points for the system (e.g., `main()`, `dispatch()`, `execute()`, `build_order_intent()`). Maintain this list in `specs/ENTRY_POINTS.md` or equivalent.
3. For each enforcement function, trace the call chain from the function up to an entry point:
   - **Preferred**: Use LSP `incomingCalls` recursively (up to 10 hops) to build the call tree from the enforcement function to an entry point
   - **Fallback**: Use `rust-callgraph` or manual grep + LSP `findReferences` to trace callers transitively
4. Classify each function as:
   - **WIRED** — reachable from a defined entry point via production code in `src/` (full call chain documented)
   - **NOT-WIRED** — only called from `tests/` or not reachable from any entry point
   - **PARTIAL** — type/struct exists in production but key methods have no callers, or caller chain terminates at a non-entry-point function (dead intermediate)

**Call chain evidence**: For WIRED functions, document the call chain: `entry_point() → ... → caller() → enforcement_function()`. This makes the wiring auditable — a reviewer can verify each link.

**Verdict enrichment**: Based on wiring status, split PROVEN verdicts:
- **PROVEN-INTEGRATED** — function works correctly AND is reachable from production code
- **PROVEN-UNIT** — function works correctly but has zero production callers (island guard)

**Example from Slice 1**:

| Wiring Status | Stories | Count |
|---------------|---------|-------|
| WIRED | S1-007, S1-008, S1-012 | 3 |
| PARTIAL | S1-005, S1-010, S1-011 | 3 |
| NOT-WIRED | S1-001, S1-002, S1-003, S1-004, S1-006 | 5 |
| N/A (CI gate) | S1-013 | 1 |
| N/A (scaffolding) | S1-009 | 1 |

**Output**: `reviews/reconciliations/<slice>/LSP_CALL_CHAIN_CHECK.md`

### R7d: Code Review Expert on Full Diff

Run the `code-review-expert` skill on the complete git diff (all Phase R5 + R7a-R7c changes).

**What it catches**: SOLID violations, security risks, error handling gaps, boundary condition bugs, and code quality issues in the remediation code itself. Reconciliation agents focus on contract alignment; a code review focuses on implementation quality.

**How to run**:
1. Run `git diff --stat` and `git diff` to scope all changes
2. Apply the code-review-expert checklist: SOLID + architecture smells, security scan, code quality scan, boundary conditions
3. Rate findings P0-P3

**Example findings from Slice 1**:
- P1: Idempotency test calling a pure function twice — tautological (type system guarantees purity)
- P2: Self-verifying assertion (`assert_eq!(variable, its_own_init_value)`)
- P2: Duplicate test with identical inputs to an existing sibling
- P2: Fragile assertion proving "a field is required" but not "which field"
- P2: Unicode normalization noise in prd.json from `ensure_ascii=True`

**Output**: `reviews/reconciliations/<slice>/CODE_REVIEW_R7.md`

### R7e: Devils Advocate (Test-the-Tests Mutation Analysis)

Run the `/devils-advocate` skill (see `SKILLS/devils-advocate.md`) on all proving tests for ATs that were flagged as gapped during reconciliation — not just new tests added during remediation.

**Scope rule**: If an AT was flagged in Phase R4 (any gap severity), R7e must cover the **full proving test suite** for that AT, including pre-existing tests. Pre-existing tests are where the vulnerabilities actually live — restricting mutation analysis to new tests only audits the patch, not the foundation.

**What it catches**: Tests that pass for the wrong reason. Two mutation categories are applied to each implementation under test:

**Structural mutations** (standard list): always-reject, always-allow, hard-coded return, off-by-one, ignore-one-field, swap-enum-variants.

**Input-boundary mutations** (added v1.3 — missed in Slice 1): For each enforcement function's inputs, test extreme/corrupt values at domain boundaries:

| Input mutation | Example | Expected |
|---------------|---------|----------|
| `type::MAX` | `expiration_ms = u64::MAX` | reject or degrade |
| Zero | `expiration_ms = 0` | reject or handle |
| Domain max + epsilon | `mm_util_kill = 1.01` (percentage > 100%) | reject |
| Corrupt/garbage | Unreasonable future date, negative unsigned | reject |

Any mutation from either category that passes the full test suite reveals a gap.

**How to run**:
1. Identify ATs requiring executable mutation evidence: any AT previously flagged `WEAK_PROOF`, `UNTESTED_ENFORCEMENT`, or `WRONG_IMPL_UNBLOCKED` in Phases R1-R4.
2. For each flagged AT, collect the **full proving test suite** (not just new tests from R5/R7 — pre-existing tests are where vulnerabilities live).
3. **Pre-filter (mental analysis)**: Apply structural and input-boundary mutations mentally to identify likely gaps. This is a fast pre-filter, not the gate — LLMs cannot reliably simulate Rust compiler behavior or complex state mutations.
4. **Gate (machine verification)**: Run `cargo mutants` using the appropriate scope path:

   **Fast path** (required for all flagged ATs): Mutants on the enforcement module, run against the AT's proving test targets.
   ```bash
   # Scoped: single enforcement file + AT-specific test targets
   cargo mutants --file crates/soldier_core/src/execution/<enforcement_file>.rs \
     -- --test <proving_test_target_1> --test <proving_test_target_2>
   # Example (S1-007 / AT-920):
   # cargo mutants --file crates/soldier_core/src/execution/dispatch_map.rs \
   #   -- --test test_dispatch_map --test test_order_size
   ```

   **Deep path** (required for P0/P1 gaps or ATs with repeated failures across review cycles): Mutants on all files in `scope.touch`, run against all test targets in the story proof scope.
   ```bash
   # Full story scope: all touched files + all story test targets
   cargo mutants --file <file1>.rs --file <file2>.rs \
     -- --test <test_target_1> --test <test_target_2> --test <test_target_3>
   ```

   Any surviving mutant is a confirmed gap **unless** it is an **equivalent mutant** — a mutation that is mathematically identical in behavior to the original code and cannot be killed by any test. Example: replacing `||` with `&&` when both operands are always simultaneously true/false (e.g., NaN/Inf propagation through arithmetic). Document equivalent mutants with a justification in the R7e output; they do not block `RECONCILED`.

   If `cargo mutants` is not available in the environment, document the gap as `MUTATION_GATE_SKIPPED` — this must be resolved before the story can reach `RECONCILED`.
5. Run the **Simpler-Than-Correct Gate** (see Glossary): for each implementation under test, ask "is there any implementation SIMPLER than the correct one that passes all tests?" If yes, the suite has a mutation gap that must be closed.
6. If gaps found, fix tests, then rerun from step 4

**Two-pass protocol**: Run the analysis once (initial), fix all gaps found, then rerun (recheck) to confirm closure. Both reports are kept for auditability.

**Example findings from Slice 1**:
- DA-002 (Medium): No test asserted `cancel_outcome == NotApplicable` for `Close` intent on expired instruments — an implementation ignoring the `intent` field would pass
- DA-003 (Low): All breach event tests used `ttl_s=3600.0` — hardcoded `ttl_s` in the struct would pass
- DA-006 (Low-Medium): Empty JSON test proved "a field is required" but per-field omission tests were missing

**Output**: `reviews/reconciliations/<slice>/DEVILS_ADVOCATE_R7.md` (initial) + `reviews/reconciliations/<slice>/DEVILS_ADVOCATE_R7_RECHECK.md` (after fixes)

### R7d-R7e Fix-and-Recheck Cycle

R7d and R7e may produce findings that require code changes. When this happens:

1. Fix all P0/P1 findings from R7d (code review) and all Medium+ gaps from R7e (devils advocate)
2. Rerun `cargo test` to confirm 0 failures
3. Rerun R7e (devils advocate recheck) to confirm gap closure
4. Rerun R7d (code review recheck) to confirm no new issues introduced

This cycle typically completes in one iteration. If it takes more than two iterations, escalate to the lead — the fixes are introducing new problems. The lead must decide whether to (a) accept the current state with debt, (b) reassign the batch to a different agent, or (c) narrow the fix scope to break the cycle.

---

### R7 Outputs Update Phase R6 Verdicts

If R7 reveals issues:
- **R7a contract violations**: Reopen the affected gap as P1, return to Phase R5 for remediation
- **R7b systemic risks**: Add to the debt register with a recommended Slice 2 story. **OPERATIONAL_ESCALATION_REQUIRED**: If R7b finds a HIGH `loss_mode` guard that is NOT-WIRED on a system that is live (accepting orders), the reconciliation process alone cannot mitigate the risk. Flag the finding as `OPERATIONAL_ESCALATION_REQUIRED` and immediately notify a human risk officer. The risk officer decides whether to suspend trading, add a temporary manual gate, or accept the risk with documentation. The reconciliation process resumes after the risk officer's decision is recorded. See the operational runbook (`specs/OPERATIONAL_RUNBOOK.md`) for escalation procedures. If no operational runbook exists, create a placeholder and escalate anyway — the absence of a runbook does not authorize continued unprotected trading.
- **R7c NOT-WIRED guards on safety-critical ATs**: Story verdict stays `RECONCILED` (proof is valid), but the runtime-enforcement gate in `prd_set_pass.sh` blocks the story from passing. Per-AT verdicts remain `PROVEN`; wiring qualifiers (`PROVEN-INTEGRATED` / `PROVEN-UNIT`) are tracked as a separate column. Create an integration story to wire the guard into the production pipeline. Non-safety-critical NOT-WIRED items (metrics, observability) are tracked as debt, not blockers.
- **R7d code quality issues**: Fix P0/P1 in place (same branch). P2 items may be deferred to debt register.
- **R7e mutation gaps**: Fix test gaps immediately, then rerun the analysis to confirm closure. Do not defer mutation gaps — a test that passes for the wrong reason is worse than no test.
- **R7f debt register violations**: If any DEFERRED gap lacks a valid debt register entry (missing `target_slice`, empty `owner`, or `target_slice: "TBD"`), block `prd_set_pass.sh` until resolved. If overdue debt is found (target_slice already passed), the item must be re-targeted to the current or next slice before the current slice can pass.

Updated final verdict table format:

| Story | Proof Verdict | R7c Wiring | Safety-Critical? | Pass-Eligible? |
|-------|--------------|------------|-----------------|----------------|
| S1-007 | RECONCILED | PROVEN-INTEGRATED | Yes | Yes |
| S1-003 | RECONCILED | PROVEN-UNIT | Yes | **No** (runtime gate: safety-critical AT not wired) |
| S1-006 | RECONCILED | PROVEN-UNIT | No (observability) | Yes (debt tracked) |

---

## File Layout (Full Process)

```
reviews/premortems/
  STORY_PREMORTEM_TEMPLATE.md                # Premortem template (§0-§10)
  PREMORTEM_RECONCILIATION_PROCESS.md        # This document
  S1-001_premortem.md                        # Per-story premortems
  ...
  CROSS_REVIEW_by_A.md                       # Premortem cross-reviews (Phase 4)
  ...

reviews/reconciliations/<slice>/               # One subdirectory per slice
  BATCH_DISPATCH_reconciliation.md           # Phase R1 evidence ledgers (grouped by batch)
  BATCH_EXPIRY_reconciliation.md
  BATCH_INFRA_reconciliation.md
  BATCH_INSTRUMENT_reconciliation.md
  RECONCILE_REVIEW_by_DISPATCH.md            # Phase R3 cross-reviews
  RECONCILE_REVIEW_by_EXPIRY.md
  RECONCILE_REVIEW_by_INFRA.md
  RECONCILE_REVIEW_by_INSTRUMENT.md
  GAP_LIST.md                                # Phase R4 unified gap list
  SELF_REVIEW_R5b.md                         # Phase R5b: self-review summary (markdown)
  receipts/                                   # Phase R5b: machine-verifiable skill receipts
    r5b_pr_review.json                        # /pr-review receipt
    r5b_failure_mode_review.json              # /failure-mode-review receipt
    r5b_strategic_review.json                 # /strategic-failure-review receipt
    r5b_contract_review.json                  # /contract-review receipt
    r5b_devils_advocate.json                  # /devils-advocate receipt
  CONTRACT_REVIEW_R5.md                      # Phase R7a: contract review on remediation diff
  STRATEGIC_REVIEW_R5.md                     # Phase R7b: strategic failure review
  LSP_CALL_CHAIN_CHECK.md                    # Phase R7c: production wiring audit
  DEVILS_ADVOCATE_R7.md                      # Phase R7e: mutation analysis (initial)
  DEVILS_ADVOCATE_R7_RECHECK.md              # Phase R7e: mutation analysis (recheck after fixes)
  DEBT_REGISTER.json                         # Phase R7f: structured debt register (strict schema)
  SUMMARY.md                                 # One-page roll-up: verdicts, metrics, links to all files

artifacts/story/<ID>/
  proof_graph.json                           # Per-story proof graph (v1.7): AT→enforcement→tests→wiring→verdict

plans/prompts/
  slice_reconcile_implement.md               # Phase R1 agent prompt (Appendix A source)

plans/step_prompts/recon/
  self_review.md                             # Phase R5b: self-review prompt (contract-proof audit + 5-skill stack)
  cycle1.md                                  # Phase R3/Cycle 1: external review prompt (story proof scope)
  cycle2.md                                  # Phase R7/Cycle 2: external review prompt (fix-diff + AT regression)
```

---

## Full Workflow Checklist (Part A + Part B)

### Part A: Premortem Authoring
- [ ] Worktree created on dedicated branch
- [ ] PRD entries extracted for all stories in scope
- [ ] CONTRACT.md AT anchors identified for each story
- [ ] Stories grouped into 3-4 balanced batches by domain affinity and estimated complexity
- [ ] Phase 1: All writer agents completed, one premortem per story
- [ ] Phase 2: Lead evaluated all outputs, issues documented per file
- [ ] Phase 3: Patch agents applied all Phase 2 fixes; escalations >30% resolved by lead
- [ ] Phase 4: Cross-reviewers assigned complement batches (not their own)
- [ ] Phase 4: Each reviewer evaluated ALL non-own premortems
- [ ] Phase 5: Lead synthesized cross-review findings, identified net-new issues; disagreements investigated
- [ ] Phase 6: Patch agents applied all Phase 5 fixes
- [ ] Phase 7: Lead verified all fixes applied, no regressions
- [ ] All STOPLIGHTs honest (no GREEN with pending assumptions)
- [ ] All AT ownership unambiguous
- [ ] All enforcement points match actual modules

### Part B: Implementation Reconciliation
- [ ] All stories have finalized premortems (Part A complete or pre-existing)
- [ ] Stories grouped into same domain batches as Part A
- [ ] Phase R1: All reconcile agents completed read-only audit, one evidence ledger per story
- [ ] Phase R1: Read-only integrity check confirmed (git status diff is empty)
- [ ] Phase R2: Lead evaluated all evidence ledgers for citation accuracy and verdict calibration
- [ ] Phase R3: Cross-reviewers evaluated ALL non-own evidence ledgers (Cycle 1: story-scope, not diff-only)
- [ ] Phase R3: Each review includes `Review basis: STORY_SCOPE (Cycle 1)` line
- [ ] Phase R3: Citation spot-checks documented
- [ ] Phase R3: Cycle 1 reviewer checklist applied (AT causal proof, §4/§5/§2, fail-closed, paper compliance)
- [ ] Phase R4: Lead compiled unified GAP-XXX-Y list with priorities
- [ ] Phase R4: Gap aggregation uses scripted JSON extraction (not single LLM synthesis across all stories)
- [ ] Phase R5: Remediation agents fixed all P0 and P1 gaps
- [ ] Phase R5: Each fix cites gap ID; commit messages reference GAP-XXX-Y
- [ ] Phase R5b: Self-review run (5-skill stack on story-scope code, not just diff)
- [ ] Phase R5b: All 5 skill receipts exist at `reviews/reconciliations/<slice>/receipts/` with `head_commit` matching HEAD
- [ ] Phase R5b: P0/P1/P2 blockers fixed before Cycle 2 external review
- [ ] Phase R5b: Gate artifact (`SELF_REVIEW_R5b.md`) written with premortem cross-check + AT proof gaps
- [ ] Phase R6: All P0 gaps closed, tests pass, no regressions
- [ ] Phase R6: No WEAK_PROOF verdicts remain on MED/HIGH loss_mode ATs (escalated to CLAIMED_NOT_PROVEN)
- [ ] Phase R6: STOPLIGHT re-evaluated if remediation introduced new assumptions or changed enforcement boundaries
- [ ] Phase R6: Skill receipts verified (existence + head_commit + timestamps + exit_status + artifact_paths) → no `SELF_REVIEW_UNPROVEN` blockers
- [ ] Phase R6: Evidence ledgers updated with FIXED status
- [ ] Final verdicts assigned: RECONCILED / RECONCILED-WITH-DEBT / NOT RECONCILED
- [ ] Debt register populated for any RECONCILED-WITH-DEBT stories
- [ ] Phase R7a: `/contract-review` run on Phase R5 diff; any violations fixed
- [ ] Phase R7b: `/strategic-failure-review` run on full reconciliation output; systemic risks documented
- [ ] Phase R7c: Production wiring audit completed; PROVEN verdicts annotated with WIRED/NOT-WIRED
- [ ] Phase R7c: Safety-critical PROVEN-UNIT ATs flagged as runtime-enforcement gate blockers (blocks `prd_set_pass.sh`)
- [ ] Phase R7c: OPERATIONAL_ESCALATION_REQUIRED flagged if HIGH loss_mode guard is NOT-WIRED on live system
- [ ] Phase R7d: `code-review-expert` run on full diff (Cycle 2); P0/P1 findings fixed
- [ ] Phase R7e: `/devils-advocate` run on full proving suite for gapped ATs (Cycle 2); `cargo mutants` executed on enforcement functions; Medium+ gaps fixed; recheck confirms closure
- [ ] Phase R7f: Debt register validation — all DEFERRED gaps have entries in `DEBT_REGISTER.json` with valid `target_slice`, `owner`, `created_at`; no overdue debt
- [ ] Phase R7: All Cycle 2 review artifacts include `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)` line
- [ ] Verdict table updated with R7c wiring + safety-critical columns
- [ ] Integration story created for PROVEN-UNIT safety-critical ATs (if any)
- [ ] Audit anchors added to enforcement points and proving tests for safety-critical ATs (if adopting v1.6 anchors)
- [ ] Proof graph: `proof_graph.json` generated via `scaffold.py`, filled in, and validates with `validate.py --strict` (or story listed in `plans/proof_graph_exempt.txt`)
- [ ] Minimum evidence pack complete for each story (preflight, self-review, Cycle 1, Cycle 2/RECON-CLEAN, resolution, verify, test output or NO_CODE_CHANGE, proof_graph.json)

---
---

# Appendix A: Phase R1 Agent Prompt

> **Scope**: This prompt governs **Phase R1 only**. It is a READ-ONLY audit step.
> Agents executing this prompt must not write or modify any file.
> Phase R5 (remediation) uses a separate prompt.
>
> This appendix is kept in sync with `plans/prompts/slice_reconcile_implement.md`.

## ROLE

You are the Builder in RECONCILIATION mode.
This step is named "implement" for workflow compatibility, but in recon mode it is a **READ-ONLY implementation audit**.
Do NOT write or modify production code, tests, PRD, or review artifacts in this step.

## STORY

- Story ID: `${STORY_ID}`
- Base Branch: `${BASE_BRANCH}`
- Current HEAD: `${HEAD}`
- Mode: RECONCILIATION (read-only)

## PURPOSE

Audit the already-implemented story against the premortem, contract, and PRD claims.
The **premortem is your primary audit checklist** — walk it section by section against the real code.
Find the real enforcement points, verify fail-closed behavior, verify causal proof quality, verify premortem decisions and wrong-impl tightenings, and produce a remediation plan.
No edits in this step.

## READ FIRST (required)

1. **The story premortem**: `reviews/premortems/${STORY_ID}_premortem.md`
   This is your primary audit checklist. Walk §0-§8 against reality.
2. Recon preflight artifact from Step 1 (contract -> AT -> test proof audit)
3. Prior postmortem(s) for this slice/story (if any)
4. `specs/CONTRACT.md` (relevant clauses for this story)
5. `specs/DESIGN_PATTERNS.md` §0 (if present / used in this repo)
6. `plans/prd.json` (the story entry for `${STORY_ID}`)
   - AT source: `jq '.stories["${STORY_ID}"].enforcing_contract_ats' plans/prd.json`
   - Scope source: `jq '.stories["${STORY_ID}"].scope.touch' plans/prd.json`
7. Files listed in the premortem §0 `scope.touch`

**MISSING ARTIFACT RULE**: If any of items 4-7 is missing from the workspace (file does not exist,
story ID not found in prd.json), immediately return:
```
GATE: NO-GO
Reason: MISSING_ARTIFACT: <filename or description>
```
Do not proceed. Do not guess or hallucinate the content of missing artifacts.

**Item 2 (recon preflight) is OPTIONAL when the premortem (item 1) exists.** The preflight's
value is as a surrogate when no premortem was written. When the premortem exists, it is already
your primary audit checklist and the preflight adds marginal value. If the preflight exists, read
it for additional context. If it does not exist and the premortem does, proceed without it.

**Item 3 (prior postmortems) is OPTIONAL.** If no postmortem exists for this story, proceed
without it. Note in output: `NO_PRIOR_POSTMORTEM`.

**PREMORTEM FALLBACK RULE** (item 1 only): If `reviews/premortems/${STORY_ID}_premortem.md` does not exist:
- Use the Step 1 recon preflight artifact as the **surrogate premortem**. It contains the
  contract-to-AT-to-test proof audit, which covers the core reconciliation checks (§1 clause audit,
  §6 proof plan equivalents).
- Skip premortem-specific checks (§2 assumptions, §4 decisions, §5 wrong impls) — these sections
  don't exist in the surrogate. Note in the output: `PREMORTEM_ABSENT: using recon preflight as surrogate.`
- The surrogate mode produces a narrower audit (enforcement + causal proof + fail-closed only).
  Mark the story for **retro-premortem** creation if it is safety-critical (MED/HIGH risk).
- Do NOT hallucinate premortem content. Do NOT invent §5 wrong impls from imagination.

**RULE PRIORITY**: When multiple rules apply, evaluate in this order:
1. **MISSING_ARTIFACT** (items 4-7) — if any required context file is absent → NO-GO. This fires first regardless of premortem status.
2. **PREMORTEM_FALLBACK** (item 1) — if premortem is absent but items 4-7 are present → use surrogate.
3. If both item 1 AND any of items 4-7 are missing → NO-GO (MISSING_ARTIFACT takes precedence).

## HARD GATE

Open the premortem §10 STOPLIGHT result before doing anything else:
- **RED**    -> STOP. Do not proceed. Report which blockers must be fixed first.
- **YELLOW** -> Proceed only if every gap is explicitly marked:
  - DEFERRED (future slice), or
  - FIX IN STEP 5
- **GREEN**  -> Proceed.

If the recon preflight from Step 1 also has a STOPLIGHT, check it too. The more restrictive gate wins.

## READ-ONLY INTEGRITY CHECK

Run at the **start** of this step:
```bash
git status --porcelain > /tmp/recon_start_status_${STORY_ID}.txt
```

Run at the **end** of this step (before writing READY FOR SELF_REVIEW):
```bash
git status --porcelain > /tmp/recon_end_status_${STORY_ID}.txt
diff /tmp/recon_start_status_${STORY_ID}.txt /tmp/recon_end_status_${STORY_ID}.txt
```

If the diff is non-empty, the workspace was modified during a read-only step.
Report: `READ_ONLY_VIOLATION: <list of changed files>` and include it in Section A (GATE RESULT).
A read-only violation does NOT automatically mean NO-GO — the audit findings are still valid —
but the violation must be reported so the lead can investigate.

---

## TASK (READ-ONLY AUDIT)

For each AT in `enforcing_contract_ats[]` for `${STORY_ID}`:

### 1) Locate the enforcement point

- Identify the real code path that enforces the behavior.
- Record: file, line number, function/method name, and the specific guard/branch.
- Cross-reference against premortem §6 proof plan: is this the enforcement point the premortem predicted?
- If no real enforcement point exists, mark: **CLAIMED_NOT_PROVEN**

### 2) Verify fail-closed behavior

- Check how the code behaves for:
  - Missing input (None / empty / absent field)
  - Stale input (expired cache, old timestamp)
  - Invalid input (negative where positive expected, wrong type)
  - NaN / Inf / contradictory values
  - Retries / restarts / partial state (if applicable)
- Confirm behavior is reject / degrade / halt (not warn-and-continue).
- If fail-open exists, flag it clearly as **FAIL_OPEN**.
- Run: `rg "unwrap()" <enforcement_file>` — any hits in production paths?
  - Acceptable only in tests or with a documented safety comment.
  - If found in production code, flag as **UNWRAP_IN_PROD**.

### 3) Verify causal proof (tests)

- Find the test(s) that prove this AT.
- Record: test file, line number, and test function name.
- Confirm the test proves causality using one or more of:
  - `dispatch_count` (0 vs 1)
  - `reject_reason` / `reason_code` (exact variant match)
  - `latch_reason` (specific latch set)
  - State transition (RiskState / TradingMode change)
  - No-dispatch proof (dispatch_count == 0)
  - Idempotency proof (same input twice -> same output)
- If the test only proves "something happened" but not **why** or **which guard caused it**, mark: **WEAK_PROOF**
  - Example — Strong proof: test asserts `dispatch_count == 0 AND reject_reason == ContractsAmountMismatch`
  - Example — Weak proof: test asserts `result.is_err()` but doesn't verify which error or which guard caused it
- If the enforcement point exists and a test exists, but the test does not actually exercise the enforcement point (they are disconnected), mark: **UNTESTED_ENFORCEMENT**
- For safety-critical ATs:
  - Does a TRIP test exist? (triggers the guard, asserts causality)
  - Does a NON-TRIP test exist? (doesn't trigger, asserts pass-through)
  - Does a golden vector / table-driven test exist?
    - How many rows?
    - Does it cover boundary cases (at threshold, off-by-one)?
    - Does it cover NaN / Inf / missing for each numeric input?
    - Does it include at least one case from premortem §5?
  - If no golden vector exists for a safety-critical gate, mark: **MISSING_GOLDEN_VECTOR**

### 4) Verify premortem §5 wrong impls are blocked

This is the highest-value check. The premortem identified specific wrong implementations that would pass naive tests.

- For each wrong implementation in the premortem's §5 table:
  - Find the tightening test that distinguishes correct from wrong.
  - If the test exists, record: test file, test function, what it catches.
  - If no tightening test exists, mark: **WRONG_IMPL_UNBLOCKED**
  - A wrong impl that is easier than the correct impl and has no tightening test is a **P0 gap**.

### 5) Verify premortem §4 decisions were implemented as chosen

The premortem recorded explicit design decisions with a chosen option and rejected alternatives.

- For each decision in §4:
  - Was the chosen option implemented? Cite file:line.
  - If a different option was implemented, flag: **DECISION_DIVERGENCE**
  - Decision divergence is not automatically wrong — but it must be explained.
  - **Auto-escalation rule (v1.6)**: If the code implements an option that was **explicitly rejected** in the premortem §4, the divergence is automatically **P1** (not INFO). The premortem already evaluated and dismissed that option — silently re-adopting it is suspicious, not "better." Only the lead can downgrade a rejected-option divergence from P1 to INFO, and the downgrade must include a written justification recorded in the evidence ledger.
  - If the code uses a novel approach (not the chosen option, not a rejected option), note it as INFO with a brief explanation of why it's acceptable.
  - If the code uses the rejected option **with documented justification** (e.g., a code comment explaining why the premortem's choice was wrong), note as P2 for lead review.

### 6) Verify premortem §2 assumptions

The premortem made assumptions that "must become a test or get killed."

- For each assumption in §2:
  - Does the predicted test exist? Record test name.
  - If the assumption was wrong, was it killed with evidence?
  - If the assumption is still relevant and has no test, mark: **ASSUMPTION_UNTESTED**

### 7) Check observability on reject/degrade paths

- For each rejection or degradation path:
  - Is there a structured log via `tracing` (warn/error level)?
  - Does the log include: reason code, relevant IDs (intent, instrument), diagnostic values?
  - Is there a metric that increments? (counter for reject events, gauge for state)
  - If a reject path is silent (no log, no metric, no reason code), mark: **SILENT_REJECT**

### 8) Check design-pattern conformance (audit only)

- Does the implementation use real quantities (not unsafe proxies)?
  - e.g., `net_edge_usd` vs a boolean flag that approximates it
- Is idempotency handled where retries are possible?
- Is state local / blast radius bounded?
- Any hidden assumptions that could become self-destructive later?
  - e.g., "this works because the cache is always fresh" — but staleness is possible

### 9) Build the remediation list (NO EDITS YET)

Classify every issue as one of:

| Classification | Meaning | When to use |
|---------------|---------|-------------|
| **CODE_FIX** | Fix in Phase R5 (remediation) | Missing enforcement, fail-open path, unwrap in prod |
| **TEST_FIX** | Fix in Phase R5 (remediation) | Missing TRIP/NON-TRIP, missing golden vector, weak proof |
| **PRD_FIX** | Fix in Phase R5 (remediation) | Wrong `implementation_tests[]`, stale `enforcing_contract_ats[]` |
| **DEFERRED** | Future slice | Include owner + target slice |
| **INFO** | Non-blocking, no action required | Observations, minor style notes, "better design" ideas |

### IMPORTANT

- If you discover a "better design," do NOT redesign here. Mark it:
  - **BLOCKING** if it creates loss/safety risk (must fix now)
  - **HARDENING** if it is an improvement but not required for contract compliance (defer)
- Decision rule for BLOCKING vs HARDENING:
  - Fail-open path reachable in **normal operation** (valid inputs, standard flow) -> **BLOCKING**
  - Fail-open path requires **adversarial or out-of-spec input** to reach -> **HARDENING** (document the assumption about what is out-of-spec)
- Do not conflate "different from premortem prediction" with "wrong."
  The premortem was written before code existed. The code may have found a better path.
  Only flag divergence as a problem when the code violates the contract or is fail-open.

---

## ALLOWED COMMANDS (read-only)

```
rg / grep / cat / jq / less          (inspection)
cargo check --workspace              (compilation check)
cargo test <target>                   (verification — run, don't create)
git diff / git show / git log        (inspection)
```

### PROHIBITED COMMANDS

```
sed -i / awk (with file modification) / any write command
cargo add / cargo rm                  (dependency changes)
```

---

## OUTPUT (required format)

### A) GATE RESULT

```
GATE: GO | NO-GO
Reason: <one line>
READ_ONLY_VIOLATION: <files> | NONE
```

### B) AT AUDIT TABLE

For each AT, provide all columns:

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|

Verdict values:
- **PROVEN** — enforcement exists, test proves causality, fail-closed confirmed
- **CLAIMED_NOT_PROVEN** — no enforcement found, or enforcement exists but no causal test
- **WEAK_PROOF** — test exists but doesn't prove causality (checks existence, not cause)
- **UNTESTED_ENFORCEMENT** — enforcement point exists and test exists, but the test does not exercise the enforcement point (they are disconnected)
- **WRONG_IMPL_UNBLOCKED** — §5 wrong impl has no tightening test
- **DEFERRED** — AT not yet implemented (tracked in debt register)

### C) PREMORTEM CROSS-REFERENCE

#### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|

#### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|

#### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|

### D) DESIGN RISK NOTES

List any risks discovered:
- Fail-open paths
- Hidden assumptions (e.g., "works because X is always true" but X can be false)
- Proxy decisions (using a flag where a real quantity is needed)
- Idempotency gaps
- Blast radius concerns
- Silent reject paths (no log, no metric)

### E) REMEDIATION PLAN (ordered by priority, smallest fix first within each priority)

```
[P0][CODE_FIX]  GAP-XXX-1: <description>
[P0][TEST_FIX]  GAP-XXX-2: <description>
[P1][TEST_FIX]  GAP-XXX-3: <description>
[P2][PRD_FIX]   GAP-XXX-4: <description>
[DEFERRED]      GAP-XXX-5: <description> (owner: <who>, target: <slice>)
[INFO]          <observation>
```

### F) SCOPE CHECK

- Confirm each file in premortem §0 `scope.touch` exists
- Note any scope drift (files touched that weren't predicted, or predicted files not touched)
- Note any files that should have been in scope but weren't listed

### FINAL LINE (exact)

```
READY FOR SELF_REVIEW
```

---

## PROHIBITED

- Do NOT edit production code
- Do NOT edit tests
- Do NOT edit `plans/prd.json`
- Do NOT create or modify review artifacts
- Do NOT create new files in any directory
- Do NOT run `./plans/prd_set_pass.sh`
- Do NOT claim a fix was applied in this step
- Do NOT skip the premortem §10 STOPLIGHT gate
- Do NOT skip reading the premortem — it is your primary audit checklist
- Do NOT treat "different from premortem" as automatically wrong — evaluate against the contract

---

## QUALITY BAR

A good reconciliation audit:
- Cites **file:line** for every PASS claim (no "I believe it exists")
- Flags every §5 wrong impl that lacks a tightening test
- Distinguishes WEAK_PROOF from PROVEN (a test that checks "something happened" is not proof)
- Notes DECISION_DIVERGENCE without assuming it's wrong — but auto-escalates rejected-option divergence to P1
- Produces a remediation plan that a different agent could execute without further context
- Never marks PROVEN on a safety-critical AT without verifying both TRIP and NON-TRIP tests

---

# Appendix B: Codebase Audit Anchors

> Added v1.6. Addresses anti-pattern #12 (fake citation pass-through).

## Problem

File:line citations are fragile. Code moves, lines shift, and a citation that was accurate at review time may point to a blank line or comment after a rebase. Worse, an agent can cite a real file and line that contains *some* code but not the *actual enforcement gate* — and spot-checks may miss the difference.

## Solution: `#[audit_anchor]` Attributes

Annotate enforcement points with machine-readable audit anchors:

```rust
/// Validates that contracts * multiplier ≈ amount within relative tolerance.
/// Rejects with ContractsAmountMismatch if delta exceeds threshold or is NaN.
#[audit_anchor(AT-920, TRIP, enforcement)]
fn validate_contracts_amount_match(
    contracts: f64,
    multiplier: f64,
    amount: f64,
    tolerance: f64,
) -> Result<(), RejectReason> {
    // ...
}
```

Annotate proving tests similarly:

```rust
#[cfg(test)]
#[audit_anchor(AT-920, TRIP, test)]
fn test_mismatch_beyond_tolerance_rejects() {
    // ...
}
```

### Anchor Format

```
#[audit_anchor(AT-ID, TRIP|NON_TRIP|GOLDEN_VECTOR, enforcement|test)]
```

- `AT-ID`: The acceptance test this code proves (must match `prd.json` `enforcing_contract_ats[]`)
- `TRIP|NON_TRIP|GOLDEN_VECTOR`: The proof category
- `enforcement|test`: Whether this is the enforcement point or a proving test

### CI Validation

A CI script (`plans/validate_audit_anchors.sh` or equivalent) checks:

1. **Completeness**: Every AT in `prd.json` with `passes=true` has at least one `enforcement` anchor and one `test` anchor in the codebase.
2. **Consistency**: No orphaned anchors (AT-IDs in code that don't exist in `prd.json`).
3. **Connectivity**: Every `enforcement` anchor has a corresponding `test` anchor for the same AT-ID (i.e., the enforcement is tested).

Anchor validation runs as part of `verify.sh full`.

### Adoption Strategy

Introduce incrementally — one story at a time during reconciliation. Phase R5 remediation adds anchors to enforcement points and proving tests. Over time, anchor coverage grows until CI can enforce completeness.

For stories reconciled before v1.6, anchors are added during the next reconciliation pass or dedicated anchor-sweep story.

---

# Appendix C: Future Roadmap

> Items identified during review but too large for v1.6. Tracked here for visibility.

## Machine-Verifiable Proof Graphs — ~~v2.0~~ **V1 SHIPPED (v1.7)**

> **Status**: V1 implemented. See `python/proof_graph/` for the full package.

V1 delivers per-story `proof_graph.json` with:
- **Schema**: Frozen dataclasses with `from_dict()` + deny-unknown-fields (`schema_version: 1`)
- **Validator**: 18 rules (`python/proof_graph/validate.py --strict`) — enforcement-critical at pass-flip
- **Scaffolder**: `python/proof_graph/scaffold.py` generates skeleton from prd.json + CONTRACT.md
- **Gate integration**: `prd_set_pass.sh` validates with `--strict` (exit 10 on failure)
- **Legacy exemption**: `plans/proof_graph_exempt.txt` grandfathers existing stories; shrinks via reconciliation
- **Stdlib-only**: Zero external dependencies

Key rules: R-001 (RECONCILED + BLOCKING contradiction), R-004 (stale test SHA), R-007 (phantom AT not in CONTRACT.md), R-008 (placeholder detection), R-015 (FAIL_OPEN_RISK), R-016b (safety-critical without TRIP tests).

**V2 roadmap** (remaining from original proposal):
- Cross-slice regression detection (detect if a later slice overwrites earlier AT ownership)
- Auto-generation from R1 evidence ledger output
- R4 aggregation script integration
- JSON Schema file with sync test (deferred from V1 to avoid dual-source-of-truth)

## Post-Rejection Blast-Radius Audit

Current reconciliation audits "does the guard work?" but not "what happens after the guard fires?" For safety-critical gates, add downstream impact analysis:

- **Idempotency**: If the guard rejects and the system retries, does the retry see the same state? Or does the rejection poison a WAL entry / cache / state machine?
- **Cascading effects**: Does rejection of one intent affect unrelated intents? (e.g., shared position state, rate limiters)
- **Recovery path**: After rejection, what is the operator's recovery procedure? Is it documented?

**Proposed implementation**: Add a §9 "Post-Rejection Analysis" section to the premortem template. During reconciliation, Phase R1 audits the downstream effects as Task 8.5 (between design-pattern conformance and remediation list).

**Blockers**: Expands the reconciliation scope significantly (~doubles R1 audit work per AT). Better introduced as a dedicated process for HIGH `loss_mode` stories only, or as a separate Phase R8.
