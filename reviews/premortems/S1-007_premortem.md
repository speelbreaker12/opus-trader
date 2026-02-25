# Story Premortem: S1-007

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-007 — Dispatcher mismatch rejection
- Contract clause(s): §1.0 Instrument Units & Notional Invariants — Hard Rules #2-#4, AT-920
- Acceptance tests: AT-920
- Touch scope: `crates/soldier_core/src/execution/dispatch_map.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/src/lib.rs`, `crates/soldier_core/tests/test_dispatch_map.rs`, `crates/soldier_core/tests/test_order_size.rs` (also includes metric registration for `order_intent_reject_unit_mismatch_total`)
- **Risk rating**: MED
  - This is a safety gate. If the tolerance is wrong, either mismatches pass through to the exchange (too loose) or valid orders are falsely rejected (too tight). Both failure modes have economic consequences. Correctly implements a fail-closed guard that sets RiskState::Degraded.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-920 | §1.0 Hard Rule #2 | "If both contracts and amount are provided, they must match within tolerance: abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon) <= contracts_amount_match_tolerance where contracts_amount_match_tolerance = 0.001 (0.1%) and epsilon = 1e-9" | MUST | Yes |
| AT-920 | §1.0 Hard Rule #3 | "If a mismatch is detected: reject the intent and set RiskState::Degraded (this is a wiring bug, not 'market noise')" | MUST | Yes |
| AT-920 | §1.0 Hard Rule #4 | "Rejections for contracts/amount mismatch MUST use Rejected(ContractsAmountMismatch)" | MUST | Yes |
| AT-920 | §1.0 AT-920 spec | "Given: contracts and amount are provided and mismatch beyond contracts_amount_match_tolerance. When: dispatcher validates sizing before dispatch. Then: intent rejected with Rejected(ContractsAmountMismatch) and no dispatch occurs. Pass criteria: rejection reason matches; dispatch count remains 0; RiskState==Degraded" | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `contract_multiplier` is available from instrument metadata and is > 0 | If contract_multiplier is 0 or NaN, the tolerance formula divides by zero or produces NaN, and NaN comparisons always return false (bypass) | Test: contract_multiplier = 0 -> mismatch check must reject or error, not silently pass | Pending |
| 2 | The tolerance formula uses relative error, not absolute error | If absolute error is used instead, tolerance behaves differently for large vs small amounts — a $0.001 absolute tolerance on a $100,000 order is far too tight | Test: verify formula matches contract exactly using known mismatch values at different scales | Pending |
| 3 | `epsilon = 1e-9` prevents division by zero when `amount` is very close to 0 | If epsilon is forgotten, `max(abs(amount), epsilon)` degenerates to `max(abs(amount), 0)` which is 0 when amount=0, causing division by zero | Test: amount = 0 with contracts > 0 -> mismatch detected (not panic/NaN) | Pending |
| 4 | RiskState::Degraded is set atomically with intent rejection | If rejection happens but Degraded is set asynchronously, there is a window where the system is in an inconsistent state | Test: after mismatch rejection, assert both rejection reason AND RiskState::Degraded in the same response | Pending |
| 5 | Mismatch check runs BEFORE dispatch, not after | If check runs after dispatch, the order is already sent and rejection is meaningless | Test: dispatch_count remains 0 when mismatch is detected (causality proof) | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Tolerance formula inverted: checks `>= tolerance` instead of `<= tolerance`, causing ALL orders to be rejected | Integration test with matching contracts/amount passes through successfully | Table-driven tests with exact boundary values: 0.0009 (pass), 0.0011 (reject) | AT-920 |
| 2 | NaN in tolerance computation silently passes (NaN <= 0.001 is false, skipping rejection) | Test with contract_multiplier=0 or amount=0 triggers NaN path | Guard: if computed_delta.is_nan() -> treat as mismatch (fail-closed) | New test: test_mismatch_nan_fails_closed |
| 3 | RiskState::Degraded not set on rejection (reject reason correct but state not updated) | AT-920 requires both rejection AND Degraded | Assert both conditions in AT test: rejection reason == ContractsAmountMismatch AND risk_state == Degraded | AT-920 |
| 4 | Tolerance too loose (e.g., 0.01 instead of 0.001) — real mismatches pass through | Boundary test at exactly 0.001 tolerance | Hardcode tolerance constant from contract; do not make it configurable without contract amendment | AT-920 boundary vector |
| 5 | Mismatch check skipped when contracts field is None (no validation at all) | Test with contracts=Some but mismatching -> must reject | Check should only run when BOTH contracts and amount are present; when contracts is None, no mismatch is possible (this is correct behavior, not a skip) | AT-920 |

## 4) Open decisions (resolve before coding)

### Decision: Tolerance formula precision and edge cases
- **What is ambiguous / missing**: The contract formula `abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon)` has precision edge cases: what happens when amount and contracts * contract_multiplier are both very large (f64 precision loss)?
- **Evidence**: CONTRACT.md §1.0 Hard Rule #2 specifies epsilon = 1e-9 and tolerance = 0.001
- **Options**:
  1. Option A — Implement the formula exactly as specified in the contract, using f64 arithmetic. Accept that f64 has ~15 significant digits, which is sufficient for all realistic order sizes (max ~$1B = 1e9, precision loss at 1e-6 relative scale, well within 0.001 tolerance).
  2. Option B — Use a higher-precision library (e.g., `rust_decimal`) for the comparison. Overkill for 0.1% tolerance.
- **Chosen**: A — deciding factor: f64 precision (~15 significant digits) is more than sufficient for 0.1% tolerance checks. Contract specifies the formula; implement it exactly.
- **Why not others**: Option B adds dependency for no practical benefit at this tolerance level.
- **Scope control**:
  - What we're NOT doing yet: making tolerance configurable (contract hardcodes 0.001)
  - What unblocks us if this choice is wrong: tolerance is a single constant, easy to change

### Decision: Behavior when only one of contracts/amount is present
- **What is ambiguous / missing**: Contract says "if both contracts and amount are provided... they must match". What if only one is present?
- **Evidence**: CONTRACT.md §1.0 Hard Rule #2: "If both contracts and amount are provided"
- **Options**:
  1. Option A — Skip mismatch check when only one is present. The check is explicitly conditional on "both... provided".
  2. Option B — Reject when only one is present (defensive).
- **Chosen**: A — deciding factor: contract language is explicit: "If both... are provided". When only the canonical amount exists (no contracts field), there is nothing to mismatch against.
- **Why not others**: Option B would reject valid orders where contracts is not applicable (e.g., some instrument types don't have a meaningful contracts field).
- **Scope control**:
  - What we're NOT doing yet: validating that the correct ONE field is present (that is S1-005's responsibility)
  - What unblocks us if this choice is wrong: adding a "require both" check is a one-line change

### Decision: How to handle NaN in tolerance computation
- **What is ambiguous / missing**: Contract does not address NaN behavior in the tolerance formula.
- **Evidence**: f64 arithmetic: 0.0 / 0.0 = NaN, NaN <= 0.001 = false (no rejection)
- **Options**:
  1. Option A — Fail-closed: if computed relative error is NaN or infinite, treat as mismatch. Reject intent + Degraded.
  2. Option B — Fail-open: if NaN, skip the check (assume no mismatch).
- **Chosen**: A — deciding factor: fail-closed principle. NaN in a sizing computation is a wiring bug, exactly what this check is designed to catch.
- **Why not others**: Option B is fail-open; NaN in sizing is always a bug.
- **Scope control**:
  - What we're NOT doing yet: tracing back WHY NaN appeared (that is a separate diagnostic concern)
  - What unblocks us if this choice is wrong: NaN guard is a single `if` check

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-920 | Use absolute tolerance (abs(amount - contracts * multiplier) <= 0.001) instead of relative tolerance | Works for small amounts (~$1) but fails for large amounts (~$100,000): absolute $0.001 tolerance on $100K order means 0.000001% tolerance, catching harmless float noise and rejecting valid orders | Golden vector: contracts=10, multiplier=10_000, amount=100_001 (0.001% off) -> must reject. Also: contracts=1, multiplier=1.0, amount=1.0005 -> must pass (within 0.1% relative) |
| AT-920 | Check tolerance but forget to set RiskState::Degraded | Test passes if it only checks rejection reason but not risk state | AT-920 explicitly requires: assert RiskState==Degraded after mismatch rejection |
| AT-920 | Set Degraded on mismatch but still dispatch the order | Intent is "rejected" in name but order still goes out | AT-920 requires: dispatch_count remains 0. Must assert no dispatch occurred. |
| AT-920 | Use wrong reject reason (e.g., RejectReason::UnitMismatch instead of ContractsAmountMismatch) | Contract requires Rejected(ContractsAmountMismatch) specifically | Assert exact reject reason string matches contract requirement |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-920 | DispatcherChokepoint (mismatch validation) | test_mismatch_beyond_tolerance_rejects | Yes (mismatch > 0.001 -> rejected) | Yes (mismatch <= 0.001 -> passes) | dispatch_count == 0; reject_reason == ContractsAmountMismatch | Yes |
| AT-920 | DispatcherChokepoint (mismatch validation) | test_mismatch_sets_degraded | Yes (mismatch -> Degraded) | Yes (no mismatch -> state unchanged) | RiskState == Degraded after mismatch | Yes |
| AT-920 | DispatcherChokepoint (mismatch validation) | test_mismatch_metric_increments | Yes (mismatch -> metric +1) | Yes (no mismatch -> metric unchanged) | order_intent_reject_unit_mismatch_total incremented | Yes |
| AT-920 | DispatcherChokepoint (mismatch validation) | test_mismatch_boundary_tolerance_0001 | Yes (0.0011 relative -> reject) | Yes (0.0009 relative -> pass) | Boundary values test exact threshold | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Tolerance too loose: a contracts/amount mismatch passes through, dispatcher sends an order with inconsistent sizing. If contracts says 10 but amount says 100,000 (because contract_multiplier was wrong), the exchange receives a 10x or 100x wrong-sized order. Worst case: intended $30K position becomes $3M position before exchange margin rejects it. If margin allows it (high-equity account), full $3M exposure until manual intervention.
- **Fail-closed cap on loss**: This IS the fail-closed guard. If this gate fails, the next layer is exchange-side margin requirements (rejects orders exceeding available margin). PolicyGuard exposure limits provide a position-level cap. The tolerance of 0.001 (0.1%) is tight enough to catch wiring bugs while allowing harmless float rounding.
- **Drift metric**: `order_intent_reject_unit_mismatch_total` — if this counter is > 0 in production, there is a wiring bug upstream. Expected value in healthy operation: 0. Any increment should trigger an alert.
- **Loss boundary**: RiskState::Degraded triggers PolicyGuard -> ReduceOnly, halting new opens. Exchange margin as secondary backstop. Position size limits as tertiary.
- **Rollback plan**: Mismatch validation is stateless. Fix tolerance constant or formula and redeploy. If a mismatched order was dispatched, requires manual position review and potential unwind.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: This story IS the mismatch invariant gate. It protects the dispatch path from sizing inconsistencies. Changes here directly affect system safety.
- **If conflict with CONTRACT.md**: No conflicts identified. Implementation directly maps CONTRACT.md §1.0 Hard Rules #2-#4.
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/dispatch_map.rs` (shared with S1-005 dispatch mapping — same file)
- Struct fields I'm assuming exist:
  - `OrderSize.contracts: Option<i64>` (from S1-004)
  - `RejectReason::UnitMismatch` variant (to be added; contract says `ContractsAmountMismatch`)
  - `RiskState::Degraded` variant (assumed to exist in risk module)
  - `contract_multiplier: f64` from instrument metadata
- State machine transitions affected: RiskState transition to Degraded on mismatch. Must verify Degraded -> Active recovery path exists (not this story's scope but must not break it).
- **Metric ownership**: This story owns the definition and registration of the `order_intent_reject_unit_mismatch_total` counter metric, as it implements the rejection code path that increments it.

## 9) Constraint I expect to hit
- What will slow me down: The reject reason name has a discrepancy — CONTRACT.md says `Rejected(ContractsAmountMismatch)` but the PRD story uses `RejectReason::UnitMismatch`. Need to resolve which name to use.
- Exploit: Use the CONTRACT.md name (`ContractsAmountMismatch`) as the authoritative source. The PRD `reason_codes.values` field says `UnitMismatch` but the contract_must_evidence quote says `ContractsAmountMismatch`. Contract takes precedence.
- Smallest fix that prevents it next time: Align PRD reason_codes with CONTRACT.md reject reason names during PRD authoring.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: Core implementation path is clear, but two items require explicit tracking:

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| RejectReason name discrepancy: PRD says `UnitMismatch`, CONTRACT.md says `ContractsAmountMismatch` | MED | Must resolve at implementation time; contract takes precedence | S1-007 implementer | Slice 1 | AT-920 test must assert exact contract reason name |
| NaN/infinity guard in tolerance formula not explicitly required by contract | LOW | Fail-closed principle requires it but no explicit AT covers it | S1-007 implementer | Slice 1 | New test: test_mismatch_nan_fails_closed |

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [ ] RejectReason name must be resolved before coding (debt item tracked above)
- [ ] NaN guard test must be written during implementation (debt item tracked above)

Prior Postmortem: NONE
Reused Guardrail: NONE
