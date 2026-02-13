# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_202233`
- Generated (UTC): `2026-02-13T20:23:03.828029+00:00`
- Repo A: `opus` at `/private/tmp/phase1-compare-pinned-20260213_142229/opus`
- Repo B: `ralph` at `/private/tmp/phase1-compare-pinned-20260213_142229/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `HEAD` | `HEAD` |
| ref | `phase1-impl-opus` | `phase1-impl-ralph` |
| ref sha | `16aa006395e5d143aec4c99e1020963083cc7e27` | `c6b8947b55333c365d84e6fd23b4d2e912e2e51d` |
| dirty files | `0` | `0` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `pass (0.26s)` | `pass (0.47s)` |
| verify quick | `not run` | `not run` |
| verify full | `not run` | `not run` |
| scenario cmd | `pass (8.08s)` | `pass (4.33s)` |
| flakiness runs | `5` | `5` |
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
| latest artifact run id | `20260114_124934` | `20260114_124934` |
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
| flakiness command runs | `5` | `5` |
| flakiness success runs | `5` | `5` |
| flakiness failed runs | `0` | `0` |
| flakiness exit code set | `[0]` | `[0]` |
| flakiness avg elapsed (s) | `0.657` | `0.631` |
| flakiness min..max elapsed (s) | `0.593..0.824` | `0.577..0.71` |

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

## Churn (Base→Ref)

| Metric | Repo A | Repo B |
|---|---:|---:|
| diff shortstat | `13 files changed, 186 insertions(+), 89 deletions(-)` | `12 files changed, 183 insertions(+), 32 deletions(-)` |
| changed files | `13` | `12` |

## Weighted Decision (Auto)

| Category | Weight | Repo A | Repo B |
|---|---:|---:|---:|
| correctness/safety | `60.0%` | `98.919` | `96.536` |
| performance | `25.0%` | `71.548` | `100.0` |
| maintainability | `15.0%` | `90.378` | `100.0` |
| total weighted score | `100%` | `90.795` | `97.921` |
- Winner: `ralph` (margin `7.126` points)

## Warnings

- Repo A: scenario command runs on working tree HEAD; requested ref differs from HEAD
- Repo A: flakiness command runs on working tree HEAD; requested ref differs from HEAD
- Repo B: scenario command runs on working tree HEAD; requested ref differs from HEAD
- Repo B: flakiness command runs on working tree HEAD; requested ref differs from HEAD

## Logs

- Repo A meta test: `artifacts/phase1_compare/20260213_202233/opus/logs/phase1_meta_test.log`
- Repo B meta test: `artifacts/phase1_compare/20260213_202233/ralph/logs/phase1_meta_test.log`
- Repo A scenario: `artifacts/phase1_compare/20260213_202233/opus/logs/scenario.log`
- Repo B scenario: `artifacts/phase1_compare/20260213_202233/ralph/logs/scenario.log`
- Repo A flakiness logs: `artifacts/phase1_compare/20260213_202233/opus/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_202233/opus/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_202233/opus/logs/flaky_run_03.log, artifacts/phase1_compare/20260213_202233/opus/logs/flaky_run_04.log, artifacts/phase1_compare/20260213_202233/opus/logs/flaky_run_05.log`
- Repo B flakiness logs: `artifacts/phase1_compare/20260213_202233/ralph/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_202233/ralph/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_202233/ralph/logs/flaky_run_03.log, artifacts/phase1_compare/20260213_202233/ralph/logs/flaky_run_04.log, artifacts/phase1_compare/20260213_202233/ralph/logs/flaky_run_05.log`

## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer green full/quick verify parity, then higher evidence and traceability coverage. Use flakiness, scenario behavior parity, churn, and timing as tie-breakers.
