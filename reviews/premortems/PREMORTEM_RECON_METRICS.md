# Reconciliation Metrics & Reference

> Historical data, lessons learned, worked examples, rationale, and changelog.
> For execution instructions, see [RUNBOOK](RUNBOOK_PREMORTEM_RECON.md).
> For normative rules, see [POLICY](PREMORTEM_RECON_POLICY.md).
> For anti-patterns, see [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md).

---

## Table of Contents

- [Part A Metrics (Slice 1 Pilot)](#part-a-metrics-slice-1-pilot)
- [Part B Metrics (Slice 1 Reconciliation)](#part-b-metrics-slice-1-reconciliation)
- [S5-004 Metrics (Multi-Tool External Review)](#s5-004-metrics-multi-tool-external-review)
- [Lessons Learned from S5-004](#lessons-learned-from-s5-004)
- [Process Rationale](#process-rationale)
  - [Why Multi-Agent Authoring](#why-multi-agent-authoring)
  - [Why Cross-Review](#why-cross-review)
  - [Why Evidence Ledgers in Reconciliation](#why-evidence-ledgers-in-reconciliation)
  - [TOC Principle: Protect Reviewer Attention](#toc-principle-protect-reviewer-attention)
- [Worked Examples](#worked-examples)
  - [S1-007 Evidence Ledger](#s1-007-evidence-ledger)
  - [Gap Entry Format](#gap-entry-format)
  - [Agent Grouping (Slice 1)](#agent-grouping-slice-1)
  - [Cross-Review Findings Table](#cross-review-findings-table)
  - [Evidence Ledger Cross-Review Findings](#evidence-ledger-cross-review-findings)
- [Codebase Audit Anchors (Appendix B)](#codebase-audit-anchors)
- [Future Roadmap (Appendix C)](#future-roadmap)
- [Changelog (Appendix D)](#changelog)

---

# Part A Metrics (Slice 1 Pilot)

Collected during the first full execution of the 7-phase premortem authoring process on Slice 1 (13 stories, 4 agent teams, 3 review rounds).

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

---

# Part B Metrics (Slice 1 Reconciliation)

Collected during the first full execution of the R1-R7 reconciliation process on Slice 1 (13 stories, 4 domain batches, 5 review rounds).

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

---

# S5-004 Metrics (Multi-Tool External Review)

Collected during the S5-004 reconciliation, which introduced multi-tool review (3 tools), dual-prompt strategy (generic + enriched), and two full review cycles across 9 stories.

| Metric | Value |
|--------|-------|
| Stories reconciled | 9 (S1-002 through S1-012, excluding S1-001/008/009/013) |
| Review tools | 3 (Kimi K2.5, Opus 4.6, Codex gpt-5.3) |
| Prompt styles per tool | 2 (generic + enriched) |
| Review cycles | 2 (Cycle 1: pre-fix, Cycle 2: post-fix) |
| Total review artifacts | 68 (19 Codex C1 + 18 Codex C2 + 17 Opus C1 + 9 Opus C2 + 5 Kimi) |
| Unique Cycle 1 findings (body-verified) | 36 P1, 0 P0 |
| New Cycle 2 findings | 2 P1 (WAL), 1 P0 escalation (bare bool) |
| Resolution: FIXED | 17 (14 in Cycle 1 commit `de81950` + 3 in WAL fix `72d84db`) |
| Resolution: STRUCTURAL | 17 (blocked on Slice 2+ production wiring) |
| Resolution: DEFERRED | 5 (bare bool API, academic paths, contract clarification) |
| Tests before remediation | 890 |
| Tests after all fixes | 925 (+35 net new) |
| R7 5-skill stack on WAL fixes | All 5 converged on same root cause (CSP.3.2 violation) |
| Mechanical verification gates added | 3 (compile, callsite, test existence) |
| Finding unique % by prompt: Codex enriched | 39% (14 unique) |
| Finding unique % by prompt: Codex generic | 11% (4 unique) |
| Finding unique % by prompt: Opus generic | 14% (5 unique) |
| Finding unique % by prompt: Opus enriched | 8% (3 unique) |
| Multi-tool overlap | 28% (10 findings found by 2+ tools) |

---

# Lessons Learned from S5-004

## What Worked Well

1. **Dual-prompt review (generic + enriched)** -- Neither prompt alone found more than 60% of findings. Enriched found contract-level gaps (AT attribution, premortem conformance). Generic found code-level issues (NaN/Inf, panic safety, API design). Running both is non-negotiable.

2. **Multi-tool triangulation** -- Codex agent-mode explored deeply but produced noisy FINDINGS_SUMMARY counts (P0 inflation). Opus produced more structured, concise findings. Kimi caught batch-level issues. The tools complement rather than duplicate each other.

3. **5-skill stack convergence** -- When 3+ of 5 skills (PR review, failure-mode, strategic, contract, devils advocate) converge on the same finding, it's real. In S5-004, all 3 HIGH+ reviews found the same WAL CSP.3.2 violation independently. Convergence = high signal.

4. **Mechanical verification (`verify_mechanical.sh`)** -- Catches Themes 3/5/21/22 (non-compiling tests, phantom tests, dead callsites) with zero reviewer attention. Should run as a hard gate before any review cycle begins.

5. **Consolidated findings crosswalk** -- The 39-finding table with Resolution/Commit columns (`recon_S5-004_consolidated_findings.md`) was the single most useful artifact for tracking completion. Every finding mapped to FIXED/STRUCTURAL/DEFERRED with evidence.

## What Didn't Work

1. **Informal R4 synthesis** -- LLM synthesis of findings produced count contradictions (said "3 fixed" when table showed 11, said "all 9 stories" when data showed 6/9). Scripted JSON aggregation would have prevented this. The cycle2_summary required 5 corrections post-hoc.

2. **Missing per-story evidence ledgers** -- Without formal AT-by-AT verdicts per story, there's no structured way to assign RECONCILED/NOT-RECONCILED. The consolidated crosswalk was retroactively added but is a poor substitute.

3. **R5b self-review only on WAL fixes** -- The 5-skill stack ran on the WAL fix commit but NOT on the initial 14-finding remediation. This meant the initial fix had no formal self-review gate before Cycle 2.

4. **No debt register** -- 5 DEFERRED findings had no `DEBT_REGISTER.json` entries, violating the R7f gate. Added retroactively.

5. **FINDINGS_SUMMARY lines are unreliable** -- Codex auto-generated summary lines reported P0=16/P0=34 but only 1 actual P0 existed in review bodies. Always use body-verified counts, not summary aggregates.

6. **Blanket `--theirs` merge destroyed branch tooling** -- Resolving 8 merge conflicts with `git checkout --theirs` lost the enriched prompt infrastructure (`review_logged.sh`) and the detailed resolution prompt (`recon/resolution.md`). Both had to be manually restored from git history. Always diff each conflicted file against the merge base before blanket-accepting.

---

# Process Rationale

## Why Multi-Agent Authoring

A single agent writing premortems sequentially produces consistent but blind-spotted output. The agent's own biases (enforcement point labeling, assumption rigor, economic risk calibration) propagate uniformly across all documents. No single-pass self-review catches systemic patterns because the same agent that introduced the pattern evaluates it.

This process uses **adversarial cross-review** to surface issues that the original author cannot see, then **targeted patching** to fix them without rewriting from scratch.

## Why Cross-Review

Cross-review works because **different writers bring different blind spots**. The writer-dispatch agent, having deeply studied tolerance formulas and dispatch mechanics, naturally caught enforcement point errors in stories about data structs. The writer-expiry agent, having dealt with complex state machine interactions, caught assumption-vs-decision contradictions in other stories.

**Single-reviewer evaluation has diminishing returns; multi-reviewer cross-evaluation has compounding returns.**

Each reviewer evaluates **ALL premortems they did NOT write**. This is essential:
- A reviewer who only sees one other batch cannot detect systemic patterns.
- Cross-batch visibility reveals enforcement point mislabeling, AT ownership conflicts, and assumption rigor inconsistencies that only appear when you compare 10+ documents side by side.

## Why Evidence Ledgers in Reconciliation

Evidence ledger cross-review has failure modes that don't exist in premortem cross-review:

- **Familiarity bias**: An agent reconciling its own domain knows where the code lives and may accept "close enough" evidence. A cross-reviewer from a different domain will question whether the cited test actually proves causality, not just existence.
- **Citation accuracy**: Premortems contain predictions; evidence ledgers contain citations to real code. A cross-reviewer can spot-check whether `dispatch_map.rs:142` actually contains `validate_contracts_amount_match()`.
- **Verdict calibration drift**: An agent may apply a lenient standard to its own domain ("this is close enough to a TRIP test") that a cross-reviewer would reject. Calibration drift is invisible from within a single batch -- it only shows when you compare verdicts across batches.

## TOC Principle: Protect Reviewer Attention

The constraint in the review process is **reviewer attention** -- it is finite, expensive, and non-renewable within a review cycle. The highest-throughput setup:

1. **Self-review (R5b) should be heavy** -- 6 parallel reviewer agents run the skill stack (R5b.1), a planner agent synthesizes findings and writes a fix plan (R5b.2), a fixer agent executes the plan (R5b.3), and affected skills are re-run by fresh agents (R5b.4).
2. **Cycle 1 external review can be lighter** if self-review is high quality -- the reviewer stress-tests and catches what slipped, rather than starting from scratch.
3. **Cycle 2 is narrowly scoped** -- only the fixes, only the affected AT proofs.

Spend reviewer attention where it changes outcomes. Don't burn it on issues the builder already knows about (hence R5b fix-before-external) or on unchanged code that was already audited in Cycle 1.

---

# Worked Examples

## S1-007 Evidence Ledger

Full worked example of a reconciliation evidence ledger for story S1-007 (Contracts/Amount Mismatch Rejection).

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
| Enforcement point exists? | PROVEN | `dispatch_map.rs:142` -- `validate_contracts_amount_match()` |
| Proving test exists? | PROVEN | `test_dispatch_map.rs:89` -- `test_mismatch_beyond_tolerance_rejects` |
| Causality proof? | PROVEN | dispatch_count == 0, reject_reason == ContractsAmountMismatch |
| TRIP test? | PROVEN | `test_mismatch_beyond_tolerance_rejects` -- mismatch > 0.001 triggers rejection |
| NON-TRIP test? | PROVEN | `test_within_tolerance_passes` -- mismatch <= 0.001 passes through |
| Golden vector table? | WRONG_IMPL_UNBLOCKED | 8 rows present, but no absolute-vs-relative tolerance row from S5 |
| S5 wrong impls blocked? | WRONG_IMPL_UNBLOCKED | NaN guard present (line 156), but no test for absolute tolerance wrong impl |
| Fail-closed on error? | PROVEN | `if delta.is_nan() { return Err(ContractsAmountMismatch) }` at line 156 |
| No unwrap()? | PROVEN | `rg "unwrap()" dispatch_map.rs` -- 0 matches |
| Observability? | SILENT_REJECT | Metric incremented but no `tracing::warn!` with diagnostic fields on rejection |

## S2 Assumptions Validated?

| # | Assumption | Premortem prediction | Actual status |
|---|-----------|---------------------|---------------|
| 1 | contract_multiplier > 0 | Test for multiplier=0 | PROVEN -- `test_zero_multiplier_rejects` exists |
| 2 | Relative error formula | Verify at different scales | PROVEN -- golden vectors include $1 and $100K scales |
| 3 | epsilon prevents div-by-zero | Test amount=0 | PROVEN -- `test_zero_amount_mismatch` at line 134 |
| 4 | Degraded set atomically | Assert both in same response | PROVEN -- test asserts reject + Degraded together |
| 5 | Check runs before dispatch | dispatch_count == 0 | PROVEN -- causality proof in TRIP test |

## S4 Decisions -- Implemented as Chosen?

| Decision | Chosen option | Implemented? | Evidence |
|----------|--------------|-------------|----------|
| Tolerance formula precision | Option A (f64 arithmetic) | YES | No decimal crate dependency; f64 at line 148 |
| Behavior when one field missing | Option A (skip check) | YES | Guard `if contracts.is_some() && amount.is_some()` at line 140 |
| NaN handling | Option A (fail-closed) | YES | `delta.is_nan()` guard at line 156 |

## S5 Wrong Impls -- Blocked?

| Wrong impl | Blocked? | Evidence |
|-----------|---------|----------|
| Absolute tolerance instead of relative | NO | No golden vector testing large amounts where absolute != relative |
| Forget RiskState::Degraded | YES | TRIP test asserts both reject reason AND Degraded |
| Dispatch despite rejection | YES | TRIP test asserts dispatch_count == 0 |
| Wrong reject reason variant | YES | Test asserts exact `ContractsAmountMismatch` string |

## Gaps Found

1. **[P1][TEST_FIX] GAP-007-1**: Missing golden vector for absolute-vs-relative tolerance
   (S5 row 1). Need a test row with contracts=10, multiplier=10_000, amount=100_001 that
   distinguishes relative from absolute tolerance.
2. **[P1][CODE_FIX] GAP-007-2**: Missing structured log on rejection path. Metric increments
   but no `tracing::warn!` with `intent_id`, `computed_delta`, `tolerance` fields for
   operator debugging.

## Verdict: PARTIAL -- 2 gaps require remediation
```

---

## Gap Entry Format

The standard gap entry format for Phase R4 synthesis output:

```markdown
### [P1][TEST_FIX] GAP-007-1: Missing absolute-vs-relative tolerance golden vector

- **Story**: S1-007
- **AT**: AT-920
- **Premortem S**: S5 wrong-impl row 1
- **What's missing**: Golden vector row that distinguishes absolute from relative tolerance
- **Proposed fix**: Add test row: `contracts=10, multiplier=10_000, amount=100_001`
  (0.001% off, relative tolerance passes, absolute tolerance rejects)
- **Owner**: reconcile-dispatch agent
```

Gap JSON structure (used in R3 cross-review output):

```json
{
  "gap_id": "GAP-007-1",
  "at_id": "AT-920",
  "priority": "P1",
  "classification": "TEST_FIX",
  "premortem_section": "S5",
  "description": "Missing golden vector for absolute-vs-relative tolerance (S5 wrong-impl row 1)",
  "proposed_fix": "Add test row: contracts=10, multiplier=10_000, amount=100_001",
  "verdict_impact": "WRONG_IMPL_UNBLOCKED -> PROVEN (if fixed)"
}
```

**Required gap fields**: `gap_id`, `at_id`, `priority` (P0/P1/P2/DEFERRED), `classification` (CODE_FIX/TEST_FIX/PRD_FIX/DEFERRED/INFO), `description`, `proposed_fix`. Optional: `premortem_section`, `verdict_impact`.

**Gap ID Format**:
- Story-specific gap: `GAP-<STORY-ID>-<SEQUENCE>` (e.g., `GAP-007-1`)
- Cross-story systemic gap: `GAP-SYSTEMIC-<SEQUENCE>` (e.g., `GAP-SYSTEMIC-1`)

---

## Agent Grouping (Slice 1)

Example grouping for Slice 1 (13 stories), demonstrating domain affinity batching:

| Agent | Domain | Stories |
|-------|--------|---------|
| writer-infra | Scaffolding, config, QA | S1-001, S1-008, S1-009, S1-010 |
| writer-instrument | Venue types, cache, observability | S1-002, S1-011, S1-003, S1-006 |
| writer-dispatch | Order sizing, dispatch mapping | S1-004, S1-005, S1-007 |
| writer-expiry | Lifecycle, CI gates | S1-012, S1-013 |

Grouping principles:
- **Shared file ownership** stays in one batch (e.g., stories touching `execution/dispatch_map.rs` together).
- **Dependency chains** stay in one batch (e.g., S1-011 structs -> S1-002 derivation -> S1-003 cache).
- **Batch sizes are balanced** by estimated complexity, not just story count -- a batch of 2 complex stories may take longer than a batch of 4 simple ones.

Cross-review assignments (each reviewer reviews ALL premortems they did NOT write):

| Reviewer | Wrote | Reviews (count) |
|----------|-------|-----------------|
| reviewer-A (was writer-instrument) | S1-002, 011, 003, 006 | All 9 others |
| reviewer-B (was writer-dispatch) | S1-004, 005, 007 | All 10 others |
| reviewer-C (was writer-expiry) | S1-012, 013 | All 11 others |
| reviewer-D (was writer-infra) | S1-001, 008, 009, 010 | All 9 others |

---

## Cross-Review Findings Table

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

---

## Evidence Ledger Cross-Review Findings

Examples of what cross-reviewers of evidence ledgers find that lead evaluation misses:

| Finding | Why Lead Missed It |
|---------|--------------------|
| Cited test doesn't exercise the enforcement point | Lead verified the test name existed; didn't check whether it called the enforcement function |
| PROVEN verdict where the "causality proof" only checks `result.is_err()` | Lead accepted the test as sufficient; cross-reviewer recognized it as WEAK_PROOF |
| S5 wrong impl marked "blocked" by a test that doesn't distinguish correct from wrong | Lead checked a test was cited; cross-reviewer read the test and found it would pass either impl |
| Enforcement point citation is to a helper function, not the actual gate | Lead accepted the citation; cross-reviewer traced the call graph and found the real gate upstream |

---

## R3 Cross-Review No-Gaps Declaration Format

When a cross-reviewer reports zero gaps for a story, they must output a structured checklist proving they checked all dimensions:

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

A story with an empty gap array and no coverage proof produces `UNCHECKED_CLEAN_REVIEW` -- the lead must investigate whether the reviewer actually engaged with the story or skipped it.

---

## Step Supervisor Phase Mapping

> Core mapping: [RUNBOOK §3](RUNBOOK_PREMORTEM_RECON.md#3-mode-b--reconciliation-r1r7). Extended here with "What happens" commentary.

The `plans/step_supervisor.sh` and `plans/wf_step.sh` use a 9-step receipt chain. This table maps those steps to Part B reconciliation phases:

| `wf_step.sh` step | Part B phase(s) | Pod | What happens |
|--------------------|----------------|-----|-------------|
| `preflight` | R1 (Parallel Reconcile) | A | Read-only audit: locate enforcement, verify fail-closed, build evidence ledger |
| `implement` | R5 (Remediation) | A | Fix gaps from R4 gap list (only phase that modifies code) |
| `self_review` | R5b (Self-Review: R5b.1→R5b.2→R5b.3→R5b.4) | B | 6-skill stack (R5b.1), synthesis + fix plan (R5b.2), execute fixes (R5b.3), re-run affected skills (R5b.4), produce gate artifact + skill receipts |
| `cycle1` | R2 (Lead Eval) + R3 (Cross-Review) + R4 (Synthesis) | B | External story-scope audit, cross-review, gap aggregation |
| `fix` | R7a-R7c fixes | C | Apply contract review, strategic review, and wiring audit fixes |
| `cycle2` | R7d (Code Review) + R7e (Devils Advocate) + R7f (Debt Validation) | C | Post-remediation audit on fix diff + AT regression |
| `resolution` | R6 (Verify) | D | Lead confirms all gaps closed, assigns final verdicts, STOPLIGHT re-eval |
| `verify_full` | `verify.sh full` | D | Mechanical verification: clippy, tests, preflight gates |
| `pass` | `prd_set_pass.sh` | supervisor | Proof gate + runtime-enforcement gate + mechanical checks + proof graph gate |

**Note**: The `cycle1` step spans R2-R4 because the receipt tracks the completion of the entire Cycle 1 review round, not individual sub-phases. Similarly, `cycle2` spans R7d-R7f.

**Receipt system distinction**: `wf_step.sh` receipts (`.wf/receipts/<ID>/`) track workflow step completion. R5b skill receipts (`reviews/reconciliations/<slice>/receipts/`) track individual skill execution within R5b.1. R5b also produces `R5B_FIX_PLAN.md` (R5b.2) and `R5B_FIX_LOG.md` (R5b.3). These are complementary -- the workflow receipt proves the step ran, the skill receipts prove *how* reviews ran, and the fix plan/log prove *what* was planned vs changed.

---

## Debt Register Schema

> Canonical schema and validation rules: [POLICY §7](PREMORTEM_RECON_POLICY.md#7-debt-register-schema).

Location: `reviews/reconciliations/<slice>/DEBT_REGISTER.json`. See POLICY §7 for required fields, constraints, and R7f validation rules.

---

## Fix Categories Reference

Phase 6 (Part A) and Phase R5 (Part B) use different fix category tables. Both are included here for lookup.

### Part A Fix Categories (Premortem Patching)

| Category | Example | Fix Pattern |
|----------|---------|-------------|
| Factual error | `mark_price` -> `index_price` | Direct string replacement |
| Enforcement point mislabel | "DispatcherChokepoint" -> "ConfigLoader (soldier_infra::config)" | Replace in S6 table |
| STOPLIGHT dishonesty | GREEN with pending assumptions | Change to YELLOW, add debt register |
| AT ownership conflict | Two stories claim same AT | Narrow one story's claim to side-conditions |
| Section contradiction | Assumption says X, Decision says Y | Reconcile with evidence, update both |
| Wrong mitigation | `deny_unknown_fields` for missing fields | Replace with correct technique |
| Missing ownership | Metric referenced but no story owns it | Add ownership declaration in S8 |
| Assumption misclassification | Contract citation listed as assumption | Change to validated citation with evidence |

### Part B Fix Categories (Reconciliation Remediation)

| Gap type | Fix pattern |
|----------|------------|
| Missing enforcement | Implement the guard per premortem S6, fail-closed |
| Missing TRIP test | Add test that triggers the guard and asserts causality |
| Missing NON-TRIP test | Add test that doesn't trigger the guard and asserts pass-through |
| Missing golden vector row | Add row to existing table-driven test |
| Missing observability | Add `tracing::warn!` / `tracing::info!` with structured fields |
| Missing metric | Register counter/gauge, wire to code path |
| Wrong decision implemented | Rewrite to match premortem S4 chosen option (flag to lead if ambiguous) |

---

# Codebase Audit Anchors

> Added v1.6. Addresses anti-pattern #12 (fake citation pass-through).

## Problem

File:line citations are fragile. Code moves, lines shift, and a citation that was accurate at review time may point to a blank line or comment after a rebase. Worse, an agent can cite a real file and line that contains *some* code but not the *actual enforcement gate* -- and spot-checks may miss the difference.

## Solution: `#[audit_anchor]` Attributes

Annotate enforcement points with machine-readable audit anchors:

```rust
/// Validates that contracts * multiplier ~ amount within relative tolerance.
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

- `AT-ID`: The acceptance test this code proves (must match `prd.json` `enforcing_contract_ats[]`).
- `TRIP|NON_TRIP|GOLDEN_VECTOR`: The proof category.
- `enforcement|test`: Whether this is the enforcement point or a proving test.

### CI Validation

A CI script (`plans/validate_audit_anchors.sh` or equivalent) checks:

1. **Completeness**: Every AT in `prd.json` with `passes=true` has at least one `enforcement` anchor and one `test` anchor in the codebase.
2. **Consistency**: No orphaned anchors (AT-IDs in code that don't exist in `prd.json`).
3. **Connectivity**: Every `enforcement` anchor has a corresponding `test` anchor for the same AT-ID (i.e., the enforcement is tested).

Anchor validation runs as part of `verify.sh full`.

### Adoption Strategy

Introduce incrementally -- one story at a time during reconciliation. Phase R5 remediation adds anchors to enforcement points and proving tests. Over time, anchor coverage grows until CI can enforce completeness.

For stories reconciled before v1.6, anchors are added during the next reconciliation pass or dedicated anchor-sweep story.

---

# Future Roadmap

> Items identified during review but too large for v1.6. Tracked here for visibility.

## Machine-Verifiable Proof Graphs -- V1+V2 SHIPPED

> **Status**: V1+V2 implemented. See `python/proof_graph/` for the full package (60 rules, 319 tests).

V1+V2 delivers per-story `proof_graph.json` with:
- **Schema**: Frozen dataclasses with `from_dict()` + deny-unknown-fields, type-safe `_require_bool`/`_require_int` helpers (`schema_version: 1` and `2`)
- **Validator**: 60 rules (`python/proof_graph/validate.py --strict`) -- enforcement-critical at pass-flip
- **Scaffolder**: `python/proof_graph/scaffold.py` generates skeleton from prd.json + CONTRACT.md
- **Gate integration**: `prd_set_pass.sh` validates with `--strict` (exit 1 on validation failure; exit 20 on trading halt)
- **Legacy exemption**: `plans/proof_graph_exempt.txt` grandfathers existing stories; shrinks via reconciliation
- **Stdlib-only**: Zero external dependencies

Key rules: R-001 (RECONCILED + BLOCKING contradiction), R-004 (stale test SHA), R-007 (phantom AT not in CONTRACT.md), R-008 (placeholder detection), R-015 (FAIL_OPEN_RISK), R-016b (safety-critical without TRIP tests), R-050 (duplicate at_id), R-052 (wiring-verdict alignment), R-056 (DEFERRED on safety_critical), R-057 (escalation verdicts on safety_critical).

**V2 status**: Shipped — 17 V2-only rules, strictest-wins aggregate merge (`aggregate.py`), trading halt detection, type-safe schema parsing. **Remaining roadmap**:
- Cross-slice regression detection (detect if a later slice overwrites earlier AT ownership)
- Auto-generation from R1 evidence ledger output
- R4 aggregation script integration
- JSON Schema file with sync test (deferred from V1 to avoid dual-source-of-truth)

## Post-Rejection Blast-Radius Audit

Current reconciliation audits "does the guard work?" but not "what happens after the guard fires?" For safety-critical gates, add downstream impact analysis:

- **Idempotency**: If the guard rejects and the system retries, does the retry see the same state? Or does the rejection poison a WAL entry / cache / state machine?
- **Cascading effects**: Does rejection of one intent affect unrelated intents? (e.g., shared position state, rate limiters)
- **Recovery path**: After rejection, what is the operator's recovery procedure? Is it documented?

**Proposed implementation**: Add a S9 "Post-Rejection Analysis" section to the premortem template. During reconciliation, Phase R1 audits the downstream effects as Task 8.5 (between design-pattern conformance and remediation list).

**Blockers**: Expands the reconciliation scope significantly (~doubles R1 audit work per AT). Better introduced as a dedicated process for HIGH `loss_mode` stories only, or as a dedicated post-reconciliation phase.

---

# Changelog

> Full version history. Header shows only current + previous version summary.

### v3.1
- Proof graph V2 pipeline: 60 rules (43 V1+V2, 17 V2-only), 319 tests
- Strictest-wins reviewer merge (`aggregate.py`) with conflict tracking and stale rationale detection
- Type-safe schema parsing (`_require_bool`/`_require_int`), `schema_version: 2`
- Trading halt detection (exit code 20), safety-critical rules (R-056, R-057)
- `RECONCILED_UNIT_ONLY` reconciliation status, `reconciliation_stale` aggregate flag
- Unknown severity/verdict fail-closed defaults (rank 3/9)

### v3.0 (2026-02-23)
- 3-layer split: RUNBOOK (operator instructions), POLICY (normative rules), ANTIPATTERNS (failure catalog) + METRICS (reference data)
- JSON schemas for all gate-driving artifacts (`specs/schemas/recon/`)
- Hard gates with named Gate IDs at every phase boundary
- Mechanical validators (`validate_recon_artifact.sh`, `validate_review_header.py`, `validate_external_manifest.py`)
- Provenance headers (5 mandatory fields) on all review artifacts
- Canonical directory layout with deterministic, phase-prefixed filenames
- Wave migration plan for schema promotion (Wave 1 active, Wave 2/3 planned)

### v2.1 (2026-02-23)
- Step-supervisor phase mapping table: explicit mapping between `wf_step.sh` 9-step receipt chain and Part B phases (R1-R7f), with pod assignments and receipt system distinction
- R3 gap output JSON schema: worked example for stories with gaps (required fields: `gap_id`, `at_id`, `priority`, `classification`, `description`, `proposed_fix`; `coverage_proof` required even when gaps found)
- Tiered anti-patterns: Top 5 Most Dangerous callout (#20, #6, #12, #25, #26) for agent context window prioritization
- Version history moved to Appendix D (header truncated to current + previous)
- Canonicalized entry points location: `specs/ENTRY_POINTS.md` (removed "or equivalent")
- RECON-CLEAN independent verification gate: lead must independently verify `BLOCKING=0` before approving Cycle 2 skip (read artifact, confirm finding_counts, record verification)
- Appendix A sync directive: `plans/prompts/slice_reconcile_implement.md` is canonical source of truth; appendix is reference snapshot with diff command for drift detection

### v2.0 (2026-02-22)
- Anti-pattern #26 (blanket `--theirs` merge destroys branch-specific tooling)
- Lessons learned #6 (merge loss of enriched prompt + resolution prompt, required manual git-history restoration)
- Root cause: 8 merge conflicts resolved with `--theirs` without per-file diff inspection; 2/8 had substantial unique work lost

### v1.9
- Anti-patterns #23-#25 (consolidated findings without evidence ledgers, multi-tool phase-mapping gap, single-prompt blind spots)
- Dual-prompt review strategy (generic + enriched for each tool)
- S5-004 lessons learned (multi-tool convergence, mechanical verification, informal R4 risks)
- Debt register for 5 deferred findings
- Root cause: S5-004 reconciliation retrospective revealed process gaps despite 68 review artifacts and 39 tracked findings

### v1.8
- Anti-patterns #16-#19 (batch-deserialization blast radius, early-return branch exhaustiveness, AT attribution trust propagation, input-scope too narrow for intermediate computations)
- 6-category fail-closed check (adds narrowing casts)
- AT semantic match check, combinatorial coverage check, constants accuracy check
- Root cause: Opus 4.6 external review surfaced 5 gaps missed by all prior review layers including Kimi K2.5

### v1.7
- Machine-verifiable proof graphs V1 (`python/proof_graph/`)
- Per-story `proof_graph.json` with stdlib-only Python validator (18 rules, `--strict` enforcement at pass-flip)
- Scaffolder (`scaffold.py`), deny-unknown-fields schema, `schema_version: 1`
- Legacy exemption list (`plans/proof_graph_exempt.txt`)
- `prd_set_pass.sh` gate integration (V1: exit 10; V2: exit 1 on failure, exit 20 on trading halt)
- Appendix C roadmap item marked DONE (V1)

### v1.6
- Anti-patterns #12-#15 (workflow bypass vectors: fake citation pass-through, diff-only review gaming, DECISION_DIVERGENCE escape hatch, silent debt deferral)
- Enforceable Cycle 1 pre-existing-code gate
- DECISION_DIVERGENCE auto-escalation for rejected options
- Debt register JSON schema + R7f validation
- R7c call-graph reachability (entry-point assertion replaces single-caller check)
- Codebase audit anchors (`#[audit_anchor]`)
- Future roadmap (proof graphs, post-rejection blast-radius audit)

### v1.5
- GAP-P0-01: Separated proof verdicts from runtime-enforcement gate (PROVEN-INTEGRATED required for pass-eligibility on safety-critical ATs; proof verdict stays clean)
- GAP-P0-02: Machine mutation testing via `cargo mutants` with fast/deep path scoping (mental analysis demoted to pre-filter, scope extended to full proving suite for gapped ATs)
- GAP-P0-03: Structured R5b skill receipts with head_commit validation (replaces mtime checks, SELF_REVIEW_UNPROVEN blocker)
- GAP-P0-04: OPERATIONAL_ESCALATION_REQUIRED flag for live-system unwired guards
- GAP-P1-01: Decentralized R4 synthesis (scripted JSON aggregation, lead resolves conflicts only)
- GAP-P1-02: WEAK_PROOF on MED/HIGH loss_mode ATs escalated to CLAIMED_NOT_PROVEN
- GAP-P1-03: STOPLIGHT re-evaluation in Phase R6 verify

### v1.4
- Expanded fail-closed check (5-category input validation)
- Input-boundary mutations in R7e
- Anti-patterns #10 (recusal blind spot) and #11 (saturating arithmetic != input validation)
- Root cause: Kimi K2.5 external review surfaced 2 gaps missed by all prior review layers

### v1.3
- PARTIAL verdict
- R7 sub-phase breakdown, R7d-R7e escalation
- MISSING_ARTIFACT/FALLBACK priority, emergency escalation
- Review Basis enforcement
- `prd_set_pass.sh` cross-reference
- Simpler-Than-Correct Gate dual-application

### v1.2
- Review scope rules, Phase R5b
- Story proof scope, Review Basis
- Evidence Index, minimum evidence pack
- Positive/negative evidence
