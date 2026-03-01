# S2-000 Step 6 Addendum — External Review Rerun (All 3 Tools)

Date: 2026-02-27  
Story: `S2-000`  
Goal: rerun external review with `codex`, `opus`, `kimi` and record issues.

## Commands

1. `plans/review_logged.sh S2-000 --tool codex --prompt enriched --base main`
2. `plans/review_logged.sh S2-000 --tool kimi --prompt enriched --base main`
3. `plans/review_logged.sh S2-000 --tool opus --prompt enriched --base main` (attempted twice; both hung with no transcript stream)

## Outcomes

- `codex`: artifact regenerated, command exited non-zero due canonical copy step.
  - Artifact: `artifacts/story/S2-000/codex/codex.enriched.md`
- `kimi`: artifact regenerated, command exited non-zero due canonical copy step.
  - Artifact: `artifacts/story/S2-000/kimi/kimi.enriched.md`
- `opus`: no new artifact from this rerun; wrapper hung in `claude` child with zero-byte transcript until terminated.
  - Latest existing artifact (pre-rerun): `artifacts/story/S2-000/opus/opus.enriched.md`

## Issues Observed

1. `plans/review_logged.sh` canonical copy bug:
   - `outfile` already points to canonical file (`<tool>.<style>.md`), then script runs:
   - `cp "$outfile" "$canonical_path"` where source == destination
   - On macOS BSD `cp`, this returns non-zero and flips overall command to failure.

2. Opus runner instability/hang:
   - `claude` child process started but emitted no output to transcript (`tee` target remained 0 bytes), causing indefinite hang behavior.

3. Findings-summary mismatch:
   - All sidecars and markdown footers report `FINDINGS_SUMMARY: P0=0 P1=0 P2=0`.
   - Narrative bodies include non-zero findings (e.g., codex includes `[P1]` and `[P2]`; kimi/opus include explicit P1/P2 sections).
   - Structured finding counts are currently not trustworthy for gate severity decisions.

## Artifact/Schema Checks

- Header validator PASS for all available artifacts (`codex`, `kimi`, and existing `opus` artifact):
  - `python3 plans/validators/validate_review_header.py --artifact <path> --expect-cycle C2 --format json --strict`
