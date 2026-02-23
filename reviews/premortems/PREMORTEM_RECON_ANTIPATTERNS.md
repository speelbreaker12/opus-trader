# Reconciliation Anti-Pattern Catalog

> Failure modes discovered across Slice 1 and S5-004 reconciliation.
> For execution instructions, see [RUNBOOK](RUNBOOK_PREMORTEM_RECON.md).
> For normative rules, see [POLICY](PREMORTEM_RECON_POLICY.md).
> For metrics and lessons learned, see [METRICS](PREMORTEM_RECON_METRICS.md).

---

## Top 5 Most Dangerous

Prioritize these in agent context windows when space is limited.

| Rank | # | Name | Why |
|------|---|------|-----|
| 1 | #20 | Paper enforcement (defined + tested, never called) | Creates false RECONCILED verdicts on guards with zero runtime protection. Highest blast radius. |
| 2 | #6 | Skipping R7c wiring audit | The only check that catches #20. Without it, all other review layers produce false confidence. |
| 3 | #12 | Fake citation pass-through | Poisons every downstream layer (cross-review, evidence ledger, proof graph) with unverifiable claims. |
| 4 | #25 | Single-prompt blind spots | Neither generic nor enriched alone finds >60% of findings. Skipping one loses 40%+ of signal. |
| 5 | #26 | Blanket `--theirs` merge | Destroys branch-specific tooling silently. Unrecoverable without git history forensics. |

---

## Taxonomy

Anti-patterns are grouped by failure domain for faster lookup during reviews.

### Process Failures (review/workflow structure)

| # | Name | Phase |
|---|------|-------|
| 1 | Each reviewer only reviews one other batch | Phase 4 (cross-review assignment) |
| 2 | Reviewer reviews their own work | Phase 4 (cross-review assignment) |
| 3 | Patches rewrite entire sections | Phase R5 (remediation) |
| 4 | Skipping Phase 5 synthesis | Phase 5 (synthesis) |
| 5 | Treating scores as absolute | Phase 5 (synthesis) |
| 9 | Skipping Phase R5b self-review | Phase R5b (self-review) |
| 10 | Cross-review recusal without secondary coverage | Phase 4 (cross-review assignment) |
| 23 | Consolidated findings without per-story evidence ledgers | Phase R1-R2 (evidence) |
| 24 | Multiple review tools without phase-mapping | Phase R1-R7 (tooling) |

### Review Quality Failures (what reviewers miss)

| # | Name | Missed Category |
|---|------|-----------------|
| 5 | Treating scores as absolute | Calibration |
| 8 | Diff-only review in Cycle 1 | Scope |
| 11 | Saturating arithmetic treated as input validation | Semantic gap |
| 13 | Diff-only review gaming in Cycle 1 | Scope (deliberate) |
| 17 | Early-return branch exhaustiveness | Control flow |
| 18 | AT attribution trust propagation | Traceability |
| 19 | Input-scope too narrow for intermediate computations | Scope |
| 25 | Single-prompt review | Prompt coverage |

### Proof Integrity Failures (verdicts that lie)

| # | Name | Failure Mechanism |
|---|------|-------------------|
| 6 | Skipping R7c wiring audit | Missing verification layer |
| 7 | Conflating proof verdicts with deployment readiness | Semantic confusion |
| 12 | Fake citation pass-through | Fabricated evidence |
| 14 | DECISION_DIVERGENCE escape hatch | Suppressed finding |
| 15 | Silent debt deferral | Lost tracking |
| 20 | Paper enforcement | Island code |
| 21 | Phantom test | Nonexistent test |
| 22 | Non-compiling test | Broken test |

### Code-Level Failures (patterns in Rust code)

| # | Name | Rust Pattern |
|---|------|-------------|
| 11 | Saturating arithmetic treated as input validation | `saturating_sub` / `checked_mul` |
| 16 | Batch-deserialization blast radius | `#[serde(other)]` missing |
| 17 | Early-return branch exhaustiveness | Early return + fall-through |
| 19 | Input-scope too narrow | `as i64` narrowing casts |

### Merge/Git Failures

| # | Name |
|---|------|
| 26 | Blanket `--theirs` on merge conflicts |

---

## Full Catalog

---

### #1 — Each reviewer only reviews one other batch

**Pattern**: Cross-reviewer is assigned a single batch instead of reviewing across all batches.
**Risk**: Systemic patterns only emerge when a reviewer sees 9+ documents from different authors; single-batch review misses them entirely.
**Fix**: Assign each cross-reviewer to review ALL batches (excluding their own). The Slice 1 per-batch approach had to be restarted for this reason.
**Gate**: No automated gate — lead must catch during Phase 4 assignment.

---

### #2 — Reviewer reviews their own work

**Pattern**: A reviewer is assigned cross-review duty on a batch they authored.
**Risk**: Self-review has near-zero marginal value after the writing phase. Findings converge to what the author already knows.
**Fix**: Assign complements only — never assign a reviewer to their own batch. Lead verifies assignments before Phase 4 begins.
**Gate**: No automated gate — lead must catch during Phase 4 assignment.

---

### #3 — Patches rewrite entire sections

**Pattern**: Remediation patch replaces a full premortem section rather than making surgical edits.
**Risk**: Rewrites introduce new errors that were not present in the original. Verifiability drops because the diff is too large to audit.
**Fix**: Patches must be surgical edits. If a section needs full rewrite, escalate to the lead via the ~30% rule (rewrite >30% of a section = lead decision).
**Gate**: No automated gate — lead must catch during Phase R6 verification.

---

### #4 — Skipping Phase 5 synthesis

**Pattern**: Lead skips the step of comparing cross-review findings against their own Phase 2 evaluation.
**Risk**: Net-new findings from cross-reviewers are invisible. The entire purpose of cross-review — identifying what the lead missed — is defeated.
**Fix**: Lead must produce a synthesis artifact listing: (a) findings that confirm Phase 2, (b) net-new findings the lead missed, (c) disagreements between reviewers.
**Gate**: No automated gate — lead must self-enforce.

---

### #5 — Treating scores as absolute

**Pattern**: Numerical ratings or letter grades from reviewers are compared as absolute quality measures.
**Risk**: Scores are calibration signals, not grades. A uniform PASS-WITH-ISSUES is fine; a split between PASS and NEEDS-PATCH indicates a disagreement worth investigating.
**Fix**: Use score divergence (not absolute values) as the signal. When reviewers disagree by more than one tier, investigate the specific items of disagreement.
**Gate**: No automated gate — lead must catch during Phase 5 synthesis.

---

### #6 — Skipping Phase R7c wiring audit

**Pattern**: Post-reconciliation review omits the production wiring audit that classifies enforcement points as WIRED vs NOT-WIRED.
**Risk**: The most dangerous false sense of security: a RECONCILED verdict on a guard with zero production callers. Without the wiring audit, you can report "all stories reconciled" while only a fraction are actually enforced at runtime. This was the single highest-value finding in the Slice 1 pilot.
**Fix**: Run `verify_mechanical.sh` callsite check on every enforcement point. Zero production callers = P1 finding. Add `PROVEN-UNIT` wiring qualifier and block `prd_set_pass.sh` until an integration story wires it.
**Gate**: `verify_mechanical.sh` callsite check. Hard gate in RUNBOOK — R7c is mandatory before any slice can pass.

---

### #7 — Conflating proof verdicts with deployment readiness

**Pattern**: A RECONCILED verdict is treated as meaning "ready to deploy" rather than "unit correctness proven."
**Risk**: RECONCILED means the proof is real — it does not mean the guard is wired into production dispatch. Stories can be honestly RECONCILED and still have zero runtime enforcement.
**Fix**: Keep proof verdict clean (RECONCILED). Enforce a separate runtime-enforcement gate: every safety-critical AT must be `PROVEN-INTEGRATED`. A blocked story needs an integration story, not a verdict change.
**Gate**: `prd_set_pass.sh` enforces the `PROVEN-INTEGRATED` gate separately from proof verdicts.

---

### #8 — Diff-only review in Cycle 1

**Pattern**: Cycle 1 reviewer scopes their review to the git diff only.
**Risk**: In reconciliation, bugs may exist in old code. If the recon diff is zero or tiny, a diff-scoped review reviews nothing — the entire audit is vacuous.
**Fix**: Cycle 1 reviewers must audit the full story proof scope (all files in `scope.touch`), not just the changes. Cite at least one observation from pre-existing code.
**Gate**: `review_logged.sh` post-validation — hard gate in RUNBOOK. Reviews where every cited file:line also appears in `git diff` are auto-rejected with `DIFF_ONLY_REVIEW_REJECTED`.

---

### #9 — Skipping Phase R5b self-review

**Pattern**: Builder sends remediation code directly to external review (Cycle 2) without running the 5-skill self-review stack first.
**Risk**: Wastes the scarce constraint of reviewer attention. External reviewers rediscover issues the builder already saw, consuming review budget on known problems.
**Fix**: Builder must run the 5-skill stack (`/pr-review` -> `/failure-mode-review` -> `/strategic-failure-review` -> `/contract-review` -> `/devils-advocate`), fix P0/P1/P2 blockers, and produce a gate artifact before Cycle 2 begins.
**Gate**: No automated gate — step supervisor enforces ordering (self_review step must precede cycle2).

---

### #10 — Cross-review recusal without secondary coverage

**Pattern**: A reviewer correctly recuses from their own batch, but no secondary reviewer is assigned to cover that batch's domain-specific edge cases.
**Risk**: Domain-specific gaps go unreviewed. In Slice 1, the EXPIRY reviewer recused from S1-012, and no other reviewer had the domain context to catch timestamp input-boundary gaps.
**Fix**: When a reviewer recuses, assign a secondary reviewer from a different batch. Add checklist item: "For recused stories, verify boundary inputs were tested by another reviewer."
**Gate**: No automated gate — lead must catch during Phase 4 assignment.

---

### #11 — Saturating arithmetic treated as input validation

**Pattern**: Reviewer sees `saturating_sub` or `checked_mul` and concludes the function is "overflow-safe" without checking whether inputs themselves are bounded.
**Risk**: Saturating/checked arithmetic protects computation from overflow but does not validate that inputs are sane. `expiration_ms = u64::MAX` from a corrupt feed passes all saturating checks but produces nonsense results.
**Fix**: Always ask: "Are the inputs themselves bounded?" Saturating arithmetic is a defense layer, not input validation. Verify that upstream feeds are validated before reaching arithmetic operations.
**Gate**: No automated gate — reviewer must catch. Include in Cycle 1 checklist: "For each arithmetic operation, are inputs bounded independently?"

---

### #12 — Fake citation pass-through

**Pattern**: Agent cites a real `file:line` but the cited line is blank, a comment, or a helper function — not the actual enforcement gate.
**Risk**: Poisons every downstream layer (cross-review, evidence ledger, proof graph) with unverifiable claims. All subsequent reviews inherit the false citation without rechecking.
**Fix**: (a) Automated AST/grep validation of all `file:line` citations — verify the cited line contains a function call or guard expression, not whitespace. (b) Introduce Codebase Audit Anchors (`#[audit_anchor(AT-920)]`) that CI validates against `prd.json` AT lists. Citations referencing functions without audit anchors on safety-critical ATs produce `CITATION_UNANCHORED` warning.
**Gate**: `validate.py` citation check. Hard gate in RUNBOOK — pre-existing citations must be verified before evidence ledger is accepted.

---

### #13 — Diff-only review gaming in Cycle 1

**Pattern**: Agent ignores the "Story Proof Scope" directive, reviews only the git diff (which may be empty for retro-audits), and marks PROVEN. Distinct from #8 in that this is deliberate gaming, not accidental scoping.
**Risk**: Review artifact appears compliant but contains zero substantive analysis. All downstream verdicts inherit a vacuous review.
**Fix**: Require Cycle 1 reviewers to cite at least one observation from pre-existing code (not the recon diff). If every cited `file:line` in the review artifact also appears in `git diff`, auto-reject.
**Gate**: `review_logged.sh` post-validation enforces `DIFF_ONLY_REVIEW_REJECTED`. Hard gate — review basis line check is mandatory.

---

### #14 — DECISION_DIVERGENCE escape hatch

**Pattern**: Agent finds code doesn't match the premortem section 4 decision. To avoid writing a gap ticket and remediation plan, they mark it `INFO: Code is better` without evidence.
**Risk**: Silently re-adopts a previously rejected option from the premortem. The premortem already evaluated and dismissed that option — re-adopting it without justification is suspicious, not "better."
**Fix**: Any divergence toward a previously rejected option in the premortem is automatically P1. Only the lead can downgrade a rejected-option divergence from P1 to INFO, and the downgrade must include written justification recorded in the evidence ledger.
**Gate**: No automated gate — lead must catch during Phase R2 evaluation. Evidence ledger must record lead sign-off for any P1-to-INFO downgrade.

---

### #15 — Silent debt deferral

**Pattern**: Agent marks a gap `DEFERRED` without creating a debt register entry, or sets `target_slice` to "TBD." The gap effectively disappears from tracking.
**Risk**: Deferred gaps are never addressed. Technical debt accumulates invisibly. No one knows what was punted or when it's due.
**Fix**: Debt register must follow strict JSON schema (Phase R4). Every `DEFERRED` gap in evidence ledgers must have a corresponding entry in the debt register with valid `target_slice` (not "TBD"), `owner`, and `created_at`. Overdue debt (target_slice already passed) blocks `prd_set_pass.sh`.
**Gate**: Phase R7f validation script checks debt register schema. Overdue debt blocks `prd_set_pass.sh`.

---

### #16 — Batch-deserialization blast radius

**Pattern**: A serde enum has correct variant coverage for all known values, so it passes review. But the enum lacks `#[serde(other)]`, and when the venue adds a new variant, one unknown element in a `Vec<T>` batch poisons the entire deserialization.
**Risk**: Disproportionate blast radius — all instruments go stale, not just the unknown one. A single unexpected variant causes total data loss for the batch.
**Fix**: For every serde enum used in a collection/batch context, ask: "Does one invalid element fail the entire batch? If so, is the blast radius proportionate?" Add `#[serde(other)]` fallback or deserialize-then-filter pattern for venue-facing enums.
**Gate**: No automated gate — reviewer must catch. Include in Cycle 1 checklist: "For each serde enum in a Vec, is there an `other` fallback?"

---

### #17 — Early-return branch exhaustiveness

**Pattern**: A function handles `input = None` with an early return for type X. Reviewers see the branch, conclude "type X is handled," and move on. But the fall-through path (`input = Some`) does not re-check type X.
**Risk**: Type X with an unexpected `Some` value takes a code path designed for other types. Untested behavior occurs silently. In Slice 1, a Perpetual instrument with a bogus `Some(near_term_timestamp)` would hit the buffer check — a path no test covers.
**Fix**: For each function with early-return branches, verify the fall-through path is correct for ALL input types that reach it, not just the "expected" ones. Check: "If type X takes the fall-through instead of its early-return, is the behavior still correct?"
**Gate**: No automated gate — reviewer must catch. Include in Cycle 1 checklist: "For each early return, what happens if the guarded type takes the fall-through path?"

---

### #18 — AT attribution trust propagation

**Pattern**: Every downstream layer (evidence ledger, cross-review, external review) inherits the premortem's AT mapping without independently verifying that the AT's actual clause text matches what the code enforces.
**Risk**: A misattributed AT propagates through all review layers unchallenged. In Slice 1, AT-333 (quantization parameters) was attributed to instrument kind derivation tests — a prerequisite, not the AT itself. All reviewers agreed the test was "PROVEN for AT-333" because they checked internal consistency, not external consistency.
**Fix**: At least one review layer must re-read the AT anchor text in CONTRACT.md and verify semantic match, not just structural presence. Add to Cycle 1 reviewer checklist: "For one random AT per story, re-read the clause text. Does the enforcement match the literal requirement?"
**Gate**: No automated gate — reviewer must catch. Consider adding to `validate.py` as a spot-check that AT descriptions match enforcement point names.

---

### #19 — Input-scope too narrow for intermediate computations

**Pattern**: The 5-category input validation framework (Missing/None, NaN/Inf, Negative, Out-of-domain, Corrupt) is applied only to function inputs, missing intermediate computations and narrowing casts.
**Risk**: (a) Intermediate computations that cross type boundaries (e.g., `(f64).round() as i64` silently saturates). (b) Constants with wrong comments (e.g., `~7.3e15` on a `7.3e12` value). (c) Input combinations where one input's presence causes checks on other inputs to be skipped.
**Fix**: Expand validation scope to "each input, intermediate type conversion, and output." Add category (6): narrowing casts. Add combinatorial coverage check for functions with multiple Optional/enum inputs.
**Gate**: No automated gate — reviewer must catch. Narrowing cast detection could be added to clippy or a custom lint.

---

### #20 — Paper enforcement (defined + tested, never called)

**Pattern**: A guard function exists, has unit tests, passes all ATs, and receives a PROVEN verdict. But `findReferences` shows zero callers in the production dispatch path — the function is an island.
**Risk**: Highest blast radius anti-pattern. Creates false RECONCILED verdicts on guards with zero runtime protection. In Slice 1, `derive_instrument_kind`, `opens_blocked`, `build_order_size`, `validate_and_dispatch`, and `resolve_config_value` all had this pattern.
**Fix**: Run `verify_mechanical.sh` callsite check. Zero production callers on an enforcement point = P1 finding. Keep the proof verdict valid but add `PROVEN-UNIT` wiring qualifier and block `prd_set_pass.sh` until an integration story wires it.
**Gate**: `verify_mechanical.sh` callsite check. Hard gate — zero-caller enforcement points block slice pass.

---

### #21 — Phantom test (PRD lists test that doesn't exist)

**Pattern**: `implementation_tests[]` in `prd.json` references `path::test_fn_name`, but the file doesn't contain `fn test_fn_name` (or the file doesn't exist at all).
**Risk**: Story appears compliant because no one checked whether the named tests actually exist. In Slice 1, 3 PRD-named tests were phantoms: planned but never implemented.
**Fix**: For each `implementation_tests[]` entry, verify the file exists AND contains `#[test] fn <name>`. Missing file = FAIL. Missing function = FAIL.
**Gate**: `verify_mechanical.sh` test existence check. Hard gate — phantom tests block slice pass.

---

### #22 — Non-compiling test

**Pattern**: Test file exists and contains `#[test]` functions, but `cargo test --no-run --workspace` fails because imports reference types that were renamed or never defined.
**Risk**: Test verdicts are trusted without ever building the tests. In Slice 1, `PricerSide` was consolidated into `Side` and `WalWriterConfig` was referenced but never defined — neither compile error was caught.
**Fix**: Run `cargo test --no-run --workspace` as a compile gate before any test verdicts are trusted.
**Gate**: `verify_mechanical.sh` compile gate (part of `verify.sh full`). Hard gate — non-compiling tests block slice pass.

---

### #23 — Consolidated findings without per-story evidence ledgers

**Pattern**: Multiple review tools produce dozens of artifacts. The lead consolidates them into a single findings report ("36 P1 findings across 6 themes") but skips the per-story AT-by-AT verdict table.
**Risk**: No formal RECONCILED/NOT-RECONCILED assignment per story, no per-AT proof verdict, and no structured way to track which ATs are PROVEN vs CLAIMED_NOT_PROVEN. In S5-004, 68 review artifacts were produced but no evidence ledgers.
**Fix**: Even when using external review tools, produce one evidence ledger per story mapping each AT to its verdict. The consolidated findings report is an additional rollup, not a replacement.
**Gate**: Hard gate in RUNBOOK — evidence ledger per story is a prerequisite for Phase R2 evaluation. `prd_set_pass.sh` checks for evidence ledger existence.

---

### #24 — Multiple review tools without phase-mapping

**Pattern**: External review tools (Kimi, Opus, Codex) produce review artifacts outside the R1-R7 phase structure. Without explicit mapping, it's unclear which artifacts correspond to which phase or cycle.
**Risk**: Cannot determine whether the full review checklist was applied, whether Cycle 1 or Cycle 2 scope was used, or whether any phase was skipped. In S5-004, the mapping was implicit and had to be reconstructed retroactively.
**Fix**: When using external tools, explicitly label each review batch with its phase-equivalent and cycle. Add a "Phase Mapping" section to the consolidated findings report (e.g., `Kimi C1 = Phase R1`, `Codex C2 enriched = Phase R7`).
**Gate**: Hard gate in RUNBOOK — phase-mapping section is required in consolidated findings before Phase R6 verification.

---

### #25 — Single-prompt review (missing generic or enriched)

**Pattern**: Review tool is run with only one prompt style (generic OR enriched) instead of both.
**Risk**: Systematic blind spots. Generic prompts find code-level issues (overflow, panic safety, dead code). Enriched prompts find contract-level issues (AT proof gaps, premortem conformance, phantom tests, decision divergence). In S5-004: enriched found 14 unique findings (39%) including all phantom-test discoveries; generic found 4 unique (11%) including `as i64` saturation. Neither alone exceeds ~60%.
**Fix**: Always run BOTH generic and enriched prompts for each review tool via `review_logged.sh --prompt enriched` and `--prompt generic`. Compare findings to identify prompt-specific blind spots. Track "unique finding %" per prompt style.
**Gate**: `review_logged.sh` tracks prompt style in artifact provenance header. No hard automated gate — lead must verify both styles were run.

---

### #26 — Blanket `--theirs` on merge conflicts

**Pattern**: When merging main into a feature branch, accepting `--theirs` (main's version) for all conflicted files without inspecting per-file diffs.
**Risk**: Destroys branch-specific tooling silently. In S5-004, 8 files had conflicts; 6/8 were convergent (no loss), but 2 had substantial unique work on the feature branch: `review_logged.sh` lost the entire dual-prompt infrastructure, and `recon/resolution.md` lost detailed resolution guidance. Both required manual restoration from git history.
**Fix**: Before accepting `--theirs`, run `git diff <merge-base> <ours> -- <file>` for each conflicted file. If ours has >20 diff lines that theirs doesn't, inspect manually. For tooling/workflow files that evolve on feature branches, prefer manual merge over `--theirs`.
**Gate**: `/git` skill enforces per-file diff check before `--theirs` resolution. Hard gate in RUNBOOK.

---

## Cross-Reference Chains

Anti-patterns that interact or compound each other. If you find one, check for the related ones.

| Primary | Related | Relationship |
|---------|---------|-------------|
| #6 (skip R7c) | #20 (paper enforcement) | R7c is the only gate that catches #20. Skipping #6 enables #20. |
| #8 (diff-only) | #13 (diff-only gaming) | #8 is accidental, #13 is deliberate. Same `DIFF_ONLY_REVIEW_REJECTED` gate catches both. |
| #12 (fake citation) | #18 (AT trust propagation) | A fake citation in the premortem propagates through all layers via #18. |
| #20 (paper enforcement) | #7 (proof vs deployment) | #7 confusion causes people to skip the wiring check that would catch #20. |
| #21 (phantom test) | #22 (non-compiling test) | Both are "test exists on paper but not in reality." #21 = doesn't exist at all. #22 = exists but broken. |
| #23 (no evidence ledgers) | #24 (no phase-mapping) | Both are organizational debt from using external tools. Fix #24 first (map tools to phases), then #23 (produce per-story ledgers). |
| #14 (divergence escape) | #15 (silent debt) | Both suppress findings. #14 downgrades severity, #15 defers without tracking. Together they can hide gaps entirely. |
| #11 (saturating = validation) | #19 (narrow input scope) | #11 is a specific instance of #19's broader pattern of missing intermediate computation checks. |
| #1 (single-batch review) | #10 (recusal gap) | Both are cross-review assignment failures that leave batches under-reviewed. |
| #25 (single prompt) | #8 (diff-only) | A single-prompt diff-only review combines both blind spots: wrong scope AND wrong depth. |

---

## Gate Coverage Summary

| Gate | Anti-patterns caught |
|------|---------------------|
| `verify_mechanical.sh` | #20 (callsite), #21 (phantom test), #22 (compile) |
| `review_logged.sh` | #8 (diff-only), #13 (diff-only gaming) |
| `validate.py` | #12 (fake citation) |
| `prd_set_pass.sh` | #7 (PROVEN-INTEGRATED), #15 (overdue debt), #20 (zero-caller block) |
| `/git` skill | #26 (per-file diff before --theirs) |
| RUNBOOK hard gates | #6 (R7c mandatory), #8 (review basis), #12 (citation check), #23 (evidence ledger), #24 (phase-mapping) |
| No automated gate | #1, #2, #3, #4, #5, #9, #10, #11, #14, #16, #17, #18, #19, #25 |

---

## Reviewer Checklist Extract

These questions are derived from the anti-patterns above. Include them in Cycle 1 reviewer instructions.

### For each enforcement function:
- [ ] Does `findReferences` show at least one caller in the production dispatch path? (#20)
- [ ] Are the inputs themselves bounded, not just the arithmetic? (#11)
- [ ] For each early return, what happens if the guarded type takes the fall-through? (#17)
- [ ] For each intermediate type conversion (`as i64`, `.round()`), can the value overflow? (#19)

### For each serde enum in a `Vec<T>`:
- [ ] Does one invalid element fail the entire batch? Is there a `#[serde(other)]` fallback? (#16)

### For each AT citation:
- [ ] Does the cited `file:line` contain actual enforcement code (not a comment, blank, or helper)? (#12)
- [ ] Re-read the AT clause text in CONTRACT.md — does the enforcement match the literal requirement? (#18)
- [ ] Is at least one observation cited from pre-existing code (not only the diff)? (#8, #13)

### For each evidence ledger:
- [ ] Does every `DEFERRED` gap have a debt register entry with valid `target_slice`? (#15)
- [ ] Is there a per-story AT-by-AT verdict table (not just a consolidated rollup)? (#23)
- [ ] Are review artifacts labeled with their phase-equivalent and cycle? (#24)

### For each premortem divergence:
- [ ] If code diverges toward a previously rejected option, is it flagged P1 (not INFO)? (#14)
- [ ] Has the lead explicitly signed off on any P1-to-INFO downgrades? (#14)

### For merge conflicts:
- [ ] Did you run `git diff <merge-base> <ours> -- <file>` before accepting `--theirs`? (#26)
- [ ] For files with >20 unique diff lines on our branch, did you merge manually? (#26)
