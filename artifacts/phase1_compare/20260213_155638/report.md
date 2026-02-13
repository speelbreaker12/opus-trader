# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_155638`
- Generated (UTC): `2026-02-13T15:58:14.720549+00:00`
- Repo A: `opus` at `/Users/admin/Desktop/opus-trader`
- Repo B: `ralph` at `/Users/admin/Desktop/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `codex/preflight-fixture-profiles-sync` | `pr-112` |
| ref | `7152fb9fcc186b34391a261c48580f9cd7a37d6e` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| ref sha | `7152fb9fcc186b34391a261c48580f9cd7a37d6e` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| dirty files | `29` | `2` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `pass (0.24s)` | `pass (0.28s)` |
| verify quick | `FAIL (92.13s)` | `FAIL (1.40s)` |
| scenario cmd | `not run` | `not run` |
| blockers | `2` | `2` |

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

- Repo A meta test: `artifacts/phase1_compare/20260213_155638/opus/logs/phase1_meta_test.log`
- Repo B meta test: `artifacts/phase1_compare/20260213_155638/ralph/logs/phase1_meta_test.log`
- Repo A verify quick: `artifacts/phase1_compare/20260213_155638/opus/logs/verify_quick.log`
- Repo B verify quick: `artifacts/phase1_compare/20260213_155638/ralph/logs/verify_quick.log`

## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer the one with green quick verify and higher evidence coverage. Use churn and scenario timing only as tie-breakers.
