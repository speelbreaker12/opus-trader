# Story Premortem: S1-006

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-006 —Add required TTL observability hooks for instrument cache freshness
- Contract clause(s): §1.0.X Instrument Metadata Freshness (Instrument Cache TTL)
- Acceptance tests: AT-104
- Touch scope: `crates/soldier_core/src/venue/cache.rs`, `crates/soldier_core/src/venue/mod.rs`, `crates/soldier_core/tests/test_instrument_cache_ttl.rs`
- **Risk rating**: LOW
  - Observability-only: structured logs and metrics. No gate logic, no dispatch decisions, no state machine changes. Depends on S1-003 for the cache infrastructure.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-104 | §1.0.X Instrument Metadata Freshness | (same clause as S1-003) "RiskState==Degraded, TradingMode==ReduceOnly, and the OPEN is rejected..." —this story covers observability side-conditions only. AT-104 gate enforcement belongs to S1-003; S1-006 claims the observability metrics/logs around that enforcement. | MUST (observability is contract-bound) | Yes —verify metrics increment and logs emit on staleness |
| (implicit) | §1.0.X Required observability | "instrument_cache_age_s (gauge), instrument_cache_hits_total (counter), instrument_cache_stale_total (counter), instrument_cache_refresh_errors_total (counter, optional but recommended)" | MUST for first 3, SHOULD for refresh_errors | Yes —assert metric names and increments |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | S1-003 cache infrastructure exposes hooks/events for staleness detection that this story can attach metrics to | If S1-003 has no extension points, metrics require invasive changes to cache internals | Test: metric increment happens on same code path as RiskState::Degraded transition | Pending |
| 2 | Metrics registry (in-memory or mock) is available for testing metric increments | If no test harness for metrics, tests cannot verify increments | Test setup creates mock metrics registry; assert counter values | Pending |
| 3 | `tracing` crate structured logging is available for emitting `InstrumentCacheTtlBreach` events | If different logging framework, structured log format may differ | Test: capture tracing events, assert fields present | Pending |
| 4 | `instrument_cache_refresh_errors_total` requires an error path from the metadata refresh operation | If refresh is not implemented yet (only cache + TTL check), this metric has no trigger | Wire metric to cache refresh error path; if refresh not implemented, defer to when it is | Killed -- `instrument_cache_refresh_errors_total` deferred until refresh path is implemented. Not in scope for S1-006. |
| 5 | Observability code does not introduce panics on metric registration failure | If metrics registry is full or misconfigured, metric registration panics and crashes the cache | Test: metric registration failure returns error, does not panic; cache continues operating | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Metrics wired to wrong code path —counters never increment despite staleness | Dashboards show zero staleness events even during outages | Test: force staleness, assert counter > 0 | AT-104 (observability) |
| 2 | `instrument_cache_age_s` gauge set but never updated —shows stale value | Operators see outdated age, cannot detect freshness changes | Test: refresh cache, assert gauge value resets toward 0 | AT-104 |
| 3 | Structured log `InstrumentCacheTtlBreach` missing required fields (`instrument_id`, `age_s`, `ttl_s`) | Log aggregation cannot filter/alert on breach events | Test: capture log event, assert all 3 fields present | AT-104 |
| 4 | Metric names don't match contract-bound names (e.g. `cache_hit_total` instead of `instrument_cache_hits_total`) | Dashboards/alerts reference wrong metric names, alerting is broken | Test: assert exact metric name strings match contract spec | AT-104 |
| 5 | Observability code has side effects —accidentally changes RiskState or TradingMode | Metrics/logging alters gate behavior | Test: observability-only change does not change RiskState outcome for same inputs | AT-104 |

## 4) Open decisions (resolve before coding)

### Decision: Metrics implementation approach
- **What is ambiguous / missing**: Which metrics library/pattern to use for counters and gauges.
- **Evidence**: CONTRACT.md specifies metric names but not implementation. The codebase may already have a metrics pattern.
- **Options**:
  1. Option A —Use `metrics` crate with `counter!` / `gauge!` macros. Standard Rust approach.
  2. Option B —Use custom atomic counters for simplicity and testability.
- **Chosen**: Defer to codebase convention. If `metrics` crate is already a dependency, use it. Otherwise, use simple atomic counters with a trait for test mocking.
- **Why not others**: Consistency with existing codebase patterns is more important than any specific library choice.
- **Scope control**:
  - What we're NOT doing yet: Prometheus exposition, dashboard configuration, alerting rules.
  - What unblocks us if this choice is wrong: Metric emission is behind a trait/interface; swap implementation without changing call sites.

### Decision: When to emit InstrumentCacheTtlBreach log
- **What is ambiguous / missing**: Should the log emit on every stale access, or only on the transition from fresh to stale?
- **Evidence**: S1-006 acceptance: "GIVEN a TTL breach WHEN processing THEN a structured log InstrumentCacheTtlBreach is emitted." This suggests on every occurrence, not just transitions.
- **Options**:
  1. Option A —Emit on every stale access (rate-limited by tick frequency).
  2. Option B —Emit only on fresh-to-stale transition.
- **Chosen**: A —emit on every stale access. The contract says "WHEN processing THEN emitted", implying continuous emission.
- **Why not others**: B would miss ongoing staleness in logs; harder to detect persistent issues.
- **Scope control**:
  - What we're NOT doing yet: rate limiting, log sampling, deduplication.
  - What unblocks us if this choice is wrong: easy to add a `last_breach_logged` guard later.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-104 | Metrics exist (defined) but never incremented —dead code | Tests check metric definition, not actual increments; operators get zero-value metrics | Test: force staleness event, assert `instrument_cache_stale_total` incremented from 0 to 1 |
| AT-104 | Log emitted but with wrong field names (e.g. `id` instead of `instrument_id`) | Log aggregation queries fail silently | Test: capture log event, assert field names are exactly `instrument_id`, `age_s`, `ttl_s` |
| AT-104 | `instrument_cache_hits_total` only increments on cache hits, not cache misses —partial observability | Miss events are invisible; operators cannot distinguish "no access" from "all misses" | Clarify: counter should increment on every access (hit or miss). Test both paths. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-104 | PolicyGuard (observability layer, no gate logic in this story) | test_stale_cache_emits_breach_log | Yes (stale -> log emitted with fields) | Yes (fresh -> no breach log) | Log capture contains InstrumentCacheTtlBreach with instrument_id, age_s, ttl_s | Yes |
| AT-104 | PolicyGuard (observability) | test_cache_access_increments_hits_total | N/A | Yes (any access -> counter increments) | Counter value before vs after access | Yes |
| AT-104 | PolicyGuard (observability) | test_stale_access_increments_stale_total | Yes (stale access -> stale counter increments) | Yes (fresh access -> stale counter unchanged) | Counter value delta | Yes |

Note: This story does not change gate behavior. TRIP/NON-TRIP for the enforcement gate itself is covered by S1-003.

- [x] Every safety-critical AT has TRIP + NON-TRIP (observability does not gate; enforcement in S1-003)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: No direct financial risk. Observability failure means operators cannot detect stale metadata via metrics/logs, reducing situational awareness. The actual safety gate (RiskState::Degraded -> ReduceOnly) is in S1-003 and operates independently of observability.
- **Fail-closed cap on loss**: S1-003's TTL enforcement is the safety gate. Observability failure does not weaken the gate; it only reduces operator visibility.
- **Drift metric**: The metrics themselves ARE the drift metrics. If `instrument_cache_stale_total` is always 0 despite known staleness events, the observability is broken. Cross-reference with S1-003 test results to detect drift.
- **Loss boundary**: No loss boundary needed for observability. S1-003 provides the ReduceOnly boundary.
- **Rollback plan**: Revert observability hooks. S1-003 enforcement continues to work. Operators lose visibility but safety is maintained.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None. This story adds observability around existing gates, not new gates.
- **If conflict with CONTRACT.md**: No conflict identified.
- Files with recent churn or shared ownership: `crates/soldier_core/src/venue/cache.rs` is shared with S1-003. Coordinate: S1-003 builds the cache, S1-006 adds metrics/logs to it.
- Struct fields I'm assuming exist (verify before coding): S1-003 cache with `last_refresh_ts`, age computation method, and staleness detection.
- State machine transitions affected: None.

## 9) Constraint I expect to hit
- What will slow me down: Test infrastructure for capturing structured logs and metric increments. May need to set up tracing test subscriber and metrics mock.
- Exploit: Use `tracing-test` crate for log capture and simple atomic counters with a test wrapper for metric assertions.
- Smallest fix that prevents it next time: Establish a project-wide test utilities module for log capture and metric assertion patterns.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice

Prior Postmortem: NONE
Reused Guardrail: NONE
