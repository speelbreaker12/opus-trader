# S2 Premortem Authoring — Handoff

**Created:** 2026-02-23 | **Updated:** 2026-02-27
**Status:** Mode A Phase 2 complete
**Next action:** Phase 3 — Targeted Patch (apply 8 patches from patch list)

## Source-of-Truth Documents (Current)

| Document | Path |
|---|---|
| Protocol | `reviews/reconciliations/PROTOCOL.md` |
| Reference | `reviews/reconciliations/REFERENCE.md` |
| Handoff template | `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` |
| Workflow contract | `specs/WORKFLOW_CONTRACT.md` |
| Step tracker | `plans/wf_step.sh` |
| Verify entrypoint | `plans/verify.sh` |
| Pass-flip gate | `plans/prd_set_pass.sh` |

Legacy runbook/policy references later in this handoff are historical context only; execution authority is the block above.

## What Was Done

1. Codebase mapping complete (`.planning/codebase/` — 7 docs, committed as `5bfc230`)
2. Identified task: Mode A (Premortem Authoring) for Slice 2
3. Gathered all context: prd.json entries, CONTRACT.md AT clauses, template

## Slice 2 Stories (5 total, all `passes=true`)

| Story | Domain | Enforcement | ATs | Risk | Scope |
|-------|--------|-------------|-----|------|-------|
| S2-000 | Quantization rounding | DispatcherChokepoint | AT-926, AT-280, AT-219, AT-908 | low | quantize.rs, execution/mod.rs |
| S2-001 | Intent hash from quantized fields | WAL | AT-201, AT-343, AT-928, AT-218 | low | idempotency/hash.rs, idempotency/mod.rs |
| S2-002 | Compact label schema | WAL | AT-216, AT-217, AT-041, AT-921 | low | label.rs, execution/mod.rs |
| S2-003 | Label match disambiguation | PolicyGuard | AT-217, AT-216 | med | lib.rs, recovery/ |
| S2-004 | RejectReasonCode registry | DispatcherChokepoint | AT-201 | med | reject_reason.rs, execution/mod.rs |

## Recommended Batch Grouping (3 agents)

- **Agent 1:** S2-000 + S2-004 (DispatcherChokepoint, execution domain)
- **Agent 2:** S2-001 (idempotency/hash, standalone)
- **Agent 3:** S2-002 + S2-003 (label domain, shared AT-216/217)

## Mode A Phases (from RUNBOOK)

1. **Phase 1 — Parallel Write** ← START HERE
   - Spawn writer agents per batch grouping
   - Each creates `reviews/premortems/S2-XXX_premortem.md` filling §0-§10
   - Writers must NOT inspect implementation code
   - Template: `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md`
2. **Phase 2 — Lead Evaluation** (score batches, create patch list)
3. **Phase 3 — Targeted Patch** (Round 1, surgical fixes only)
4. **Phase 4 — Cross-Review** (reviewers review stories they did NOT write)
5. **Phase 5 — Synthesis** (merge findings, prioritize fixes)
6. **Phase 6 — Final Patch** (Round 2)
7. **Phase 7 — Verify** (confirm premortems are implementation-ready)

## Key Documents

| Document | Path |
|----------|------|
| Process index + R1 prompt | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` |
| Runbook (operator instructions) | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` |
| Policy (verdicts, gates) | `reviews/premortems/PREMORTEM_RECON_POLICY.md` |
| Anti-patterns | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` |
| Metrics + lessons | `reviews/premortems/PREMORTEM_RECON_METRICS.md` |
| Premortem template | `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` |
| DESIGN_PATTERNS §0 | `specs/DESIGN_PATTERNS.md` |

## Resume Command

```
/clear
```

Then:
```
Resume S2 premortem authoring from reviews/reconciliations/S2/HANDOFF.md — start Mode A Phase 1 (parallel write). Read the handoff, then read RUNBOOK_PREMORTEM_RECON.md §2 Phase 1 and spawn 3 writer agents per the batch grouping. Each agent needs: the premortem template, the prd.json story entry, relevant CONTRACT.md AT clauses, and DESIGN_PATTERNS.md §0. Writers must NOT read implementation code.
```

---

## Reconciliation Dry-Run (S2-003, S2-000)

### Story Status Matrix

Legend: `·` not started, `→` in progress, `✓` passed, `✗` blocked/failed

| Story | R1 Preflight | R2 | R3 | R4 | R5 | R6 | R7 |
|-------|--------------|----|----|----|----|----|----|
| S2-000 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S2-003 | · | · | · | · | · | · | · |

### Story-Step Block (S2-000, S2-003)

| Story | Step | Status | Gate | Receipt |
|-------|------|--------|------|---------|
| S2-000 | Step 1 (preflight/R1) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step1_report.md`, `.wf/receipts/S2-000/00_preflight.json` |
| S2-000 | Step 2 (implement) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step2_report.md`, `.wf/receipts/S2-000/01_implement.json` |
| S2-000 | Step 3 (self_review) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step3_report.md`, `.wf/receipts/S2-000/02_self_review.json` |
| S2-000 | Step 4 (cycle1) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step4_report.md`, `.wf/receipts/S2-000/03_cycle1.json` |
| S2-000 | Step 5 (fix) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step5_report.md`, `.wf/receipts/S2-000/04_fix.json` |
| S2-000 | Step 6 (cycle2) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step6_report.md`, `.wf/receipts/S2-000/05_cycle2.json` |
| S2-000 | Step 7 (resolution) | COMPLETE | GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step7_report.md`, `.wf/receipts/S2-000/06_resolution.json` |
| S2-000 | Step 8 (verify_full) | BLOCKED | NO-GO (official wf_step) | `reviews/reconciliations/S2/S2-000_step8_report.md` |
| S2-003 | Step 1 (preflight/R1) | READY_TO_RETRY | GO (premortem_ready) | `reviews/reconciliations/S2/S2-003_step1_report.md` |

### S2-000 — Step 1 (preflight/R1)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step1_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 preflight` exit `0`)
- Gate evidence summary:
  - Command: `plans/premortem_ready.sh S2-000` → exit `0`
  - Command: `plans/premortem_ready.sh S2-000 --json` → exit `0`, with `ready=true`, `ownership_conflicts=0`, `reasons=[]`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 preflight --dry-run` → exit `0`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 preflight` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `preflight` marked `[DONE]`
- Notes:
  - Premortem entry gate passed with `STOPLIGHT=YELLOW`.
  - JSON gate output confirms `ready=true`, `ownership_conflicts=0`, `context_files_ok=true`, `yellow_gaps_ok=true`, `premortem_gate_exit_code=0`.
  - Official Step 1 receipt: `.wf/receipts/S2-000/00_preflight.json`.

### S2-000 — Step 2 (implement)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step2_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 implement` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 implement --dry-run` → exit `0`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 implement` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `implement` marked `[DONE]`
- Notes:
  - Official Step 2 receipt: `.wf/receipts/S2-000/01_implement.json`.
  - `01_implement.json` includes `recon_relaxation: implement_diff_check_skipped` under `WF_RECON_MODE=1`.

### S2-000 — Step 3 (self_review)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step3_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 self_review` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 self_review --dry-run` → exit `0`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 self_review` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `self_review` marked `[DONE]`
- Notes:
  - Official Step 3 receipt: `.wf/receipts/S2-000/02_self_review.json`.
  - No blockers were reported in Step 3 execution.

### S2-000 — Step 4 (cycle1)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step4_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle1` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle1 --dry-run` → exit `0`, prerequisites OK
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle1` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `cycle1` marked `[DONE]`
- Notes:
  - Step 4 receipt written: `.wf/receipts/S2-000/03_cycle1.json`.
  - Earlier block history preserved in `S2-000_step4_report.md` (missing ledger, then citation pre-gate failure), then resolved in latest run.
  - `--status` still shows prior-step `HEAD MISMATCH` markers for older receipts created on previous HEAD.

### S2-000 — Step 5 (fix)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step5_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 fix` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 fix --dry-run` → exit `0`, prerequisites OK
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 fix` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `fix` marked `[DONE]`
- Notes:
  - Step 5 receipt written: `.wf/receipts/S2-000/04_fix.json`.
  - `fix` executed with `code_changed=false`; no code changes required.
  - Script logged fallback to legacy findings detection due to missing `artifacts/story/S2-000/cycle1/evidence_ledger.md`.

### S2-000 — Step 6 (cycle2)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step6_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle2` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle2 --dry-run` → exit `0`, prerequisites OK
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 cycle2` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `cycle2` marked `[DONE]`
- Notes:
  - Step 6 receipt written: `.wf/receipts/S2-000/05_cycle2.json`.
  - Resolved by adding a valid C2 artifact with FIX_DIFF basis:
    - `artifacts/story/S2-000/codex/20260227T191500Z_review.md`
  - Run remained on GREEN path (`min_reviews=1`) due `fix.code_changed=false`.
  - External rerun with all 3 tools logged in:
    - `reviews/reconciliations/S2/S2-000_step6_all3_external_review_rerun.md`
  - Post-fix scoped rerun (all 3 tools) logged in:
    - `reviews/reconciliations/S2/S2-000_step6_all3_external_review_rerun_after_fixes.md`
  - Final hardening rerun (all 3 tools) logged in:
    - `reviews/reconciliations/S2/S2-000_step6_all3_external_review_rerun_round2.md`

### S2-000 — Step 7 (resolution)

- Status: `Completed`
- Receipt: `reviews/reconciliations/S2/S2-000_step7_report.md`
- Gate: `GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 resolution` exit `0`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 resolution --dry-run` → exit `0`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 resolution` → exit `0`, receipt written
  - Command: `plans/wf_step.sh S2-000 --status` → exit `0`, `resolution` marked `[DONE]`
- Notes:
  - Step 7 receipt written: `.wf/receipts/S2-000/06_resolution.json`.
  - `review_resolution.md` satisfied required gate lines.

### S2-000 — Step 8 (verify_full)

- Status: `Blocked`
- Receipt: `reviews/reconciliations/S2/S2-000_step8_report.md`
- Gate: `NO-GO` (`WF_RECON_MODE=1 plans/wf_step.sh S2-000 verify_full` exit `3`)
- Gate evidence summary:
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 verify_full --dry-run` → exit `3`, initial blocker `mode=quick, need mode=full`
  - Command: `./plans/verify.sh full` → exit `1`, initial failure at `preflight` (`test_artifact_lint`)
  - Command: `bash plans/tests/test_artifact_lint.sh` → exit `0`, fixture now passing
  - Command: `./plans/verify.sh full` → exit `1`, latest failure at `rust_fmt`
  - Command: `WF_RECON_MODE=1 plans/wf_step.sh S2-000 verify_full --dry-run` → exit `3`, blocker `FAILED_GATE present`
- Notes:
  - No Step 8 receipt was written (`.wf/receipts/S2-000/07_verify_full.json` absent).
  - Current blocker is `rust_fmt` failure on modified file `crates/soldier_core/tests/test_idempotency.rs` in latest full verify artifact.

### S2-003 — Step 1 (preflight/R1)

- Status: `Completed (blocked)`
- Receipt: `reviews/reconciliations/S2/S2-003_step1_report.md`
- Gate: `RETRY READY` (`plans/premortem_ready.sh S2-003` now exits `0` after ownership metadata fix)
- Notes:
  - Historical Step 1 report captured a NO-GO state before workflow-script and PRD ownership fixes.
  - Current readiness check is GO; step can be rerun officially via `WF_RECON_MODE=1 plans/wf_step.sh S2-003 preflight`.
  - Prior blockers (heading-literal mismatch, YELLOW keyword over-match, directory `scope.touch`, ownership ambiguity) were removed in this run.

### Gate Evidence Summary (Step 1)

- Command: `plans/premortem_ready.sh S2-003`
  - Exit code: `0` (current)
  - Key blockers:
    - none (current)
- Command: `plans/premortem_ready.sh S2-003 --json`
  - Exit code: `0` (current)
  - Key fields: `ready=true`, `ownership_conflicts=0`, `yellow_gaps_ok=true`, `context_files_ok=true`

### Friction (Top 3)

1. `premortem_ready` default output is coarse and hides precise conflict IDs/root causes unless `--json` is run.
2. AT ownership gate has no primary-owner metadata, so legitimate shared AT coverage across stories blocks entry.
3. Step progression can reach `cycle1` before warning about missing evidence-ledger artifacts, causing avoidable late blocking.

### Simplification Proposals (3)

1. Make structured diagnostics default in `plans/premortem_ready.sh` (or print detailed failure expansions automatically).
2. Add explicit primary/shared AT ownership fields to premortem/PRD so the ownership gate can enforce intent instead of raw AT overlap.
3. Add a pre-step readiness command (or preflight check) that validates evidence-ledger presence before running `cycle1`.

## HANDOFF — Process Dry-Run (S2-001)

**Updated**: 2026-02-27
**Purpose**: Stress-testing the full recon pipeline on S2-001 to find friction points.

### Progress

| Phase | Status | Artifacts | Key Finding |
|-------|--------|-----------|-------------|
| Mode A (Premortem) | DONE | `/tmp/S2-001_premortem_fresh.md` | §4/§8/§9 are ceremony for LOW-risk; §1 caught 2 misattributed ATs |
| R1 (Read-Only Recon) | DONE | `S2-001_reconciliation.md`, `S2-001_reconciliation.json` | GAP-S2-001-3: zero production callers (PROVEN-UNIT); fail-closed 6-cat was 0/6 applicable |
| R2 (Lead Eval) | DONE | `R2_LEAD_EVAL.md`, `R2_LEAD_EVAL.json` | 0 verdict overrides; 4/4 citations accurate; 1 new P2 gap (LabelTooLong reason_codes misattributed) |
| R3 (Cross-Review + External) | DONE | `R3_RECONCILE_REVIEW_by_AGENT.md`, `R3_RECONCILE_REVIEW_by_AGENT.json`, codex + kimi artifacts | 4/4 AT verdicts AGREE with R1; R3B complete (codex + kimi, enriched + generic); 2 INFO findings (PRD metadata drift) |
| R4 (Synthesis + Gap List) | DONE | `GAP_LIST.json`, `GAP_LIST.md`, `R4B_EXTERNAL_MAPPING.json`, `R4B_EXTERNAL_MAPPING.md`, `DEBT_REGISTER.json` | 7 total gaps (was 5 pre-R3B). 2 genuinely NEW from kimi-enriched (golden vector test, non-canonical field test). 12 of 18 external findings were false positives. 0 P0, 1 P1 (AT-928 WAL dedup -- debt), 6 P2. Zero code changes needed; 2 test additions + 3 PRD metadata fixes. |
| R5 (Remediation) | DONE | `R5_REMEDIATION_PLAN.md`, `R5_REMEDIATION_NOTES.md` | 5/7 gaps fixed (2 tests added, 3 PRD metadata fixes). 2 deferred to debt. ~55 lines of test code + ~15 lines PRD edits. Process overhead: plan + notes + ledger update = ~3x code volume. |
| R5b (Self-Review) | DONE | `SELF_REVIEW_R5b.md`, `R5B_SELF_REVIEW_GATE.json`, `R5B_NO_FIXES_NEEDED.md` | 0 issues found. 5 friction findings (F29-F33): 6-skill stack and 4-phase agent model are massively disproportionate for LOW-risk test-only R5. Proposed R5b-LITE: single-pass, 8 minutes, 3 artifacts. |
| R6 (Verify + Verdict) | DONE | `R6_VERIFY_SUMMARY.md`, `R6_VERIFY_SUMMARY.json` | Verdict: RECONCILED-WITH-DEBT. 11-step checklist: 7 meaningful, 4 ceremony. 5 friction findings (F34-F38). |
| R7 (Post-Recon Validation) | DONE | `R7_POST_RECON_VALIDATION.md`, `SUMMARY.md` | R7a PASS (0 misalignment), R7b SKIP (LOW risk), R7c confirmed PROVEN-UNIT, R7d SKIP (disproportionate), R7e 6/6 mutants caught, R7f debt register valid. 5 friction findings (F39-F43). |

### Cumulative Friction Log

| # | Phase | Finding | Severity | Proposed Fix |
|---|-------|---------|----------|-------------|
| F1 | Mode A | §1 and §6 overlap (clause audit + proof plan trace same chain) | HIGH | Merge into single AT traceability table |
| F2 | Mode A | TRIP/NON-TRIP forced on pure functions | MED | Add "property test" category |
| F3 | Mode A | §4/§8/§9 empty for LOW-risk greenfield | MED | LOW-risk fast-path: make optional |
| F4 | Mode A | ~40% ceremony overhead for LOW-risk | HIGH | Require only §0,§1,§3,§5,§7,§10 for LOW |
| F5 | R1 | Fail-closed 6-category: 0/6 applicable for pure function | HIGH | Allow one-line "N/A: pure function with typed inputs" |
| F6 | R1 | "READ_ONLY" but must create artifact files | MED | Clarify: "no mods to existing files; new artifacts permitted" |
| F7 | R1 | No scope-lock creation script exists | MED | Create `plans/create_scope_lock.sh` |
| F8 | R1 | premortem_ready.sh blocks retroactive recon entry | MED | Add `--recon` flag to allow YELLOW premortems |
| F9 | R1 | Evidence ledger ~176 lines; ~40 lines carry signal | HIGH | SHORT-FORM for LOW-risk: verdict table + gaps + 1 paragraph |
| F10 | R1 | Enforcement/test tables restate premortem | LOW | Could reference premortem instead of duplicating |
| F11 | R2 | R2 escalation rules (step 3) and cross-story checks (step 5) are N/A for LOW-risk single-story -- pure ceremony | LOW | Skip for LOW + single-story; require only for batched MED/HIGH |
| F12 | R2 | Red flag scan (step 6) found nothing; all checks trivially pass for a well-structured R1 | LOW | Downgrade to "spot-check 2 flags" for LOW-risk |
| F13 | R2 | R2 produces ~100 lines for a ledger that had 0 verdict changes -- overhead:signal ratio is high | MED | For 0-override R2, allow a SHORT-FORM: verdict confirmation table + new gaps + rating |
| F14 | R3B | External review tools not available in dry-run environment; R3B gate cannot pass | MED | For dry-run, allow R3B skip with documented friction note |
| F15 | R3A | 8 of 9 checklist items confirmed R1 findings with zero disagreements -- cross-review was mostly verification, not discovery | HIGH | For LOW-risk + AGREE-on-all-verdicts, allow abbreviated R3A: "AGREE ALL + N new gaps" one-liner |
| F16 | R3A | Scope-lock prerequisite (`.wf/recon_scope_lock/`) referenced in RUNBOOK but no creation tooling exists | MED | Same as F7; scope-lock remains unimplemented |
| F17 | R3A | R3A checklist item "combinatorial coverage" is meaningful for multi-input gates but low-value for sequential-buffer hash functions | LOW | Make combinatorial coverage conditional on function type |
| F18 | R4 | Codex (enriched + generic) produced zero actionable findings -- only evidence citations. For LOW-risk pure-function stories, codex adds no signal beyond "I can see the code." | HIGH | For LOW-risk stories, consider codex-only with single prompt style, or skip codex entirely and rely on kimi/opus. |
| F19 | R4 | Kimi enriched vs generic had significant differentiation: enriched found 2 genuinely new gaps (golden vector, non-canonical field); generic found 0 new gaps and its only P1 was a false positive (mis-scoped responsibility boundary). Enriched prompt is strictly superior when premortem context exists. | MED | For stories with premortems, run enriched first and skip generic if enriched is comprehensive. Generic adds value only when no premortem context is available. |
| F20 | R4 | 12 of 18 external findings (67%) were false positives. Most FPs were code-quality observations (buffer sizing, naming, observability) that are valid engineering concerns but not contract gaps. The boundary between "contract gap" and "code quality suggestion" is the primary judgment call in R4. | HIGH | Define explicit filter criteria: "A finding is a gap if it maps to an AT, a premortem S5 wrong-impl, or a fail-closed hazard. All other findings are code-quality suggestions and should be tracked separately." |
| F21 | R4 | R4 was ~90% mechanical aggregation, ~10% judgment. The mechanical part: collecting, deduplicating, assigning IDs. The judgment part: downgrading kimi-generic P1 to false positive (responsibility boundary call) and deciding that kimi-enriched AT-218 "partial" was a false positive. | LOW | R4 could be largely automated with a script that ingests JSON gap lists from R1/R2/R3 and produces a merged list. Only severity disputes and false-positive calls need human/lead judgment. |
| F22 | R4 | For a LOW-risk single-story recon, 4 external review artifacts (2 tools x 2 styles) produced 18 findings, of which only 2 were genuinely new. The signal-to-noise ratio is ~11%. Running 4 external reviews to find 2 P2 test gaps is disproportionate effort. | HIGH | For LOW-risk single-story: 1 tool x 1 style (enriched) should be sufficient. Reserve dual-tool dual-style for MED/HIGH risk or multi-story batches. |
| F23 | R4b | R4b mapping was straightforward because all external findings had clear dispositions. No ambiguous cases, no severity disputes between tools. The anti-gaming value of R4b is theoretical for this story. | LOW | For LOW-risk with 0 P0/P1 external findings, R4b could be a single-line attestation: "All N external findings mapped; 0 unmapped P0/P1." The full mapping table is documentation overhead. |
| F24 | R5 | Cold-start context build (Step 0: read 6 files) was ~80% redundant with R1. The premortem, evidence ledger, and gap list all repeat the same AT verdicts and gap descriptions. Only the prd.json entry and source code were genuinely needed for R5 implementation. | MED | For LOW-risk R5 with only test additions: require reading only GAP_LIST.json + source code + test file. Skip re-reading premortem/ledger unless GAP references them. |
| F25 | R5 | The remediation plan (Step 1) was useful but disproportionate for 2 small test additions + 3 metadata fixes. Writing a formal plan document with file:line targets and expected assertions took longer than implementing the changes. The plan's value was highest for the golden vector test (needed to probe the actual hash value before writing the assertion). | MED | For LOW-risk R5 with <=3 code changes: allow inline plan in R5_REMEDIATION_NOTES.md (single doc) instead of separate PLAN + NOTES. Reserve the full plan document for >=5 changes or MED/HIGH risk. |
| F26 | R5 | Total code written: ~55 lines of Rust tests + ~15 lines of prd.json edits = ~70 lines of actual change. Total process artifacts: R5_REMEDIATION_PLAN.md (~80 lines) + R5_REMEDIATION_NOTES.md (~100 lines) + evidence ledger updates (~20 lines) = ~200 lines of process. Process:code ratio is ~3:1. | HIGH | For LOW-risk stories, the process:code ratio should be <=1:1. Combine plan + notes into a single document. Reduce evidence ledger updates to a single status column addition. |
| F27 | R5 | PRD metadata fixes (GAP-1, GAP-4, GAP-5) were entirely mechanical and zero-risk. Editing JSON arrays in prd.json required no judgment beyond confirming the gap description was correct. These could be automated with a jq script. | LOW | Create `plans/prd_metadata_fix.sh` for mechanical PRD fixes. |
| F28 | R5 | The golden vector probe (temporary panic test to capture actual hash value, then pin it) was the most valuable part of R5. This pattern should be documented as a standard technique. | LOW | Document the "probe test" pattern in RUNBOOK or DESIGN_PATTERNS. |
| F29 | R5b | 6-skill parallel review (`/pr-review`, `/failure-mode-review`, `/strategic-failure-review`, `/contract-review`, `/validator-audit`, `/devils-advocate`) for 2 test additions + 3 metadata fixes. All 6 would return "PASS, 0 findings." | HIGH | For LOW-risk test-only R5: skip 6-skill stack entirely. Single-pass review covering 4 checks (quality, contract, fail-closed, wrong-impl) is sufficient. |
| F30 | R5b | 4-phase agent model (reviewer -> planner -> fixer -> re-runner) adds 3 unnecessary decision points when R5b.1 finds 0 issues. Phases 2-4 collapse to "no fixes needed." | HIGH | For 0-finding R5b.1: collapse to single-phase with binary PASS/FAIL gate. Reserve 4-phase for >0 findings. |
| F31 | R5b | 6 JSON receipt files (one per skill) with near-zero information density ("PASS, 0 findings" x6). | MED | Single gate JSON with a checks object (4 keys) replaces 6 receipt files. |
| F32 | R5b | Minimum viable R5b for test-only changes: (1) do tests pass? (2) do assertions match gap descriptions? (3) can a wrong impl survive? Total: 5 minutes. Everything else is ceremony. | HIGH | Define R5b-LITE as the default for LOW-risk test-only R5 changes. |
| F33 | R5b | Proposed R5b-LITE: 1 agent phase, 0 skill invocations, 3 artifacts, ~8 minutes. vs FULL R5b: 4 agent phases, 6 skill invocations, 9+ artifacts, ~60 minutes. Signal difference: zero (both produce PASS for this story). | HIGH | Codify R5b-LITE in RUNBOOK. Escalation trigger: R5 touched production code OR >50 lines non-test. |
| F34 | R6 | Steps 1-3 (P0 closed, P1 closed, escalation) are 3 separate checks reducible to a single GAP_LIST.json jq query. 30 seconds of work in 3 minutes of checklist. | MED | Single "unresolved gaps" check for LOW-risk. |
| F35 | R6 | Phantom test check (step 5) requires manual cross-referencing PRD implementation_tests vs grep. Should be a script. | MED | Automate: `plans/check_phantom_tests.sh S2-001`. |
| F36 | R6 | STOPLIGHT recheck (step 7) -- STOPLIGHT never changes after R5 in retroactive recon. Always "same as before." | LOW | Skip STOPLIGHT recheck for retroactive recon. |
| F37 | R6 | Postmortem gate (step 11) -- YELLOW + safety-critical almost never co-occur for LOW-risk. Always NO. | LOW | Skip postmortem gate for LOW-risk. |
| F38 | R6 | R6 overall: 7 of 11 steps meaningful, 4 ceremony. ~10 min meaningful, ~5 min ceremony. | MED | 7-step R6-LITE for LOW-risk. |
| F39 | R7d | External Review Cycle 2 skipped: 70 lines of test+JSON does not justify external API call. R5b already covered same changes. | HIGH | For LOW-risk test-only R5: skip R7d. Require only when R5 touched production code. |
| F40 | R7b | Strategic failure review skip-justification required a paragraph. Should be a simple gate. | LOW | Add skip-gate to RUNBOOK: `risk_tier == LOW && touches_safety_critical == false -> SKIP`. |
| F41 | R7e | Mutation testing (8 min) was highest-signal R7 sub-phase. 6/6 mutants caught = objective proof. Should be mandatory. | MED | Make R7e mandatory for all risk tiers. |
| F42 | R7f | Debt register validation is mechanical. Could be a jq script. | LOW | Create `plans/validate_debt_register.sh`. |
| F43 | R7 | R7 had 7 sub-phases; only 4 needed for LOW-risk (R7a, R7c, R7e, R7f). 3 skipped (R7b, R7c-fix, R7d). | HIGH | For LOW-risk: require only R7a + R7c + R7e + R7f. |

### Resume Command

```
DRY-RUN COMPLETE. S2-001 reconciliation finished: Mode A through R7, all phases executed. Verdict: RECONCILED-WITH-DEBT. 43 friction findings. See SUMMARY.md for full roll-up and proposed LOW-risk fast-path pipeline.
```

### Dry-Run Summary

**Total friction findings**: 43 (F1-F43)

**Top 5 by severity**:

| Rank | ID | Phase | Finding | Severity |
|------|-----|-------|---------|----------|
| 1 | F4 | Mode A | ~40% ceremony for LOW-risk (empty premortem sections) | HIGH |
| 2 | F9 | R1 | Evidence ledger ~176 lines; ~40 carry signal | HIGH |
| 3 | F22 | R4 | 4 external reviews for 2 new P2 findings (11% signal rate) | HIGH |
| 4 | F29 | R5b | 6-skill stack for 2 test additions + 3 metadata fixes | HIGH |
| 5 | F43 | R7 | 7 sub-phases; only 4 needed for LOW-risk | HIGH |

**Proposed LOW-risk fast-path** (estimated ~1.75 hours, ~10 artifacts):

| Step | Phase | Time | Key Change vs Full |
|------|-------|------|--------------------|
| 1 | Mode A-LITE | 20 min | Skip empty sections (§4/§8/§9) |
| 2 | R1-LITE | 15 min | SHORT-FORM ledger; skip 6-cat fail-closed for pure functions |
| 3 | R3B-LITE | 10 min | 1 tool x 1 prompt style (enriched only) |
| 4 | R4 (Synthesis) | 10 min | Same as full |
| 5 | R5 (Remediation) | 15 min | Combined plan+notes single doc |
| 6 | R5b-LITE | 8 min | Single-pass, 4 checks, 1 gate artifact |
| 7 | R6-LITE | 8 min | 7-step checklist (skip 4 ceremony steps) |
| 8 | R7-LITE | 15 min | R7a + R7c + R7e (mandatory mutation) + R7f only |
| **Total** | | **~1.75h** | **50% time reduction, 63% artifact reduction vs full** |

**Escalation triggers** (require full pipeline): production code changes, MED/HIGH risk, P0 gap found, safety-critical paths touched.

## HANDOFF — Reconciliation Dry-Run (Current: S2-000 Step 8 blocked)

- Stopped at: `S2-000 Step 8 (verify_full) blocked — NO-GO`
- What happened:
  - Completed Step 6 (cycle2) and Step 7 (resolution), with receipts written.
  - Attempted Step 8 and ran `./plans/verify.sh full` twice.
  - First full verify failed in `preflight` (`test_artifact_lint`), then artifact-lint was fixed and re-run green.
  - Latest full verify still fails at `rust_fmt`, so `FAILED_GATE` remains and Step 8 is still blocked.
- Must read first:
  - `reviews/reconciliations/S2/S2-000_step7_report.md`
  - `reviews/reconciliations/S2/S2-000_step8_report.md`
  - `reviews/reconciliations/S2/HANDOFF.md` (Reconciliation Dry-Run section)
  - `artifacts/verify/20260226_185444/rust_fmt.log`
- Next steps (exact commands):
  - `rustfmt crates/soldier_core/tests/test_idempotency.rs`
  - `./plans/verify.sh full`
  - `WF_RECON_MODE=1 plans/wf_step.sh S2-000 verify_full --dry-run`
  - `WF_RECON_MODE=1 plans/wf_step.sh S2-000 verify_full`
  - `plans/wf_step.sh S2-000 --status`
- Resume command:
  - `Resume S2-000 continuation from reviews/reconciliations/S2/HANDOFF.md; clear rust_fmt failure, rerun full verify, then complete Step 8 and Step 9.`
