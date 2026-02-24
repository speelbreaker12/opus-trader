---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INSTRUMENT_reconciliation.md
story_id: S1-006
story_title: "InstrumentCache TTL observability hooks"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (PROVEN, GAP-006-1 P2)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-006 (InstrumentCache TTL observability hooks)

## §10 STOPLIGHT: GREEN

## A) GATE RESULT
```
GATE: GO
Reason: GREEN STOPLIGHT. Observability hooks implemented and tested.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-104 (observability) | §1.0.X Instrument Metadata Freshness | `cache.rs:143::get_at` (hits_total), `cache.rs:163` (stale_total), `cache.rs:168` (breach event), `cache.rs:155` (last_age_s gauge) | `test_cache_hits_counter_increments` (line 189), `test_stale_total_counter_increments` (line 322), `test_ttl_breach_event_emitted_on_stale` (line 346), `test_last_age_s_gauge_updates` (line 421) | Yes — counter values asserted before/after | N/A (observability) | Partial (see §5) | Yes | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | S1-003 cache exposes hooks | Metric increment on same path as Degraded | VALIDATED |
| 2 | Metrics registry for testing | Mock metrics | VALIDATED — simple u64 counters |
| 3 | `tracing` available for structured logging | Capture events | NOT DIRECTLY TESTED — drain pattern, struct exists but no tracing::warn! capture test |
| 4 | `refresh_errors_total` requires error path | Wire to refresh error | KILLED — deferred. `record_refresh_error()` exists (line 227) and tested (line 407) |
| 5 | Observability code doesn't panic on registration failure | Error return | VALIDATED — no external registration |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Metrics implementation | Simple atomic counters | Yes | cache.rs:70-77 |
| When to emit breach log | A — every stale access | Yes | cache.rs:164-172 |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Metrics defined but never incremented | Yes | `test_stale_total_counter_increments` (line 322) | Yes |
| Wrong field names in log | Yes | `test_ttl_breach_event_emitted_on_stale` (line 346) | Yes |
| hits_total counts misses too | Yes | `test_cache_hits_counter_increments` (line 189, 204) | Yes — miss excluded |

## D) DESIGN RISK NOTES

1. No tracing log emission test — drain pattern, caller responsibility.
2. Breach queue capped at 1024 (tested, line 390). Good.
3. `refresh_errors_total` uncalled — deferred until refresh path.

## E) REMEDIATION PLAN

```
[TEST_FIX]  GAP-006-1: Add tracing emission test for CacheTtlBreach. (P2)
[INFO]      hits_total counts hits only. Correct semantics.
[INFO]      Breach queue bounded. FIFO eviction tested.
```

## F) SCOPE CHECK

All scope.touch files exist. No scope drift.

```
READY FOR SELF_REVIEW
```
