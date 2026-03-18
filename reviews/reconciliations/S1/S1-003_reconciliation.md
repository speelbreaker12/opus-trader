# S1-003 Reconciliation: Instrument Cache TTL

**Date**: 2026-02-23
**Auditor**: Claude Opus 4.6 (R1 Preflight)
**Mode**: READ-ONLY
**Story**: S1-003 — S1.1 Instrument cache TTL
**Enforcement Point**: PolicyGuard
**Enforcing ATs**: AT-104, AT-279
**STOPLIGHT**: YELLOW (2 debt items: PolicyGuard integration test deferred, per-instrument TTL deferred)

---

## READ-ONLY INTEGRITY CHECK (START)

```
git status --porcelain (snapshot at audit start)
```

Workspace had pre-existing modifications (unrelated to S1-003 scope files). No S1-003 scope files were modified:
- `crates/soldier_core/src/venue/cache.rs` — CLEAN (tracked, unmodified)
- `crates/soldier_core/src/venue/mod.rs` — CLEAN (tracked, unmodified)
- `crates/soldier_core/tests/test_instrument_cache_ttl.rs` — CLEAN (tracked, unmodified)

---

## A) GATE RESULT

**PASS WITH FINDINGS** — Story implementation is materially sound. Enforcement is real and tested. Two findings require attention (TEST_FIX priority).

---

## B) AT AUDIT TABLE

| AT ID | Contract Section | Enforcement Point (file:line::function) | Proving Test(s) | Causal Proof? | Fail-Closed? | Section 5 Wrong Impls Blocked? | Section 4 Decision As Chosen? | Verdict |
|-------|-----------------|----------------------------------------|-----------------|--------------|-------------|-------------------------------|------------------------------|---------|
| AT-104 | Section 1.0.X Instrument Metadata Freshness (line ~703 of CONTRACT.md) | `crates/soldier_core/src/venue/cache.rs:167::get_at` (staleness detection) + `crates/soldier_core/src/venue/cache.rs:282::opens_blocked` (OPEN gating) + `crates/soldier_core/src/execution/build_order_intent.rs:283::chokepoint_evaluate` (production dispatch) | `test_stale_cache_blocks_opens` (cache layer), `test_at104_degraded_blocks_open_at_chokepoint` (pipeline layer with dispatch_count=0 for OPEN, dispatch_count=1 for CLOSE/HEDGE/CANCEL) | **PROVEN** — dispatch_count causality via `approved_total()==0` for OPEN, `approved_total()==1` for CLOSE/HEDGE/CANCEL, plus reject reason `RiskStateNotHealthy` | YES (5/6 categories) | 4/5 blocked (see Section C) | YES | **PASS** |
| AT-279 | Appendix A `instrument_cache_ttl_s` (line ~5151 of CONTRACT.md) | `crates/soldier_core/src/venue/cache.rs:167::get_at` (age > ttl comparison) + `crates/soldier_infra/src/config.rs:160::appendix_a_default` (default=3600.0) | `test_default_instrument_cache_ttl_is_3600` (boundary at 3600s), `test_different_ttl_config_respected` (custom TTL=60s proves not hardcoded), `test_missing_instrument_cache_ttl_s_applies_default_3600` (infra layer) | **PROVEN** — boundary behavior at exact TTL (Healthy) and TTL+1 (Degraded), plus non-default TTL proves configurability | YES (5/6 categories) | 5/5 blocked (see Section C) | YES | **PASS** |

### Enforcement Chain Detail

**AT-104 full chain**:
1. `InstrumentCache::get_at()` at `cache.rs:167` — computes `cache_age_s > ttl_s`, returns `RiskState::Degraded`
2. `opens_blocked()` at `cache.rs:282` — maps `Degraded|Maintenance|Kill` to `true` (OPEN blocked)
3. `chokepoint_evaluate()` at `build_order_intent.rs:283` — `if intent_class == Open && opens_blocked(risk_state)` rejects with `RiskStateNotHealthy`
4. `reject_reason_from_chokepoint()` at `reject_reason.rs:155` — maps `RiskStateNotHealthy` to `MarginHeadroomRejectOpens`

**AT-279 full chain**:
1. `appendix_a_default(InstrumentCacheTtlS)` at `config.rs:160` — returns `Some(3600.0)`
2. `resolve_config_value()` at `config.rs:471` — uses default when `None`, rejects NaN/negative/Inf
3. `InstrumentCache::get_at()` at `cache.rs:167` — applies the TTL for staleness comparison

---

## C) PREMORTEM CROSS-REFERENCE

### Section 2 Assumptions

| # | Assumption | Status | Proving Test | Notes |
|---|-----------|--------|-------------|-------|
| 1 | Cache age computed from `last_refresh_timestamp`, not `first_insert_timestamp` | **PROVEN** | `test_cache_refresh_resets_staleness` (line 299 of test file) — inserts, goes stale, re-inserts, verifies freshness reset | Re-insert at stale_time resets `inserted_at`; age drops to 0 |
| 2 | TTL comparison is strict greater-than (`>`) | **PROVEN** | `test_cache_age_at_exact_ttl_is_healthy` (line 56) + `test_cache_age_one_second_past_ttl_is_degraded` (line 75) | Boundary: `age==ttl` -> Healthy, `age==ttl+1` -> Degraded. Implementation at `cache.rs:167`: `cache_age_s > ttl_s` |
| 3 | Clock source is monotonic (via `Instant`) | **PARTIALLY PROVEN** | `test_cache_age_deterministic` (line 216) proves same inputs give same outputs. Clock injection via `_at` methods proves determinism. | Production uses `Instant::now()` which is monotonic. `saturating_duration_since` at `cache.rs:156` handles anomalous clocks gracefully (saturates to 0 -> fresh, which is fail-safe for the clock-backwards edge case). Not a gap because `Instant` guarantees monotonicity. |
| 4 | RiskState::Degraded feeds into PolicyGuard to produce ReduceOnly | **PROVEN** | `test_at104_degraded_blocks_open_at_chokepoint` (test_intent_pipeline.rs:211) — Degraded -> OPEN rejected at pipeline level with `approved_total()==0` | Full pipeline proof, not just cache layer |
| 5 | CLOSE/HEDGE/CANCEL remain dispatchable when stale | **PROVEN** | `test_at104_degraded_blocks_open_at_chokepoint` Parts 2-4 (lines 231-282) — CLOSE=approved(1), HEDGE=approved(1), CancelOnly=approved(1) | All three non-OPEN intent classes verified |
| 6 | Default TTL is 3600 seconds | **PROVEN** | `test_default_instrument_cache_ttl_is_3600` (line 471) + `test_missing_instrument_cache_ttl_s_applies_default_3600` (soldier_infra) + `test_appendix_a_defaults_match_contract` | Verified at both cache layer and config resolution layer |

### Section 4 Decisions

| Decision | Chosen Option | Implemented As Chosen? | Evidence |
|----------|--------------|----------------------|----------|
| Cache age computation source | Option A: single `last_refresh_ts` via `inserted_at` per entry | **YES** | `cache.rs:54-57` — `CacheEntry { instrument_kind, inserted_at: Instant }`. Re-insert overwrites `inserted_at`. `test_cache_refresh_resets_staleness` proves reset behavior. |
| Where to enforce OPEN blocking | Option A: layered (cache signals Degraded, PolicyGuard enforces ReduceOnly) | **YES** | Cache returns `RiskState::Degraded` at `cache.rs:184`. `opens_blocked()` at `cache.rs:282` is the bridge. `build_order_intent.rs:283` is the production chokepoint. No direct dispatch blocking in cache. |
| Clock source for deterministic testing | Option A: injectable clock via `_at` suffix methods | **YES** | `insert_at()` at `cache.rs:115`, `get_at()` at `cache.rs:140`, `risk_state_for_at()` at `cache.rs:206`. All tests use `_at` variants with explicit `Instant` values. |

### Section 5 Wrong Implementations Blocked

| AT | Wrong Impl | Tightening Test | Blocked? |
|----|-----------|----------------|----------|
| AT-104 | Cache returns Degraded but OPEN not actually blocked (test only checks RiskState) | `test_at104_degraded_blocks_open_at_chokepoint` — asserts `approved_total()==0` for OPEN (pipeline level, not just cache level) | **YES** |
| AT-104 | OPEN blocked but CLOSE also blocked (over-restrictive) | `test_at104_degraded_blocks_open_at_chokepoint` Parts 2-4 — CLOSE/HEDGE/CANCEL each have `approved_total()==1` | **YES** |
| AT-104 | Always returns Degraded regardless of cache age (pessimistic) | `test_fresh_instrument_cache_returns_healthy` + `test_fresh_cache_allows_opens` + `test_risk_state_for_fresh_returns_healthy` | **YES** |
| AT-279 | TTL hardcoded to 3600s, ignoring configuration | `test_different_ttl_config_respected` — uses custom TTL=60s, asserts staleness at 61s (not 3601s) + `test_breach_event_ttl_reflects_custom_config` — uses TTL=120s | **YES** |
| AT-279 | Cache age never increases (always returns 0, appears always fresh) | `test_stale_instrument_cache_sets_degraded` — injected clock at t0+7200s, asserts `cache_age_s ~= 7200.0` AND `RiskState::Degraded` + `test_cache_age_one_second_past_ttl_is_degraded` | **YES** |

---

## D) DESIGN RISK NOTES

### D1: Stale TODO comment (INFO)

`cache.rs:273` contains: `// TODO(slice-N): Wire into production dispatch — currently only called from unit tests`

This comment is **stale**. The `opens_blocked()` function defined immediately below (line 282) IS imported and called from production code at `build_order_intent.rs:22,283`. The TODO should be removed or reworded.

### D2: Negative TTL not explicitly tested (TEST_FIX — LOW)

The cache's `get_at()` function handles `NaN` and `Infinity` TTL values via the `ttl_invalid = !ttl_s.is_finite()` check at `cache.rs:166`. However, a **negative TTL** (e.g., `-100.0`) is finite and would pass the `is_finite()` check. In practice, `cache_age_s > -100.0` is always true (since `saturating_duration_since` returns non-negative durations), so the behavior is **accidentally fail-closed** (always Degraded for negative TTL). This is correct behavior but there is no test documenting it.

Mitigating factor: `resolve_config_value()` at `config.rs:482-486` rejects negative values at the config resolution layer (`v < 0.0` returns error). So a negative TTL cannot reach the cache through the canonical config path. The gap is only exploitable via direct API misuse.

### D3: `opens_blocked` lives in cache module (DESIGN — INFO)

The `opens_blocked()` function at `cache.rs:282` is a pure function on `RiskState`. It is logically part of the dispatch authorization layer, not the cache layer. Its placement in `cache.rs` is an artifact of S1-003 scope constraints (`scope.avoid` includes `crates/soldier_core/src/execution/**`). The function is correctly re-exported via `venue/mod.rs:9` and consumed at `build_order_intent.rs:22`.

### D4: `unwrap()` usage

Production code in `cache.rs` contains **zero** `unwrap()` calls. Two `unwrap()` calls exist at lines 308 and 329, both inside `#[cfg(test)] mod tests` blocks — acceptable.

### D5: Observability completeness

- `instrument_cache_age_s` gauge: updated at `cache.rs:160` on every `get_at()` call. Accessible via `last_age_s()`.
- `instrument_cache_hits_total` counter: incremented at `cache.rs:149`. Accessible via `hits_total()`.
- `instrument_cache_stale_total` counter: incremented at `cache.rs:168`. Accessible via `stale_total()`.
- `instrument_cache_refresh_errors_total` counter: incremented via `record_refresh_error()` at `cache.rs:239`.
- `instrument_cache_lookups_total` counter: incremented at `cache.rs:146`. Accessible via `lookups_total()`.
- `CacheTtlBreach` structured event: emitted via `tracing::warn!` at `cache.rs:178-183` AND buffered in `pending_breaches` VecDeque.
- Breach queue cap: `MAX_PENDING_BREACH_EVENTS = 1024` at `cache.rs:21`, enforced at `cache.rs:169-171`.

All observability hooks are tested:
- `test_cache_hits_counter_increments` (line 195)
- `test_stale_total_counter_increments` (line 328)
- `test_ttl_breach_event_emitted_on_stale` (line 352)
- `test_refresh_errors_counter` (line 413)
- `test_last_age_s_gauge_updates` (line 427)
- `test_pending_breaches_queue_is_capped` (line 396)
- `test_ttl_breach_emits_structured_log` (cache.rs:299, in-module test)

### D6: Fail-closed coverage (6-category checklist)

| Category | Handled? | Evidence |
|----------|---------|----------|
| Missing/None (cache miss) | **YES** | `risk_state_for_at()` at `cache.rs:214` returns `Degraded` on `None`. Test: `test_risk_state_for_cache_miss_returns_degraded` (line 237). |
| NaN | **YES** | `cache.rs:166`: `ttl_invalid = !ttl_s.is_finite()` catches NaN. Test: `test_nan_ttl_fails_closed_to_degraded` (line 89). |
| Inf | **YES** | Same `is_finite()` check catches both `INFINITY` and `NEG_INFINITY`. Test: `test_infinite_ttl_fails_closed_to_degraded` (line 101). |
| Negative | **IMPLICIT** | Negative TTL is finite, but `cache_age_s >= 0.0` (from `saturating_duration_since`), so `age > negative_ttl` is always true -> Degraded. Config layer also rejects negatives. **No explicit test.** |
| Out-of-domain | **YES** | Non-existent instrument returns `None` from `get_at()`, handled by `risk_state_for_at()` as `Degraded`. Test: `test_missing_instrument_returns_none` (line 119) + `test_risk_state_for_cache_miss_returns_degraded` (line 237). |
| Corrupt / Narrowing casts | **N/A** | Cache stores `InstrumentKind` (an enum) and `Instant` (opaque type). No narrowing casts in production code. `cache_age_s` is `f64` from `as_secs_f64()` — lossless for practical durations. |

**Score: 5/6 explicit + 1 implicit (negative TTL).**

---

## E) REMEDIATION PLAN

| Priority | Type | Finding | Recommendation | Severity |
|----------|------|---------|----------------|----------|
| 1 | TEST_FIX | Negative TTL not explicitly tested | Add `test_negative_ttl_fails_closed_to_degraded`: verify `cache.get_at("X", -100.0, now)` returns `Degraded`. This documents the implicit behavior and prevents regressions. | LOW |
| 2 | INFO | Stale TODO at `cache.rs:273` | Remove or update the TODO comment. `opens_blocked()` is already wired to production dispatch at `build_order_intent.rs:283`. | LOW |
| 3 | DEFERRED | `test_instrument_cache_ttl_s_expires_after_3600s` test name binding in CONTRACT.md (line 4975) references a test that does not exist by that exact name | The test `test_default_instrument_cache_ttl_is_3600` (line 471) covers the same behavior. CONTRACT.md's Appendix A binding names a non-existent test function. Either rename the test or update CONTRACT.md. Since CONTRACT.md is out of S1-003 scope, DEFERRED. | LOW |
| 4 | DEFERRED | Full PolicyGuard integration test (from premortem debt register) | Deferred to Slice 2+ per premortem. The pipeline-level test (`test_at104_degraded_blocks_open_at_chokepoint`) provides sufficient proof at the chokepoint layer. | MEDIUM |
| 5 | DEFERRED | Per-instrument TTL tracking (from premortem debt register) | CONTRACT.md does not require per-instrument TTL. Batch refresh makes this unnecessary. | LOW |

---

## F) SCOPE CHECK

| Scope File | In `scope.touch`? | Modified by S1-003? | Content Matches Story? |
|-----------|-------------------|---------------------|----------------------|
| `crates/soldier_core/src/venue/cache.rs` | YES | YES | YES — contains `InstrumentCache`, `CacheLookupResult`, `CacheTtlBreach`, `opens_blocked`, TTL enforcement logic |
| `crates/soldier_core/src/venue/mod.rs` | YES | YES | YES — re-exports all cache public API including `opens_blocked` |
| `crates/soldier_core/tests/test_instrument_cache_ttl.rs` | YES | YES | YES — 25+ tests covering fresh/stale, boundary, NaN/Inf, missing, observability, wrong-impl tightening |
| `crates/soldier_core/tests/test_intent_pipeline.rs` | NOT in scope.touch | Contains AT-104 companion test | Scope touch could be expanded, but test was likely added by a later story or as a companion. The test is critical for AT-104 causality proof. |
| `crates/soldier_core/src/execution/build_order_intent.rs` | In `scope.avoid` | Contains production `opens_blocked` callsite | `opens_blocked` is imported and called. The function definition is in-scope (`cache.rs`), the callsite is out-of-scope but pre-existing. |

### Out-of-scope dependencies verified:
- `soldier_infra::config::appendix_a_default(InstrumentCacheTtlS)` returns `3600.0` — tested in `test_config_defaults.rs:18` and `test_config_init.rs:72`
- `resolve_config_value()` rejects NaN, Inf, and negative values — `config.rs:476-486`
- `RiskState` enum at `risk/state.rs:13` has `Healthy|Degraded|Maintenance|Kill` — matches `opens_blocked()` match arms

---

## READ-ONLY INTEGRITY CHECK (END)

This audit wrote only one file: `reviews/reconciliations/S1/S1-003_reconciliation.md`. No production code or test files were modified. No `wf_step.sh` or `prd_set_pass.sh` commands were executed.

---

**READY FOR SELF_REVIEW**
