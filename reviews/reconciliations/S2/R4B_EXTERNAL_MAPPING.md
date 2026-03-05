---
provenance:
  tool: internal
  model: claude-opus-4-6
  prompt_style: none
  cycle: NONE
  phase_equivalent: R4b
  review_basis: "LEAD_SYNTHESIS"
  story_id: S2-001
  slice_id: S2
  head_commit: "c034cfee2be6d3131d155215572e8e42dd1bab01"
  generated_at: "2026-03-05T17:50:46Z"
  artifact_provenance: manual
  schema_version: "phase_mapping.v1"
---

# R4b External Finding Mapping: S2-001

## External Review Matrix (Cycle 1 rerun, 2026-03-05)

| Tool | Style | Status | Findings (P0/P1/P2) | Source |
|---|---|---|---|---|
| codex | enriched | SUCCESS | 2 / 4 / 2 | `artifacts/story/S2-001/codex/codex.enriched.sidecar.json` |
| codex | generic | SUCCESS | 0 / 2 / 4 | `artifacts/story/S2-001/codex/codex.generic.sidecar.json` |
| kimi | enriched | SUCCESS | 0 / 2 / 2 | `artifacts/story/S2-001/kimi/kimi.enriched.sidecar.json` |
| kimi | generic | SUCCESS | 0 / 0 / 3 | `artifacts/story/S2-001/kimi/kimi.generic.sidecar.json` |
| gemini | enriched | SUCCESS | 1 / 1 / 2 | `artifacts/story/S2-001/gemini/gemini.enriched.sidecar.json` |
| gemini | generic | SUCCESS | 0 / 0 / 2 | `artifacts/story/S2-001/gemini/gemini.generic.sidecar.json` |
| opus | enriched | SUCCESS | 0 / 2 / 5 | `artifacts/story/S2-001/opus/opus.enriched.sidecar.json` |
| opus | generic | SUCCESS | 0 / 1 / 1 | `artifacts/story/S2-001/opus/opus.generic.sidecar.json` |

## Model Compare (Aggregated Across Prompts)

| Model | P0 | P1 | P2 | Total Findings | Blocking (P0+P1) |
|---|---:|---:|---:|---:|---:|
| codex | 2 | 6 | 6 | 14 | 8 |
| opus | 0 | 3 | 6 | 9 | 3 |
| kimi | 0 | 2 | 5 | 7 | 2 |
| gemini | 1 | 1 | 4 | 6 | 2 |

## Notes

1. All 8 external review combos completed with real tool calls and produced schema-valid sidecars.
2. Parser coverage now includes Gemini severity labels and Opus `F-<n>` heading style.
3. Gemini `3.1-pro-preview` required retry due transient capacity exhaustion, but final runs completed successfully.

## Mapping Outcome

- `GAP-S2-001-EXTERNAL-BLOCKING-PROOF`: Codex + Gemini enriched blocking proof/AT-ownership concerns.
- `GAP-S2-001-EXTERNAL-HASH-CANONICALIZATION`: Codex/Kimi/Gemini generic canonicalization and input-validation concerns.
- `GAP-S2-001-EXTERNAL-PROOF-COVERAGE`: Kimi + Opus proof-chain, golden-vector, and causality-test quality concerns.

## Gate Checks

| Gate ID | Status | Notes |
|---|---|---|
| `R4B_ALL_FINDINGS_MAPPED` | PASS | Every external batch has an explicit gap mapping. |
| `R4B_NO_UNMAPPED_P0_P1` | PASS | No unmapped P0/P1 entries remain. |
