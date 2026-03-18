# Reconcil Process Audit — 2026-02-26

**Goal**: Find inconsistencies, issues, and improvement opportunities to make reconcil simpler, faster, less paperwork, higher code review quality.

---

## Section 1: Hard Inconsistencies

**I-1: Pass-flip gate count wrong in HANDOFF template**
- HANDOFF_TEMPLATE.md Step 9 says "15 checks" — prd_set_pass.sh has 12 gates
- Fix: update template Step 9 reference

**I-2: R5B_SELF_REVIEW_GATE.json is slice-level but treated as per-story**
- File lives at `reviews/reconciliations/<SLICE>/R5B_SELF_REVIEW_GATE.json` (one per slice)
- wf_step.sh self_review checks `artifacts/story/<STORY>/self_review/*.md` — different path, different scope
- A clean story can pass with a gate file containing another story's UNPROVEN findings
- Fix: move gate file to per-story `artifacts/story/<STORY>/self_review_gate.json`

**I-3: Evidence ledger has 4 candidate paths, none match actual S1 location**
- wf_step.sh cycle1 checks: `artifacts/story/<STORY>/*_reconciliation.md/json` + `evidence_ledger.*`
- S1 ledgers live at `reviews/reconciliations/S1/<STORY>_reconciliation.md` — NOT in that list
- This silently fails the evidence_found check for all S1 stories
- Fix: add slice-level path to lookup OR enforce single canonical path

**I-4: step_supervisor.sh deprecated but RUNBOOK still references it**
- Script has deprecation banner; removal conditions all satisfied
- RUNBOOK §3 still shows "Step Supervisor Phase Mapping" decoder table
- Fix: remove table from RUNBOOK §3, replace with direct wf_step.sh commands; archive script

**I-5: R3_EXTERNAL_MANIFEST.json validator fails all S1 stories — root cause in schema_version**
- Validator line 853: `FAIL: unknown phase={phase!r} (expected R3 or R7d)`
- Manifests have `"phase": "R3"` correctly, BUT the provenance block lacks `"schema_version": "r3_external_manifest.v2"`
- Schema `provenance_script_r3` requires `schema_version` as a required field
- S1 manifests were generated before v2 schema was finalized — missing that field
- Fix: add `"schema_version": "r3_external_manifest.v2"` to provenance block in all S1 manifests, OR make validator accept v1 provenance blocks with a warning

**I-6: cycle2 review count check can't distinguish C1 from C2 artifacts**
- wf_step.sh cycle2 counts files in `artifacts/story/<STORY>/{codex,opus,kimi}/` — same dirs as C1
- A story that never ran C2 passes if C1 had ≥1 review
- Fix: separate C1/C2 artifact directories, or add basis-label check requiring ≥1 artifact with `Review basis: FIX_DIFF`

---

## Section 2: Structural Issues

**S-1: 9-step / 16-R-phase mismatch creates constant lookup overhead**
- "step 4 (cycle1)" = R2 + R3A + R3B + R4 + R4b — requires reading 5 RUNBOOK sections
- wf_step.sh only tracks outer step; doesn't enforce R-phase completion within it
- Fix: add gap_list existence check inside cycle1 validation; or flatten R-phases into wf_step.sh steps

**S-2: Mode A (7-phase premortem authoring) is massive overhead for retroactive context**
- Mode A was designed for pre-implementation; retroactive context constrains design space
- 7 phases (parallel write → lead eval → patch → cross-review → synthesis → patch → verify) for 1-3 stories
- Fix: add "Mode A — Retroactive (single story)" option: 1 writer reads implementation → lead spot-checks AT ownership conflicts. No cross-review needed.

**S-3: 11-part debrief blocks per step generate noise, not signal**
- 99 debrief fields per story (§0-§11 × 9 steps)
- In practice almost all are "CLEAN" or blank
- §0: CLEAN shortcut was added — implicit acknowledgment the structure is too heavy
- Fix: remove §1-§11 from step blocks; keep only Status/Receipt/Gate/artifact-paths + one `Notes:` line; promote real friction to Process Backlog (already exists)

**S-4: ~45 artifact files per story × 138 stories = ~6,200 files at project end**
- High signal artifacts (keep): evidence_ledger.md, R3_EXTERNAL_MANIFEST.json, proof_graph.json, GAP_LIST.json, DEBT_REGISTER.json, review_resolution.md, 9 receipts
- Low signal (merge/eliminate): R2_LEAD_EVAL → embed in evidence_ledger header; R3 cross-review findings → flow into GAP_LIST; R4B mapping → field in GAP_LIST; R5 plan/notes → single remediation.md; R5B fix plan/log → section in self_review.md; R7A/B/C reviews → single fix_cycle_audit.md; GAP_LIST.md → auto-render; postmortem → section in review_resolution.md
- Target: ~12 files per story (down from ~45)

**S-5: 5 documentation files (~3,450 lines) to read before executing one step**
- PROCESS.md + RUNBOOK + POLICY + ANTIPATTERNS + METRICS all listed as required reading
- Fix: consolidate to 2 files: PROTOCOL.md (operational: steps + gates + verdicts + schemas inline) + EXAMPLES.md (worked examples + anti-patterns + lessons)

---

## Section 3: Improvement Opportunities

**O-1: Reduce artifact count from ~45 to ~12 per story** (see S-4 above)

**O-2: Add `prd_set_pass.sh <ID> true --dry-run`**
- Currently no way to pre-check 12 gates without actually flipping passes=true
- `wf_step.sh pass` only checks 8 receipt files, not PRD fields
- Fix: dry-run mode runs all 12 checks, writes nothing

**O-3: Document GREEN fast-path explicitly**
- GREEN path (0 findings) still requires 9 steps with 5 being paperwork-only
- The relaxation infrastructure exists (recon_relaxation, cycle2_path.mode=recon_clean_single)
- Proposed fast-path: R1 preflight → cycle1 (external dual-prompt) → if 0 findings → verify_full → pass (4 effective steps)
- Fix: add explicit GREEN fast-path table to RUNBOOK mode selection

**O-4: Apply S0-PB-4 — scope mechanical check in verify_fork.sh to src/ only** (recurring false-failures)

**O-5: Flatten R-phase terminology to match wf_step.sh steps**
- Removes decoder-ring lookup table; sub-phases become ordered bullet points within steps

**O-6: Consolidate premortem_ready.sh into wf_step.sh preflight**
- Both run the same PREMORTEM_READY validation; RUNBOOK describes both as separate actions
- Fix: wf_step.sh preflight IS the premortem_ready gate; remove manual step from RUNBOOK

**O-7: Replace §0-§11 debrief with single `friction:` line per step**
- Written only when something broke or took significantly longer than expected
- Format: `friction: <what broke> · root cause: <file:line> · fix needed: <action>`

---

## Section 4: S0 Process Backlog (open P0/P1) — Action Before S1 Continues

| # | Severity | Action |
|---|----------|--------|
| PB-1 | P1 | Add `PREFLIGHT_TIMEOUT=1200` to RUNBOOK §3 verify_full section |
| PB-2 | P1 | Add sidecar JSON validator call to review_logged.sh exit path |
| PB-3 | P1 | Add per-finding closure field + worked example to R5b gate schema |
| PB-4 | P1 | Scope mechanical check in verify_fork.sh to src/ only |
| PB-5 | P2 | Add "next step: run fix" prompt after cycle1 receipt write |

---

## Section 5: What's Working Well (Keep)

- wf_step.sh receipt chain with HEAD-sha anchoring
- prd_set_pass.sh 12-check gate sequence
- TRIP/NON-TRIP causal proof requirement (highest-signal check)
- Fail-closed as a first-class verdict (WRONG_IMPL_UNBLOCKED, CLAIMED_NOT_PROVEN)
- proof_graph.json with 60 validation rules
- Dual-prompt external review (enriched + generic, anti-pattern #25)

---

## Prioritized Action List

| Priority | Issue | Fix | Effort |
|----------|-------|-----|--------|
| P0 | I-3: evidence ledger path not found for S1 | Add `reviews/reconciliations/*/` to wf_step.sh cycle1 lookup | 30m |
| P0 | I-5: S1 manifests missing `schema_version` in provenance | Add field to all S1 manifests OR make validator accept v1 | 1h |
| P1 | PB-4: mechanical check false-fails on test files | Scope to src/ in verify_fork.sh | 15m |
| P1 | PB-1: verify.sh full times out at 900s | Add PREFLIGHT_TIMEOUT=1200 to RUNBOOK §3 | 5m |
| P1 | I-4: step_supervisor still in RUNBOOK | Remove table, archive script | 30m |
| P1 | I-6: cycle2 can't distinguish from C1 artifacts | Add basis-label check or separate dirs | 1h |
| P1 | I-1: HANDOFF template says "15 checks" not 12 | Update template Step 9 | 5m |
| P2 | PB-2: sidecar validator in review_logged.sh | Add validator call to exit path | 2h |
| P2 | I-2: R5B gate is slice-level not story-level | Move to per-story path | 1h |
| P2 | O-2: prd_set_pass.sh --dry-run | Implement dry-run mode | 2h |
| P2 | O-3: GREEN fast-path not documented | Add to RUNBOOK mode selection table | 2h |
| P3 | O-1: reduce artifact count ~45→~12 | Merge low-signal artifacts | 1 day |
| P3 | O-5: consolidate 5 docs to 2 | PROTOCOL.md + EXAMPLES.md | 1 day |

---

**Implementation approach**: Use obra/superpowers (github.com/obra/superpowers) subagent-driven development skill — plan first, then dispatch parallel agents per independent fix group.
