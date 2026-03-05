# R5b Self-Review: S2-001 (Post-Rerun)

**Story**: S2-001  
**Phase**: R5b  
**Date**: 2026-03-05  
**Reviewer**: internal synthesis (post external rerun)

## Objective

Confirm that external review findings are correctly ingested into reconciliation artifacts and not silently dropped.

## What Changed In This Rerun

1. Patched `plans/review_logged.sh` severity parsing so `FINDINGS_SUMMARY` and sidecar counts include:
   - `- **Severity:** P1-High` style (Gemini)
   - `1. **P2 - ...**` style
   - `### F-1 · P1 · ...` heading style (Opus)
2. Fixed missing Gemini timeout default in `plans/review_logged.sh`.
3. Re-ran external reviews with real tool calls for all four models across `enriched` and `generic` prompts.
4. Revalidated sidecars and rebuilt R4 mapping/compare artifacts from current counts.

## External Rerun Evidence

| Tool | Enriched | Generic | Notes |
|---|---|---|---|
| codex | SUCCESS (`P0=2 P1=4 P2=2`) | SUCCESS (`P0=0 P1=2 P2=4`) | Highest blocker yield in this run set.
| kimi | SUCCESS (`P0=0 P1=2 P2=2`) | SUCCESS (`P0=0 P1=0 P2=3`) | Strong proof-coverage and metadata-gap detection.
| gemini | SUCCESS (`P0=1 P1=1 P2=2`) | SUCCESS (`P0=0 P1=0 P2=2`) | Needed retry due transient model capacity exhaustion; final sidecars valid.
| opus | SUCCESS (`P0=0 P1=2 P2=5`) | SUCCESS (`P0=0 P1=1 P2=1`) | Parser now correctly counts `F-<n>` heading format.

## Root Cause Confirmation

The earlier self-review missed Gemini findings because:
1. self-review artifacts were generated before Gemini artifacts existed for that rerun path; and
2. parser patterns did not capture Gemini `Severity:` style output, yielding zero sidecar counts.

A secondary parser gap existed for Opus enriched output (`F-<n>` headings), now fixed and regression-tested.

## Why Self-Review Previously Missed Gemini Findings

- R5b skill selection consumes sidecar counts.
- Gemini sidecars previously had `P0/P1/P2 = 0/0/0` due parser mismatch.
- Zero-count bundles were de-prioritized in the R5b synthesis path.
- After parser fix and rerun, Gemini contributes blockers and is represented in gate totals.

## Gate Assessment

- `R5B_SELF_REVIEW_PROVEN`: **FAIL (pending remediation)**
- Blocking reasons:
  1. External blockers remain (`P0/P1`) across successful runs and are not remediated in code/docs.
  2. Cross-model overlap confirms repeated AT ownership/proof-causality and golden-vector proof concerns.

## Required Follow-up

1. Triage and disposition all blocking findings, especially Codex/Gemini enriched blocker set.
2. Decide and normalize S2-001 AT ownership metadata (`AT-201`, `AT-928`) in PRD + evidence ledger.
3. Add/pin golden-vector proof and remove tautological proof patterns where unresolved.
