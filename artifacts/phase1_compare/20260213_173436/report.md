# Phase 1 Cross-Repo Comparison

- Run ID: `20260213_173436`
- Generated (UTC): `2026-02-13T18:08:28.389550+00:00`
- Repo A: `opus` at `/private/tmp/phase1-compare-full-20260213/opus`
- Repo B: `ralph` at `/private/tmp/phase1-compare-full-20260213/ralph`

## Snapshot

| Metric | Repo A | Repo B |
|---|---:|---:|
| branch | `HEAD` | `HEAD` |
| ref | `7152fb9fcc186b34391a261c48580f9cd7a37d6e` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| ref sha | `7152fb9fcc186b34391a261c48580f9cd7a37d6e` | `9d1be45a6942affca60bf29a23ea1b0077ab27ec` |
| dirty files | `0` | `0` |
| required evidence coverage | `6/7` | `6/7` |
| any-of groups satisfied | `1/1` | `1/1` |
| phase1_meta_test | `pass (0.24s)` | `pass (0.25s)` |
| verify quick | `pass (124.42s)` | `pass (1529.27s)` |
| verify full | `pass (357.19s)` | `FAIL (0.60s)` |
| scenario cmd | `FAIL (0.67s)` | `pass (3.32s)` |
| flakiness runs | `3` | `3` |
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

## Verify Gate Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| verify gate headers detected | `26` | `18` |
| first verify failure | `n/a` | `FAIL: malformed spec validator line (expected name|timeout|command): bad_line_without_separators` |
| shared verify gates | `4` | `4` |
| gates only in Repo A | `22` | `n/a` |
| gates only in Repo B | `n/a` | `14` |
- Repo A-only gates: `AT coverage report, AT profile parity, Verify context, arch flows, contract crossrefs, contract kernel, contract profiles, crash matrix, crash replay idempotency, crossref execution invariants, csp trace, global invariants, phase0 meta-test, phase1 meta-test, preflight, reconciliation matrix, rust gates, state machines, status fixtures, time freshness, vendor docs lint, verify gate contract`
- Repo B-only gates: `0.1) Workflow preflight, Contract coverage matrix, Endpoint-level test gate, Optional gates (only when enabled), PR postmortem gate, PRD Cache Integration Tests, Parallel primitives smoke test, Repo sanity, Rust vendor docs lint, Spec integrity gates, Status contract validation (CSP), Summary: 5 passed, 0 failed, Workflow acceptance (full), using parallel runner with 4 workers`
- Repo B failure lines: `FAIL: malformed spec validator line (expected name|timeout|command): bad_line_without_separators; FAIL: validator list suspiciously short (1 < MIN_SPEC_VALIDATORS=7); FAIL: required workflow artifact missing: plans/workflow_contract_map.json`

## Verify Full Gate Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| full verify gate headers detected | `30` | `0` |
| first full verify failure | `n/a` | `FAIL: local full verify disabled; run in CI or set VERIFY_ALLOW_LOCAL_FULL=1 with approval` |
| shared full verify gates | `0` | `0` |
| full gates only in Repo A | `30` | `n/a` |
| full gates only in Repo B | `n/a` | `0` |
- Repo A-only full gates: `AT coverage report, AT profile parity, Rust clippy, Rust format, Rust tests, Timing Summary, VERIFY OK (mode=full), Verify context, arch flows, contract coverage, contract crossrefs, contract kernel, contract profiles, crash matrix, crash replay idempotency, crossref execution invariants, crossref gate, csp trace, global invariants, phase0 meta-test, phase1 meta-test, preflight, reconciliation matrix, rust gates, slice completion enforcement, state machines, status fixtures, time freshness, vendor docs lint, verify gate contract`
- Repo B full verify failure lines: `FAIL: local full verify disabled; run in CI or set VERIFY_ALLOW_LOCAL_FULL=1 with approval`

## Verify Artifact Gate+Timing Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| latest artifact run id | `20260114_124934` | `20260114_124934` |
| latest artifact passing gates | `0` | `0` |
| latest artifact failing gates | `0` | `0` |
| latest artifact gates with time | `0` | `0` |
| shared latest artifact gates | `0` | `0` |
| shared gates with different rc | `0` | `0` |
- Repo A quick-run artifact: `20260213_113442` (28 pass / 0 fail)
- Repo B quick-run artifact: `20260213_114252` (22 pass / 0 fail)
- Repo A full-run artifact: `20260213_113646` (32 pass / 0 fail)
- Repo B full-run artifact: `20260213_114252` (22 pass / 0 fail)

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
| flakiness success runs | `0` | `3` |
| flakiness failed runs | `3` | `0` |
| flakiness exit code set | `[101]` | `[0]` |
| flakiness avg elapsed (s) | `0.719` | `0.794` |
| flakiness min..max elapsed (s) | `0.627..0.775` | `0.758..0.86` |

## Scenario Behavioral Output Parity

| Metric | Repo A | Repo B |
|---|---:|---:|
| scenario reason code count | `0` | `0` |
| scenario status fields seen | `0` | `1` |
| scenario dispatch count values seen | `[]` | `[]` |
| scenario rejection/blocked lines | `1` | `1` |
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
| diff shortstat | `32 files changed, 2575 insertions(+), 67 deletions(-)` | `12 files changed, 183 insertions(+), 32 deletions(-)` |
| changed files | `32` | `12` |

## Warnings

- none

## Logs

- Repo A meta test: `artifacts/phase1_compare/20260213_173436/opus/logs/phase1_meta_test.log`
- Repo B meta test: `artifacts/phase1_compare/20260213_173436/ralph/logs/phase1_meta_test.log`
- Repo A verify quick: `artifacts/phase1_compare/20260213_173436/opus/logs/verify_quick.log`
- Repo B verify quick: `artifacts/phase1_compare/20260213_173436/ralph/logs/verify_quick.log`
- Repo A verify full: `artifacts/phase1_compare/20260213_173436/opus/logs/verify_full.log`
- Repo B verify full: `artifacts/phase1_compare/20260213_173436/ralph/logs/verify_full.log`
- Repo A scenario: `artifacts/phase1_compare/20260213_173436/opus/logs/scenario.log`
- Repo B scenario: `artifacts/phase1_compare/20260213_173436/ralph/logs/scenario.log`
- Repo A flakiness logs: `artifacts/phase1_compare/20260213_173436/opus/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_173436/opus/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_173436/opus/logs/flaky_run_03.log`
- Repo B flakiness logs: `artifacts/phase1_compare/20260213_173436/ralph/logs/flaky_run_01.log, artifacts/phase1_compare/20260213_173436/ralph/logs/flaky_run_02.log, artifacts/phase1_compare/20260213_173436/ralph/logs/flaky_run_03.log`

## Decision Rule

Pick the implementation with fewer blockers first; if tied, prefer green full/quick verify parity, then higher evidence and traceability coverage. Use flakiness, scenario behavior parity, churn, and timing as tie-breakers.
