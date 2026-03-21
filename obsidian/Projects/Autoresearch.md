---
status: in-progress
priority: P1
branch: project/contract-autoresearch-harness-fix
base: main
pr: 224
started: 2026-03-16
aliases: []
keywords:
  - contract autoresearch
  - codex backend
scope_paths:
  - autoresearch/contract/**
  - autoresearch/skills/harness.sh
  - autoresearch/tests/test_contract_phase_runs.py
  - obsidian/Projects/Autoresearch.md
  - obsidian/Debriefs/Autoresearch *.md
---

## Commits
- `pending` — 2026-03-20 — Reviewed the hardened Phase 2 proposal packages, wrote review decisions, and rendered accepted-only patch artifacts.
- `a92bced4` — 2026-03-20 — Hardened Codex wrapper with persistent home + retry/backoff and ran Phase 2 live per-section slices on the tracked backend.
- `52cf1b15` — 2026-03-20 — Tracked Codex backend support for contract autoresearch; reran Phase 1 and Phase 2 through Codex-backed paths.
- `54b97205` — 2026-03-19 — Phase 4 remaining sections: 10 new ATs (AT-1272..AT-1281) + 3 mechanical fixes
- `049b85dd` — 2026-03-19 — Phase 4 LG+OPL patch: 7 new ATs (AT-1265..AT-1271)
- `120759bc` — 2026-03-18 — Phase 4 section-compatibility fix + gitignore lock
- `5ec15230` — 2026-03-18 — Phase 4 gap detection: 23 findings, 10 proposals (2/5 sections), pipeline infra improvements.
- `1c48e654` — 2026-03-18 — Hardened contract render-review for sample fixture guard and add regression.

## Current State

Follow-up branch `project/contract-autoresearch-harness-fix` is active with PR #224 open. Phase 1 reruns completed as `phase1-mar20-20260320_191211-5ccf6c48` and tracked-backend `phase1-mar20codex-20260320_195735-903f0acd`, both with `checks=12/12` and `score=1.000`. Phase 2 rerun completed as `phase2-mar20-20260320_193507-66196f79` with `fixtures=1`, `proposals=2`, `checks=8/8`, and `score=1.000`. The tracked repo-owned Codex backend path now exists via `--backend codex`, and a live smoke run through that path completed as `phase2-mar20codex-20260320_194341-e183cb6b` with `proposals=3`, `checks=8/8`, and `score=1.000`. After hardening `codex_wrapper.py` to use a persistent isolated home plus transient retry/backoff, all five per-section Phase 2 live evals succeeded on the tracked backend: OPL `phase2-mar20codexhardened-opl-20260320_210643-d8538cc4` (`2` proposals), LG `phase2-mar20codexhardened-lg-20260320_211226-33896e77` (`2` proposals), EG `phase2-mar20codexhardened-eg-20260320_211637-c80be6bb` (`3` proposals), TMC `phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7` (`3` proposals), and EC `phase2-mar20codexhardened-ec-20260320_212954-8cae5620` (`4` proposals), each with `checks=8/8` and `score=1.000`. Manual review is now complete for those five runs: `6` proposals accepted, `7` marked `pending_scope_review`, and `1` rejected; accepted-only patch artifacts were rendered for each run (the OPL patch is intentionally empty because both OPL proposals remained pending).

## Key Files
- `autoresearch/contract/README.md`
- `autoresearch/contract/codex_wrapper.py`
- `autoresearch/tests/test_contract_phase_runs.py`
- `autoresearch/contract/render_review.py`
- `autoresearch/skills/harness.sh`
- `autoresearch/tests/test_contract_render_review.py`
- `autoresearch/tests/test_contract_harness_cli.py`
- `autoresearch/contract/phase1/`
- `autoresearch/contract/phase2/`

## Debriefs
- [[Autoresearch 2026-03-20 Codex Backend Support]]
- [[Autoresearch 2026-03-17 Phase3 Gap Detection Run]]
- [[Autoresearch 2026-03-17 Phase3 Review Decisions]]
- [[Autoresearch 2026-03-17 Phase3 Patch Applied]]
- [[Autoresearch 2026-03-18 render_review sample fixture guard]]

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
### 2026-03-17
- Backfilled the Phase 3 gap-detection debrief with split commit `da5b38cf` after the mixed commit was separated.
- Phase 3 contract gap detection run (phase2-mar17-20260317_141745-bb818649), score 1.000 (20/20 checks)
- 18 findings across 3 fixtures (s1_execution_pipeline, s2_2_policyguard, sample_contract_patch)
- 19 proposals: 16 proposed, 1 rejected (enforcement evidence missing), 2 pending_scope_review
- P0: Margin Headroom Gate NaN/missing fail-closed gap; bunker_mode_active staleness unimplementable
- P1: drain_all() 0 ATs, Pricer fail-closed 0 ATs, Inventory Skew SELL formula vague, AT-1243 duplicate ID, fee_model hard-stale 0 ATs, cortex_override fail-open risk, reconciliation REST failure 0 ATs, field rename alias 0 ATs, TradingModeBlockedOpen missing from registry
- Review complete: 16 accepted, 3 rejected (P-209 pre-rejected, P-400/P-401 fixture-only). P-208 rewritten to bind bunker_mode_active + bunker_exit_stable_s.
- Accepted-only patch rendered at `autoresearch/contract/phase2/review/CONTRACT_PATCH_phase2-mar17-20260317_141745-bb818649.patch`
- Patch audit caught 3 gaps: missing AT-1262, missing Appendix A entry for inventory_skew_sell_floor, duplicate line-513 hunk. All fixed.
- Next: apply corrected patch to CONTRACT.md (new context recommended — 16 semantic edits on 6400+ line file)
- Applied phase3 accepted patch to CONTRACT.md: 16 proposals, 11 new ATs, 2 SHALL->MUST, CSP-063 dedup, AT-1243->AT-1253 renumber, MarginHeadroomInputMissing + TradingModeBlockedOpen in registry, bunker_mode/cortex_override/account_summary staleness rules, inventory_skew_sell_floor formula
- Reverted phase2 proposals (AT-1247..AT-1252) superseded by phase3 findings + CCL-2026-03-16-01 ledger entry
- Re-added AT-1251 (hedge qty bound) and AT-1252 (retry monotonic) — restored after phase2 revert
- Renumbered 11 AT-PROP-xxx provisional IDs to permanent AT-1254..AT-1264
- Refreshed contract_kernel.json and context_manifest.json hashes
- Added TF-917 (bunker_mode) and TF-918 (account_summary) to TIME_FRESHNESS.yaml
- Added CSP-063 (Recovery/Matching Rule dedup) to TRACE.yaml
- Creating separate autoresearch PR branch for all phase3 changes
- PR #214 rebased onto main, added S6.13 to IMPLEMENTATION_PLAN.md to fix doc_sync_check
### 2026-03-18
- Added hard-fail guard in `autoresearch/contract/render_review.py` to prevent accidental acceptance of `sample_contract_patch` in `--accepted-only`.
- Added regression in `autoresearch/tests/test_contract_render_review.py` to assert sample fixture proposals cannot be accepted.
- Updated proposal seeding helper to support configurable fixture names and dedupe keys for targeted tests.
- Phase 4 gap detection: Phase 1 run on refreshed CONTRACT.md — 23 live findings across 5 sections (score 1.000)
- Phase 4 proposals: 2/5 sections succeeded (LG: 4 proposed, OPL: 5 proposed). 3/5 fail pipeline (EC/EG/TMC: section mismatch + empty output)
- Infrastructure: added 5 per-section snapshot targets (§1.3, §2.2.2, §2.2.3, §2.2.4, §3.1), eval_live.json, per-fixture eval configs
- Pipeline fix: relaxed section-match validation to use section-number prefix matching instead of exact string equality (fixes known ~100% failure on TMC/EC)
- Review fix: tightened section-compatibility to require 2-level prefix overlap (prevents false positives like §1.3 matching §1.4). Gitignored proposals_index.lock.
### 2026-03-19
- Reviewed 10 Phase 4 LG+OPL proposals manually against CONTRACT.md source text: 7 accepted, 2 rejected (P-001 impl detail, P-003 AT-909 rewrite), 1 pre-rejected
- Applied 7 accepted LG+OPL proposals to CONTRACT.md: 7 new ATs (AT-1265..AT-1271); tightened AT-222 bypass criteria; added §2.2.4 cross-ref plus reconcile_stall_max_delay_s default + fail-closed text
- Fix: reverted spurious AT-909 rewrite (rejected P-003 was applied by hook; restored original stale-L2 reject semantics)
- Manual proposals for EC/EG/TMC: triaged 15 findings, accepted 12, rejected 3. 10 new ATs (AT-1272..AT-1281) + 3 mechanical fixes (cause enum closed, SHALL→MUST, AT-918 reason code, EG cooldown default, EC partial fill text)
- Refreshed context (at_registry, context_manifest, section_index, fixtures, contract_kernel) after CONTRACT.md edits
- Rebuilt contract_kernel.json (hash mismatch blocked push)
- Fix: section-compatibility now uses longest common prefix (>= 3 levels for siblings, or exact match). §2.2.3.7 vs §2.2.3.1.1 → True; §1.3 vs §1.4 → False.
### 2026-03-20
- Repaired the Codex transport path for contract autoresearch by turning the one-off `/tmp` shim behavior into tracked repo support via `autoresearch/contract/codex_wrapper.py` and `harness.sh contract ... --backend codex`.
- Documented the tracked backend path and auth expectations in `autoresearch/contract/README.md`.
- Added a contract phase-run regression that requires the Codex backend to rewrite prompts into the short file-reading form instead of shipping giant inline fixture payloads to `codex exec`.
- Reran Phase 1 live contract gap detection under Codex `gpt-5.4` + `xhigh`: `phase1-mar20-20260320_191211-5ccf6c48`, 6 fixtures, `checks=12/12`, `score=1.000`.
- Reran full Phase 1 through the tracked repo-owned backend: `phase1-mar20codex-20260320_195735-903f0acd`, 6 fixtures, `checks=12/12`, `score=1.000`.
- Reran Phase 2 live proposals under the temporary Codex path: `phase2-mar20-20260320_193507-66196f79`, 1 fixture, 2 proposals, `checks=8/8`, `score=1.000`.
- Verified the tracked repo-owned backend directly with `--backend codex`: `phase2-mar20codex-20260320_194341-e183cb6b`, 1 fixture, 3 proposals, `checks=8/8`, `score=1.000`.
- Pushed branch `project/contract-autoresearch-harness-fix` and opened PR #224 against `main`.
- Attempted full live Phase 2 (`eval_live.json`) twice through the committed backend (`phase2-mar20codexlive-*` and `phase2-mar20codexlive-retry-*`), but both runs failed on Codex upstream `500`/`503` high-demand errors before the first proposal payload completed.
- Hardened `autoresearch/contract/codex_wrapper.py` again to move its isolated Codex home off `/tmp` and into a persistent wrapper-owned path, and added transient retry/backoff controls for high-demand and websocket-class failures.
- Added regression coverage proving the hardened wrapper reuses a persistent home and retries a transient Codex failure before Phase 2 succeeds.
- Re-ran the full `autoresearch.tests.test_contract_phase_runs` module (`19` tests), `autoresearch.tests.test_contract_harness_cli` (`8` tests), `python3 -m py_compile autoresearch/contract/codex_wrapper.py`, and `bash -n autoresearch/skills/harness.sh` after the hardening change.
- Completed hardened live Phase 2 per-section slices on the tracked backend: OPL `phase2-mar20codexhardened-opl-20260320_210643-d8538cc4` (`2` proposals), LG `phase2-mar20codexhardened-lg-20260320_211226-33896e77` (`2` proposals), EG `phase2-mar20codexhardened-eg-20260320_211637-c80be6bb` (`3` proposals), TMC `phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7` (`3` proposals), and EC `phase2-mar20codexhardened-ec-20260320_212954-8cae5620` (`4` proposals), each with `checks=8/8` and `score=1.000`.
- Reviewed the five hardened Phase 2 proposal packages and wrote `REVIEW_DECISIONS_*.json` for each run: accepted `LG:P-002`, `EG:P-002`, `TMC:P-001/P-002/P-003`, and `EC:P-003`; marked `LG:P-001`, `EG:P-001/P-003`, `OPL:P-001/P-002`, and `EC:P-001/P-002` as `pending_scope_review`; rejected `EC:P-004` as over-strict.
- Rendered accepted-only patch artifacts for all five hardened runs. OPL produced an empty patch because both proposals remained pending; LG, EG, TMC, and EC produced non-empty accepted-only patch files under `autoresearch/contract/phase2/review/`.
