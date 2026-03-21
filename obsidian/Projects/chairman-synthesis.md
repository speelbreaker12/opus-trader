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
- `dfcf814d` — 2026-03-19 — Harden chairman synthesis script (cleanup, tee check, sidecar fields, JSON validation)
- `4f61a633` — 2026-03-19 — Integrate chairman synthesis into parallel review pipeline
- `pending` — 2026-03-19 — Fix PIPESTATUS bash 3.2 bug, transcript extraction, sidecar cross-pollination, dry-run prompt preservation, chairman failure exit code

## Key Files
- plans/chairman_synthesis.sh
- plans/parallel_review.sh
- plans/review_logged.sh

## Debriefs
- [[chairman-synthesis 2026-03-19 Add Chairman Script]]
- [[chairman-synthesis 2026-03-19 Pipeline Integration]]
- [[chairman-synthesis 2026-03-19 Harden Script]]
- [[chairman-synthesis 2026-03-19 PIPESTATUS and Parser Fixes]]
- [[chairman-synthesis 2026-03-21 PR Review Fixes]]
- [[chairman-synthesis 2026-03-21 Fail-Explicit Fixes]]

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
- Hardened chairman_synthesis.sh: consolidated temp cleanup, early model ID, tee exit check, broader citation regex, sidecar description/fix fields, JSON validation gate
- Fixed PIPESTATUS bash 3.2 array reset bug (reading [0] resets array under set -u)
- Fixed transcript extraction: check for markers before fallback, 3-tier extraction (markers > frontmatter > raw)
- Fixed sidecar finding parser: stop look-ahead at next heading to prevent cross-pollination, guard against duplicate description/fix captures
- Dry-run now preserves prompt file for inspection instead of deleting on exit
- Added error handling for canonical artifact read failure in sidecar parser
- Added zero-findings warning when chairman output does not match expected format
- parallel_review.sh: chairman failure now returns distinct exit code 4, dry-run reports chairman intent

### 2026-03-21
- Address PR #221 review comments:
  - Default chairman style changed from `generic` to `enriched` to match parallel_review/review_logged defaults
  - Guard cleanup trap `rm -f` against empty CLEANUP_FILES array
  - Added smoke test `plans/tests/test_chairman_integration.sh` for --chairman integration path
  - P1: exit non-zero when --chairman requested but run directory missing (was false-green WARN + exit 0)
  - P2: redirect chairman CLI stderr to `$OUTDIR/chairman_stderr.log` instead of `/dev/null`
