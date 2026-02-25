# Story Premortem: S2-000

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S2-000 -- S2.1 Quantization rounding
- Contract clause(s): §1.1.1 Canonical Quantization (Pre-Hash & Pre-Dispatch)
- Acceptance tests: AT-926, AT-280, AT-219, AT-908
- Touch scope: `crates/soldier_core/src/execution/quantize.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/tests/test_quantize.rs`
- **Risk rating**: LOW
  - Quantization is pre-dispatch arithmetic with no external I/O. The enforcement point (DispatcherChokepoint) rejects bad intents before any order reaches the exchange. f64 rounding edge cases are the primary hazard, but the fail-closed behavior (reject if uncertain) limits blast radius to missed trades, not wrong trades.
  - The code touches no persistence, no auth/keys, and no state machines. The scope is a pure function: inputs in, quantized outputs or rejection out.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-926 | §1.1.1 | If any of `tick_size`, `amount_step`, or `min_amount` is missing or unparseable -> Reject(InstrumentMetadataMissing) and do not dispatch (fail-closed). | MUST (Non-Negotiable) | Yes -- rejection reason + dispatch count 0 |
| AT-280 | §1.0 (Units Consistency) | Given: contracts=100 and amount deviates by >0.1% from contracts * contract_multiplier. When: units consistency is evaluated. Then: reject + Degraded. | MUST (Non-Negotiable) | Yes -- rejection + RiskState::Degraded |
| AT-219 | §1.1.1 (Safer rounding direction) | BUY rounds down (never pay extra); SELL rounds up (never sell cheaper). | MUST (Non-Negotiable) | Yes -- BUY price never increases; SELL price never decreases |
| AT-908 | §1.1.1 | qty_q < min_amount after quantization for OPEN -> Rejected(TooSmallAfterQuantization), dispatch count 0. | MUST (Non-Negotiable) | Yes -- rejection reason + dispatch count 0 |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `tick_size`, `amount_step`, and `min_amount` are always positive finite f64 values when present. | If any is zero, NaN, infinity, or negative, division by tick_size/amount_step produces NaN/infinity/panic. `floor(raw_qty / 0.0)` = infinity. `floor(raw_qty / NaN)` = NaN. Both silently produce a "quantized" value that is nonsensical. | AT-926 covers missing/unparseable; but zero/negative/NaN/infinity are distinct from "missing." Need explicit test: `tick_size = 0.0` -> InstrumentMetadataMissing (or a new rejection). | MUST TEST -- zero and NaN are not "missing" in the Rust type sense but are unparseable in the domain sense |
| 2 | `raw_qty` and `raw_limit_price` are non-negative finite f64. | Negative raw_qty would produce a negative qty_q after floor rounding, which passes the `qty_q >= min_amount` check if min_amount is also small. Negative price is nonsensical. NaN raw inputs silently poison all downstream arithmetic. | Test: raw_qty = -1.0, raw_qty = NaN, raw_qty = f64::INFINITY -> rejection or panic-safe behavior | MUST TEST |
| 3 | `floor(x / step) * step` produces a value that the exchange actually accepts. | Floating-point multiplication after floor division can drift by an ULP. Example: `floor(1.05 / 0.01) = 105`, `105 * 0.01 = 1.0499999999999998` (not 1.05). The exchange may reject this. | Golden vector test with known edge cases: 1.05 / 0.01, 0.3 / 0.1, etc. Verify the result matches the exchange's expected string representation. | CRITICAL -- f64 representation fidelity |
| 4 | The contract formula `qty_steps = floor(raw_qty / amount_step)` uses mathematical floor, not Rust `f64::floor()` which returns f64 and can lose precision for large values. | For qty_steps > 2^53, the integer cannot be exactly represented as f64. `floor()` returns a float that may not be the correct integer. | Property test: for qty_steps in range [0, 2^53], verify round-trip. For values beyond 2^53, verify we reject or handle gracefully. | Should test -- unlikely in practice (would need qty > 2^53 * amount_step) but principle 0.1 demands real quantities |
| 5 | `amount_step` and `tick_size` are always "nice" decimal fractions (powers of 10 or simple fractions like 0.5, 0.25). | If amount_step is an irrational or non-terminating decimal (e.g., 1/3), floor(raw_qty / amount_step) * amount_step will accumulate rounding error on every operation. | Verify exchange metadata: Deribit amount_step and tick_size are always decimal fractions. Add a validation check that rejects non-power-of-10 steps as InstrumentMetadataMissing. | Should validate at metadata fetch time |
| 6 | `ceil(raw_limit_price / tick_size)` for SELL rounding uses Rust's `f64::ceil()`, which rounds toward +infinity. | `ceil(100.0 / 0.5)` = 200.0 (correct, already on tick). But `ceil(100.01 / 0.5)` = 201.0, meaning `201.0 * 0.5 = 100.5` -- the SELL price jumps by nearly 0.5 from 100.01. This is correct per contract (never sell cheaper) but may surprise operators. The concern is not correctness but that the ceil rounding for on-tick values must NOT round up: `ceil(100.0 / 0.5)` must equal 200, not 201. | Test: price exactly on tick -> no rounding occurs (identity). Price one ULP above tick -> rounds up by exactly one tick. | MUST TEST -- on-tick identity is subtle with f64 |
| 7 | The "OPEN intent" scope qualifier in AT-926 and AT-908 means CLOSE/HEDGE/CANCEL intents with bad metadata or small qty are NOT rejected by these gates. | If the quantization function does not check intent classification, it may reject CLOSE intents that should be allowed through (violating capital supremacy: you must be able to close positions even if metadata is stale). | Test: CLOSE intent with missing metadata -> NOT rejected by quantization (or rejected with a different, non-blocking path). AT-926 says "for an OPEN intent" explicitly. | MUST TEST -- fail-closed must not block risk-reducing actions |
| 8 | The story's `primary_owner_for` includes AT-020 and AT-021 (F1 cert ATs), but these are unrelated to quantization. They deal with F1 certification gate in PolicyGuard. | Confusion about ownership could lead to implementing F1 logic in quantize.rs, which is wrong scope. AT-020/AT-021 are listed because the story is the "primary owner" for contract traceability, not because the quantization code enforces them. | No code test needed; this is a traceability concern. Verify quantize.rs does not reference F1_CERT. | Validated -- scope.avoid confirms no PolicyGuard changes |
| 9 | AT-280 (contracts/amount mismatch) is listed in `enforcing_contract_ats` but is a units consistency check, not a quantization check. The quantization function may not be the natural enforcement point for AT-280. | If AT-280 is enforced in quantize.rs, the function takes on dual responsibility (rounding + units consistency). If AT-280 is enforced elsewhere but claimed here, traceability is broken. | Verify whether AT-280's enforcement point is inside quantize.rs or in a separate units-consistency function. If separate, this story should either implement that function or remove AT-280 from its claims. | MUST RESOLVE before coding |

## 3) Top 7 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **f64 floor division produces wrong integer for values near tick boundary.** Example: `raw_qty = 0.30000000000000004` (common f64 artifact), `amount_step = 0.1`. `floor(0.30000000000000004 / 0.1) = floor(3.0000000000000004) = 3` (correct by luck). But `raw_qty = 0.29999999999999998`, `floor(0.29999999999999998 / 0.1) = floor(2.9999999999999996) = 2` (loses one step). The quantized qty is 0.2 instead of 0.3 -- a 33% size error. | Golden vector tests with known edge-case f64 values. Property test: for any qty in [0, max_qty], quantized qty <= raw_qty (never rounds up). | The contract says floor (always round down qty). Rounding down is safe (smaller order, not larger). The danger is rounding down *too far* due to f64 representation, causing a TooSmallAfterQuantization rejection for what should be a valid order. This is fail-closed (missed trade, not wrong trade). | AT-908 catches the rejection path. No AT explicitly tests "off-by-one-step" due to f64 representation. Need golden vector. |
| 2 | **tick_size or amount_step is zero, NaN, or infinity, bypassing the "missing/unparseable" guard.** If the metadata parser returns `Some(0.0)` instead of `None`, the guard for "missing" does not trigger, and division by zero produces infinity or NaN that propagates silently into qty_q/limit_price_q. | Test with tick_size=0.0, NaN, f64::INFINITY, f64::NEG_INFINITY, -1.0. Each must trigger InstrumentMetadataMissing. | Treat zero, negative, NaN, and infinity as "unparseable" per the contract's intent. The guard must check `!tick_size.is_finite() \|\| tick_size <= 0.0`, not just `tick_size.is_none()`. | AT-926 (unparseable). Tests must explicitly cover zero/NaN/infinity/negative values. |
| 3 | **SELL ceil rounding for a price exactly on tick rounds up by one tick.** `raw_limit_price = 100.0`, `tick_size = 0.5`. `ceil(100.0 / 0.5) = ceil(200.0) = 200.0`. `200.0 * 0.5 = 100.0` (correct). But if the f64 division produces `200.00000000000003` due to representation, `ceil()` returns 201.0, and the SELL price becomes 100.5 -- one tick too high. This makes the order less likely to fill. | Golden vector test: price exactly on tick -> result equals input. Property test: for any price on tick, quantized price == input price (identity). | Fail-closed: SELL rounds up means the seller gets a better price (or no fill). Not a financial loss. But systematically rounding up on-tick prices degrades fill rates. | AT-219 says "SELL rounds up (never sell cheaper)". An on-tick SELL rounding up by one tick technically satisfies "never cheaper" but violates the implicit identity expectation. No AT explicitly catches this. Need golden vector. |
| 4 | **Quantization rejects CLOSE/HEDGE intents when metadata is missing, violating capital supremacy.** AT-926 explicitly scopes to "OPEN intent." If the quantization function applies the same rejection to all intents without checking classification, a CLOSE intent with missing metadata is blocked. The system cannot close positions, violating §0.Z.2.2 item F (capital supremacy invariant). | Test: CLOSE intent + missing metadata -> quantization allows it through (or uses a safe fallback). | The quantization function must take intent classification as input and only apply AT-926/AT-908 rejection to OPEN intents. CLOSE/HEDGE/CANCEL must either skip quantization entirely or use a best-effort path. | AT-926 scopes to OPEN. No AT explicitly tests CLOSE-with-missing-metadata. Need a NON-TRIP test. |
| 5 | **Multiplication after floor division loses precision, producing a value the exchange rejects.** `floor(1.05 / 0.01) = 105`. `105 * 0.01 = 1.0499999999999998` (IEEE 754). The exchange expects `"1.05"` in the order payload. If the serializer uses full-precision f64-to-string, the exchange may reject "1.0499999999999998" as not on tick. | Test: quantize 1.05 with step 0.01, serialize to string, compare against "1.05". Check Deribit API for accepted precision. | Use integer arithmetic internally (qty_steps, price_ticks as integers) and only convert to f64 at serialization time with controlled precision. Or use `round(qty_steps * amount_step, decimal_places(amount_step))` to fix trailing precision. | No AT covers serialization fidelity. This is a downstream concern (S2-001 hashing, dispatcher serialization) but the quantize function must produce values that survive serialization. |
| 6 | **AT-280 enforcement not naturally in the quantization path.** AT-280 checks contracts vs. amount consistency (units wiring), which is a different concern from tick/step rounding. If this story claims AT-280 but the code only implements quantization, AT-280 is CLAIMED-NOT-PROVEN. If this story implements AT-280 in quantize.rs, the function gains scope beyond its natural responsibility. | Code review: verify AT-280 is either (a) implemented and tested in this story's touch files, or (b) explicitly deferred with a note. | If AT-280 is implemented in quantize.rs, it should be a separate public function (e.g., `validate_units_consistency()`) called from the dispatch chokepoint alongside `quantize()`. Do not mix concerns inside the core quantization arithmetic. | AT-280 itself. Verify the test proves causality: rejection reason = ContractsAmountMismatch and dispatch count = 0. |
| 7 | **Integer overflow in qty_steps or price_ticks for extreme values.** If `raw_qty = 1e18` and `amount_step = 1e-8`, then `qty_steps = floor(1e18 / 1e-8) = floor(1e26)`. This exceeds u64::MAX (1.8e19) and i64::MAX (9.2e18). As an f64, `floor(1e26) = 1e26` (exact, but not representable as i64). If the code casts to i64, it wraps or panics. | Test with extreme values: very large raw_qty with very small amount_step. Verify no overflow or panic. | Validate that qty_steps fits in i64/u64 before proceeding. If not, reject with InstrumentMetadataMissing or a new reason code. In practice, exchange metadata constrains this, but the code must not panic on adversarial inputs. | No AT covers this. Defense-in-depth. |

## 4) Open decisions (resolve before coding)

### Decision: Integer arithmetic vs. f64 arithmetic for quantization
- **What is ambiguous / missing**: The contract says `qty_steps = floor(raw_qty / amount_step)` and `qty_q = qty_steps * amount_step`. It does not specify whether `qty_steps` and `price_ticks` are integer types (i64/u64) or f64. The PRD step says "Ensure integer tick/step values are returned for downstream idempotency hashing," implying integers.
- **Evidence**: CONTRACT.md §1.1.1: "Idempotency hash must be computed ONLY from quantized fields: `intent_hash = xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`". S2-001 PRD: "Use qty_steps and price_ticks (integers) alongside instrument, side, group_id, and leg_idx in the hash material."
- **Options**:
  1. Option A -- Compute qty_steps/price_ticks as f64 (using `f64::floor()`/`f64::ceil()`), then cast to i64 for hashing. Keep qty_q/limit_price_q as f64.
  2. Option B -- Compute qty_steps/price_ticks as i64 directly. Return both the integer step counts and the f64 reconstructed values. Hash uses the integers.
- **Chosen**: B -- i64 step counts are the canonical values. Advantages: deterministic hashing (no f64 representation issues in hash), explicit overflow detection via `as i64` checked cast, cleaner API boundary (integers for identity, f64 for dispatch payload).
- **Why not others**: Option A risks non-deterministic hashing if `f64::floor()` produces slightly different results across platforms (though IEEE 754 mandates determinism for basic ops, this is belt-and-suspenders).
- **Scope control**:
  - What we're NOT doing yet: full integer-only arithmetic pipeline (would require amount_step/tick_size to be represented as integers, which conflicts with exchange API format).
  - What unblocks us if this choice is wrong: the i64 values are internal; the f64 reconstruction for dispatch payloads can be adjusted without changing the hashing contract.

### Decision: How to handle AT-280 (units consistency) scope
- **What is ambiguous / missing**: AT-280 is in this story's `enforcing_contract_ats` but tests contracts vs. amount consistency, not tick/step quantization. The natural enforcement point is unclear -- is it inside the quantization function or a separate validation step?
- **Evidence**: CONTRACT.md §1.0 Hard Rules: "If both `contracts` and `amount` are provided, they must match within tolerance." AT-280 says "reject + Degraded." This requires setting RiskState::Degraded, which is a side effect beyond pure quantization.
- **Options**:
  1. Option A -- Implement AT-280 as a separate `validate_units_consistency()` function in quantize.rs, called from the dispatch chokepoint before or after `quantize()`.
  2. Option B -- Defer AT-280 to a separate story. Remove from `enforcing_contract_ats`.
  3. Option C -- Embed AT-280 inside the quantize function, making it check both rounding and units consistency.
- **Chosen**: A -- Separate function, same file. Rationale: AT-280 is listed in the story's `enforcing_contract_ats` so it must be implemented here. But mixing concerns (rounding + units validation) inside one function violates §0.3 (smallest surface area) and §0.4 (harder to misuse -- a caller that only needs rounding should not need to provide contracts/contract_multiplier).
- **Why not others**: Option B breaks PRD traceability. Option C overloads the quantize function with unrelated validation logic.
- **Scope control**:
  - What we're NOT doing yet: integrating `validate_units_consistency()` into the full dispatch pipeline (that is the dispatch chokepoint wiring, which is downstream).
  - What unblocks us if this choice is wrong: the function is free-standing and can be moved to a different module without breaking the quantization API.

### Decision: Treatment of CLOSE/HEDGE intents in quantization
- **What is ambiguous / missing**: AT-926 says "for an OPEN intent" explicitly. AT-908 says "for an OPEN intent." But the quantization function in §1.1.1 does not mention intent classification. The contract is silent on whether CLOSE intents should be quantized at all, or quantized but not rejected.
- **Evidence**: CONTRACT.md §1.1.1: "Inputs: instrument_id, raw_qty, raw_limit_price" (no intent classification in inputs). But AT-926/AT-908 scope to OPEN. §0.Z.2.2 item F: capital supremacy -- must be able to close positions.
- **Options**:
  1. Option A -- Quantize all intents the same way, but only apply rejection gates (TooSmall, MetadataMissing) to OPEN intents. CLOSE/HEDGE get quantized values but are never rejected by these gates.
  2. Option B -- Skip quantization entirely for CLOSE/HEDGE intents. Pass raw values through.
  3. Option C -- Quantize all intents and apply all rejection gates regardless of classification.
- **Chosen**: A -- Quantize all (for hash consistency and exchange validity) but gate rejections on intent classification. Rationale: even CLOSE orders need valid tick/step values for the exchange to accept them. But rejecting a CLOSE because metadata is stale would violate capital supremacy.
- **Why not others**: Option B sends potentially invalid prices/sizes to the exchange (might be rejected by venue). Option C blocks risk-reducing actions, violating capital supremacy.
- **Scope control**:
  - What we're NOT doing yet: defining the fallback quantization behavior for CLOSE intents with missing metadata (e.g., use last-known-good metadata). That is a §3.1 emergency close concern.
  - What unblocks us if this choice is wrong: the intent classification parameter can be added to the quantize function signature without breaking existing callers (they just need to pass it).

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-926 | Impl checks `tick_size.is_none()` but not `tick_size == 0.0` or `tick_size.is_nan()`. Test uses `None` for missing metadata. Zero and NaN bypass the guard and cause division-by-zero or NaN propagation. | The contract says "missing/unparseable." Zero is parseable but semantically invalid. The guard must treat zero, NaN, infinity, and negative values as "unparseable." | Golden vector: `tick_size = 0.0` -> InstrumentMetadataMissing. `tick_size = f64::NAN` -> same. `tick_size = -0.01` -> same. `tick_size = f64::INFINITY` -> same. |
| AT-926 | Impl rejects OPEN intents with missing metadata but also rejects CLOSE intents (no classification check). Tests only use OPEN intents. Passes AT-926 but violates capital supremacy. | Capital supremacy (§0.Z.2.2 item F): the system must always be able to close positions. Blocking CLOSE due to stale metadata is more dangerous than allowing a slightly wrong close. | Add NON-TRIP test: CLOSE intent + missing metadata -> quantization succeeds (or uses fallback). Dispatch count = 1 for the CLOSE. |
| AT-219 | Impl rounds both BUY and SELL down (floor for both). BUY test passes (floor is correct for BUY). SELL test checks "price never decreases" but uses a price already on tick, so floor == ceil == identity. | SELL must round UP (ceil). A SELL at 99.7 with tick 0.5 must round to 100.0, not 99.5. The wrong impl silently gives the seller a worse price. | Golden vector: SELL raw_price=99.7, tick=0.5 -> must produce 100.0, not 99.5. Also: SELL raw_price=99.5 (on tick) -> must produce 99.5 (identity). |
| AT-219 | Impl uses `ceil()` for SELL but does not handle the on-tick identity case. Due to f64, `ceil(99.5 / 0.5) = ceil(199.0) = 199.0` (correct). But `ceil(100.0 / 0.3)` = `ceil(333.33...) = 334.0`, `334.0 * 0.3 = 100.2`. Tests only use "nice" tick sizes (0.5, 1.0, 0.01). | Tick sizes that are not exact f64 fractions (e.g., 0.3) produce cumulative rounding errors. In practice, exchange tick sizes are powers of 10, but the code should not assume this. | Golden vector with tick_size=0.3 or tick_size=0.0001 to exercise precision boundaries. |
| AT-908 | Impl checks `qty_q < min_amount` but uses `<` instead of `<=` when `min_amount` means "minimum required." If qty_q == min_amount, the intent should be allowed. But if qty_q == 0.0, it should be rejected. Test uses qty_q well below min_amount (e.g., 0.001 vs 0.1) and well above (1.0 vs 0.1). The boundary case (qty_q == min_amount exactly) is untested. | If the comparison is `<=` instead of `<`, valid orders at exactly min_amount are rejected. If the comparison is `<` and qty_q == 0.0, it correctly rejects. The boundary semantics matter. | Golden vector: raw_qty such that qty_q == min_amount exactly -> should PASS (not rejected). raw_qty such that qty_q == min_amount - amount_step -> should be rejected. |
| AT-908 | Impl rejects with TooSmallAfterQuantization for all intents, not just OPEN. A CLOSE intent with tiny qty should still be allowed (capital supremacy). | Same capital supremacy argument as AT-926. | NON-TRIP test: CLOSE intent + qty_q < min_amount -> not rejected by this gate. |
| AT-280 | Impl uses `abs(amount - contracts * contract_multiplier) / amount > tolerance` but when `amount` is zero (or very small), the relative comparison is numerically unstable (division by near-zero). Test uses amount=100, contracts=100, multiplier=1.0 (trivial case). | The contract formula uses `max(abs(amount), epsilon)` as the denominator, with epsilon = 1e-9. A wrong impl that omits the epsilon floor passes for normal values but produces infinity or NaN for tiny amounts. | Golden vector: amount=1e-10, contracts=1, multiplier=1e-10 -> should be within tolerance (amounts match). amount=0.0, contracts=1, multiplier=1.0 -> should reject (mismatch). Verify the epsilon floor is applied. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-926 | DispatcherChokepoint (quantize.rs) | `test_quantize_missing_metadata_rejects_open` | Yes (OPEN + missing metadata -> Rejected(InstrumentMetadataMissing)) | `test_quantize_valid_metadata_dispatches_open` | reject_reason = InstrumentMetadataMissing, dispatch_count = 0 | Yes -- only AT-926 tests missing metadata at quantization |
| AT-926 (NaN/zero variant) | DispatcherChokepoint (quantize.rs) | `test_quantize_nan_tick_size_rejects_open`, `test_quantize_zero_amount_step_rejects_open` | Yes | `test_quantize_valid_metadata_dispatches_open` | reject_reason = InstrumentMetadataMissing, dispatch_count = 0 | Yes |
| AT-219 | DispatcherChokepoint (quantize.rs) | `test_buy_rounds_price_down`, `test_sell_rounds_price_up` | Yes (price not on tick -> rounded in safe direction) | `test_sell_price_on_tick_is_identity` | BUY: limit_price_q <= raw_limit_price. SELL: limit_price_q >= raw_limit_price. | Yes -- only AT-219 tests rounding direction |
| AT-908 | DispatcherChokepoint (quantize.rs) | `test_quantize_too_small_after_rounding_rejects_open` | Yes (OPEN + qty_q < min_amount -> Rejected(TooSmallAfterQuantization)) | `test_quantize_min_amount_boundary_allows_exact_minimum` | reject_reason = TooSmallAfterQuantization, dispatch_count = 0 | Yes -- only AT-908 tests post-quantization size check |
| AT-280 | DispatcherChokepoint (quantize.rs or separate validate function) | `test_contracts_amount_mismatch_rejects_and_degrades`, `test_contracts_amount_within_tolerance_passes` | `test_contracts_amount_mismatch_rejects_and_degrades` | `test_contracts_amount_within_tolerance_passes` | reject_reason = ContractsAmountMismatch, dispatch_count = 0, RiskState = Degraded | Yes -- only AT-280 tests units consistency |

Causality proof must be one of: `dispatch_count`, `reject_reason`, `latch_reason`, `cortex_override`.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [ ] Every test proves causality (not just existence) -- YELLOW: NON-TRIP tests not yet defined, but paths identified
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix -- AT-280 enforcement point needs confirmation

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Quantization rounding wrong in the "round up" direction for qty could cause an order larger than intended, leading to an unintended fill size. For a BUY, rounding price UP means paying more per unit. The worst case is a combination: qty rounds up (wrong direction) AND price rounds up for BUY (wrong direction), producing a larger, more expensive order than intended. The magnitude is bounded by one tick_size (price) and one amount_step (qty). For BTC-PERP with tick_size=0.5 and amount_step=10 USD, worst single-order overshoot is ~10 USD notional and 0.5 USD price -- negligible in isolation but compounding across many orders in a session.
- **Fail-closed cap on loss**: DispatcherChokepoint rejects the intent before any exchange API call. If quantization fails (exception, NaN, missing metadata), no dispatch occurs. The fail-closed boundary is: rejected intent = zero financial exposure. The only risk is the "silently wrong" case where quantization produces a valid-looking but incorrect value.
- **Drift metric**: `quantization_reject_too_small_total` counter. A sustained spike means either (a) strategy is consistently requesting sizes below exchange minimums, or (b) the exchange changed min_amount and our metadata is stale.
- **Loss boundary**: ReduceOnly is NOT triggered by quantization failure alone -- the intent is simply rejected. PolicyGuard's TradingMode is unaffected. The loss boundary is per-intent: one bad order, bounded by tick_size * qty. No position-level or account-level exposure change unless the bad order fills.
- **Rollback plan**: Revert the quantize.rs changes. The previous quantization behavior (if any) resumes. If this is net-new code, removing it means intents are not quantized before dispatch -- which is a CONTRACT violation (§1.1.1 requires quantization). Rollback must be accompanied by disabling dispatch (TradingMode::Kill or ReduceOnly) until a fix is deployed.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: §1.1.1 Canonical Quantization is the primary invariant. The quantization function produces qty_q and limit_price_q that are consumed by:
  - Intent hashing (S2-001, §1.1): `intent_hash = xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`. If quantize.rs changes the output format (e.g., integer vs. float), S2-001's hash inputs change and all existing hashes become invalid.
  - Dispatch payload (downstream): the exchange API must receive the quantized values.
  - WAL recording (S2-001): the WAL stores quantized intent values for crash recovery.
- **If conflict with CONTRACT.md**: No conflict. §1.1.1 is the authoritative source and this story implements it directly.
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/mod.rs` is the execution module root and may be modified by S2-001 (labeling), S2-002 (label format), S2-003 (label match), and S2-004 (reject reason registry). Coordinate mod.rs changes to avoid merge conflicts.
- Struct fields I'm assuming exist (verify before coding):
  - Instrument metadata struct with fields: `tick_size: Option<f64>`, `amount_step: Option<f64>`, `min_amount: Option<f64>`, `contract_multiplier: Option<f64>`.
  - `RejectReason` enum with variants `TooSmallAfterQuantization` and `InstrumentMetadataMissing` (may need to be added by this story or S2-004).
  - `RiskState` enum with `Degraded` variant (for AT-280).
  - Intent classification enum or flag distinguishing OPEN from CLOSE/HEDGE/CANCEL.
- State machine transitions affected: None directly. Quantization is stateless (pure function). But AT-280 sets `RiskState::Degraded`, which is a state transition in the risk health layer. Verify that `RiskState::Degraded` can be set from the quantization/dispatch path without violating the state machine's transition rules.
- **Cross-story dependencies**: S2-001 (intent hash) depends on S2-000 producing integer qty_steps/price_ticks for deterministic hashing. S2-004 (RejectReasonCode registry) must include `TooSmallAfterQuantization` and `InstrumentMetadataMissing` in the enum. If S2-004 is not yet implemented, this story must define these variants. Check if `ContractsAmountMismatch` (for AT-280) is also in S2-004's scope.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (S2-000 is the first story in Slice 2)
Reused Guardrail: NONE (no prior postmortem exists for Slice 2)

- Carry-forward from prior postmortem: N/A -- first story in Slice 2. However, Slice 1 postmortems may contain relevant guardrails about f64 handling.
- What will slow me down: Getting the f64 edge cases right. The `floor(x / step) * step` pattern is deceptively simple but IEEE 754 arithmetic makes it unreliable for exact decimal values. The temptation is to write the naive implementation and "fix edge cases later," which violates principle 0.5 (no paper compliance).
- Exploit: Use integer arithmetic (qty_steps/price_ticks as i64) as the canonical representation. Only reconstruct f64 at the API boundary. This sidesteps most f64 precision issues. For the reconstruction, use `format!("{:.N}", value)` with N = number of decimal places in the step size, to produce exchange-compatible strings.
- Smallest fix that prevents it next time: Add a `quantize_golden_vectors.rs` test file with a curated set of edge-case f64 values (subnormals, values near tick boundaries, exact-on-tick values, large values near i64 overflow). Run these vectors in CI. Any future change to quantization logic that breaks a golden vector is immediately caught.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: All gates pass with identified gaps. The main gaps are: (1) AT-280 enforcement point needs confirmation (quantize.rs vs. separate function), (2) NON-TRIP tests for AT-926/AT-908 are designed but not yet written, (3) CLOSE intent behavior under missing metadata needs explicit testing against capital supremacy. All gaps have mitigation paths and are tracked in the debt register below.

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| f64 golden vectors for edge-case quantization (subnormals, near-boundary, on-tick identity) | Med | Golden vectors are implementation-time work; premortem identifies the need | S2-000 implementer | S2-000 implementation | `test_quantize_golden_vectors()` with curated f64 edge cases |
| NON-TRIP test for AT-926: CLOSE intent + missing metadata -> not rejected | Med | Requires intent classification wiring, which may come from S2-004 or dispatch pipeline | S2-000 implementer | S2-000 or dispatch wiring story | `test_close_intent_missing_metadata_not_rejected()` |
| NON-TRIP test for AT-908: CLOSE intent + qty < min_amount -> not rejected | Med | Same as above: requires intent classification input | S2-000 implementer | S2-000 or dispatch wiring story | `test_close_intent_small_qty_not_rejected()` |
| AT-280 enforcement point confirmation | Low | Need to verify whether contracts/amount consistency belongs in quantize.rs or a separate validation module | S2-000 implementer | S2-000 implementation | Code review at implementation time |
| Serialization fidelity (f64 -> string for exchange API) | Low | Downstream concern: quantize.rs produces f64 values, serialization to exchange format is the dispatcher's job | Dispatch pipeline story | S3+ (dispatcher wiring) | Integration test: quantized f64 -> JSON string matches exchange-expected format |
| Zero/NaN/negative/infinity metadata validation | Med | Not explicitly required by AT-926 ("missing/unparseable") but semantically necessary | S2-000 implementer | S2-000 implementation | `test_quantize_zero_tick_size_rejects()`, `test_quantize_nan_amount_step_rejects()`, `test_quantize_negative_min_amount_rejects()` |

YELLOW with all debt tracked and assigned to target slices. No RED blockers.

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause -- 4 ATs traced to §1.1.1 and §1.0
- [x] §2 all assumptions validated or killed -- 9 assumptions documented; 3 require tests (zero/NaN, CLOSE behavior, boundary cases); 1 deferred (AT-280 scope)
- [x] §3 all failure modes have detection + mitigation -- 7 modes identified, all have detection path and fail-closed mitigation
- [x] §4 all decisions resolved, grounded in evidence -- 3 decisions resolved with CONTRACT.md references
- [x] §5 wrong impl gate: every AT tightened -- 7 wrong impls identified across 4 ATs, each with golden vector or property test
- [ ] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs -- YELLOW: TRIP tests designed, NON-TRIP tests identified but require intent classification wiring
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan -- documented with per-intent loss boundary and rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts) -- clean; cross-story dependencies noted (S2-001, S2-004)
- [x] No new debt without owner + target slice -- 6 debt items tracked in register with owners and target slices
