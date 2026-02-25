# Reconciliation Handoff — S1

---

## Your Role (read this first)

You are a **Reconciliation Agent** working on `S1`.

Your job is to complete the 9-step reconciliation workflow for the in-scope stories and enforce machine-verifiable proof artifacts.

### Source-of-Truth Documents (read before starting any step you're unfamiliar with)

| Document | Path |
|----------|------|
| RUNBOOK | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` |
| POLICY | `reviews/premortems/PREMORTEM_RECON_POLICY.md` |
| INDEX + R1 prompt | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` |
| ANTI-PATTERNS | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` |
| METRICS | `reviews/premortems/PREMORTEM_RECON_METRICS.md` |

## Slice Context

| Field | Value |
|-------|-------|
| Slice ID | S1 |
| Integration branch | main |
| Stories in scope | S1-001, S1-002, S1-003, S1-004, S1-005, S1-006, S1-007, S1-008, S1-009, S1-010, S1-011, S1-012, S1-013 |
| Started | 2026-02-25 |
| Last updated | 2026-02-25 |

## Story Status Matrix

Fill as you go. Symbols: `·` not started · `→` in progress · `✓` done · `✗` blocked

| Story | preflight | implement | self_review | cycle1 | fix | cycle2 | resolution | verify | pass |
|-------|-----------|-----------|-------------|--------|-----|--------|------------|--------|------|
| S1-001 | · | · | · | · | · | · | · | · | · |
| S1-002 | · | · | · | · | · | · | · | · | · |
| S1-003 | · | · | · | · | · | · | · | · | · |
| S1-004 | · | · | · | · | · | · | · | · | · |
| S1-005 | ✓ | ✓ | ✓ | ✓ | · | · | · | · | · |
| S1-006 | · | · | · | · | · | · | · | · | · |
| S1-007 | ✓ | ✓ | ✓ | ✓ | · | · | · | · | · |
| S1-008 | · | · | · | · | · | · | · | · | · |
| S1-009 | · | · | · | · | · | · | · | · | · |
| S1-010 | ✓ | ✓ | ✓ | ✓ | · | · | · | · | · |
| S1-011 | · | · | · | · | · | · | · | · | · |
| S1-012 | · | · | · | · | · | · | · | · | · |
| S1-013 | · | · | · | · | · | · | · | · | · |

## Per-Story Work Log

### S1-005

**Premortem**: `reviews/premortems/S1-005_premortem.md` — STOPLIGHT: UNKNOWN

#### Step 1 · preflight (R1 — read-only audit)

- Reference: RUNBOOK §3 → R1
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-005/00_preflight.json`
- Gate: UNKNOWN
- Notes: Reviewed prior external review artifacts existed for all prompt/tool combinations.

#### Step 2 · implement (R5 — code fixes)

- Reference: RUNBOOK §3 → R5
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-005/01_implement.json`
- Notes: No production code changes in this pass; review tooling rerun only.

#### Step 3 · self_review (R5b — 6-skill stack)

- Reference: RUNBOOK §3 → R5b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-005/02_self_review.json`
- Notes: Prior self-review artifacts were already present.

#### Step 4 · cycle1 (R2+R3+R4+R4b — external review)

- Reference: RUNBOOK §3 → R2, R3, R4, R4b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-005/03_cycle1.json`
- External manifest: `artifacts/story/S1-005/R3_EXTERNAL_MANIFEST.json`
- Notes: Re-ran external C1 reviews for codex/kimi generic+enriched. Sidecars were fixed to valid JSON after logger patch.

#### Step 5 · fix (R7a+R7b+R7c reviews → R7c-fix)

- Reference: RUNBOOK §3 → R7a/R7b/R7c
- Status: NOT_STARTED
- Receipt: `.wf/receipts/S1-005/04_fix.json`

### S1-007

**Premortem**: `reviews/premortems/S1-007_premortem.md` — STOPLIGHT: UNKNOWN

#### Step 1 · preflight (R1 — read-only audit)

- Reference: RUNBOOK §3 → R1
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-007/00_preflight.json`

#### Step 2 · implement (R5 — code fixes)

- Reference: RUNBOOK §3 → R5
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-007/01_implement.json`

#### Step 3 · self_review (R5b — 6-skill stack)

- Reference: RUNBOOK §3 → R5b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-010/02_self_review.json`

#### Step 4 · cycle1 (R2+R3+R4+R4b — external review)

- Reference: RUNBOOK §3 → R2, R3, R4, R4b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-007/03_cycle1.json`
- External manifest: `artifacts/story/S1-007/R3_EXTERNAL_MANIFEST.json`
- Notes: Re-ran external C1 reviews for codex/kimi generic+enriched. Sidecars validated after logger fix.

### S1-010

**Premortem**: `reviews/premortems/S1-010_premortem.md` — STOPLIGHT: UNKNOWN

#### Step 1 · preflight (R1 — read-only audit)

- Reference: RUNBOOK §3 → R1
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-010/00_preflight.json`

#### Step 2 · implement (R5 — code fixes)

- Reference: RUNBOOK §3 → R5
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-010/01_implement.json`

#### Step 3 · self_review (R5b — 6-skill stack)

- Reference: RUNBOOK §3 → R5b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-007/02_self_review.json`

#### Step 4 · cycle1 (R2+R3+R4+R4b — external review)

- Reference: RUNBOOK §3 → R2, R3, R4, R4b
- Status: COMPLETE
- Receipt: `.wf/receipts/S1-010/03_cycle1.json`
- External manifest: `artifacts/story/S1-010/R3_EXTERNAL_MANIFEST.json`
- Notes: Re-ran external C1 reviews for codex/kimi generic+enriched. Sidecars validated after logger fix.

### Other S1 stories (scope-expanded set)

- `S1-001`, `S1-002`, `S1-003`, `S1-004`, `S1-006`, `S1-008`, `S1-009`, `S1-011`, `S1-012`, `S1-013` have pre-existing C1 artifacts for:
  - `artifacts/story/<story>/R3_EXTERNAL_MANIFEST.json`
  - `artifacts/story/<story>/codex/{codex.generic.md,codex.enriched.md}`
  - `artifacts/story/<story>/kimi/{kimi.generic.md,kimi.enriched.md}`
- Reconciliation step artifacts (`.wf/receipts/<story>/<step>.json`) are still pending for these stories.
- Next actions should create cycle1 receipts for each newly included story and then advance through fix/resolve steps if needed.

## Process Backlog

> Inherits S0 backlog + new S1 findings. P0 = blocks progress · P1 = repeated rework · P2 = friction.
> Next slice lead must patch all P0/P1 entries before starting Step 1.

| # | Step | §8 rule (condensed) | Severity | Fix target | §11 status |
|---|------|---------------------|----------|-----------|-----------|
| 1 | cycle1 | `rule: lock story scope at R1 completion, not at cycle1 start · trigger: before running any cycle1 review · prevents: scope expansion mid-cycle requiring preflight re-run · enforce: add scope-lock gate to RUNBOOK §3 R1 final step` | P1 | RUNBOOK §3 R1 | open |
| 2 | cycle1 | `rule: confirm review_logged.sh sidecar patch is on HEAD before any cycle · trigger: slice start checklist · prevents: sidecar parse failures from logger preamble text (S0 recurrence) · enforce: add git log check to slice start checklist` | P0 | tooling (`plans/review_logged.sh`) | open |
| 3 | self_review | `rule: validate receipt story ID matches receipt path story ID · trigger: wf_step.sh before writing any receipt · prevents: cross-wired receipt paths (S1-007 referenced S1-010 path) · enforce: add ID-path consistency check to wf_step.sh` | P2 | tooling (wf_step.sh) | open |
| 4 | cycle1 | `rule: do not reference batch gate scripts that don't exist · trigger: HANDOFF authoring · prevents: next agent hitting missing-script error · enforce: verify all script paths exist before writing HANDOFF next steps` | P1 | RUNBOOK / template | open |
| 5 | cycle1 | `rule: only rerun missing/failed Cycle 1 review combinations · trigger: scope expands or failed sidecars seen · prevents: unnecessary rework/noise in external review queue · enforce: add `plans/review_missing_refresh.sh` as a deterministic replay path` | P2 | tooling (`plans/review_missing_refresh.sh`) | DONE |

---

## HANDOFF

### Stopped at

- Story: `S1-002`
- Step: `cycle1`
- Status: `Scope expanded to all S1 stories; next step is deterministic missing/failed-cycle1 refresh`
- HEAD at stop: `03b3ebcb4a51c2cfca372094d55057bc59de5937`

### What happened (2–5 bullets)

- Scope is still the full S1 set (`S1-001` through `S1-013`).
- Existing C1 external review coverage exists for all stories, but one Codex sidecar was normalized in the logger path (`plans/review_logged.sh`) to prevent malformed `*.sidecar.json`.
- Added a replay helper (`plans/review_missing_refresh.sh`) that can refresh only missing or failed-cycle1 review combos.
- `S1-013` Codex artifact refreshes in C1 were run for both prompts and validated as part of manual checks; run the same helper to sweep all remaining missing/failed combos.

### Must read first (in order)

1. `plans/review_logged.sh` — contains the patched sidecar logic used in this rerun.
2. `reviews/reconciliations/S1/HANDOFF.md` — this file.
3. `plans/review_missing_refresh.sh` — helper for deterministic C1 missing/failed reruns.
4. `artifacts/story/<story>/R3_EXTERNAL_MANIFEST.json` and `artifacts/story/<story>/*/*.sidecar.json` — review artifacts and validation output.

### Next steps (exact actions)

1. Run `./plans/review_missing_refresh.sh --base main --mode failed --tools codex,kimi --prompts enriched,generic`.
   - Use `--story <ID>` to target one story, or pass any subset without `--story` to default all S1.
2. Re-run your cycle1 receipt command/gate (`wf_step.sh cycle1` per story) after refresh, then create `.wf/receipts/<story>/03_cycle1.json`.
3. For any story with remaining C1 findings, continue Step 5 (R7 path) using existing reconcilation docs in this slice.

### Open decisions / blockers

- None confirmed. Validate whether cycle1 gate should reissue to a fresh manifest location under `reviews/reconciliations/S1/external/cycle1/*` if required by local convention.

### Resume command

```bash
STEP_SUPERVISOR_BASE_BRANCH=main \
  plans/step_supervisor.sh S1-001 prompt --recon
```
