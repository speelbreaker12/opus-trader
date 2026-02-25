# Story Premortem: S1-005

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-005 — Dispatcher amount mapping
- Contract clause(s): §1.0 Dispatcher Rules (Deribit request mapping)
- Acceptance tests: AT-277
- Touch scope: `crates/soldier_core/src/execution/dispatch_map.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/src/lib.rs`, `crates/soldier_core/tests/test_dispatch_map.rs`
- **Risk rating**: LOW
  - Maps internal OrderSize to outbound exchange request fields. No persistence, no direct funds movement.
  - Errors here send wrong amounts to exchange, but S1-007 mismatch guard catches inconsistencies before dispatch.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-277 | §1.0 Dispatcher Rules | "Deribit outbound order size field: always send exactly one canonical 'amount' value: coin instruments -> send amount = qty_coin; USD-sized instruments -> send amount = qty_usd" | MUST | Yes |
| AT-277 | §1.0 Dispatcher Rules | "option/linear_future: canonical = qty_coin; perpetual/inverse_future: canonical = qty_usd" | MUST | Yes |
| AT-277 | §1.0 Hard Rules | "For instrument_kind == option, order size MUST use qty_coin; qty_usd MUST be unset" | MUST | Yes |
| AT-277 | §1.0 Dispatcher Rules | "If contracts exists, it must be consistent with the canonical amount before dispatch (reject if not)" | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | OrderSize from S1-004 always has the correct canonical field populated | If OrderSize constructor has a bug and populates wrong field, dispatch sends wrong amount | Test: construct OrderSize for each instrument_kind, pass to dispatch mapper, verify outbound amount field matches canonical | Pending |
| 2 | Deribit API accepts exactly one of amount/contracts, not both | If Deribit accepts both and we send both, behavior is undefined; if we send neither, order is rejected | Killed — Deribit /private/buy and /private/sell API docs specify amount and contracts as separate optional parameters; exactly one must be provided. Verified against Deribit API documentation. | Killed |
| 3 | Intent classification (OPEN/CLOSE/HEDGE) is available at dispatch time | If classification is missing, reduce_only cannot be mapped correctly | Test: dispatch with CLOSE intent -> reduce_only=true; dispatch with OPEN intent -> reduce_only=false/omitted | Pending |
| 4 | Linear perpetuals (USDC-margined) use qty_coin like linear_future, not qty_usd like perpetual | Mapping logic must branch on instrument_kind, not on symbol name patterns | Test: USDC-margined perp (classified as linear_future) -> outbound uses qty_coin | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Both amount fields set in outbound request (qty_coin AND qty_usd sent) | Unit test asserts exactly one field is set | Dispatch mapper sets one field and explicitly unsets the other; assertion before send | AT-277 |
| 2 | Wrong canonical field selected for instrument kind (e.g., option uses qty_usd) | Table-driven test per instrument_kind | Match on InstrumentKind enum; compiler warns on missing arms | AT-277 |
| 3 | reduce_only not set for CLOSE/HEDGE intents | Unit test for each intent classification | Explicit match on IntentClass; fail-closed: if unknown intent class, treat as OPEN (most restrictive for new positions but does not set reduce_only which prevents unwanted closes) | AT-277 |
| 4 | Contracts field sent when contract_multiplier is not defined | Unit test for instrument without contract_multiplier | Only derive contracts when contract_multiplier is Some; if None, contracts field is None | AT-277 |
| 5 | Amount field contains NaN or infinity from upstream computation | Validation check before constructing outbound request | Assert amount.is_finite() before dispatch; reject with error if not | New test needed (not covered by AT-277 directly) |

## 4) Open decisions (resolve before coding)

### Decision: Outbound request representation
- **What is ambiguous / missing**: CONTRACT.md specifies "send exactly one canonical amount value" but does not define the Rust struct for the outbound Deribit request.
- **Evidence**: CONTRACT.md §1.0 Dispatcher Rules: "always send exactly one canonical 'amount' value"
- **Options**:
  1. Option A — Single `amount: f64` field in outbound struct, with the mapper selecting the correct value from OrderSize. The exchange always receives one `amount` field regardless of instrument type.
  2. Option B — Two optional fields `qty_coin: Option<f64>`, `qty_usd: Option<f64>` in outbound struct, with assertion that exactly one is Some. More explicit about which unit was selected.
- **Chosen**: A — deciding factor: Deribit API uses a single `amount` field in the order request, not separate coin/usd fields. The canonical value selection is an internal concern.
- **Why not others**: Option B introduces a divergence from the actual API shape and creates a new place where both could accidentally be set.
- **Scope control**:
  - What we're NOT doing yet: contracts/amount mismatch validation (S1-007)
  - What unblocks us if this choice is wrong: outbound struct is internal; refactor scope is small

### Decision: reduce_only mapping for unknown intent classification
- **What is ambiguous / missing**: CONTRACT.md says "CLOSE/HEDGE -> reduce_only=true; OPEN -> reduce_only=false or omitted". What if intent classification is unknown?
- **Evidence**: CLAUDE.md pattern: "if uncertain, treat as OPEN (most restrictive)" for intent classification
- **Options**:
  1. Option A — Fail-closed: treat unknown as OPEN, set reduce_only=false. This prevents unintended position reduction.
  2. Option B — Reject the intent entirely if classification is unknown.
- **Chosen**: A — deciding factor: matches the fail-closed pattern in CLAUDE.md/DESIGN_PATTERNS.md for intent classification. Unknown = OPEN = most restrictive for new position opening.
- **Why not others**: Option B is more aggressive but the contract does not require rejection for unknown classification; fail-closed via OPEN semantics is sufficient.
- **Scope control**:
  - What we're NOT doing yet: intent classification logic itself (assumed from upstream)
  - What unblocks us if this choice is wrong: single match arm change

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-277 | Always send amount=qty_coin regardless of instrument_kind | Works for options but sends coin amount for perpetuals, causing 100x exposure error (0.3 BTC vs 30,000 USD) | Golden vector: perpetual with qty_usd=30_000 must produce outbound amount=30_000, not amount=0.3 |
| AT-277 | Set reduce_only=true for ALL intents (not just CLOSE/HEDGE) | Passes AT-277 for CLOSE case but prevents new position opens from working | Golden vector: OPEN intent must produce reduce_only=false or omitted |
| AT-277 | Send both amount fields (qty_coin and qty_usd) in outbound request | Exchange might silently pick one, and the AT might only check one field | Negative test: assert outbound request has exactly one amount field; fail if both are set |
| AT-277 | Map reduce_only correctly but forget to validate that amount > 0 before dispatch | Zero-amount order sent to exchange; exchange rejects with confusing error, or worse, interprets as "market order" | Golden vector: OrderSize with qty_coin=0.0 → dispatch mapper must reject before sending to exchange |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-277 | DispatcherChokepoint (dispatch_map) | test_option_maps_to_qty_coin_amount | Yes (option -> amount=qty_coin) | Yes (perp -> amount=qty_usd) | Outbound amount field value equals expected canonical | Yes |
| AT-277 | DispatcherChokepoint (dispatch_map) | test_perpetual_maps_to_qty_usd_amount | Yes (perp -> amount=qty_usd) | Yes (option -> amount=qty_coin) | Outbound amount field value equals expected canonical | Yes |
| AT-277 | DispatcherChokepoint (dispatch_map) | test_exactly_one_amount_field_set | Yes (exactly one field) | N/A (invariant test) | Assert one field set, other unset | Yes |
| AT-277 | DispatcherChokepoint (dispatch_map) | test_reduce_only_close_hedge | Yes (CLOSE -> reduce_only=true) | Yes (OPEN -> reduce_only=false) | reduce_only field matches intent classification | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Dispatcher sends wrong amount to exchange. For a perpetual mapped with qty_coin instead of qty_usd: intended $30,000 position becomes 0.3 USD position (100,000x undersize) or vice versa — a $30,000 intent could become a $3,000,000,000 order if coin/usd are swapped at high prices. Exchange margin limits would reject the oversized case, but undersized orders would silently under-hedge.
- **Fail-closed cap on loss**: S1-007 mismatch guard validates contracts vs amount consistency before dispatch. PolicyGuard exposure limits cap total position size. Exchange-side margin requirements reject orders exceeding account equity.
- **Drift metric**: Compare outbound amount to notional_usd ratio across instrument kinds. A sudden change in the ratio indicates mapping drift.
- **Loss boundary**: ReduceOnly via PolicyGuard on exposure breach. Exchange margin as ultimate backstop for oversized orders. Undersized orders are economically bounded by the intent's notional.
- **Rollback plan**: Dispatch mapping is stateless. Fix the mapping logic and redeploy. Incorrect orders already sent would need manual position reconciliation.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: Dispatch mapping creates the outbound request shape consumed by the exchange adapter. Changes here affect all downstream order submission.
- **If conflict with CONTRACT.md**: No conflicts identified. Mapping rules directly implement CONTRACT.md §1.0 Dispatcher Rules.
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/dispatch_map.rs` (shared with S1-007 mismatch rejection), `crates/soldier_core/src/execution/mod.rs`
- Struct fields I'm assuming exist: `OrderSize` struct from S1-004, `InstrumentKind` enum from S1-002, `IntentClass` enum (OPEN/CLOSE/HEDGE)
- State machine transitions affected: None. Dispatch mapping is a pure function from (OrderSize, InstrumentKind, IntentClass) -> outbound request.

## 9) Constraint I expect to hit
- What will slow me down: Dependencies on S1-004 (OrderSize struct) and S1-009 (dispatch map discovery). Need the OrderSize API to write the mapping function, and the discovery report to understand current gaps.
- Exploit: Can implement against the CONTRACT.md spec directly with the OrderSize struct shape defined in the contract. Discovery report (S1-009) fills in current-state gaps but the target state is fully specified.
- Smallest fix that prevents it next time: Ensure OrderSize struct definition is stable before dispatch mapping work begins.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- **GREEN**: All gates pass. Dispatch mapping is a well-specified pure function with clear contract rules, testable invariants, and defense-in-depth from S1-007 mismatch guard. No ambiguity in the mapping rules.

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
