# Focused Compare: Execution / Gates / Tests

- Scope: pinned refs `phase1-impl-opus` (`7152fb9fcc186b34391a261c48580f9cd7a37d6e`) vs `phase1-impl-ralph` (`9d1be45a6942affca60bf29a23ea1b0077ab27ec`)
- Worktrees: clean detached under `/tmp/phase1-focused-compare-20260213_143323`
- Artifacts directory: this folder

## 1) Execution Architecture Delta

- File footprint:
  - Opus execution files: `12` (`opus_execution_files.txt`)
  - Ralph execution files: `14` (`ralph_execution_files.txt`)
- Ralph adds modules not present in opus:
  - `crates/soldier_core/src/execution/order_type_guard.rs`
  - `crates/soldier_core/src/execution/state.rs`
- Gate orchestration style:
  - Opus uses explicit 9-step chokepoint trace including `DispatchAuth` and `RecordedBeforeDispatch` in gate trace (`opus_gate_flow_anchors.txt`).
  - Ralph separates gate sequence from dispatch sequence (`GateStep` vs `DispatchStep`), with record/dispatch tracked separately (`ralph_gate_flow_anchors.txt`).

## 2) Gate Behavior / Observability Delta

- Opus path is largely in-memory metric structs and explicit reject enums; low runtime stderr telemetry by default.
- Ralph emits structured runtime metric lines and reason-coded reject telemetry:
  - `gate_sequence_total result=...`
  - `liquidity_gate_reject_total reason=...`
  - `net_edge_reject_total reason=...`
  - Evidence: `logs/ralph_test_gate_ordering_nocapture.log`, `logs/ralph_test_missing_config_nocapture.log`
- In missing-config execution, Ralph also writes matrix evidence during test execution:
  - `[P1Evidence] Wrote: .../evidence/phase1/config_fail_closed/missing_keys_matrix.json`

## 3) Test Strategy Delta

- Test-file footprint:
  - Opus soldier_core tests: `22` files (`opus_test_files.txt`)
  - Ralph soldier_core tests: `24` files (`ralph_test_files.txt`)
- Ralph-only test files:
  - `crates/soldier_core/tests/test_fee_cache.rs`
  - `crates/soldier_core/tests/test_phase1_dispatch_auth.rs`
- Focused target test-case counts (`test_count_table.csv`):
  - `test_gate_ordering`: opus `36`, ralph `2`
  - `test_missing_config`: opus `14`, ralph `1`
  - `test_quantize`: opus `38`, ralph `4`
  - `test_preflight`: opus `25`, ralph `8`
  - `test_liquidity_gate`: opus `27`, ralph `4`
  - `test_fee_staleness_or_cache`: opus `10`, ralph `3`
  - `test_phase1_dispatch_auth`: opus `0`, ralph `2`
- Total focused test cases counted: opus `150`, ralph `24`.

Interpretation:
- Opus: high case-by-case explicitness and wider edge-case enumeration at test granularity.
- Ralph: compact/parameterized tests with stronger runtime telemetry and targeted auth/fee-cache suites.

## 4) Runtime Spot Checks (Executed)

Executed with `--nocapture` logs saved under `logs/`:
- Opus:
  - `logs/opus_test_gate_ordering_nocapture.log` (36 tests pass)
  - `logs/opus_test_missing_config_nocapture.log` (14 tests pass)
  - `logs/opus_test_fee_staleness_nocapture.log` (10 tests pass)
- Ralph:
  - `logs/ralph_test_gate_ordering_nocapture.log` (2 tests pass + gate telemetry output)
  - `logs/ralph_test_missing_config_nocapture.log` (1 test pass + reject reason telemetry + evidence write)
  - `logs/ralph_test_fee_cache_nocapture.log` (3 tests pass)
  - `logs/ralph_test_phase1_dispatch_auth_nocapture.log` (2 tests pass)

## 5) Practical Tradeoff Summary

- If priority is explicit edge-case proof density in tests, opus is stronger in current form.
- If priority is leaner execution API + runtime reason-code observability + operational telemetry, ralph is stronger.
- Best blend: retain ralph telemetry model and dispatch/auth split, while porting selected high-value opus edge-case matrices into ralph focused tests (or property/table-driven equivalents).
