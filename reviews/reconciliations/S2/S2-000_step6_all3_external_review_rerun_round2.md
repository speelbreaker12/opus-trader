# S2-000 Step 6 Addendum — All 3 External Reviews After Final Logger Hardening

Date: 2026-02-27  
Story: `S2-000`  
Scope: post-fix rerun with all 3 tools on scoped file input.

## Commands

1. `plans/review_logged.sh S2-000 --tool codex --prompt enriched --files "plans/review_logged.sh" --timeout-seconds 180`
2. `plans/review_logged.sh S2-000 --tool opus --prompt enriched --files "plans/review_logged.sh" --timeout-seconds 180`
3. `plans/review_logged.sh S2-000 --tool kimi --prompt enriched --files "plans/review_logged.sh" --timeout-seconds 180`

## Outcomes

- `codex` completed (exit `0`), sidecar regenerated.
  - `artifacts/story/S2-000/codex/codex.enriched.md`
  - `artifacts/story/S2-000/codex/codex.enriched.sidecar.json`
- `kimi` completed (exit `0`), sidecar regenerated.
  - `artifacts/story/S2-000/kimi/kimi.enriched.md`
  - `artifacts/story/S2-000/kimi/kimi.enriched.sidecar.json`
- `opus` timed out and fail-closed (exit `7`) with timeout hard gate.
  - `artifacts/story/S2-000/opus/opus.enriched.md`
  - `artifacts/story/S2-000/opus/opus.enriched.sidecar.json` is intentionally absent (stale sidecar cleared at run start, no regeneration on failed run)

## Confirmed Fix Behavior

1. Canonical self-copy no longer fails (`Normalized: ... (already canonical)`).
2. Timeout hard-gate emits deterministic marker: `HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)`.
3. Stale sidecar prevention works: failed `opus` run leaves no sidecar file.
4. Prompt contract now explicitly requires `path/to/file.ext:line` citations.

## Local Verification Used

- `bash plans/tests/test_review_logged.sh` → PASS
- `bash plans/tests/test_review_logged_proof_graph.sh` → PASS
- `bash plans/tests/test_preflight_fixture_profiles.sh` → PASS
