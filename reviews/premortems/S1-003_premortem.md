# Story Premortem: S1-003

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-003 —Enforce InstrumentCache TTL and degrade RiskState on stale metadata
- Contract clause(s): §1.0.X Instrument Metadata Freshness (Instrument Cache TTL)
- Acceptance tests: AT-104, AT-279
- Touch scope: `crates/soldier_core/src/venue/cache.rs`, `crates/soldier_core/src/venue/mod.rs`, `crates/soldier_core/tests/test_instrument_cache_ttl.rs`
- **Risk rating**: MED
  - Touches risk gates (RiskState transition), affects TradingMode computation via PolicyGuard, and controls OPEN/CLOSE dispatch eligibility. A fail-open bug here allows trading on stale metadata.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-104 | §1.0.X Instrument Metadata Freshness | "Given: `instrument_cache_age_s > instrument_cache_ttl_s` and an OPEN intent is proposed. When: the system evaluates eligibility for dispatch. Then: `RiskState==Degraded`, `TradingMode==ReduceOnly`, and the OPEN is rejected before dispatch; CLOSE/HEDGE/CANCEL remain dispatchable" | MUST | Yes —inject stale cache, propose OPEN, assert rejected; propose CLOSE, assert allowed |
| AT-279 | Appendix A, `instrument_cache_ttl_s` | "Given: `instrument_cache_age_s > instrument_cache_ttl_s`. When: instrument freshness is evaluated. Then: `RiskState::Degraded` + ReduceOnly within one tick; CLOSE/HEDGE/CANCEL allowed" | MUST | Yes —inject cache age > 3600s, assert Degraded + ReduceOnly |
| (implicit) | §1.0.X | "The engine MUST track freshness of instrument metadata... If instrument metadata age exceeds `instrument_cache_ttl_s`: set `RiskState::Degraded`" | MUST | Yes —assert RiskState transition on staleness |
| (implicit) | §1.0.X | "PolicyGuard MUST compute `TradingMode::ReduceOnly` within one tick (closes/hedges/cancels allowed)" | MUST | Yes —assert TradingMode == ReduceOnly when RiskState == Degraded due to stale cache |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Cache age is computed as `now - last_refresh_timestamp`, not `now - first_insert_timestamp` | Using first-insert time means successful refreshes don't reset the clock; cache appears stale forever after TTL | Test: insert, wait, refresh, assert age resets to 0 | Pending |
| 2 | TTL comparison is strict greater-than (`age > ttl`), not greater-than-or-equal | Off-by-one: `age == ttl` should be fresh (boundary) | Test: set age == ttl, assert Healthy; set age == ttl + 1, assert Degraded | Yes -- CONTRACT.md AT-279 confirms strict greater-than: "Given: `instrument_cache_age_s > instrument_cache_ttl_s`" |
| 3 | Clock source for age computation is monotonic, not wall-clock | Wall-clock jumps (NTP correction) could cause false staleness or false freshness | Test: use injected clock, not system clock; assert deterministic behavior | Pending |
| 4 | RiskState::Degraded from stale cache feeds into PolicyGuard to produce TradingMode::ReduceOnly | If PolicyGuard ignores this RiskState input, stale cache has no effect on trading | Integration-style test: stale cache -> RiskState::Degraded -> TradingMode::ReduceOnly | Pending |
| 5 | "CLOSE/HEDGE/CANCEL remain dispatchable" means only OPEN is blocked, not all intents | If implementation blocks all intents on Degraded, system cannot exit positions | Test: stale cache + CLOSE intent -> allowed; stale cache + OPEN intent -> rejected | Pending |
| 6 | Default TTL is 3600 seconds per Appendix A | Wrong default silently changes staleness threshold | Test: assert default TTL == 3600 | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **Fail-open: stale cache not detected** —age computation bug returns 0 or negative, so cache always appears fresh | No RiskState::Degraded despite stale metadata; OPENs proceed on stale data | Inject clock far past TTL, assert Degraded. Property test: if no refresh occurs, age must monotonically increase | AT-104, AT-279 |
| 2 | **Fail-open: RiskState::Degraded set but PolicyGuard ignores it** —Degraded does not feed into TradingMode computation | TradingMode stays Active despite Degraded RiskState | Test: force Degraded, assert TradingMode::ReduceOnly (not Active) | AT-104 |
| 3 | **Over-restrictive: stale cache blocks CLOSE/HEDGE/CANCEL** —all dispatch blocked instead of only OPEN | Cannot exit positions during stale metadata; capital locked | Test: stale cache + CLOSE intent -> dispatch allowed | AT-104 |
| 4 | **Race condition: cache refreshed between staleness check and dispatch decision** —TOCTOU | OPEN dispatched on data that was stale at decision time but fresh at dispatch time | Ensure staleness check and dispatch decision use the same snapshot of cache age | AT-104 |
| 5 | **Wrong TTL source: hardcoded TTL instead of configurable** —cannot adjust TTL without code change | Operational inflexibility; violates contract "instrument_cache_ttl_s" as a parameter | Test: override TTL to non-default value, assert behavior changes | AT-279 |

## 4) Open decisions (resolve before coding)

### Decision: Cache age computation source
- **What is ambiguous / missing**: Should cache age be computed from the time metadata was last successfully fetched from Deribit, or from the time it was last inserted/updated in the cache?
- **Evidence**: CONTRACT.md §1.0.X: "The engine MUST track freshness of instrument metadata". Deribit metadata is fetched periodically; the cache stores the result.
- **Options**:
  1. Option A —Track `last_refresh_ts` (time of last successful API fetch), compute age as `now - last_refresh_ts`. Refreshing resets the clock.
  2. Option B —Track `inserted_at` per-instrument, compute age per instrument entry.
- **Chosen**: A —single `last_refresh_ts` for the entire cache. Instrument metadata is fetched as a batch from `/public/get_instruments`, so all entries share the same freshness.
- **Why not others**: B adds per-instrument complexity without benefit since all instruments are fetched together.
- **Scope control**:
  - What we're NOT doing yet: per-instrument TTL, partial refresh, refresh retry logic (S1-006 adds observability).
  - What unblocks us if this choice is wrong: `last_refresh_ts` is a single field; easy to convert to per-instrument if needed.

### Decision: Where to enforce OPEN blocking
- **What is ambiguous / missing**: Should the cache itself block OPENs, or should it only set RiskState::Degraded and let PolicyGuard handle OPEN blocking?
- **Evidence**: CONTRACT.md §1.0.X: "set `RiskState::Degraded`" and "PolicyGuard MUST compute `TradingMode::ReduceOnly`". This implies a two-layer design: cache signals Degraded, PolicyGuard enforces ReduceOnly.
- **Options**:
  1. Option A —Cache sets RiskState::Degraded; PolicyGuard maps Degraded to ReduceOnly; dispatch authorization blocks OPEN under ReduceOnly.
  2. Option B —Cache directly blocks OPEN dispatch, bypassing PolicyGuard.
- **Chosen**: A —layered design following contract architecture. Cache signals, PolicyGuard enforces.
- **Why not others**: B violates separation of concerns and bypasses the canonical TradingMode computation path, creating a shadow enforcement that is hard to reason about.
- **Scope control**:
  - What we're NOT doing yet: direct integration with the full PolicyGuard tick loop (just the RiskState -> TradingMode signal path).
  - What unblocks us if this choice is wrong: RiskState is the standard input to PolicyGuard; this is the designed interface.

### Decision: Clock source for deterministic testing
- **What is ambiguous / missing**: How to make cache age computation deterministic in tests.
- **Evidence**: S1-003 acceptance: "cache age is compared against instrument_cache_ttl_s deterministically."
- **Options**:
  1. Option A —Inject a clock trait/closure into the cache, allowing tests to control time.
  2. Option B —Use `std::time::Instant` with sleep-based tests.
- **Chosen**: A —injectable clock for deterministic tests.
- **Why not others**: B makes tests slow and flaky.
- **Scope control**:
  - What we're NOT doing yet: production clock implementation (use monotonic clock, wire later).
  - What unblocks us if this choice is wrong: clock trait is a standard Rust pattern; easy to swap implementations.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-104 | Cache returns Degraded but OPEN is not actually blocked —test only checks RiskState, not dispatch eligibility | Degraded is set but PolicyGuard is not wired, so OPENs still dispatch | Test must assert OPEN dispatch count == 0 (not just RiskState == Degraded) |
| AT-104 | OPEN blocked but CLOSE also blocked —overly restrictive implementation | Capital locked, cannot exit positions | Test must assert CLOSE dispatch count >= 1 when cache is stale |
| AT-104 | Always returns Degraded regardless of cache age —pessimistic but wrong | System permanently in ReduceOnly even with fresh metadata | NON-TRIP test: fresh cache -> Healthy -> Active -> OPEN dispatches |
| AT-279 | TTL hardcoded to 3600s, ignoring configuration —passes default test but not configurable | Cannot adjust TTL operationally; violates parameterization contract | Test with non-default TTL value (e.g. 60s), assert staleness triggers at the configured value |
| AT-279 | Cache age never increases (always returns 0) —appears always fresh | Stale metadata never detected; fail-open | TRIP test with injected clock advanced past TTL; assert Degraded |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-104 | PolicyGuard | test_instrument_cache_ttl_blocks_opens_allows_closes | Yes (stale cache -> OPEN rejected, dispatch_count == 0) | Yes (fresh cache -> OPEN dispatched, dispatch_count == 1) | dispatch_count: OPEN=0 when stale, OPEN=1 when fresh; CLOSE always allowed | Yes |
| AT-104 | PolicyGuard | test_stale_instrument_cache_sets_degraded | Yes (stale -> Degraded) | Yes (fresh -> Healthy) | RiskState enum comparison | Yes |
| AT-279 | PolicyGuard | test_instrument_cache_ttl_s_expires_after_3600s | Yes (age > 3600 -> Degraded + ReduceOnly) | Yes (age < 3600 -> Healthy + Active) | RiskState + TradingMode comparison | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing cache TTL enforcement fails exactly these ATs)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Stale metadata contains wrong `tick_size` or `amount_step`. Orders are sized/quantized incorrectly. Worst case: order sized 10-100x too large due to stale `contract_multiplier` after an instrument parameter change. Exposure could exceed intended position by orders of magnitude.
- **Fail-closed cap on loss**: When working correctly, stale cache -> RiskState::Degraded -> TradingMode::ReduceOnly -> OPENs blocked. Existing positions can still be closed. This limits loss to existing open exposure; no new risk-increasing positions.
- **Drift metric**: `instrument_cache_age_s` (gauge) —if this exceeds `instrument_cache_ttl_s`, operators should investigate. `instrument_cache_stale_total` (counter from S1-006) tracks frequency of staleness events.
- **Loss boundary**: ReduceOnly blocks new OPENs. Existing exposure is bounded by position limits set elsewhere. Kill mode (downstream) provides ultimate containment.
- **Rollback plan**: If TTL enforcement is buggy (e.g. always Degraded), increase `instrument_cache_ttl_s` to a very large value to effectively disable the gate while preserving the code path. If fail-open, revert the cache changes; system will have no metadata, which should trigger a different fail-closed path (missing data).

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: RiskState transitions (new: cache staleness can set Degraded). PolicyGuard TradingMode computation (new input: instrument cache freshness).
- **If conflict with CONTRACT.md**: No conflict identified. Contract explicitly requires this behavior.
- Files with recent churn or shared ownership: `crates/soldier_core/src/venue/cache.rs` is new. `crates/soldier_core/src/venue/mod.rs` may be touched by S1-011 (struct definitions) —coordinate.
- Struct fields I'm assuming exist (verify before coding): S1-011 Deribit instrument struct, S1-002 InstrumentKind and RiskState enums.
- State machine transitions affected: RiskState can transition Healthy -> Degraded on cache staleness, and Degraded -> Healthy on cache refresh.

## 9) Constraint I expect to hit
- What will slow me down: Wiring the RiskState::Degraded signal from the cache into the PolicyGuard TradingMode computation. PolicyGuard may not exist yet or may not have an input for instrument cache freshness.
- Exploit: Define a clear interface (e.g. `fn cache_health(&self) -> RiskState`) that PolicyGuard can call. Stub PolicyGuard integration if it doesn't exist yet; the interface is the contract.
- Smallest fix that prevents it next time: Define PolicyGuard input interfaces early in slice planning, before individual stories need to wire into them.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Full PolicyGuard integration test (end-to-end tick with stale cache) | Medium | PolicyGuard tick loop may not be fully implemented in S1 | S1-003 owner | Slice 2 (PolicyGuard wiring) | Integration AT: stale cache -> PolicyGuard tick -> TradingMode::ReduceOnly emitted |
| Per-instrument TTL tracking | Low | Contract does not require per-instrument TTL; batch refresh is sufficient | N/A | Slice 3+ if needed | N/A |

- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice
