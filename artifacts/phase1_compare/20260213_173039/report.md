# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_173039`
- Generated (UTC): `2026-02-13T17:30:49.304834+00:00`
- Repo A: `opus` at `/Users/admin/Desktop/opus-trader`
- Repo B: `ralph` at `/Users/admin/Desktop/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `codex/preflight-fixture-profiles-sync` | `pr-112` |
| ref | `HEAD` | `HEAD` |
| ref sha | `8c59b20b14032cf21f8ece2f77f681d5665092e5` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| dirty files | `30` | `3` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `not run` | `not run` |
| verify quick | `not run` | `not run` |
| verify full | `not run` | `not run` |
| scenario cmd | `pass (0.21s)` | `pass (0.18s)` |
| flakiness runs | `2` | `2` |
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
| latest artifact run id | `20260213_112850` | `20260213_100707` |
| latest artifact passing gates | `28` | `0` |
| latest artifact failing gates | `0` | `0` |
| latest artifact gates with time | `28` | `0` |
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
| flakiness command runs | `2` | `2` |
| flakiness success runs | `2` | `2` |
| flakiness failed runs | `0` | `0` |
| flakiness exit code set | `[0]` | `[0]` |
| flakiness avg elapsed (s) | `0.202` | `0.182` |
| flakiness min..max elapsed (s) | `0.195..0.209` | `0.18..0.184` |

## Scenario Behavioral Output Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| scenario reason code count | `1` | `1` |
| scenario status fields seen | `1` | `1` |
| scenario dispatch count values seen | `[0]` | `[0]` |
| scenario rejection/blocked lines | `2` | `2` |
| shared scenario reason codes | `1` | `1` |

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

- Repo A scenario: `artifacts/phase1_compare/20260213_173039/opus/logs/scenario.log`
- Repo B scenario: `artifacts/phase1_compare/20260213_173039/ralph/logs/scenario.log`
- Repo A flakiness logs: `artifacts/phase1_compare/20260213_173039/opus/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_173039/opus/logs/flaky_run_02.log`
- Repo B flakiness logs: `artifacts/phase1_compare/20260213_173039/ralph/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_173039/ralph/logs/flaky_run_02.log`

## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer green full/quick verify parity, then higher evidence and traceability coverage. Use flakiness, scenario behavior parity, churn, and timing as tie-breakers.
