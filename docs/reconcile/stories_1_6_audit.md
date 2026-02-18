# Stories 1-6 Contract Compliance Audit
Date: 2026-02-17 (original), 2026-02-18 (AT-925/AT-969 partial coverage updates)
Auditor: Claude Sonnet 4.6 (original), Claude Opus 4.6 (updates)

---

## Overall Stoplight

- **GREEN**: 35 stories (fully compliant — tests exist, behavior aligned)
- **YELLOW**: 11 stories (minor gaps — weak causality tests, missing RiskState::Degraded assertion, doc-only claims, or partial AT coverage with explicit deferral)
- **RED**: 1 story (contract conflict — AT-920 requires RiskState::Degraded but implementation does not enforce/assert it)

---

## Reconciliation Table

| Story | Story Ref | AT(s) | Actual Behavior | Verdict | Why | Required Patch |
|-------|-----------|-------|-----------------|---------|-----|----------------|
| S0-000 | P0-A Launch Policy Baseline | — | docs/launch_policy.md exists; evidence/phase0/policy/launch_policy_snapshot.md exists | KEEP | No ATs, doc-only; test file references test_trading_policy.rs which is a smoke check | None |
| S0-001 | P0-B Environment Isolation | — | docs/env_matrix.md exists; no implementation tests | KEEP | No ATs; pure doc story | None |
| S0-002 | P0-C Keys & Secrets Baseline | — | docs/keys_and_secrets.md exists; no implementation tests | KEEP | No ATs; pure doc story | None |
| S0-003 | P0-D Break-Glass Runbook | — | docs/break_glass_runbook.md exists; no implementation tests | KEEP | No ATs; pure doc story | None |
| S0-004 | P0-E Health Endpoint | AT-022 | test_phase0_runtime.rs::test_status_command_behavior_runtime tests ok/build_id/contract_version via stoic-cli | YELLOW | AT-022 requires HTTP 200 with key `ok==true` from GET /api/v1/health. Test invokes a CLI tool ("dispatch-check") not the HTTP endpoint. Test scope is narrower than AT-022 contract scope. Full AT-022 enforcement deferred to S8-008 per acceptance text. | Doc drift only — acceptable per PRD note "scaffolding — full AT-022 enforcement in S8-008" |
| S0-005 | P0-F Machine Policy Loader | AT-040, AT-341 | tools/phase0_meta_test.py and test_policy_is_required_and_bound_runtime check strict loader; malformed/missing policy → non-zero exit | GREEN | Fail-closed on missing/malformed policy verified. AT-040 (fail-closed for missing non-Appendix-A params) and AT-341 (Appendix A defaults applied) both tested | None |
| S1-001 | S1.0 Workspace scaffolding | AT-905, AT-901 | Cargo.toml has both crates; cargo test --workspace passes; verify.sh runs cargo test --workspace | GREEN | Both ATs verified structurally | None |
| S1-002 | S1.1 InstrumentKind + RiskState | AT-333 | test_instrument_kind_mapping.rs maps option/perpetual/linear_future/inverse_future; all 4 kinds covered; tick_size/amount_step/min_amount/contract_multiplier in infra struct | GREEN | AT-333 fully satisfied: derived from fetched metadata (no hardcoded defaults), all 4 instrument kinds mapped | None |
| S1-003 | S1.1 Instrument cache TTL | AT-104, AT-279 | test_instrument_cache_ttl.rs: stale → Degraded; opens_blocked(); fresh → Healthy; 25 tests covering all paths | YELLOW | AT-104 requires "OPEN dispatch count remains 0" proof via a pipeline-level test. test_opens_blocked_is_sole_gate_closes_ungated acknowledges closes are "architecturally ungated by this check" but relies on PolicyGuard integration not tested here. No pipeline dispatch count assertion confirming CLOSE/HEDGE/CANCEL are NOT blocked when stale. AT-279 covered (Degraded + ReduceOnly enforced). | Add pipeline-level integration test: stale cache → OPEN dispatch=0, CLOSE dispatch=1. Low urgency since opens_blocked() is the correct gate but causality proof is weak. |
| S1-004 | S1.2 OrderSize canonical sizing | AT-277 | test_order_size.rs: option/linear_future use qty_coin, perpetual/inverse_future use qty_usd, notional_usd always populated | GREEN | AT-277 fully satisfied: both worked examples tested, qty_usd unset for options confirmed | None |
| S1-005 | S1.3 Dispatcher amount mapping | AT-277 | test_dispatch_map.rs: amount field per instrument_kind, reduce_only mapping, exactly-one-field assertions | GREEN | AT-277 dispatcher rules verified | None |
| S1-006 | S1.1 Cache TTL observability | AT-104 | test_instrument_cache_ttl.rs: hits_total, stale_total, refresh_errors_total, last_age_s, breach events | GREEN | All required observability hooks tested | None |
| S1-007 | S1.3 Dispatcher mismatch rejection | AT-920 | test_dispatch_map.rs: ContractsAmountMismatch on delta>tolerance; counter increments; no dispatch on mismatch | RED | AT-920 requires "RiskState==Degraded" as a Pass criteria. Tests verify rejection reason and dispatch count=0, but no test asserts RiskState::Degraded is set on mismatch. The dispatch_map module returns DispatchMapError, but callers are responsible for setting RiskState::Degraded — and no test proves the caller path sets it. This is a causality gap: rejection fires but Degraded state propagation is unproven. | Add test asserting RiskState::Degraded is set when validate_and_dispatch returns ContractsAmountMismatch. Must be at the integration/chokepoint level. |
| S1-008 | S1.2 OrderSize discovery | AT-277, AT-920 | docs/order_size_discovery.md exists; no implementation tests | KEEP | Discovery-only story; test count=0 is intentional | None |
| S1-009 | S1.3 Dispatcher mapping discovery | AT-277, AT-920 | docs/dispatch_map_discovery.md exists; no implementation tests | KEEP | Discovery-only story | None |
| S1-010 | S1.0 Appendix A config defaults | AT-341, AT-040, AT-424, AT-970, AT-971 | crates/soldier_infra/tests/test_config_defaults.rs covers instrument_cache_ttl_s=3600, mm_util_kill=0.95, evidenceguard_global_cooldown defaults | GREEN | AT-341 (Appendix A CSP defaults) and AT-424 (per-key default check) covered. AT-040 (fail-closed for missing params) tested via fail-closed path. AT-970/AT-971 (GOP defaults) tested | None |
| S1-011 | S1.1 Deribit instrument structs | AT-333 | DeribitPublicInstrument struct in soldier_infra with tick_size/amount_step/min_amount/contract_multiplier; serde derives | GREEN | Prerequisite struct for AT-333; fields present | None |
| S1-012 | S1.4 Expiry Cliff Guard | AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966 | test_expiry_guard.rs: 6 tests covering delist buffer rejects OPEN, outside buffer allows OPEN, idempotent cancel, non-terminal cancel doesn't mark expired, reconcile doesn't halt other instruments, no retry loop | GREEN | All 7 ATs have corresponding tests; fail-closed behaviors verified | None |
| S1-013 | S1.0b PR merge-readiness gate | AT-1056, AT-1057 | plans/tests/test_pr_gate.sh fixture tests; workflow allowlist coverage | GREEN | CI gate tested with mocked fixtures | None |
| S2-000 | S2.1 Quantization rounding | AT-926, AT-280, AT-219, AT-908 | test_quantize.rs: 25+ tests covering BUY/SELL rounding, TooSmallAfterQuantization, InstrumentMetadataMissing on zero/NaN/Inf inputs, AT-219 price direction | GREEN | All 4 ATs covered with named tests (test_at219_*, test_at908_*, test_at926_*) | None |
| S2-001 | S2.2 Intent hash from quantized fields | AT-201, AT-343, AT-928, AT-218 | test_idempotency.rs: identical canonical fields → identical hash; timestamps excluded; WAL dedupe NOOP | GREEN | AT-343 (deterministic hash), AT-218 (codepath parity), AT-928 (WAL dedupe NOOP) all tested | None |
| S2-002 | S2.3 Compact label schema | AT-216, AT-217, AT-041, AT-921, AT-933 | test_label.rs: s4: format, ≤64 char limit enforced, encode/decode roundtrip, LabelTooLong rejection | YELLOW | AT-041 requires "/status shows RiskState::Degraded" on LabelTooLong. Tests verify Rejected(LabelTooLong) and no dispatch, but no test asserts RiskState becomes Degraded in the status output path. AT-933 (WS reconnect no duplicate dispatch) is claimed but test file focuses on label encoding not reconnect deduplication. | Assert RiskState::Degraded when LabelTooLong fires. AT-933 should be deferred to a reconnect integration test. |
| S2-003 | S2.4 Label match disambiguation | AT-217, AT-216 | test_label_match.rs: tie-breaker order; ambiguous → Degraded; clear candidate → deterministic | GREEN | AT-217 fully satisfied | None |
| S2-004 | S2.5 RejectReasonCode registry | AT-201 | test_reject_reason.rs: reject includes reason code; reason in registry; registry contains contract minimum | YELLOW | AT-201 requires unknown-action intent is treated as OPEN and blocked by OPEN gates. test_reject_reason.rs tests the registry and reason-code presence but does not explicitly test an unknown-action intent being classified OPEN and then blocked. The fail-closed classification path is not directly proven by a named test targeting the AT-201 "unknown action → OPEN" scenario. | Add test: intent with unknown action → classified OPEN → blocked by gate. |
| S3-000 | S3.1 Preflight guard | AT-004, AT-016, AT-017, AT-018, AT-019, AT-913, AT-914, AT-915 | test_preflight.rs: named tests for each AT (test_at016_*, test_at017_*, test_at913_*, test_at914_*, test_at915_*); all reject reasons verified | GREEN | All 8 ATs have directly named tests with dispatch-count=0 assertions | None |
| S3-001 | S3.2 Post-only crossing guard | AT-916 | test_post_only_guard.rs: crossing → Rejected(PostOnlyWouldCross); non-crossing → allowed | GREEN | AT-916 satisfied | None |
| S3-002 | S3.3 Capabilities matrix + feature flags | AT-028, AT-004, AT-915 | test_capabilities.rs: default linked_orders_supported=false; both flags needed for true | GREEN | AT-028 (capabilities gate) satisfied | None |
| S4-000 | S4.1 WAL append + replay no-resend | AT-935, AT-906, AT-233, AT-234, AT-925, AT-940 | test_ledger_replay.rs: named AT tests (test_at935_*, test_at906_*, test_at233_*, test_at234_*); queue-full returns error; no resend on replay | YELLOW | AT-935/906/233/234: fully proven with named tests. **AT-925: PARTIAL** — S4 proves queue-full detection + WAL error counter (test_queue_full_returns_immediately, test_at906_write_error_counter_increments) but does NOT prove PolicyGuard forces TradingMode::ReduceOnly under backpressure. Mode-forcing half deferred to S8.1c (PolicyGuard integration). AT-940: WAL crash-recovery half proven; full reconciliation flow is integration-level. | AT-925 integration test `test_at925_queue_full_forces_reduce_only_via_policyguard` assigned to S8.1c. S4 `passes: true` is defensible for its sub-obligation (WAL half) only. |
| S4-001 | S4.2 TLSM out-of-order events | AT-230, AT-210 | test_tlsm.rs: fill-before-ack → Filled, no crash, WAL contains both events | GREEN | AT-230 satisfied | None |
| S4-002 | S4.3 Trade-ID registry dedupe | AT-269, AT-270 | test_trade_id_registry.rs: duplicate trade_id is NOOP; atomic insert; restart dedupe | GREEN | ATs satisfied; note: reason_codes field lists ContractsAmountMismatch which appears to be a copy-paste error in PRD metadata — actual reason codes relate to WAL not dispatch map | Minor PRD metadata cleanup (reason_code wrong) — no behavioral gap |
| S4-003 | S4.4 Dispatch requires durable WAL barrier | AT-935, AT-906, AT-233, AT-234, AT-969 | test_dispatch_durability.rs and test_crash_mid_intent.rs: fsync barrier; queue-full error path; no duplicate dispatch on crash | YELLOW | AT-935/906/233/234: fully proven. **AT-969: GOP-DEFERRED** — requires EvidenceGuard (`enforced_profile != CSP`). S4 scope is CSP-only. No test exists; explicitly deferred to EvidenceGuard integration slice. | AT-969 test deferred to GOP profile implementation. S4 `passes: true` defensible: AT-969 is GOP-only and S4 is CSP-scoped. |
| S5-000 | S5.1 Liquidity Gate | AT-222, AT-344, AT-909, AT-421, AT-317 | test_liquidity_gate.rs: named AT tests; slippage>max → Rejected(ExpectedSlippageTooHigh); stale/missing L2 → Rejected(LiquidityGateNoL2); cancel allowed without L2 | GREEN | All 5 ATs verified with named tests, dispatch count=0 asserted | None |
| S5-001 | S5.2 Fee cache staleness | AT-031, AT-032, AT-033, AT-042, AT-244, AT-246, AT-318, AT-319, AT-320, AT-245 | test_fee_staleness.rs + test_fee_cache.rs: named AT tests for each; soft-stale buffer 1.20x; hard-stale → Degraded; missing timestamp → hard-stale | GREEN | 10 ATs all have corresponding named tests | None |
| S5-002 | S5.3 NetEdge gate | AT-015, AT-932, AT-243, AT-327 | test_net_edge_gate.rs: net_edge<min → Rejected(NetEdgeTooLow); missing inputs → Rejected(NetEdgeInputMissing); dispatch count=0 | GREEN | AT-015 and AT-932 both explicitly tested with "zero dispatch" assertions | None |
| S5-003 | S5.4 IOC limit pricer clamp | AT-223 | test_pricer.rs: limit_price clamped to max_price_for_min_edge; BUY/SELL direction | GREEN | AT-223 satisfied | None |
| S5-004 | S5.5 Single chokepoint build_order_intent() | AT-015 | test_gate_ordering.rs: gate sequence trace; all gates in order; no bypass | GREEN | Chokepoint enforcement verified | None |
| S6-000 | P1-A Single Dispatch Chokepoint Proof | AT-935, AT-906, AT-925 | test_dispatch_chokepoint.rs: AST/grep checks; exchange client only inside chokepoint; visibility restricted | YELLOW | AT-935/906: architectural chokepoint proven. **AT-925: PARTIAL** — chokepoint visibility restriction proven; PolicyGuard ReduceOnly forcing under WAL backpressure not proven here. Mode-forcing half deferred to S8.1c. | AT-925 integration test assigned to S8.1c. |
| S6-001 | P1-B Determinism Snapshot Test | AT-343, AT-218, AT-219, AT-216 | test_intent_determinism.rs: same inputs → same hash across runs; frozen clock; no HashMap ordering dependency | GREEN | AT-343 (wall-clock exclusion) verified | None |
| S6-002 | P1-C No Partial Side Effects on Rejection | AT-201, AT-926 | test_rejection_side_effects.rs: WAL unchanged, no orders, no position deltas on 3+ rejection cases | GREEN | Side-effect isolation verified | None |
| S6-003 | P1-D intent_id/run_id Propagation | AT-902 | test_intent_id_propagation.rs: all log lines include same intent_id; metrics labeled | GREEN | AT-902 satisfied | None |
| S6-004 | P1-E Gate Ordering Constraints | AT-010, AT-1055, AT-338 | test_gate_ordering.rs: reject before persist; WAL before dispatch; no side effects before accept | GREEN | Ordering invariants proven | None |
| S6-005 | P1-F Fail-Closed Defaults for Missing Config | AT-926, AT-930 | test_missing_config.rs: parameterized over critical keys; rejection + no side effects + enumerated reason | GREEN | Fail-closed defaults proven for all listed keys | None |
| S6-006 | P1-G Crash Mid-Intent Proof | AT-935, AT-233, AT-234, AT-906 | test_crash_mid_intent.rs: crash before dispatch → no duplicate on restart; test_at935_unsent_dispatches_exactly_once_across_two_restarts | GREEN | Crash-safety proven | None |
| S6-007 | S6.1 Inventory skew gate | AT-030, AT-043, AT-281, AT-282, AT-224, AT-922, AT-934 | test_inventory_skew.rs: rejects risk-increasing near limit; tick_penalty_max = exactly 3 ticks at bias=1.0; missing delta_limit → fail-closed | GREEN | ATs AT-281 (45% increase at bias=0.9) and AT-282 (3 ticks at bias=1.0) explicitly verified | None |
| S6-008 | S6.2 Pending exposure reservation | AT-225, AT-910 | test_pending_exposure.rs::test_pending_exposure_reservation_blocks_overfill: 5 concurrent opens, only budget-fitting subset passes | GREEN | AT-225 (overfill blocked), AT-910 (Rejected(PendingExposureBudgetExceeded)) verified | None |
| S6-009 | S6.3 Global exposure budget | AT-226, AT-911, AT-929 | test_exposure_budget.rs::test_global_exposure_budget_correlation_rejects: BTC+ETH near limits → correlation-aware rejection | GREEN | AT-226, AT-911, AT-929 all verified | None |
| S6-010 | S6.4 Margin headroom gate | AT-300, AT-301, AT-302, AT-206, AT-207, AT-208, AT-227, AT-228, AT-912 | test_margin_gate.rs::test_margin_gate_thresholds_block_reduceonly_kill: three thresholds (reject_opens, reduceonly, kill) with exact mm_util values | GREEN | All 9 ATs verified; MarginGateMode returned from gate aligns with PolicyGuard's TradingMode computation | None |

---

## Conflict List (RED/YELLOW items)

### RED Stories

#### S1-007 — Dispatcher mismatch rejection (AT-920)

**Contract AT + clause:**
AT-920 says:
> "Given: `contracts` and `amount` are provided and mismatch beyond `contracts_amount_match_tolerance`. When: dispatcher validates sizing before dispatch. Then: intent rejected with `Rejected(ContractsAmountMismatch)` and no dispatch occurs. Pass criteria: rejection reason matches; dispatch count remains 0; **RiskState==Degraded**."

**Implementation gap:**
- `validate_and_dispatch()` returns `Err(DispatchMapError::ContractsAmountMismatch)` — rejection reason and dispatch count=0 are both proven.
- However, **no test asserts that RiskState::Degraded is set** when this error is returned. The dispatch_map layer returns an error but does not itself set RiskState. The caller is expected to set Degraded, but there is no integration test proving that caller path executes correctly.
- `implementation_tests` lists `RiskState::Degraded` as a test artifact but this appears to be a metadata annotation, not an actual test name — no test named `RiskState::Degraded` exists in the test files.

**Risk level:** HIGH — AT-920 is a safety-critical invariant. If the caller never transitions to Degraded after a mismatch, OPEN intents on subsequent ticks may proceed without the degraded mode signal that other gates rely on.

**Required patch:** Add a chokepoint-level integration test: when `validate_and_dispatch` returns `ContractsAmountMismatch`, assert that the calling pipeline sets `RiskState::Degraded` and that the next OPEN intent is blocked.

---

### YELLOW Stories

#### S4-000 — WAL append + replay no-resend (AT-925 partial)

**Contract AT + clause:**
AT-925 says:
> "Given: a hot-loop output queue reaches capacity N. When: the hot loop attempts to enqueue another item. Then: the hot loop does not block and TradingMode is forced to ReduceOnly until the queue depth falls below N. Pass criteria: no stall; queue depth <= N; ReduceOnly enforced."

**Implementation gap:**
- S4 proves the WAL half: queue-full returns error immediately (non-blocking), `wal_write_errors` increments, OPEN intent rejected before dispatch. Tests: `test_queue_full_returns_immediately`, `test_at906_write_error_counter_increments`.
- S4 does NOT prove the PolicyGuard half: `TradingMode forced to ReduceOnly` under backpressure. That requires PolicyGuard to observe WAL queue state and force ReduceOnly — a cross-crate integration that doesn't exist in Phase 1.
- `primary_owner_for` updated: AT-925 removed from S4-000; integration half assigned to S8.1c.

**Risk level:** MED — The WAL half is safe (fail-closed: OPEN rejected). The gap is that if a future caller bypasses the WAL gate and queries PolicyGuard directly, PolicyGuard wouldn't know about backpressure. This becomes relevant when PolicyGuard is implemented in S8.1c.

**Required patch:** `test_at925_queue_full_forces_reduce_only_via_policyguard` in S8.1c scope. No S4 code changes needed.

---

#### S4-003 — Dispatch requires durable WAL barrier (AT-969 GOP-deferred)

**Contract AT + clause:**
AT-969 says:
> "Given: WAL queue full + `enforced_profile != CSP`. When: EvidenceGuard evaluates EvidenceChainState. Then: EvidenceChainState != GREEN while enqueue fails."

**Implementation gap:**
- AT-969 is explicitly GOP-profile only (`enforced_profile != CSP`). S4's entire scope is CSP.
- EvidenceGuard does not exist in Phase 1. No test possible until GOP profile implementation.
- S4.4's `enforcing_contract_ats` retains AT-969 for traceability but `partial_coverage_notes` now marks it as GOP-deferred.

**Risk level:** LOW — GOP-only AT. No CSP safety impact. Correctly deferred.

**Required patch:** None for S4. AT-969 test required when EvidenceGuard is implemented.

---

#### S6-000 — Single Dispatch Chokepoint Proof (AT-925 partial)

**Same gap as S4-000:** Architectural chokepoint visibility proven; PolicyGuard ReduceOnly forcing under backpressure deferred to S8.1c.

---

#### S0-004 — Health Endpoint (AT-022)

**Contract AT + clause:**
AT-022 says:
> "Given: service is running. When: GET /api/v1/health. Then: HTTP 200 and keys ok, build_id, contract_version exist with ok==true."

**Implementation gap:**
- Test invokes `stoic-cli dispatch-check` (a command-line tool), not an HTTP endpoint. AT-022 is an HTTP endpoint test.
- PRD explicitly marks this as "scaffolding — full AT-022 enforcement in S8-008" which is acceptable deferral.

**Risk level:** LOW — explicitly deferred. Not a compliance gap, just incomplete scaffolding.

**Required patch:** None for Phase 1. Ensure S8-008 provides the HTTP endpoint test.

---

#### S1-003 — Instrument cache TTL (AT-104)

**Contract AT + clause:**
AT-104 says:
> "Pass criteria: OPEN dispatch count remains 0; CLOSE/HEDGE/CANCEL are not blocked solely by stale metadata."

**Implementation gap:**
- Tests verify `opens_blocked(RiskState::Degraded) == true` at the cache layer, which is correct.
- `test_opens_blocked_is_sole_gate_closes_ungated` explicitly notes closes are "architecturally ungated by this check" and that "Full dispatch eligibility for CLOSE in ReduceOnly is validated at the PolicyGuard integration level."
- No pipeline-level test proves OPEN dispatch count=0 while CLOSE dispatch proceeds when cache is stale.

**Risk level:** MED — The architectural claim is reasonable but the contract requires proof of causality, not just architectural reasoning.

**Required patch:** Add integration test with stale cache: OPEN intent → dispatch count=0, CLOSE intent → dispatch count=1.

---

#### S2-002 — Compact label schema (AT-041, AT-921)

**Contract AT + clause:**
AT-041 says:
> "Pass criteria: no order is sent; /status shows RiskState::Degraded; mode_reasons includes a label-length reason code if defined."

**Implementation gap:**
- Tests verify Rejected(LabelTooLong) and dispatch count=0, which is good.
- No test asserts that `/status` shows `RiskState::Degraded` after a LabelTooLong rejection.
- AT-933 (WS reconnect no duplicate) is claimed in `enforcing_contract_ats` but tests only cover label encoding, not WS reconnect scenarios.

**Risk level:** LOW — AT-041's status-endpoint assertion is a documentation gap. AT-933 is a scope mismatch in PRD metadata.

**Required patch:** Assert RiskState::Degraded is set when LabelTooLong fires. Remove AT-933 from enforcing_contract_ats for S2-002 or add a reconnect test to S2-002's scope.

---

#### S2-004 — RejectReasonCode registry (AT-201)

**Contract AT + clause:**
AT-201 says:
> "Given: an OrderIntent with an unknown action value OR missing required classification fields. When: intent classification is computed. Then: classification MUST be OPEN."

**Implementation gap:**
- Tests verify that a pre-dispatch reject includes a reason code in the registry.
- No test directly targets the AT-201 scenario: an intent with an unknown action value being classified as OPEN and then blocked by OPEN gates.
- The acceptance criteria in the PRD mentions this scenario but no test name in `implementation_tests` corresponds to it.

**Risk level:** MED — Fail-closed classification for unknown actions is safety-critical. If unknown actions bypass OPEN gates (treated as CLOSE), they could dispatch without edge/liquidity checks.

**Required patch:** Add test: intent with `action = "UNKNOWN_FUTURE_VALUE"` → classified OPEN → blocked by OPEN gate (dispatch count=0).

---

## Evidence Gaps

### Test Files Referenced but Missing Test Names

| Story | PRD `implementation_tests` claim | Actual finding |
|-------|----------------------------------|----------------|
| S1-003 | `crates/soldier_core/tests/test_instrument_cache_ttl.rs` (named "test_instrument_cache_ttl_blocks_opens_allows_closes") | File exists but that specific test name does not exist. Test `test_stale_cache_blocks_opens` covers partial behavior but no CLOSE/HEDGE/CANCEL dispatch proof. |
| S1-007 | `RiskState::Degraded` listed as an implementation test | Not a test name — a type annotation. No test by that name. |
| S2-003 | `RiskState::Degraded` listed as an implementation test | Same issue — not a test name. |

### PRD Metadata Errors

| Story | Field | Error | Impact |
|-------|-------|-------|--------|
| S4-002 | `reason_codes.values` | Lists `ContractsAmountMismatch` — this is a dispatch-layer code, not relevant to Trade-ID registry | No behavioral gap; metadata cleanup only |
| S4-001 | `reason_codes.values` | Lists `ContractsAmountMismatch` — TLSM story should list TLSM-related codes | No behavioral gap; metadata cleanup only |
| S2-002 | `enforcing_contract_ats` includes AT-933 | AT-933 is about WS reconnect deduplication, not label encoding | Scope mismatch; no WS reconnect tests in S2-002 |
| S1-008, S1-009 | `enforcement_point = StatusEndpoint` | Discovery stories should have no enforcement point | Metadata only; no code impact |

---

## Minimal Next Actions (ordered, smallest first)

1. **[HIGH — S1-007]** Add integration test at chokepoint level: when `validate_and_dispatch` returns `ContractsAmountMismatch`, assert `RiskState::Degraded` is set and subsequent OPEN intent is blocked. File: `crates/soldier_core/tests/test_dispatch_map.rs` or a new `test_chokepoint_degraded.rs`.

2. **[MED — S8.1c / AT-925]** Add integration test `test_at925_queue_full_forces_reduce_only_via_policyguard`: WAL queue full → PolicyGuard observes backpressure → TradingMode::ReduceOnly forced → OPEN blocked. This completes the AT-925 chain that S4-000 and S6-000 only partially cover (WAL detection half). Must be in S8.1c scope since it requires PolicyGuard implementation. Placeholder test name reserved.

3. **[MED — S2-004]** Add test: intent with unknown/unrecognized action value → classified as OPEN → blocked by OPEN gate → dispatch count=0. File: `crates/soldier_core/tests/test_reject_reason.rs` or `test_intent_pipeline.rs`.

4. **[MED — S1-003]** Add pipeline-level integration test proving AT-104 causality: stale instrument cache → OPEN dispatch count=0, CLOSE dispatch count=1 (CLOSE not blocked). This is the "dispatch count is sole proof" requirement from CONTRACT.md §76. File: extend `test_instrument_cache_ttl.rs` with a pipeline mock or add to `test_intent_pipeline.rs`.

5. **[LOW — S2-002]** Add assertion: `RiskState::Degraded` is set when `LabelTooLong` fires. This must be at integration/pipeline level, not just at the label-encoding layer. File: `test_label.rs` or `test_intent_pipeline.rs`.

6. **[LOW — PRD metadata]** Fix metadata errors in S4-002, S4-001 (wrong reason_codes), S2-002 (remove AT-933 or add reconnect test), S1-008/S1-009 (wrong enforcement_point). These are documentation-only corrections with no behavioral impact.

7. **[INFO — S0-004]** Confirm S8-008 is planned and will provide a proper HTTP endpoint test for AT-022. Nothing to do now; track as a future gate.

8. **[INFO — AT-969]** GOP-only AT in S4-003. Test required when EvidenceGuard is implemented (GOP profile slice). No action until then.

---

## Audit Methodology Notes

- All test file existence was verified via `ls crates/soldier_core/tests/` and `ls crates/soldier_infra/tests/`.
- AT definitions were read directly from `specs/CONTRACT.md` (5933 lines) using grep + offset reads.
- Test function names were verified by grepping each referenced test file.
- Dispatch count assertions were checked by reading test bodies for `assert_eq!(count, 0)` or equivalent.
- RiskState::Degraded assertions were checked by grepping for the string in test bodies.
- Source-level behavior was spot-checked for `test_dispatch_map.rs`, `test_instrument_cache_ttl.rs`, `test_margin_gate.rs`, `test_expiry_guard.rs`, and `test_reject_reason.rs`.
- S7+ stories (passes=false) were excluded per audit scope.
