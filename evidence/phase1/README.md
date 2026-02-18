# Phase 1 Evidence Pack

**Status:** COMPLETE (pending owner sign-off)

## What was proven

- **Single chokepoint (P1-A):** All dispatch flows route through `build_order_intent()` in `crates/soldier_core/src/execution/build_order_intent.rs`. No code path bypasses this chokepoint. Verified by `test_dispatch_chokepoint_no_direct_exchange_client_usage` and `test_dispatch_visibility_is_restricted`.
- **Determinism (P1-B):** 13 determinism tests run 100 iterations each with fixed inputs, asserting byte-exact equality of outputs. Covers quantize, pricer, net edge, liquidity gate, label encoding, and the full pipeline including HashMap ordering independence.
- **No side effects on rejection (P1-C):** 11 rejection scenarios prove that rejected intents leave zero persistent state changes (no WAL/order/position/exposure mutation). Only observability counters modified.
- **Intent ID propagation (P1-D):** `intent_id` and `run_id` propagate through both approved and rejected pipelines. All log/metric entries attributable to their originating intent.
- **Gate ordering (P1-E):** Reject-only gates execute before persistent side effects. WAL record gate comes after all validation gates. Approval requires all 8 gates to pass.
- **Fail-closed config (P1-F):** 12 missing/invalid config keys tested (tick_size, amount_step, NaN, Inf, negative, gross_edge, fee_usd, slippage, min_edge, l2_snapshot, zero qty, unhealthy RiskState). All produce deterministic rejection with specific reason codes. No side effects.
- **Crash-mid-intent (P1-G):** 7 scenarios in `soldier_infra` prove no duplicate dispatch on crash/restart. Unsent intents discarded, sent intents reconciled, terminal intents ignored, WAL failure prevents dispatch.

## What failed

Nothing. All 14 AUTO gates pass. All manual artifacts present and substantive.

## What remains risky

- P1-G crash-mid-intent AUTO test lives in `soldier_infra`, not `soldier_core`. A future refactor could split these packages and break the test without CI catching it if the workflow only runs `soldier_core` tests.
- Determinism tests use fixed seeds but do not yet test across process restarts (planned: `restart_loop/restart_100_cycles.log`).
- CI runs a single platform (Linux x86_64). No cross-platform determinism proof yet.

---

## Checklist Status

| Item | AUTO Gate | MANUAL Artifact | Status |
|------|-----------|-----------------|--------|
| P1-A | `test_dispatch_chokepoint_*`, `test_dispatch_visibility_*` | `docs/dispatch_chokepoint.md` | PASS |
| P1-B | `test_full_pipeline_determinism`, `test_chokepoint_same_inputs_same_trace` | `determinism/intent_hashes.txt` | PASS |
| P1-C | `test_rejected_intent_has_no_side_effects` + 10 more | `no_side_effects/rejection_cases.md` | PASS |
| P1-D | `test_intent_id_propagates_*` (2), `test_metrics_attributable_*` | `traceability/sample_rejection_log.txt` | PASS |
| P1-E | `test_constraint_*` (3 tests) | `docs/intent_gate_invariants.md` | PASS |
| P1-F | `test_missing_tick_size_fails_closed` + 11 more | `config_fail_closed/missing_keys_matrix.json` | PASS |
| P1-G | 7 tests in `soldier_infra` | `crash_mid_intent/drill.md` | PASS (drill) |

## Owner Sign-Off

1. Can any code path dispatch without the chokepoint? **NO** — see `docs/dispatch_chokepoint.md`, P1-A tests
2. Identical frozen inputs → identical intent bytes? **YES** — see `determinism/intent_hashes.txt`, P1-B tests (13 components, 100 iterations each)
3. Can rejected intent leave persistent state? **NO** — see `no_side_effects/rejection_cases.md`, P1-C tests (11 rejection paths)
4. All logs traceable by intent_id? **YES** — see `traceability/sample_rejection_log.txt`, P1-D tests
5. Missing config → fail-closed with enumerated reason? **YES** — see `config_fail_closed/missing_keys_matrix.json`, P1-F tests (12 keys)

**Phase 1 DONE:** YES (pending human owner review of this sign-off)
