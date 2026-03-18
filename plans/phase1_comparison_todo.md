# Phase 1 Comparison TODO (opus-trader)

Purpose: track newly found issues, fixes, and suggestions from cross-repo Phase 1 comparisons.

Last comparison run used for seed entries:
- `artifacts/phase1_compare/20260213_143551_focused_exec_gates_tests/focused_compare_summary.md`
- `artifacts/phase1_compare/20260213_202708/report.md`
- `artifacts/phase1_compare/20260213_200857/report.md`
- `artifacts/phase1_compare/20260213_160538/report.md`

## How to update

1. Add new findings to `Open Issues` or `Suggestions`.
2. When resolved, move item to `Completed Fixes` with commit/ref and verification evidence.
3. Keep newest updates at the top of each table.

## Open Issues

| ID | Status | Found In | Issue | Suggested Fix | Evidence |
|---|---|---|---|---|---|
| OPUS-CMP-010 | open | 20260213_223424_slice6_compare | Slice6 risk stories `S6-007..S6-010` are present but still `passes=false` at pinned ref, so cross-repo comparison cannot yet cover the full Slice6 scope. | Keep decisions bounded to shared passed stories (`S6-000..S6-006`) or complete `S6-007..S6-010` and rerun pinned-ref weighted compare. | `plans/prd.json`; `artifacts/phase1_compare/20260213_223424_slice6_compare/slice6_story_matrix.md` |
| OPUS-CMP-001 | open | 20260213_160538 | Missing required Phase 1 evidence file `evidence/phase1/restart_loop/restart_100_cycles.log`. | Generate restart-loop artifact via the contract-required restart proof flow and commit it. | `artifacts/phase1_compare/20260213_160538/report.md` |
| OPUS-CMP-002 | open | 20260213_160538 | `./plans/verify.sh quick` fails at contract kernel: `sources.contract_sha256 mismatch`. | Align contract source hash inputs (or regenerate expected hash) and rerun quick/full verify in clean tree. | `artifacts/phase1_compare/20260213_160538/opus/logs/verify_quick.log` |
| OPUS-CMP-003 | open | 20260213_160538 | Phase 1 PRD has remaining stories not passed: `S1-012`, `S2-004`. | Resolve acceptance gaps, run verify, and flip `passes=true` only via `plans/prd_set_pass.sh`. | `artifacts/phase1_compare/20260213_160538/report.md` |
| OPUS-CMP-004 | open | 20260213_160538 | 13 Phase 1 stories missing `enforcing_contract_ats` references. | Add explicit enforcing AT references per story where contract refs exist. | `artifacts/phase1_compare/20260213_160538/report.md` |

## Suggestions

| ID | Status | Suggestion | Why | Evidence/Context |
|---|---|---|---|---|
| OPUS-SUG-006 | completed | Split chokepoint proof into two tiers: keep ralph-style sentinel invariant checks plus opus-style deep boundary scans. | Preserves low-noise guardrails while retaining stronger bypass detection. | `crates/soldier_core/tests/test_dispatch_chokepoint.rs`; `artifacts/phase1_compare/20260213_223424_slice6_compare/diffs/crates__soldier_core__tests__test_dispatch_chokepoint.rs.diff` |
| OPUS-SUG-001 | open | Run comparison from clean worktree/CI checkout before decision sign-off. | Removes dirty-tree noise and makes verify parity auditable. | Comparison workflow notes + verify dirty-tree policy |
| OPUS-SUG-002 | open | Add per-gate normalization from verify artifact `*.rc` files. | Makes cross-repo gate parity apples-to-apples even when section names differ. | `plans/progress.txt` latest comparison note |
| OPUS-SUG-003 | open | Run periodic full-verify parity comparison (`--run-full-verify`) at frozen refs. | Exposes full gate regressions that quick mode can miss. | `tools/phase1_compare.py` new full verify parity section |
| OPUS-SUG-004 | open | Add 3-run flakiness check for the shared Phase 1 scenario command. | Detects unstable behavior hidden by single-run pass/fail checks. | `tools/phase1_compare.py` flakiness section |
| OPUS-SUG-005 | open | Define one canonical golden scenario command for behavioral diff every run. | Keeps reason-code/status-field/dispatch-count comparison consistent over time. | `tools/phase1_compare.py` scenario behavioral parity section |

## Completed Fixes

| ID | Completed On | Fix | Verification | Evidence |
|---|---|---|---|---|
| OPUS-CMP-012 | 2026-02-13 | Pinned explicit S6-000 focused compare tag refs and reran focused parity compare using those tags for reproducibility (`slice6-s6000-focused-20260213-opus`, `slice6-s6000-focused-20260213-ralph`). | Focused S6-000 compare at pinned tags completed; chokepoint tests pass in both repos (`opus 9/9`, `ralph 3/3`). | `artifacts/phase1_compare/20260213_230014_slice6_s6000_compare_tagged/s6000_compare_summary.md`; `artifacts/phase1_compare/20260213_230014_slice6_s6000_compare_tagged/opus/logs/s6000_dispatch_chokepoint.log`; `artifacts/phase1_compare/20260213_230014_slice6_s6000_compare_tagged/ralph/logs/s6000_dispatch_chokepoint.log` |
| OPUS-CMP-011 | 2026-02-13 | Added hybrid S6-000 chokepoint strategy in opus by keeping deep boundary scans and adding a sentinel-presence assertion for approval (`record_approved();`) in the chokepoint module. | `cargo test -p soldier_core --test test_dispatch_chokepoint` passed (9 tests). | `crates/soldier_core/tests/test_dispatch_chokepoint.rs`; command output from `/Users/admin/Desktop/opus-trader` |
| OPUS-CMP-009 | 2026-02-13 | Ported structured execution telemetry into opus (`gate_sequence_total`, `preflight_reject_total`, `liquidity_gate_reject_total`, `expected_slippage_bps`, `net_edge_reject_total`) with trace-id propagation support in metric lines. | Focused execution/gate suites pass with new telemetry assertions (preflight/liquidity/net-edge/gate-ordering). | `crates/soldier_core/src/execution/mod.rs`; `crates/soldier_core/src/execution/build_order_intent.rs`; `crates/soldier_core/src/execution/preflight.rs`; `crates/soldier_core/src/execution/gate.rs`; `crates/soldier_core/src/execution/gates.rs`; `crates/soldier_core/tests/test_preflight.rs`; `crates/soldier_core/tests/test_liquidity_gate.rs`; `crates/soldier_core/tests/test_net_edge_gate.rs`; `crates/soldier_core/tests/test_gate_ordering.rs` |
| OPUS-CMP-008 | 2026-02-13 | Added automated weighted scoring output (`correctness/safety`, `performance`, `maintainability`) to phase1 comparison Markdown + JSON reports with configurable weights. | Weighted section + winner margin rendered in report and serialized in JSON output. | `artifacts/phase1_compare/20260213_202708/report.md`; `artifacts/phase1_compare/20260213_202708/report.json`; `tools/phase1_compare.py`; `docs/phase1_outcome_compare_checklist.md` |
| OPUS-CMP-007 | 2026-02-13 | Added per-repo verify toggles (`--run-quick-verify-opus|ralph`, `--run-full-verify-opus|ralph`) to avoid accidental cross-repo gate execution. | Toggle smoke run executed opus quick verify only while ralph verify remained not run. | `artifacts/phase1_compare/20260213_202314/report.md`; `tools/phase1_compare.py`; `docs/phase1_outcome_compare_checklist.md` |
| OPUS-CMP-006 | 2026-02-13 | Pinned explicit Phase1 implementation tags in both repos (`phase1-impl-opus`, `phase1-impl-ralph`) and reran weighted comparison on those refs. | Clean pinned-ref rerun with `dirty files=0`, commit SHAs resolved, weighted winner produced. | `artifacts/phase1_compare/20260213_202708/report.md`; `artifacts/phase1_compare/20260213_202708/report.json` |
| OPUS-CMP-005 | 2026-02-13 | Selected canonical shared scenario command `cargo test -p soldier_core --test test_gate_ordering` (exists in both repos). | Scenario pass + 3-run flakiness pass in both repos. | `artifacts/phase1_compare/20260213_181407/report.md`; `artifacts/phase1_compare/20260213_181407/opus/logs/scenario.log`; `artifacts/phase1_compare/20260213_181407/ralph/logs/scenario.log` |
