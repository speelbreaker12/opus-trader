# GAP_LIST — Slice 1 (13 Stories)

**HEAD**: `5bfc230b766850d6c315fbd741c9657996186b21`
**Generated**: 2026-02-24T02:15:00Z
**Phase**: R4 Gap Synthesis
**Input**: R1 evidence ledgers (13) + R2 Lead Eval + R3A Cross-Review + R3B External (Codex enriched reviews for 13 stories)

---

## Gap Summary

| Severity | Count | CI-Blocking? |
|----------|-------|-------------|
| P0 | 1 (shared root cause, 2 stories) | YES |
| P1 | 4 | No (regression test debt) |
| P2 | 6 | No (deferred debt) |
| DEFERRED | 4 (multi-item) | No (future slices) |

---

## P0 Gaps (CI-Blocking)

| Gap ID | Story | Description | Source | External Corroboration | Remediation |
|--------|-------|-------------|--------|----------------------|-------------|
| GAP-S1-005-001 | S1-005, S1-007 | `test-helpers` feature flag not in committed Cargo.toml — tests don't compile on CI. `GateResults::all_passed()` is gated behind `#[cfg(any(test, feature = "test-helpers"))]` but the feature must be explicitly passed. | R1 | codex.enriched (S1-005, S1-007), R3A cross-review | Single Cargo.toml edit to add `test-helpers` to default test features |

---

## P1 Gaps (Missing Regression Tests on Safety Paths)

| Gap ID | Story | Description | Source | External Corroboration | Remediation |
|--------|-------|-------------|--------|----------------------|-------------|
| GAP-S1-005-002 | S1-005 | No negative amount input test — guard exists in `map_to_dispatch()` but no regression test exercises the rejection path for negative `canonical_qty`. | R1 | codex.enriched (S1-005 finding #2: "synthetic test, no reason code assertion" — adjacent signal) | Add test: negative `canonical_qty` -> rejection with expected reason code |
| GAP-S1-007-001 | S1-007 | `build_open_intent_with_assembly()` has zero production callers — the function exists and is tested but not called from any production code path. | R1 | codex.enriched (S1-005 finding #1: "map_to_dispatch() no production callsites" — same pattern) | Wire into production assembly path or mark as test-only utility |
| GAP-S1-007-002 | S1-007 | `DispatchConsistencyProof::unchecked(true)` bypass path exists — allows skipping AT-920 mismatch validation via a boolean flag. | R1 | None (external reviews did not flag this specifically) | Gate `unchecked(true)` behind `#[cfg(test)]` or remove bypass path |
| GAP-S1-010-001 | S1-010 | AT-040 Err path structurally unreachable in production — `resolve_config_value()` Err variant only triggered via `SyntheticNoDefault` test-only enum variant. Mechanism proven but no production path exercises it. | R1 | None (S1-010 codex review failed due to rate limit) | Track as WEAK_PROOF debt; exhaustive `EXPECTED_PARAM_COUNT` guard mitigates regression risk |

---

## P2 Gaps (Test Gaps on Guarded Code)

| Gap ID | Story | Description | Source | Remediation |
|--------|-------|-------------|--------|-------------|
| GAP-S1-002-001 | S1-002 | Assumption #2 (USDC API returns consistent pricing) unvalidated — no test asserts USDC pricing behavior. | R1 | Add validation test when API integration layer is built |
| GAP-S1-003-001 | S1-003 | Negative TTL not explicitly tested — `ttl_s < 0.0` not covered by dedicated test (NaN/Inf are tested). | R1 | Add test: negative `ttl_s` -> fail-closed to Degraded |
| GAP-S1-004-001 | S1-004 | 4 missing bad-input variant tests for `build_order_size`; missing observability metric `METRIC_ORDER_SIZE_REJECT`. | R1 | Add tests for: empty instrument_id, negative price, negative qty, zero contract_multiplier |
| GAP-S1-005-003 | S1-005 | PRD `reason_codes` metadata error — prd.json entry references incorrect reason code names. | R1 | Update prd.json metadata to match actual `RejectReasonCode` enum variants |
| GAP-S1-010-002 | S1-010 | Missing observability metric; CONTRACT.md Appendix A.7 table incomplete for config validation. | R1 | Add metric on config validation rejection; update A.7 table |
| GAP-S1-012-001 | S1-012 | `METRIC_EXPIRY_GUARD_REJECT` declared but not wired to actual metric emission; 3 deferred debt items (reconcile loop, DelistingSoon state, buffer+reconcile interaction). | R1 | Wire metric in ExpiryGuard rejection path |

---

## DEFERRED (Future Slices)

| Debt ID | Story | Description | Target Slice |
|---------|-------|-------------|-------------|
| DEBT-S1-003-001 | S1-003 | PolicyGuard integration test (stale cache -> Degraded -> ReduceOnly pipeline proof) | S2+ |
| DEBT-S1-003-002 | S1-003 | Per-instrument TTL support (currently global TTL only) | S3+ |
| DEBT-S1-010-003 | S1-010 | Config loader wiring for remaining params (7/74 wired); CI param count parity gate | S2+ |
| DEBT-S1-011-001 | S1-011 | Deribit API field validation against live responses | S3+ |
| DEBT-S1-012-002 | S1-012 | Reconcile loop integration; DelistingSoon state; buffer+reconcile interaction | S2+ |

---

## External Finding Disposition Summary

Total external (codex) P0/P1 findings across 13 stories: **21 findings**

| Disposition | Count | Percentage |
|-------------|-------|-----------|
| FALSE POSITIVE | 14 | 67% |
| DUPLICATE (matches known gap) | 5 | 24% |
| GENUINELY NEW | 2 | 9% |

The 2 genuinely new findings were both re-classified to P2 after evaluation against reconciliation policy (they are observability/metadata issues on guarded code, not safety-path regressions):
- S1-006 codex finding #2 (cache miss counter semantics) -> P2 observation, `lookups_total` already tracks all accesses
- S1-003 codex finding #3 (premortem cites nonexistent test name) -> P2 metadata hygiene, enforcement is proven via real tests

See `R4B_EXTERNAL_MAPPING.md` for the complete per-finding disposition table.
