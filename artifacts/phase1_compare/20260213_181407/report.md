# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_181407`
- Generated (UTC): `2026-02-13T18:14:26.862502+00:00`
- Repo A: `opus` at `/Users/admin/Desktop/opus-trader`
- Repo B: `ralph` at `/Users/admin/Desktop/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `story/S5-004-fixall` | `pr-112` |
| ref | `HEAD` | `HEAD` |
| ref sha | `684ddc8e324501f8b2ed2d36bc6c088addd135d2` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| dirty files | `65` | `4` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `not run` | `not run` |
| verify quick | `not run` | `not run` |
| verify full | `not run` | `not run` |
| scenario cmd | `pass (0.92s)` | `pass (1.18s)` |
| flakiness runs | `3` | `3` |
| blockers | `1` | `1` |

## Outcome Signals

| Signal | Repo A | Repo B |
|---|---:|---:|
| determinism file non-empty lines | `19` | `9` |
| determinism unique hashes | `17` | `9` |
| traceability log non-empty lines | `28` | `6` |
| traceability unique intent_id count | `4` | `1` |
| config matrix status entries | `0` | `6` |
| config matrix PASS statuses | `0` | `6` |
| config matrix FAIL statuses | `0` | `0` |

## Verify Gate Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| verify gate headers detected | `0` | `0` |
| first verify failure | `n/a` | `n/a` |
| shared verify gates | `0` | `0` |
| gates only in Repo A | `0` | `n/a` |
| gates only in Repo B | `n/a` | `0` |

## Verify Full Gate Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| full verify gate headers detected | `0` | `0` |
| first full verify failure | `n/a` | `n/a` |
| shared full verify gates | `0` | `0` |
| full gates only in Repo A | `0` | `n/a` |
| full gates only in Repo B | `n/a` | `0` |

## Verify Artifact Gate+Timing Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| latest artifact run id | `20260213_120900` | `20260213_100707` |
| latest artifact passing gates | `0` | `0` |
| latest artifact failing gates | `0` | `0` |
| latest artifact gates with time | `0` | `0` |
| shared latest artifact gates | `0` | `0` |
| shared gates with different rc | `0` | `0` |

## Phase 1 PRD Completion

| Metric | Repo A | Repo B |
|---|---:|---:|
| Phase 1 stories | `37` | `35` |
| Phase 1 stories passed | `35` | `35` |
| Phase 1 stories remaining | `2` | `0` |
| needs_human_decision stories | `0` | `0` |
| stories with verify[] commands | `37` | `35` |
| stories with observability fields | `21` | `20` |
- Repo A missing pass stories: `S1-012, S2-004`

## Phase 1 Traceability

| Metric | Repo A | Repo B |
|---|---:|---:|
| stories with contract refs | `37` | `35` |
| stories missing contract refs | `0` | `0` |
| stories with enforcing_contract_ats | `24` | `22` |
| stories missing enforcing_contract_ats | `13` | `13` |
| unique AT refs seen | `64` | `49` |
| unknown AT refs vs CONTRACT | `0` | `0` |
| unknown Anchor refs vs CONTRACT | `23` | `23` |
| unknown VR refs vs CONTRACT | `27` | `27` |
- Repo A stories missing enforcing AT refs: `S1-001, S1-008, S1-009, S1-010, S1-011, S1-013, S6-000, S6-001, S6-002, S6-003, S6-004, S6-005`
- Repo B stories missing enforcing AT refs: `S1-001, S1-008, S1-009, S1-010, S1-011, S1-012, S6-000, S6-001, S6-002, S6-003, S6-004, S6-005`

## Operational Readiness Signals

| Metric | Repo A | Repo B |
|---|---:|---:|
| health endpoint doc present | `yes` | `yes` |
| required status fields present | `5/5` | `4/5` |
| required alert metrics present | `10/10` | `10/10` |
- Repo B missing status fields: `is_trading_allowed`

## Flakiness & Stability

| Metric | Repo A | Repo B |
|---|---:|---:|
| flakiness command runs | `3` | `3` |
| flakiness success runs | `3` | `3` |
| flakiness failed runs | `0` | `0` |
| flakiness exit code set | `[0]` | `[0]` |
| flakiness avg elapsed (s) | `0.724` | `0.851` |
| flakiness min..max elapsed (s) | `0.699..0.74` | `0.722..1.104` |

## Scenario Behavioral Output Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| scenario reason code count | `0` | `0` |
| scenario status fields seen | `1` | `0` |
| scenario dispatch count values seen | `[]` | `[]` |
| scenario rejection/blocked lines | `19` | `0` |
| shared scenario reason codes | `0` | `0` |

## Evidence File Comparison

| Path | Repo A | Repo B | same sha256 |
|---|---:|---:|---:|
| `evidence/phase1/README.md` | `ok` | `ok` | `no` |
| `evidence/phase1/ci_links.md` | `ok` | `ok` | `no` |
| `evidence/phase1/config_fail_closed/missing_keys_matrix.json` | `ok` | `ok` | `no` |
| `evidence/phase1/crash_mid_intent/auto_test_passed.txt` | `missing` | `missing` | `no` |
| `evidence/phase1/crash_mid_intent/drill.md` | `ok` | `ok` | `no` |
| `evidence/phase1/determinism/intent_hashes.txt` | `ok` | `ok` | `no` |
| `evidence/phase1/no_side_effects/rejection_cases.md` | `ok` | `ok` | `no` |
| `evidence/phase1/restart_loop/restart_100_cycles.log` | `missing` | `missing` | `no` |
| `evidence/phase1/traceability/sample_rejection_log.txt` | `ok` | `ok` | `no` |

## Warnings

- none

## Logs

- Repo A scenario: `artifacts/phase1_compare/20260213_181407/opus/logs/scenario.log`
- Repo B scenario: `artifacts/phase1_compare/20260213_181407/ralph/logs/scenario.log`
- Repo A flakiness logs: `artifacts/phase1_compare/20260213_181407/opus/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_181407/opus/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_181407/opus/logs/flaky_run_03.log`
- Repo B flakiness logs: `artifacts/phase1_compare/20260213_181407/ralph/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_181407/ralph/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_181407/ralph/logs/flaky_run_03.log`

## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer green full/quick verify parity, then higher evidence and traceability coverage. Use flakiness, scenario behavior parity, churn, and timing as tie-breakers.
