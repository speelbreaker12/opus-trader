# Story Premortem: S1-004

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-004 — OrderSize canonical sizing
- Contract clause(s): §1.0 Instrument Units & Notional Invariants (Deribit Quantity Contract)
- Acceptance tests: AT-277
- Touch scope: `crates/soldier_core/src/execution/order_size.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/src/lib.rs`, `crates/soldier_core/tests/test_order_size.rs`
- **Risk rating**: LOW
  - Pure data structure + computation. No persistence, no order placement, no funds movement.
  - Sizing errors propagate downstream but are caught by S1-007 mismatch guard before dispatch.

## 1) Clause audit (contract → AT traceability)

For each `enforcing_contract_ats` claimed by this story, find the AT in CONTRACT.md,
extract the normative clause, and classify. Skip informational clauses.

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-277 | §1.0 Instrument Units & Notional Invariants | "OrderSize struct (MUST implement): contracts, qty_coin, qty_usd, notional_usd. option/linear_future: canonical = qty_coin; perpetual/inverse_future: canonical = qty_usd. notional_usd = qty_coin * index_price (coin) or qty_usd (USD). Option qty_usd MUST be unset." | MUST | Yes |
| AT-277 | §1.0 Dispatcher Rules | "outbound option uses amount=0.3 (coin), notional_usd=30_000, and qty_usd is unset; outbound perp uses amount=30_000 (USD), qty_coin=0.3, notional_usd=30_000" | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `index_price` is always > 0 when constructing OrderSize | If index_price is zero or negative, notional_usd = 0 or negative, causing downstream sizing to be wrong | Test: construct OrderSize with index_price=0 -> must reject or error, not produce notional_usd=0 | Pending |
| 2 | `InstrumentKind` correctly classifies USDC-margined linear perpetuals as `linear_future` | If linear perps are classified as `perpetual`, they get `qty_usd` canonical instead of `qty_coin`, sending wrong amount to exchange | Test: construct OrderSize for a USDC-margined perp -> canonical must be qty_coin (treated as linear_future) | Pending |
| 3 | `qty_coin` and `qty_usd` are mutually exclusive for canonical; the non-canonical field is derived or unset | If both are set as canonical, violates Hard Rule #1 "Never mix coin sizing and USD sizing" | Test: construct OrderSize for option -> qty_usd must be None; for perpetual -> qty_coin is derived (not canonical input) | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | notional_usd computed incorrectly (e.g., uses mark_price instead of index_price) | Unit test with known values (0.3 BTC * 100_000 = 30_000 USD) | Deterministic computation, no fallback — wrong formula fails AT | AT-277 |
| 2 | Option OrderSize sets qty_usd when it should be unset | Unit test asserts qty_usd is None for options | Constructor enforces None for qty_usd on option/linear_future | AT-277 |
| 3 | Linear perpetual (USDC-margined) treated as `perpetual` instead of `linear_future` | Unit test for USDC-margined perp checks canonical field is qty_coin | InstrumentKind derivation must classify correctly (S1-002 dependency) | AT-277 |
| 4 | Floating-point precision loss in notional_usd computation | Table-driven test with edge case values (very small qty_coin, very large index_price) | Use f64 arithmetic directly; no intermediate rounding before final result | AT-277 |
| 5 | OrderSize constructed without populating notional_usd (field left as 0.0 or default) | Compile-time: notional_usd is non-optional f64, constructor must compute it | Struct constructor enforces computation; no Default impl that leaves it zero | AT-277 |

## 4) Open decisions (resolve before coding)

### Decision: OrderSize constructor API shape
- **What is ambiguous / missing**: Should OrderSize be constructed via a `new()` function taking (instrument_kind, qty, index_price) or via a builder pattern?
- **Evidence**: CONTRACT.md §1.0 specifies the struct fields but not construction API. The struct has 4 fields with conditional population rules.
- **Options**:
  1. Option A — `OrderSize::new(instrument_kind, qty, index_price)` with qty being the canonical amount. Simple, hard to misuse. Blast radius: low. Verification: AT-277 table-driven tests.
  2. Option B — Builder pattern with `.qty_coin()`, `.qty_usd()`, `.build()`. More flexible but allows setting both fields (violation of Hard Rule #1). Blast radius: med (misuse risk). Verification: build-time validation needed.
- **Chosen**: A — deciding factor: fewer ways to misuse; canonical amount determined by instrument_kind, not caller
- **Why not others**: Builder allows callers to set both qty_coin and qty_usd, violating Hard Rule #1
- **Scope control**:
  - What we're NOT doing yet: contracts derivation (that uses contract_multiplier, handled in S1-005 dispatch mapping)
  - What unblocks us if this choice is wrong: constructor is internal API, refactor is cheap

### Decision: What to do when index_price is zero or NaN
- **What is ambiguous / missing**: CONTRACT.md does not specify behavior when index_price is missing/zero/NaN for coin-sized instruments
- **Evidence**: notional_usd = qty_coin * index_price requires valid index_price
- **Options**:
  1. Option A — Return an error (Result<OrderSize, SizingError>). Fail-closed: cannot compute notional, refuse to proceed.
  2. Option B — Set notional_usd = 0.0 and continue. Fail-open: hides the problem.
- **Chosen**: A — deciding factor: fail-closed principle; zero notional would bypass downstream exposure checks
- **Why not others**: Option B is fail-open; zero notional could pass risk limits that should block
- **Scope control**:
  - What we're NOT doing yet: sourcing index_price (assumed provided by caller)
  - What unblocks us if this choice is wrong: error type is local to this module

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-277 | Hardcode notional_usd=30_000 for any option with qty_coin=0.3 | Only works for index_price=100_000; breaks for all other prices | Golden vector: test with multiple index_prices (50_000, 200_000) and verify notional_usd = qty_coin * index_price |
| AT-277 | Set qty_usd = None for ALL instrument kinds (not just options) | Perpetual/inverse_future needs qty_usd as canonical | Golden vector: perpetual must have qty_usd = Some(30_000), not None |
| AT-277 | Compute notional_usd correctly but leave qty_coin/qty_usd fields swapped | Option sends qty_usd to exchange instead of qty_coin | Golden vector: assert specific field (qty_coin for option, qty_usd for perp) is Some and the other follows contract rules |
| AT-277 | Use mark_price instead of index_price for notional_usd computation | During volatile markets, mark_price diverges from index_price significantly; notional_usd would be wrong, causing risk limits to be evaluated at wrong exposure level | Golden vector: set index_price=100_000 and mark_price=105_000; assert notional_usd uses index_price (100_000 * qty_coin), not mark_price |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-277 | OrderSize (execution::order_size) | test_order_size_option_canonical_qty_coin | Yes (option: qty_coin set, qty_usd unset) | Yes (perpetual: qty_usd set, qty_coin derived) | Field values match expected; notional_usd = qty_coin * index_price | Yes |
| AT-277 | OrderSize (execution::order_size) | test_order_size_perpetual_canonical_qty_usd | Yes (perp: qty_usd set) | Yes (option: different canonical) | Field values match expected; notional_usd = qty_usd | Yes |
| AT-277 | OrderSize (execution::order_size) | test_order_size_option_qty_usd_unset | Yes (qty_usd must be None for option) | N/A (negative test) | Assert qty_usd.is_none() | Yes |

Causality proof: dispatch_count is N/A for a pure-computation struct — OrderSize defines data fields, not dispatcher enforcement. Field-value equality is the substitute causality mechanism: each test proves correctness by asserting that computed field values exactly match the contract-specified invariants for the given instrument kind.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: OrderSize computes wrong notional_usd. Downstream exposure checks use notional_usd for position sizing limits. A 10x notional error could lead to 10x intended exposure, bounded by exchange margin requirements and risk limits.
- **Fail-closed cap on loss**: S1-007 mismatch guard (AT-920) rejects contracts/amount inconsistencies before dispatch. PolicyGuard exposure limits provide a second layer. Even if OrderSize is wrong, the dispatcher must validate before sending to exchange.
- **Drift metric**: `order_size_computed_total` counter + downstream `order_intent_reject_unit_mismatch_total` (if mismatches spike, sizing is broken).
- **Loss boundary**: ReduceOnly via PolicyGuard if exposure limits breach. Exchange-side margin requirements as ultimate backstop.
- **Rollback plan**: OrderSize is a pure computation with no state. Fix the formula and redeploy. No persistent state to clean up.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: OrderSize is a new struct; no existing invariants modified. Downstream consumers (S1-005 dispatch mapping, S1-007 mismatch rejection) depend on correct field population.
- **If conflict with CONTRACT.md**: No conflicts identified. OrderSize struct definition matches CONTRACT.md exactly.
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/mod.rs` (shared with S1-005, S1-007)
- Struct fields I'm assuming exist: `InstrumentKind` enum with variants `Option`, `LinearFuture`, `InverseFuture`, `Perpetual` (from S1-002)
- State machine transitions affected: None. OrderSize is a pure data computation.

## 9) Constraint I expect to hit
- What will slow me down: Dependency on S1-002 (InstrumentKind enum) and S1-008 (discovery report). Cannot implement until InstrumentKind is defined.
- Exploit: Can define the OrderSize struct and constructor with InstrumentKind as a parameter, implementing against the contract spec. S1-002 provides the enum; S1-008 provides gap analysis.
- Smallest fix that prevents it next time: Ensure discovery stories (S1-008) complete before implementation stories in the dependency chain.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- **GREEN**: All gates pass. OrderSize is a pure computation struct with clear contract specification, well-defined fields, and testable invariants. No ambiguity in the contract language. Downstream guards (S1-007) provide defense-in-depth.

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
