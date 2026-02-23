---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INSTRUMENT_reconciliation.md
story_id: S1-003
story_title: "InstrumentCache TTL and RiskState degradation"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (PROVEN, GAP-003-1 P2 + deferred items)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-003 (InstrumentCache TTL and RiskState degradation)

## §10 STOPLIGHT: YELLOW
- Debt: PolicyGuard integration deferred to Slice 2; per-instrument TTL deferred to Slice 3+.

## A) GATE RESULT
```
GATE: GO
Reason: YELLOW STOPLIGHT — all deferred items have owner + target.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-104 | §1.0.X Instrument Metadata Freshness | `crates/soldier_core/src/venue/cache.rs:162::get_at` (TTL comparison) + `cache.rs:265::opens_blocked` | `test_stale_cache_blocks_opens` (line 123), `test_fresh_cache_allows_opens` (line 142), `test_opens_blocked_all_risk_states` (line 173), `test_opens_blocked_is_sole_gate_closes_ungated` (line 161) | Yes — `opens_blocked(RiskState::Degraded)` asserted true/false | Yes — NaN TTL fails closed (line 83), Inf (line 95), cache miss → Degraded (line 203) | Yes (see §5 table) | Yes (see §4 table) | **PROVEN** |
| AT-279 | Appendix A, `instrument_cache_ttl_s` | `crates/soldier_core/src/venue/cache.rs:162::get_at` | `test_cache_age_at_exact_ttl_is_healthy` (line 50), `test_cache_age_one_second_past_ttl_is_degraded` (line 69), `test_different_ttl_config_respected` (line 458) | Yes — boundary tests | Yes | Yes (see §5 table) | Yes | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Cache age = `now - last_refresh_timestamp` | Refresh resets age | VALIDATED — `test_cache_refresh_resets_staleness` (line 293) |
| 2 | TTL comparison is strict `>` | Boundary test | VALIDATED — `test_cache_age_at_exact_ttl_is_healthy` (line 50) |
| 3 | Clock source is monotonic | Injected clock | VALIDATED — `Instant` used, `_at` methods |
| 4 | RiskState::Degraded → ReduceOnly | Integration test | PARTIALLY — `opens_blocked(Degraded)` true; PolicyGuard integration DEFERRED |
| 5 | CLOSE/HEDGE/CANCEL remain dispatchable | Stale + CLOSE allowed | VALIDATED — `test_opens_blocked_is_sole_gate_closes_ungated` (line 161) |
| 6 | Default TTL is 3600 seconds | Assert default | PARTIALLY — tests use 3600.0 but no explicit default constant assertion |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Cache age source | A — single `last_refresh_ts` | **DECISION_DIVERGENCE (INFO)** — per-entry `inserted_at`. Better design. | cache.rs:56 |
| OPEN blocking | A — layered: cache signals, PolicyGuard enforces | Yes | cache.rs:162-176, cache.rs:265 |
| Clock for testing | A — injectable | Yes | cache.rs:136::get_at takes `now: Instant` |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Degraded but OPEN not blocked | Yes | `test_stale_cache_blocks_opens` (line 123) | Yes |
| OPEN blocked but CLOSE also blocked | Yes | `test_opens_blocked_is_sole_gate_closes_ungated` (line 161) | Yes |
| Always returns Degraded | Yes | `test_fresh_cache_allows_opens` (line 142) | Yes — NON-TRIP |
| TTL hardcoded to 3600s | Yes | `test_different_ttl_config_respected` (line 458) | Yes — custom TTL 60s |
| Cache age never increases | Yes | `test_stale_instrument_cache_sets_degraded` (line 34) | Yes |

## D) DESIGN RISK NOTES

1. Per-entry vs cache-wide freshness — DECISION_DIVERGENCE (INFO, improvement).
2. No TOCTOU risk — `CacheLookupResult` is atomic.
3. Cache miss → Degraded — correct fail-closed.
4. NaN/Inf TTL — caught and treated as stale. Excellent.

## E) REMEDIATION PLAN

```
[TEST_FIX]  GAP-003-1: Add explicit default TTL == 3600 assertion. (P2)
[DEFERRED]  GAP-003-2: PolicyGuard integration test. (Slice 2)
[DEFERRED]  GAP-003-3: Per-instrument TTL. (Slice 3+)
[INFO]      DECISION_DIVERGENCE: per-entry inserted_at. Better design.
```

## F) SCOPE CHECK

All scope.touch files exist and are touched. No scope drift.

```
READY FOR SELF_REVIEW
```
