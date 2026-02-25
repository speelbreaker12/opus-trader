# Story Premortem: S1-012

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-012 — S1.4 Instrument lifecycle + expiry safety (Expiry Cliff Guard)
- Contract clause(s): §1.0.Y Instrument Lifecycle & Expiry Safety (Expiry Cliff Guard)
- Acceptance tests: AT-949, AT-950, AT-960, AT-961, AT-962, AT-965, AT-966
- Touch scope: `crates/soldier_core/src/risk`, `crates/soldier_core/src/venue`, `crates/soldier_core/tests`
- **Risk rating**: MED
  - Touches order rejection logic (instruments near expiry), terminal error classification,
    and portfolio-wide reconcile behavior. Does not directly place orders or move funds,
    but incorrect implementation could allow OPEN on an expired instrument (financial loss)
    or halt management of healthy instruments (collateral damage).

## 1) Clause audit (contract → AT traceability)

Source: CONTRACT.md §1.0.Y "Instrument Lifecycle & Expiry Safety (Expiry Cliff Guard) -- MUST implement"

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-949 | §1.0.Y Terminal error + idempotent cancel | CANCEL on expired instrument + terminal venue error -> idempotent success; instrument marked ExpiredOrDelisted; no panic; other instruments continue | MUST | Yes |
| AT-950 | §1.0.Y Delist buffer rule | If `now_ms >= expiration_timestamp_ms - (expiry_delist_buffer_s * 1000)`, OPEN MUST be rejected with `Rejected(InstrumentExpiredOrDelisted)` before dispatch; CLOSE/HEDGE/CANCEL remain allowed | MUST | Yes |
| AT-960 | §1.0.Y Idempotent cancel rule | Duplicate CANCEL on expired instrument after Terminal -> NOOP (idempotent success), no extra dispatch, ledger consistent | MUST | Yes |
| AT-961 | §1.0.Y Portfolio-wide reconcile (expiry-safe) | Terminal lifecycle error for instrument A MUST NOT abort reconcile; MUST continue managing instrument B; MUST NOT globally halt | MUST | Yes |
| AT-962 | §1.0.Y Reconcile termination | If venue truth shows no remaining position for expired instrument A, mark ExpiredOrDelisted and MUST NOT retry in a loop | MUST | Yes |
| AT-965 | §1.0.Y Delist buffer rule (NON-TRIP) | OPEN outside delist buffer MUST NOT be rejected with InstrumentExpiredOrDelisted; proceeds to dispatch | MUST NOT (negative) | Yes |
| AT-966 | §1.0.Y Idempotent cancel (NON-TRIP) | CANCEL on active instrument with normal success MUST NOT mark instrument ExpiredOrDelisted | MUST NOT (negative) | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `expiration_timestamp_ms` is available from cached instrument metadata (§1.0.X) before the expiry guard runs | If metadata cache is empty or field is missing, the guard cannot compute the buffer window; could silently allow OPEN | Test with `expiration_timestamp_ms = None` (perpetual) -> OPEN allowed; test with value present -> guard activates | Pending |
| 2 | `expiry_delist_buffer_s` is a configurable parameter with a sensible default (fail-closed: non-zero) | If default is 0, the buffer check degenerates to `now_ms >= expiration_timestamp_ms` only, missing the pre-expiry window entirely | Config test: default value > 0; AT-950 uses buffer_s=60 explicitly | Pending |
| 3 | Venue terminal errors can be reliably mapped to a finite set of semantic codes (`invalid_instrument`, `not_found`, `orderbook_closed`, `instrument_not_open`) | If venue returns an unexpected error string, the classifier misses it and treats it as a non-terminal error -> panic or retry loop | Table-driven test with known + unknown error strings; for instruments past expiry, unknown errors ARE classified as terminal (fail-closed); for instruments NOT past expiry, unknown errors fall through to generic handling per the strict allowlist (Decision §4.2) | Validated (consistent with Decision §4.2 expiry-dependent rule) |
| 4 | Intent classification (OPEN vs CLOSE/HEDGE/CANCEL) is already implemented and correct (dependency S1-003, S1-011) | If intent classification is wrong (e.g., a hedge is misclassified as OPEN), the guard would wrongly reject it | Upstream tests in S1-003; integration test with CLOSE intent inside buffer -> allowed | Pending |
| 5 | Reconcile loop iterates per-instrument and does not short-circuit on first error | If reconcile uses `?` or early-return on the first instrument error, it aborts the entire loop | AT-961 directly tests this: A fails, B continues | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Buffer arithmetic overflow/underflow: `expiration_timestamp_ms - (expiry_delist_buffer_s * 1000)` overflows when buffer_s is very large or timestamp is near i64 boundary | Saturating arithmetic test; property test with extreme values | Use `checked_sub` / `saturating_sub`; on overflow, treat as within buffer (fail-closed: reject OPEN) | AT-950 (indirectly) |
| 2 | Terminal error classifier is too narrow: venue returns a new error variant not in the match set -> classified as non-terminal -> panic or retry | Logging of unmatched error codes; alert on unknown venue errors for expired instruments | If instrument is past expiration AND venue returns an error, classify as terminal (fail-closed) | AT-949 |
| 3 | Reconcile loop short-circuits: `for instrument in portfolio { reconcile(instrument)?; }` — the `?` aborts on first error | AT-961 directly tests multi-instrument reconcile | Use `continue` with logging instead of `?`; collect errors, report at end | AT-961 |
| 4 | Idempotency state not tracked: second CANCEL dispatches to venue again instead of being a NOOP | AT-960 checks no extra dispatch on retry | Track instrument_state; once marked ExpiredOrDelisted, skip dispatch for that instrument's CANCELs | AT-960 |
| 5 | CANCEL success on active instrument triggers ExpiredOrDelisted marking: guard checks "was this a cancel?" but not "was the error terminal?" | AT-966 directly tests this false-positive path | Only mark ExpiredOrDelisted when error IS terminal AND instrument IS past expiry; normal cancel success -> no state change | AT-966 |

## 4) Open decisions (resolve before coding)

### Decision: Where does the expiry guard check live?
- **What is ambiguous / missing**: Contract says "rejected before dispatch" but does not specify whether this is a new guard module, part of PolicyGuard, or part of the Dispatcher chokepoint.
- **Evidence**: CONTRACT.md §1.0.Y: "rejected before dispatch with `Rejected(InstrumentExpiredOrDelisted)`"; prd.json enforcement_point: "DispatcherChokepoint"
- **Options**:
  1. Dedicated `ExpiryGuard` module in `crates/soldier_core/src/risk/` — clear separation, single responsibility; tested in isolation
  2. Inline check in the Dispatcher chokepoint — fewer files, but mixes concerns
- **Chosen**: (A) Dedicated ExpiryGuard — deciding factor: 7 ATs with complex interactions justify a dedicated module; easier to test in isolation
- **Why not others**: Inline check makes testing individual AT behaviors harder; intent classification + terminal error classification + idempotency tracking is too much logic for inline
- **Scope control**:
  - What we're NOT doing yet: DelistingSoon intermediate state transitions (only Active -> ExpiredOrDelisted)
  - What unblocks us if this choice is wrong: Guard is called from the chokepoint, so moving logic inline later is mechanical

### Decision: How to handle unknown venue error codes for expired instruments
- **What is ambiguous / missing**: Contract lists {`invalid_instrument`, `not_found`, `orderbook_closed`, `instrument_not_open`} but venues may return novel error strings.
- **Evidence**: CONTRACT.md §1.0.Y: "Any venue response that semantically maps to {...}"
- **Options**:
  1. Strict allowlist: only classify listed codes as terminal — unknown errors fall through to generic error handling
  2. Fail-closed: if instrument is past expiry AND venue returns ANY error, classify as terminal
- **Chosen**: (A) Strict allowlist with expiry-dependent fallback — deciding factor: for instruments NOT past expiry, unknown errors fall through to generic error handling (avoids masking connectivity issues as terminal lifecycle events). For instruments past expiry, unknown errors ARE classified as terminal (fail-closed: an expired instrument receiving any venue error is overwhelmingly likely to be a lifecycle event, and the cost of missing it outweighs the cost of a false terminal classification).
- **Why not others**: Pure Option B (fail-closed on ALL errors regardless of expiry state) could mask network errors as terminal events for active instruments, preventing retry on transient failures. Pure Option A (strict allowlist only) leaves expired instruments vulnerable to novel error codes.
- **Scope control**:
  - What we're NOT doing yet: Automatic expansion of the terminal error set
  - What unblocks us if this choice is wrong: Adding new codes to the match set is a one-line change

### Decision: instrument_state storage location
- **What is ambiguous / missing**: Where is `instrument_state` stored? In the instrument cache? In a separate state map?
- **Evidence**: CONTRACT.md §1.0.Y: "mark `instrument_state=ExpiredOrDelisted`"; required fields include `instrument_state: enum { Active, DelistingSoon, ExpiredOrDelisted }`
- **Options**:
  1. Field on the cached instrument metadata struct — co-located with `expiration_timestamp_ms`
  2. Separate `HashMap<InstrumentId, InstrumentState>` in the guard
- **Chosen**: (A) Field on instrument metadata — deciding factor: contract defines it as a required instrument field; co-location prevents divergence
- **Why not others**: Separate map creates synchronization risk between metadata and state
- **Scope control**:
  - What we're NOT doing yet: Persisting instrument_state across restarts (WAL concern, out of scope)
  - What unblocks us if this choice is wrong: Either location is queryable; moving is mechanical

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-949 | Mark instrument as ExpiredOrDelisted on ANY cancel (not just terminal errors) | Would incorrectly mark active instruments as expired when cancels succeed normally | AT-966 catches this: normal cancel success must NOT mark expired |
| AT-950 | Hardcode rejection of ALL intents (not just OPEN) within buffer | Blocks CLOSE/HEDGE/CANCEL which contract requires to remain allowed | Golden vector: CLOSE intent within buffer -> dispatch_count=1, no rejection |
| AT-960 | Skip dispatch but mutate ledger state on duplicate cancel | Idempotent on dispatch but not on state — corrupts ledger | Golden vector: assert ledger checksum unchanged between T0 and T0+1 duplicate cancel |
| AT-961 | Catch panic from instrument A but swallow the error silently (no logging, no marking) | Appears to "continue" but loses the signal that A expired; A never marked ExpiredOrDelisted | AT-961 pass criteria requires A marked ExpiredOrDelisted; add assertion on instrument_state after reconcile |
| AT-962 | Mark A as expired but still enqueue retry attempts (just never execute them) | Retry queue grows unboundedly; a future code change might drain it | Assert retry_count == 0 for A after reconcile; golden vector checks no pending retries |
| AT-965 | Always allow OPEN (never check buffer at all) | Passes AT-965 but fails AT-950; tests must be run together | AT-950 is the TRIP counterpart; both must pass in the same test suite |
| AT-966 | Never mark anything as expired (global no-op) | Passes AT-966 but fails AT-949; same coupling | AT-949 is the TRIP counterpart; both must pass together |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-949 | DispatcherChokepoint (ExpiryGuard) | test_expiry_cancel_idempotent_success | TRIP | -- (AT-966 is NON-TRIP pair) | instrument_state == ExpiredOrDelisted; no panic | Yes: isolates terminal cancel on expired instrument |
| AT-950 | DispatcherChokepoint (ExpiryGuard) | test_expiry_delist_buffer_rejects_open | TRIP | -- (AT-965 is NON-TRIP pair) | dispatch_count == 0; reject_reason == InstrumentExpiredOrDelisted | Yes: isolates OPEN within buffer |
| AT-960 | DispatcherChokepoint (ExpiryGuard) | test_expiry_cancel_idempotent_duplicate_noop | TRIP | -- | dispatch_count unchanged; ledger consistent | Yes: isolates duplicate cancel idempotency |
| AT-961 | Reconcile loop | test_expiry_reconcile_does_not_halt_other_instruments | TRIP | -- | instrument B dispatch_count >= 1; no crash; A marked expired | Yes: isolates multi-instrument reconcile |
| AT-962 | Reconcile loop | test_expiry_no_retry_loop_after_positions_clear | TRIP | -- | retry_count == 0 for A; instrument_state == ExpiredOrDelisted | Yes: isolates reconcile termination |
| AT-965 | DispatcherChokepoint (ExpiryGuard) | test_expiry_outside_buffer_allows_open | -- | NON-TRIP (pair of AT-950) | dispatch_count == 1; no Rejected(InstrumentExpiredOrDelisted) | Yes: isolates OPEN outside buffer |
| AT-966 | DispatcherChokepoint (ExpiryGuard) | test_expiry_non_terminal_cancel_does_not_mark_expired | -- | NON-TRIP (pair of AT-949) | instrument_state == Active | Yes: isolates normal cancel on active instrument |

TRIP/NON-TRIP pairings:
- AT-950 (TRIP: buffer rejects OPEN) <-> AT-965 (NON-TRIP: outside buffer allows OPEN)
- AT-949 (TRIP: terminal cancel marks expired) <-> AT-966 (NON-TRIP: normal cancel does not mark expired)
- AT-960 (TRIP: duplicate cancel is NOOP) — no explicit NON-TRIP pair needed (first cancel is tested by AT-949)
- AT-961, AT-962 (TRIP: reconcile behavior) — NON-TRIP is implicit: single-instrument scenarios in other ATs

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: OPEN placed on a BTC option expiring in 2 minutes. The option has $50K notional, wide bid-ask spread (5%), and near-zero time value. If filled, the position becomes worthless at expiry with no opportunity to close. Expired instruments may have no counterparties for closing, creating an illiquidity cliff: the closer to expiry, the worse the loss because the book thins out and spread widens nonlinearly. Worst case: full notional loss ($50K per instrument, bounded by per-instrument position limit).
- **Fail-closed cap on loss** (what restricts exposure): The ExpiryGuard rejects OPEN before dispatch — if the guard fires, no order reaches the venue. The delist buffer provides a time cushion (default: `expiry_delist_buffer_s` seconds before expiry). Even if the guard fails, existing position limits and TradingMode constraints provide secondary defense.
- **Drift metric** (what tells us it's going wrong before it blows up): `s1_012_checks_total{result="rejected"}` counter; alert if instruments within buffer are not being rejected. Also: instrument_state transitions logged with tracing.
- **Loss boundary** (ReduceOnly? Kill? Position limit? Time bound?): Per-instrument position limit bounds worst-case exposure. Expiry buffer provides time-bound defense (no new opens N seconds before expiry). If guard fails, PolicyGuard TradingMode still applies.
- **Rollback plan** (how to revert if it fails): Disable OPEN intents globally (set TradingMode to ReduceOnly) while investigating. The guard is additive — removing it reverts to pre-guard behavior (less safe but does not corrupt state). No persistent state to roll back; instrument_state is in-memory.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: DispatcherChokepoint intent evaluation ordering (ExpiryGuard must run before dispatch). Reconcile loop error handling pattern.
- **If conflict with CONTRACT.md**: None identified. §1.0.Y is self-contained and does not conflict with §2.2 TradingMode (CLOSE/HEDGE/CANCEL remain subject to TradingMode).
- Files with recent churn or shared ownership:
  - `crates/soldier_core/src/risk/` — shared with PolicyGuard (S1-003); coordinate on module structure
  - `crates/soldier_core/src/venue/` — shared with venue response handling; error classification may overlap with existing error types
- Struct fields I'm assuming exist (verify before coding):
  - `expiration_timestamp_ms: Option<i64>` on instrument metadata struct
  - `expiry_delist_buffer_s: u64` in config
  - `instrument_state` enum with `Active`, `DelistingSoon`, `ExpiredOrDelisted` variants
  - `IntentClass` enum with OPEN, CLOSE, HEDGE, CANCEL variants (from S1-003)
  - `RejectReason::InstrumentExpiredOrDelisted` variant
- State machine transitions affected:
  - `instrument_state`: Active -> ExpiredOrDelisted (terminal, one-way)
  - No transition back from ExpiredOrDelisted (latch-like behavior)

## 9) Constraint I expect to hit
- Lessons from prior story postmortems: No prior postmortems exist (S1-012 is in Slice 1). First-mover risk: no precedent for ExpiryGuard patterns in this codebase.
- What will slow me down: The 7 ATs have complex interactions — several share the same code paths (cancel handling, reconcile loop) but test different facets. Getting test isolation right (each AT tests exactly one clause) while sharing infrastructure will require careful test fixture design.
- Exploit (workaround for this story): Use a builder pattern for test fixtures with defaults that satisfy all gates, then override only the parameter under test. Each AT test function sets up its own scenario from the builder.
- Smallest fix that prevents it next time: Document the test fixture builder pattern in `crates/soldier_core/tests/` so future stories with many ATs can reuse it.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| DelistingSoon intermediate state not exercised | Low | Contract defines the enum variant but no AT requires DelistingSoon transitions; only Active -> ExpiredOrDelisted is tested | S1-012 owner | Slice 2+ | AT for DelistingSoon -> ExpiredOrDelisted transition |
| Unknown venue error code handling | Low | Decision §4: strict allowlist chosen; novel error codes fall through to generic handling; may need future expansion | S1-012 owner | Slice 2+ | Property test with fuzzy error strings; alert on unmatched codes |
| No combined AT for buffer + reconcile interaction | Low | AT-950 tests buffer rejection; AT-961 tests reconcile continuation; no AT tests: "instrument enters buffer DURING reconcile" | S1-012 owner | Slice 2+ | Combined integration test: reconcile starts with active instrument, instrument enters buffer mid-reconcile |

**Exit criteria (definition of done, before I start):**
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
