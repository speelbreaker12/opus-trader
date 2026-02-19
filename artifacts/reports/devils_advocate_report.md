# Devil's Advocate Mutation Testing Report

**Date**: 2026-02-18
**Branch**: `feature/slice4-cherry-pick`
**Suite**: 804 tests (657 soldier_core + 147 soldier_infra), all passing

---

## Executive Summary

Systematic mutation testing across **21 components + 6 fail-closed categories**, attempting **~143 mutations**. Found and closed **27 gaps** by writing **27 tightening tests**. Every gap represented a mutation (wrong implementation simpler than correct) that would have passed the existing suite undetected.

## Campaign Results

| Round | Targets | Mutations | Gaps | Tests Written |
|-------|---------|-----------|------|---------------|
| 1 | 5 gates | 24 | 10 | 9 |
| 2 | 5 gates | 34 | 7 | 7 |
| 3 | 4 gates | 25 | 3 | 3 |
| 4 | 2 state machines | ~20 | 4 | 5 |
| 5+6 | 5 gates + 6 categories | 40 | 3 | 3 |
| **Total** | **27 targets** | **~143** | **27** | **27** |

---

## Round 1: High-Risk Gates (5 gates, 9 tests)

### MarginGate — 3 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_margin_gate.rs` | `test_margin_at_exact_limit_allowed` | `>` vs `>=` on margin check |
| `test_margin_gate.rs` | `test_margin_one_cent_over_rejected` | Boundary: limit+0.01 must reject |
| `test_margin_gate.rs` | `test_margin_nan_input_fails_closed` | NaN margin → must reject, not allow |

### InstrumentCache — 1 test written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_instrument_cache_ttl.rs` | `test_different_ttl_config_respected` | Hardcoded TTL=300 passes all default-config tests |

### DispatchConsistency — 4 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_gate_ordering.rs` | `test_dispatch_consistency_clamp_epsilon_boundary` | Epsilon boundary off-by-one |
| `test_gate_ordering.rs` | `test_dispatch_consistency_clamp_lower_boundary` | Lower clamp exact boundary |
| `test_gate_ordering.rs` | `test_dispatch_consistency_clamp_upper_boundary` | Upper clamp exact boundary |
| `test_gate_ordering.rs` | `test_dispatch_consistency_clamp_above_upper` | Values above upper clamp |

### Pricer — 1 test written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_pricer.rs` | `test_pricer_at_exact_min_edge_boundary` | `<` vs `<=` on min_edge check |

### DispatchAuth — CLEAN (0 gaps)

---

## Round 2: Medium-Risk Gates (5 gates, 7 tests)

### PendingExposure — 1 test written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_pending_exposure.rs` | `test_pending_exposure_at_exact_budget_allowed` | `>` vs `>=` on budget check |

### GlobalExposureBudget — 3 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_exposure_budget.rs` | `test_exposure_budget_at_exact_limit` | `>` vs `>=` boundary |
| `test_exposure_budget.rs` | `test_exposure_budget_correlation_multiplier` | Hardcoded multiplier=1.0 |
| `test_exposure_budget.rs` | `test_exposure_budget_nan_limit_fails_closed` | NaN budget limit → must reject |

### InventorySkew — 3 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_inventory_skew.rs` | `test_skew_at_exact_limit_allowed` | `>` vs `>=` on skew threshold |
| `test_inventory_skew.rs` | `test_skew_pending_delta_contributes` | Ignoring pending_delta field |
| `test_inventory_skew.rs` | `test_skew_nan_inputs_fail_closed` | NaN inventory → must reject |

### NetEdge — CLEAN (0 gaps)
### RecordedBeforeDispatch — CLEAN (0 gaps)

---

## Round 3: Remaining Gates (4 gates, 3 tests)

### LiquidityGate — 2 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_liquidity_gate.rs` | `test_slippage_at_exact_max_allowed` | `>` vs `>=` on slippage check (line 651) |
| `test_liquidity_gate.rs` | `test_staleness_at_exact_max_age_allowed` | `>` vs `>=` on staleness check (line 498) |

### FeeCacheCheck — 1 test written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_fee_staleness.rs` | `test_custom_config_thresholds_respected` | Hardcoded soft=300/hard=900 passes all default-config tests |

### WAL Ledger — CLEAN (0 gaps, 117+ tests)
### GroupLock — CLEAN (0 gaps)

---

## Round 4: State Machines (2 machines, 5 tests)

### TLSM (Trade Lifecycle State Machine) — 3 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_tlsm.rs` | `test_failed_from_created_transitions` | Restrict `(_, Failed)` wildcard to only `(Acked, Failed)` |
| `test_tlsm.rs` | `test_failed_from_partially_filled_transitions` | Same — `(PartiallyFilled, Failed)` untested |
| `test_tlsm.rs` | `test_take_pending_reservation_only_on_terminal` | Remove `is_terminal()` guard → early settlement |

### GroupState FSM — 2 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_atomic_group.rs` | `failure_leg_during_flattening_does_not_reenter_mixed_failed` | Remove Flattening guard from failure re-entry |
| `test_atomic_group.rs` | `failure_leg_during_flattened_does_not_reenter_mixed_failed` | Remove Flattened guard from failure re-entry |

### Skipped (not implemented or trivial):
- TradingMode FSM — not implemented (future slice)
- RiskState FSM — simple 4-value enum, no transition logic
- PolicyGuard latch — not implemented as standalone

---

## Round 5+6: Remaining Gates + Fail-Closed Categories (5 gates + 6 categories, 3 tests)

### Preflight Gate — 1 test written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_preflight.rs` | `test_linked_order_inverse_future_both_flags_allowed` | `InverseFuture => false` (only Option/Perpetual/LinearFuture were tested) |

### ExpiryGuard — 2 tests written
| File | Test | Mutation Killed |
|------|------|-----------------|
| `test_expiry_guard.rs` | `test_no_expiration_timestamp_allows_open` | `None` expiration → Rejected instead of Allowed (perpetuals) |
| `test_expiry_guard.rs` | `test_expiry_at_exact_boundary_rejects_open` | `>=` vs `>` on `now_ms >= opens_blocked_from_ms` |

### Quantize Gate — CLEAN (0 gaps, 40+ tests + property tests)
### PostOnly Guard — CLEAN (0 gaps, boundary tests at crossing point)
### Capabilities Gate — CLEAN (0 gaps, exhaustive 4-combination table test)

### 6 Fail-Closed Categories — CLEAN (0 cross-cutting gaps)
1. **Missing/Unparseable Config** — covered via `test_missing_config.rs` + individual gate suites
2. **NaN/Inf Propagation** — covered across Quantize, FeeStaleness, InventorySkew, Margin
3. **Boundary/Limit Conditions** — all `>` vs `>=` boundaries now tested at exact thresholds
4. **Retry/Dedup Idempotency** — WAL Ledger (117+ tests) + PendingExposure
5. **Missing/Stale Data Input** — LiquidityGate (None L2), InstrumentCache, FeeStaleness
6. **Risk State Escalation** — `test_unhealthy_risk_state_fails_closed` tests all 3 non-Healthy states

---

## Components Verified Clean (no gaps found)

| Component | Why Clean |
|-----------|-----------|
| DispatchAuth | Intent class filtering exhaustively tested |
| NetEdge | All Option fields tested as None; NaN covered |
| RecordedBeforeDispatch | WAL-before-dispatch invariant well-tested |
| WAL Ledger | 117+ tests, duplicate/capacity/state-transition comprehensive |
| GroupLock | Both held+expired and held+not-expired paths return TimedOut |
| Quantize Gate | 40+ unit tests + 7 property tests via proptest |
| PostOnly Guard | Boundary tests at exact crossing price (==) for both sides |
| Capabilities Gate | Exhaustive 4-combination truth table |

---

## Mutation Taxonomy

| Category | Count | % of Total |
|----------|-------|------------|
| Boundary flip (`>` vs `>=`, `<` vs `<=`) | 10 | 37% |
| Config hardcoding (default values pass all tests) | 3 | 11% |
| NaN/Inf fail-open (non-finite accepted silently) | 3 | 11% |
| Missing field ignored (None/0 treated as valid) | 3 | 11% |
| State guard removal (transition guard deleted) | 3 | 11% |
| Wildcard restriction (broad match narrowed) | 2 | 7% |
| Path elimination (code branch removed entirely) | 2 | 7% |
| Settlement timing (terminal guard removed) | 1 | 4% |

---

## Files Modified

| File | Tests Added |
|------|-------------|
| `crates/soldier_core/tests/test_margin_gate.rs` | 3 |
| `crates/soldier_core/tests/test_instrument_cache_ttl.rs` | 1 |
| `crates/soldier_core/tests/test_gate_ordering.rs` | 4 |
| `crates/soldier_core/tests/test_pricer.rs` | 1 |
| `crates/soldier_core/tests/test_pending_exposure.rs` | 1 |
| `crates/soldier_core/tests/test_exposure_budget.rs` | 3 |
| `crates/soldier_core/tests/test_inventory_skew.rs` | 3 |
| `crates/soldier_core/tests/test_liquidity_gate.rs` | 2 |
| `crates/soldier_core/tests/test_fee_staleness.rs` | 1 |
| `crates/soldier_core/tests/test_tlsm.rs` | 3 |
| `crates/soldier_core/tests/test_atomic_group.rs` | 2 |
| `crates/soldier_core/tests/test_preflight.rs` | 1 |
| `crates/soldier_core/tests/test_expiry_guard.rs` | 2 |
| **Total** | **27** |

---

## Verdict

**GREEN** — All 27 mutation gaps closed. No surviving mutations simpler than the correct implementation across all 21 components and 6 fail-closed categories. Suite stands at 804 tests with 0 failures.
