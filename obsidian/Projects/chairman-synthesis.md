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
  - obsidian/Projects/chairman-synthesis.md
---

## Current State

`plans/chairman_synthesis.sh` implemented. Script reads parallel reviewer artifacts
(codex/sonnet/opus/kimi/gemini) from a review run directory, calls a chairman model
(opus or sonnet) to synthesize deduplicated findings ordered by severity and consensus,
and writes `chairman.md` + `chairman.sidecar.json` into `<run_dir>/chairman/`.

## Commits
- `pending` — 2026-03-19 — Add chairman_synthesis.sh to plans/

## Key Files
- plans/chairman_synthesis.sh

## Debriefs
- [[chairman-synthesis 2026-03-19 Add Chairman Script]]

## Log
### 2026-03-19
- Authored `plans/chairman_synthesis.sh`: multi-model review council synthesis script
- Reads artifacts from known tools (codex, sonnet, opus, kimi, gemini) for a given run dir
- Supports --tool (opus/sonnet), --style (generic/enriched), --dry-run flags
- Writes canonical markdown artifact with YAML provenance frontmatter and JSON sidecar
- Python inline script parses chairman output to extract P0-P3 findings with consensus counts
