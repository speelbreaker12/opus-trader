# S2-000 Step 6 Addendum — All 3 External Reviews After Logger Fixes

Date: 2026-02-27  
Story: `S2-000`  
Scope: clean file-scoped rerun against workflow changes only.

## Commands

1. `plans/review_logged.sh S2-000 --tool codex --prompt enriched --files "plans/review_logged.sh plans/preflight.sh plans/tests/test_review_logged.sh plans/tests/test_preflight_fixture_profiles.sh" --timeout-seconds 180`
2. `plans/review_logged.sh S2-000 --tool opus --prompt enriched --files "plans/review_logged.sh plans/preflight.sh plans/tests/test_review_logged.sh plans/tests/test_preflight_fixture_profiles.sh" --timeout-seconds 180`
3. `plans/review_logged.sh S2-000 --tool kimi --prompt enriched --files "plans/review_logged.sh plans/preflight.sh plans/tests/test_review_logged.sh plans/tests/test_preflight_fixture_profiles.sh" --timeout-seconds 180`

## Results

- `codex`: timed out at 180s, exited fail-closed with `HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)`.
  - Artifact updated: `artifacts/story/S2-000/codex/codex.enriched.md`
- `opus`: timed out at 180s, exited fail-closed with `HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)`.
  - Artifact updated: `artifacts/story/S2-000/opus/opus.enriched.md`
- `kimi`: completed model run, emitted non-zero findings (`P0/P1/P2` narrative), then failed cycle1 citation gate (`HARD_GATE: MISSING_PRE_EXISTING_CITATIONS (exit 4)`).
  - Artifact updated: `artifacts/story/S2-000/kimi/kimi.enriched.md`

## Key Observations

1. Timeout hard-gate works as intended for stalled review commands.
2. Canonical self-copy bug is resolved (`Normalized: ... (already canonical)` no longer causes non-zero exit).
3. New severity extraction works on heading/bullet patterns (confirmed by fixture test), but these specific real runs are dominated by tool-behavior outcomes (timeout/citation gate), not stable review signal.
4. Existing sidecars for `codex`/`opus` remained stale because timeout exits skip sidecar regeneration by design (`gate_exit != 0`).

## Verification run for fixes

- `bash plans/tests/test_review_logged.sh` → PASS
- `bash plans/tests/test_review_logged_proof_graph.sh` → PASS
- `bash plans/tests/test_preflight_fixture_profiles.sh` → PASS
