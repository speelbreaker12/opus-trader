# Slice 1 Reconciliation Summary

**Date**: 2026-02-21
**Branch**: `recon/S5-004`
**Stories**: 13 (S1-001 through S1-013)
**Process**: Part B (Implementation Reconciliation), Phases R1-R7

---

## Final Verdicts

| Story | Domain | Final Verdict | R7c Wiring | Debt Items |
|-------|--------|---------------|------------|------------|
| S1-001 | Scaffolding | **RECONCILED** | NOT-WIRED | 0 |
| S1-002 | Instrument types | **RECONCILED** | NOT-WIRED | 0 |
| S1-003 | Instrument cache | **RECONCILED-WITH-DEBT** | NOT-WIRED | GAP-003-2, GAP-003-3 |
| S1-004 | Open permission | **RECONCILED** | NOT-WIRED | 0 |
| S1-005 | Dispatch mapping | **RECONCILED** | PARTIAL | 0 |
| S1-006 | Cache observability | **RECONCILED** | NOT-WIRED | 0 |
| S1-007 | Order sizing | **RECONCILED-WITH-DEBT** | WIRED | GAP-007-1 |
| S1-008 | Risk state | **RECONCILED** | WIRED | 0 |
| S1-009 | Discovery doc | **RECONCILED-WITH-DEBT** | N/A | GAP-009-1 |
| S1-010 | Config defaults | **RECONCILED-WITH-DEBT** | PARTIAL | GAP-010-4, GAP-010-5 |
| S1-011 | Deribit instrument | **RECONCILED** | PARTIAL | 0 |
| S1-012 | Expiry guard | **RECONCILED-WITH-DEBT** | WIRED | GAP-012-5, GAP-012-6, GAP-012-7 |
| S1-013 | CI gate | **RECONCILED** | N/A (CI) | 0 |

```
RECONCILED:           8  (S1-001, S1-002, S1-004, S1-005, S1-006, S1-008, S1-011, S1-013)
RECONCILED-WITH-DEBT: 5  (S1-003, S1-007, S1-009, S1-010, S1-012)
NOT RECONCILED:       0
```

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Tests before reconciliation | 890 |
| Tests after all fixes (R5 + R7) | 899 |
| Net new tests | +9 |
| P0 gaps found | 1 (GAP-012-1: compilation error) |
| P1 gaps found | 3 (GAP-010-1, GAP-012-2, GAP-007-1) |
| P2 gaps found | 12 |
| DEFERRED items | 9 (tracked for Slice 2+) |
| R7d code review findings | 1 P1, 4 P2 (all fixed) |
| R7e devils advocate gaps | 5 actionable (all closed), 1 structural (accepted) |
| Simpler-Than-Correct Gate | **PASS** (all 5 implementations) |

---

## Production Wiring Status (R7c)

| Wiring | Count | Stories |
|--------|-------|---------|
| WIRED | 3 | S1-007, S1-008, S1-012 |
| PARTIAL | 3 | S1-005, S1-010, S1-011 |
| NOT-WIRED | 5 | S1-001, S1-002, S1-003, S1-004, S1-006 |
| N/A | 2 | S1-009 (discovery), S1-013 (CI) |

**Critical finding**: 58% of enforcement functions have zero production callers. Guards are PROVEN-UNIT (correct when called) but not PROVEN-INTEGRATED (reachable at runtime). See [LSP_CALL_CHAIN_CHECK.md](LSP_CALL_CHAIN_CHECK.md) and [STRATEGIC_REVIEW_R5.md](STRATEGIC_REVIEW_R5.md) H1 ("island of guards").

---

## Highest-Impact Findings

1. **Island of guards** (R7b H1 + R7c): Most Slice 1 guards are tested in isolation but not wired into the production pipeline. `PolicyGuard` and `TradingMode` types don't exist as code. Requires a Slice 2 integration story.

2. **Caller-bypass risk** (R7b H2): `dispatch_consistency_passed` is a bare `bool` — any caller can pass `true` without running the mismatch check. `ValidatedDispatch` proof token exists but isn't threaded through the pipeline.

3. **Missing intent variation** (R7e DA-002): No test distinguished `Cancel` vs `Close` intent on expired instruments. Fixed by `test_cancel_outcome_varies_by_intent_for_expired`.

4. **Per-field deserialization** (R7e DA-006): Empty-JSON test only proved "a field is required," not "which field." Fixed by `test_required_fields_individually_enforced` (11 per-field omission tests).

5. **Hardcoded test values** (R7e DA-003): All breach tests used `ttl_s=3600.0` — hardcoded production value would pass. Fixed by adding a test with `ttl_s=120.0`.

---

## Debt Register (Deferred to Slice 2+)

| ID | Story | Description | Target |
|----|-------|-------------|--------|
| GAP-003-2 | S1-003 | PolicyGuard integration test | Slice 2 |
| GAP-003-3 | S1-003 | Per-instrument TTL configuration | Slice 3+ |
| GAP-007-1 | S1-007 | Wire `validate_and_dispatch` into production | Slice 2 |
| GAP-009-1 | S1-009 | Per-instrument-kind edge case table | Slice 2 |
| GAP-010-4 | S1-010 | Config loader wired into runtime | Slice 2 |
| GAP-010-5 | S1-010 | CI check: test param count == Appendix A count | Slice 2 |
| GAP-012-5 | S1-012 | Reconcile loop integration test | Slice 2+ |
| GAP-012-6 | S1-012 | DelistingSoon intermediate state | Slice 2+ |
| GAP-012-7 | S1-012 | Other errors -> Retryable regardless of expiry | Slice 2+ |

---

## Detailed Reports

| Phase | File | Description |
|-------|------|-------------|
| R1 | [BATCH_DISPATCH_reconciliation.md](BATCH_DISPATCH_reconciliation.md) | Evidence ledger: S1-004, S1-005, S1-007 |
| R1 | [BATCH_EXPIRY_reconciliation.md](BATCH_EXPIRY_reconciliation.md) | Evidence ledger: S1-012, S1-013 |
| R1 | [BATCH_INFRA_reconciliation.md](BATCH_INFRA_reconciliation.md) | Evidence ledger: S1-001, S1-008, S1-009, S1-010 |
| R1 | [BATCH_INSTRUMENT_reconciliation.md](BATCH_INSTRUMENT_reconciliation.md) | Evidence ledger: S1-002, S1-003, S1-006, S1-011 |
| R3 | [RECONCILE_REVIEW_by_DISPATCH.md](RECONCILE_REVIEW_by_DISPATCH.md) | Cross-review (dispatch reviewer) |
| R3 | [RECONCILE_REVIEW_by_EXPIRY.md](RECONCILE_REVIEW_by_EXPIRY.md) | Cross-review (expiry reviewer) |
| R3 | [RECONCILE_REVIEW_by_INFRA.md](RECONCILE_REVIEW_by_INFRA.md) | Cross-review (infra reviewer) |
| R3 | [RECONCILE_REVIEW_by_INSTRUMENT.md](RECONCILE_REVIEW_by_INSTRUMENT.md) | Cross-review (instrument reviewer) |
| R4 | [GAP_LIST.md](GAP_LIST.md) | Unified gap list with priorities and fixes |
| R7a | [CONTRACT_REVIEW_R5.md](CONTRACT_REVIEW_R5.md) | Contract review on remediation diff |
| R7b | [STRATEGIC_REVIEW_R5.md](STRATEGIC_REVIEW_R5.md) | Strategic failure review |
| R7c | [LSP_CALL_CHAIN_CHECK.md](LSP_CALL_CHAIN_CHECK.md) | Production wiring audit |
| R7e | [DEVILS_ADVOCATE_R7.md](DEVILS_ADVOCATE_R7.md) | Mutation analysis (initial) |
| R7e | [DEVILS_ADVOCATE_R7_RECHECK.md](DEVILS_ADVOCATE_R7_RECHECK.md) | Mutation analysis (recheck — all gaps closed) |

---

## Process Observations

**What worked well**:
- Cross-review (R3) found 8 issues the lead missed (+53% lift)
- Devils advocate (R7e) found 5 test gaps invisible to structural review
- Strategic review (R7b) found the systemic "island of guards" pattern
- Two-pass R7e protocol (find → fix → recheck) confirmed all closures

**What to improve for Slice 2**:
- Add production wiring check earlier (R7c found the biggest issue — move it to R1 or R2)
- Run the Simpler-Than-Correct Gate as part of initial test writing, not just post-hoc review
- Create an integration story for NOT-WIRED guards before starting Slice 2 implementation
