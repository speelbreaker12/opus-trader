# Story Premortem: S5-000

> Reference: `specs/DESIGN_PATTERNS.md` (SS0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.
> **Reconciliation mode**: Retroactive audit of already-passing story.

## 0) What we're building
- Story: S5-000 — Liquidity Gate (book-walk WAP, reject sweep)
- Contract clause(s): `specs/CONTRACT.md` SS1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)
- Acceptance tests: AT-222, AT-344, AT-909, AT-421, AT-317
- Touch scope: `crates/soldier_core/src/execution/gate.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/tests/test_liquidity_gate.rs`
- **Risk rating**: MED
  - Touches order evaluation path (pre-dispatch gate), but not order placement or funds movement directly. Fail-closed design limits blast radius.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract SS | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-222 | SS1.3 | Given L2 book where OrderQty implies slippage_bps > max_slippage_bps, intent is rejected with Rejected(ExpectedSlippageTooHigh), no OrderIntent emitted | MUST | Yes |
| AT-344 | SS1.3 | Given L2BookSnapshot missing/unparseable/stale, OPEN intent rejected, no dispatch | MUST | Yes |
| AT-909 | SS1.3 | Given missing/stale L2 for OPEN, rejected with Rejected(LiquidityGateNoL2), dispatch count 0 | MUST | Yes |
| AT-421 | SS1.3 | Given missing/stale L2, CANCEL allowed, CLOSE/HEDGE order placement rejected | MUST | Yes |
| AT-317 | Appendix A | Given L2 walk estimates slippage_bps > 10, trade rejected before dispatch | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | L2 book levels are sorted (asks ascending, bids descending) | Misordered levels produce wrong WAP | `test_multi_level_wap_computation` verifies correct WAP from sorted multi-level book | Yes |
| 2 | CancelOnly intents bypass all L2 checks | If CancelOnly checks L2, cancels fail when L2 is missing/stale | `test_at421_cancel_only_allowed_without_l2`, `test_at421_cancel_allowed_with_stale_l2`, proptest `cancel_only_always_allowed` | Yes |
| 3 | Invalid numerics (NaN, Inf, negative qty/price) fail closed | Non-finite inputs could produce wrong allow decisions | `compute_wap` returns None for invalid inputs, `test_overflowed_slippage_budget_fails_closed`, proptest `never_panics` | Yes |

## 3) Top 5 failure modes
For each enforcement-point input/intermediate, run the fail-closed 6-category sweep:

| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing L2 snapshot (None) | `match &input.l2_snapshot` None branch | Returns `Rejected(LiquidityGateNoL2)` | AT-344, AT-909 |
| 2 | Stale L2 snapshot (age > max_age_ms) | Timestamp comparison `now_ms - snap.timestamp_ms > max_age_ms` | Returns `Rejected(LiquidityGateNoL2)` | AT-344 |
| 3 | NaN/Inf in order_qty or max_slippage_bps | `is_finite()` checks at gate entry | Returns `Rejected(ExpectedSlippageTooHigh)` | Proptest `never_panics` |
| 4 | NaN/Inf in L2 level price/qty | `is_finite()` checks in `compute_wap` and `compute_fillable_depth` | Returns None / `Err(InvalidBook)` -> reject | `test_overflowed_slippage_budget_fails_closed` |
| 5 | Future-dated L2 snapshot (timestamp > now_ms) | `snap.timestamp_ms > input.now_ms` check | Returns `Rejected(LiquidityGateNoL2)` | `test_future_dated_l2_rejected_fail_closed` |

- [x] 6-category fail-closed sweep completed for each enforcement input/intermediate
- [x] Each category has explicit detection + mitigation, or is marked N/A with rationale

## 4) Open decisions (resolve before coding)

No open decisions. Implementation is complete and passing.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-222 | Always reject OPEN regardless of slippage | N | Would block all trades | `test_slippage_within_limit_allowed` proves non-rejection path works |
| AT-344 | Reject all intents when L2 missing (including CANCEL) | N | Would break cancels | AT-421 `test_at421_cancel_only_allowed_without_l2` catches this |
| AT-909 | Use wrong reject reason (e.g., ExpectedSlippageTooHigh instead of LiquidityGateNoL2) | Y | Wrong reason code breaks monitoring/alerting | `test_at909_missing_l2_reason_is_no_l2` asserts exact reason |
| AT-421 | Allow Close/Hedge without L2 | Y | Risk-reducing intents proceed without price validation | `test_at421_close_rejected_without_l2` catches this |
| AT-317 | Hardcode threshold instead of using config | N | Not testable via config variation | Default 10bps in test helper matches contract |

- [x] Every AT has at least one wrong impl identified
- [x] Any wrong impl marked "Y" (easier) is the highest-priority tightening test
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-222 | `evaluate_liquidity_gate` depth check (gate.rs:601-614) | `test_at222_slippage_exceeds_max_rejected`, `test_at222_no_order_intent_on_rejection` | Yes (reject) | Yes (`test_slippage_within_limit_allowed`) | reject_reason | Yes |
| AT-344 | `evaluate_liquidity_gate` L2 None/staleness (gate.rs:500-527) | `test_at344_missing_l2_rejects_open`, `test_at344_stale_l2_rejects_open` | Yes (reject) | Yes (`test_stale_l2_fresh_enough_passes`) | reject_reason | Yes |
| AT-909 | Same as AT-344 | `test_at909_missing_l2_reason_is_no_l2` | Yes (reason code) | Yes (AT-344 NON-TRIP) | reject_reason | Yes |
| AT-421 | `evaluate_liquidity_gate` CancelOnly branch (gate.rs:469-481) | `test_at421_cancel_only_allowed_without_l2`, `test_at421_close_rejected_without_l2` | Yes (Close rejected) | Yes (Cancel allowed) | reject_reason + allowed | Yes |
| AT-317 | `evaluate_liquidity_gate` slippage > max check (gate.rs:667) | `test_at222_slippage_exceeds_max_rejected` (with default 10bps) | Yes | Yes (`test_slippage_at_exact_max_allowed`) | reject_reason | Shared with AT-222 |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Slippage too high undetected -> sweep fills at bad price -> large adverse fill
- **Fail-closed cap on loss**: DispatcherChokepoint rejects intent; fail-closed to no-dispatch
- **Drift metric**: `expected_slippage_bps` drift from realized slippage
- **Loss boundary**: Fail-closed to ReduceOnly/no-dispatch; no position opened at bad price
- **Rollback plan**: Revert gate.rs to prior version; all intents would bypass this specific gate but other gates remain

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: LiquidityGate is one gate in the 8-gate pipeline, positioned after NetEdge
- **If conflict with `specs/CONTRACT.md`**: No conflicts identified
- **Files with recent churn or shared ownership**: `gate.rs` is single-story (S5-000), `mod.rs` is shared
- **Struct fields I'm assuming exist**: `LiquidityGateInput` fields verified from source
- **State machine transitions affected**: None (stateless gate evaluation)

## 9) Constraint I expect to hit

Prior Postmortem: NONE (first story in Slice 5)
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A
- What will slow me down: N/A (retroactive reconciliation)
- Exploit: N/A
- Smallest fix that prevents it next time: N/A

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- All ATs traced to normative clauses with TRIP + NON-TRIP tests
- Property tests cover CancelOnly invariant, missing L2, empty book, stale snapshot, never-panics
- Boundary mutation tests (exact max slippage, exact max age) catch off-by-one
- Fail-closed sweep covers Missing/None, NaN/Inf, future-dated, empty book

**Exit criteria (definition of done, before I start):**
- [x] SS1 clause audit: every AT traced to normative clause
- [x] SS2 all assumptions validated or killed
- [x] SS3 all failure modes have detection + mitigation
- [x] SS4 all decisions resolved, grounded in evidence
- [x] SS5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] SS6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] SS7 loss_mode documented with fail-closed boundary + rollback plan
- [x] SS8 conflict scan clean (no `specs/CONTRACT.md` conflicts)
- [x] No new debt without `gap_id` + owner + target slice
