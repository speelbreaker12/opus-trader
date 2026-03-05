---
provenance:
  tool: internal
  model: claude-opus-4-6
  prompt_style: none
  cycle: NONE
  phase_equivalent: R4c
  review_basis: "EXTERNAL_COMPARE"
  story_id: S2-001
  slice_id: S2
  head_commit: "c034cfee2be6d3131d155215572e8e42dd1bab01"
  generated_at: "2026-03-05T17:50:47Z"
---

# R4c Model Findings Compare: S2-001

## Per-Model Counts (generic + enriched)

| Model | P0 | P1 | P2 | Blocking (P0+P1) |
|---|---:|---:|---:|---:|
| codex | 2 | 6 | 6 | 8 |
| opus | 0 | 3 | 6 | 3 |
| kimi | 0 | 2 | 5 | 2 |
| gemini | 1 | 1 | 4 | 2 |

## Theme Overlap Matrix

| Theme | Codex | Kimi | Gemini | Opus |
|---|---|---|---|---|
| AT ownership / scope mismatch (AT-201, AT-928) | YES | YES | YES | YES |
| Golden-vector / test-oracle weakness | YES | YES | YES | YES |
| Canonicalization / input-validation hardening | YES | PARTIAL | YES | PARTIAL |
| Premortem-to-implementation decision drift | YES | NO | PARTIAL | YES |

## Notes

- Strongest overlap across all four: AT scope/proof-chain mismatch and missing hardcoded golden-vector anchors.
- Codex surfaced the highest blocker volume.
- Codex and Gemini are the only models surfacing P0 findings in this run set.
- Opus added broad P2 hardening depth after parser normalization (`F-<n>` heading support).
