# Slice6 Cross-Repo Code Comparison (Frozen Refs)

- Generated (UTC): 2026-02-13T22:34:34.814614+00:00
- opus ref: `phase1-impl-opus`
- ralph ref: `phase1-impl-ralph`

## Story Matrix
- opus Slice6 stories: 11
- ralph Slice6 stories: 7
- common story ids: 7
- opus-only story ids: S6-007, S6-008, S6-009, S6-010
- ralph-only story ids: (none)

Story status matrix: `slice6_story_matrix.md`

## Common-Story Scope File Delta (S6 overlap only)
- candidate scope paths (union): 15
- common-scope files existing in both repos: 15
- common-scope files only in opus: 0
- common-scope files only in ralph: 0
- common-scope paths missing in both: 0
- common-scope files same hash: 0
- common-scope files different hash: 15

### Top Changed Common-Scope Files (adds, dels, path)
- `147	875	crates/soldier_core/tests/test_gate_ordering.rs`
- `173	405	crates/soldier_core/tests/test_rejection_side_effects.rs`
- `218	345	crates/soldier_core/tests/test_missing_config.rs`
- `196	350	crates/soldier_core/tests/test_intent_determinism.rs`
- `97	310	crates/soldier_core/tests/test_intent_id_propagation.rs`
- `69	291	crates/soldier_infra/tests/test_crash_mid_intent.rs`
- `61	292	crates/soldier_core/tests/test_dispatch_chokepoint.rs`
- `10	73	evidence/phase1/no_side_effects/rejection_cases.md`
- `30	28	evidence/phase1/crash_mid_intent/drill.md`
- `11	44	docs/dispatch_chokepoint.md`
- `33	17	evidence/phase1/config_fail_closed/missing_keys_matrix.json`
- `19	31	docs/critical_config_keys.md`
- `7	37	docs/intent_gate_invariants.md`
- `8	28	evidence/phase1/traceability/sample_rejection_log.txt`
- `12	19	evidence/phase1/determinism/intent_hashes.txt`

## Artifacts
- Story matrix: `/Users/admin/Desktop/opus-trader/artifacts/phase1_compare/20260213_223424_slice6_compare/slice6_story_matrix.md`
- Common scope numstat: `/Users/admin/Desktop/opus-trader/artifacts/phase1_compare/20260213_223424_slice6_compare/common_scope_numstat.tsv`
- Raw diffs dir: `/Users/admin/Desktop/opus-trader/artifacts/phase1_compare/20260213_223424_slice6_compare/diffs`

## Notes
- This compare uses explicit PRD `scope.touch` from common Slice6 stories only (S6 overlap).
- opus-only Slice6 stories are listed separately in the story matrix.
