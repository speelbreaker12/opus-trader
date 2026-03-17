---
status: in-progress
priority: P1
branch: main
pr: 207
started: 2026-03-16
---

## Current State

Phase 2 complete — 8 of 10 machine-generated proposals accepted, 6 new ATs added (AT-1247 through AT-1252). CONTRACT.md patched across §1.3, §2.2.2, §2.2.3, §2.2.4, §3.1. 2 proposals rejected (redundant CSP bypass AT, AT-1100 structural move).

## Key Files
- `autoresearch/contract/render_review.py`
- `autoresearch/skills/harness.sh`
- `autoresearch/tests/test_contract_render_review.py`
- `autoresearch/tests/test_contract_harness_cli.py`
- `autoresearch/contract/phase1/`
- `autoresearch/contract/phase2/`

## Debriefs
- None yet.

## Log
### 2026-03-16
- Fixed accepted-only contract patch rendering to fail closed when the live `specs/CONTRACT.md` hash drifts from recorded batch provenance.
- Fixed baseline scoring so valid JSON from `evaluate.py --json` is recorded even when the evaluator exits non-zero for an imperfect score.
- Added regression coverage for both failure modes in the autoresearch contract and harness tests.
- Folded PR #208 render_review.py IndexError guard into #207 branch (cherry-pick, harness.sh conflict resolved — HEAD's tmpfile pattern already had the set-e fix).
- Rebased PR #207 onto main (10 commits, 17 conflicts resolved, 0 markers remaining).
- Reviewed CONTRACT.md/prd.json/contract_kernel.json as contract set. Found and fixed duplicate AT-1239 in S7-002.
- contract_kernel.json line numbers are stale — needs regeneration post-merge.
- Follow-up review fixes: made malformed fixture_metadata top-level payloads fail closed and correlated the Liquidity Gate P0 semantic assertion to the same finding in eval.json
- Hardened contract autoresearch live-fixture flow: refresh-common now regenerates tracked live Phase 1 fixtures and phase1 run fails closed on stale live fixture drift
- Tightened Phase 1 live eval assertions and added regression coverage for stale-fixture refresh + workflow preflight fixtures
- Verified workflow changes in a clean detached worktree after syncing updated preflight fixture tests; kept dirty CONTRACT-derived generated artifacts out of commit scope
- Phase 1 fixtures and eval written
- Context manifest updated
- Results TSV updated
- Added skills-index consistency checker (preflight gate 6, smoke test)
- Extended Phase 1 eval.json with TradingMode + OpenPermissionLatch scoring rules
- Updated refresh_context.py to include live phase1 fixtures in manifest
- Added autoresearch test coverage for phase runs and refresh
- Phase 1 verification: fixed 21 REAL CONTRACT.md spec gaps (1 P0, 13 P1, 7 P2), 2 false positives skipped
- New ATs: AT-1241 (LG no-fallback CLOSE/HEDGE), AT-1242 (OPL trigger events), AT-1243 (OPL concurrent cert+reconcile)
- Review fix: attribution_write_errors increment-trigger rule + AT-1244 (mode_reasons ordering/tier purity)
- Phase 2 proposal run: 10 proposals from 5 sections, deep_end_line extraction fix, 5 new snapshot targets
- Phase 2 review: accepted 8, rejected 2 (CSP bypass redundant with AT-991, AT-1100 structural move)
- CONTRACT.md patched: AT-1247 (LG CLOSE/HEDGE slippage), AT-1248 (EG attribution missing), AT-1249 (TMC bunker_mode stale), AT-1250 (OPL clear transition), AT-1251 (EC hedge bound), AT-1252 (EC monotonic retry), cooldown scope, Profile:ALL tags
