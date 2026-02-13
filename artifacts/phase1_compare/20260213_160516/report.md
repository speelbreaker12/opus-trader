# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_160516`
- Generated (UTC): `2026-02-13T16:05:24.563300+00:00`
- Repo A: `opus` at `/Users/admin/Desktop/opus-trader`
- Repo B: `ralph` at `/Users/admin/Desktop/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `codex/preflight-fixture-profiles-sync` | `pr-112` |
| ref | `HEAD` | `HEAD` |
| ref sha | `7152fb9fcc186b34391a261c48580f9cd7a37d6e` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| dirty files | `32` | `2` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `not run` | `not run` |
| verify quick | `not run` | `not run` |
| scenario cmd | `not run` | `not run` |
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


## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer the one with green quick verify and higher evidence coverage. Use churn and scenario timing only as tie-breakers.
