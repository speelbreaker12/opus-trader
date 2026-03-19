---
status: in-progress
priority: P2
branch: feat/chairman-synthesis
base: main
pr:
started: "2026-03-19"
aliases: []
keywords: [chairman, synthesis, multi-model, review, council]
scope_paths:
  - plans/chairman_synthesis.sh
  - plans/parallel_review.sh
  - plans/review_logged.sh
  - obsidian/Projects/chairman-synthesis.md
  - obsidian/Debriefs/chairman-synthesis*
---

## Current State

`plans/chairman_synthesis.sh` implemented and integrated into `plans/parallel_review.sh`
via `--chairman` flag. Script reads parallel reviewer artifacts (codex/sonnet/opus/kimi/gemini)
from a review run directory, calls a chairman model (opus or sonnet) to synthesize
deduplicated findings ordered by severity and consensus, and writes `chairman.md` +
`chairman.sidecar.json` into `<run_dir>/chairman/`.

Also fixed `review_logged.sh` to always build diff context for all tools so that
the codex exec fallback path has content available.

## Commits
- `pending` — 2026-03-19 — Integrate chairman synthesis into parallel review pipeline

## Key Files
- plans/chairman_synthesis.sh
- plans/parallel_review.sh
- plans/review_logged.sh

## Debriefs
- [[chairman-synthesis 2026-03-19 Add Chairman Script]]
- [[chairman-synthesis 2026-03-19 Pipeline Integration]]

## Log
### 2026-03-19
- Authored `plans/chairman_synthesis.sh`: multi-model review council synthesis script
- Reads artifacts from known tools (codex, sonnet, opus, kimi, gemini) for a given run dir
- Supports --tool (opus/sonnet), --style (generic/enriched), --dry-run flags
- Writes canonical markdown artifact with YAML provenance frontmatter and JSON sidecar
- Python inline script parses chairman output to extract P0-P3 findings with consensus counts
- Integrated chairman into `parallel_review.sh` via `--chairman <sonnet|opus>` flag
- Fixed citation regex in chairman_synthesis.sh to accept line ranges (e.g. `file.py:10-20`)
- Fixed `review_logged.sh` to always build diff context for all tools (codex exec fallback fix)
