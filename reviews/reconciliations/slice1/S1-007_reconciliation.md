---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_DISPATCH_reconciliation.md
story_id: S1-007
story_title: "Dispatcher mismatch rejection"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-007 (Dispatcher mismatch rejection)

## A) GATE RESULT

```
GATE: GO
Reason: Premortem §10 STOPLIGHT = YELLOW. Debt items tracked. Proceeding.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-920 | §1.0 Hard Rules #2-#4 | `crates/soldier_core/src/execution/dispatch_map.rs:179-224::validate_and_dispatch` | test_at920_mismatch_rejected (line 313), test_at920_consistent_contracts_passes (line 288), test_at920_mismatch_increments_counter (line 341), test_at920_no_dispatch_on_mismatch (line 565), test_at920_mismatch_caller_sets_degraded_and_blocks_open (line 596), test_at920_tolerance_constant (line 556), test_at920_within_tolerance_passes (line 501), test_at920_non_finite_multiplier_rejected (line 443), test_at920_epsilon_denominator_allows_small_amount_within_tolerance (line 418), test_at920_perpetual_mismatch_rejected (line 473), test_at920_delta_in_error (line 525) | Yes — dispatch_count remains 0 on mismatch; reject_reason == ContractsAmountMismatch; metric incremented; Degraded blocks subsequent OPEN | Yes — NaN/Inf fail-closed; missing multiplier fail-closed; tolerance formula handles edge cases | Yes (see §5 below) | Yes (see §4 below) | **PROVEN** |

### Enforcement point detail:
- `dispatch_map.rs:187-217`: AT-920 validation block
- `dispatch_map.rs:22`: `CONTRACTS_AMOUNT_MATCH_TOLERANCE = 0.001`
- `dispatch_map.rs:24`: `CONTRACTS_AMOUNT_MATCH_EPSILON = 1e-9`

### Fail-closed verification:
- NaN multiplier: **Rejected** (line 199) — tested (line 443)
- Missing contract_multiplier: **Rejected** (line 188) — tested (line 396)
- Epsilon prevents div-by-zero: **Handled** (line 207) — tested (line 418)
- No unwrap() in production code: **CONFIRMED**

### Causal proof analysis (safety gate):
- **TRIP**: `test_at920_mismatch_rejected` (line 313) + `test_at920_no_dispatch_on_mismatch` (line 565)
- **NON-TRIP**: `test_at920_consistent_contracts_passes` (line 288) + `test_at920_within_tolerance_passes` (line 501)
- **RiskState::Degraded**: `test_at920_mismatch_caller_sets_degraded_and_blocks_open` (line 596) — proves mismatch → Degraded → Open blocked at chokepoint

**NOTE**: validate_and_dispatch returns Err(ContractsAmountMismatch) but does NOT set RiskState::Degraded directly. Degraded is caller convention. Test at line 596 has TODO for production wiring verification.

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | contract_multiplier available and > 0 | Test multiplier=0 → reject | **TESTED**: None → Err (line 396). NaN → Err (line 443). Note: multiplier=0.0 not explicitly tested at dispatch level (upstream catches). |
| 2 | Tolerance formula uses relative error | Known-value formula test | **TESTED**: `test_at920_delta_in_error` (line 525): delta=|5-3|/3=0.6667 |
| 3 | epsilon=1e-9 prevents div-by-zero | Amount=0 with contracts>0 | **TESTED**: line 418 |
| 4 | RiskState::Degraded set atomically | Both in same response | **PARTIALLY**: Degraded is caller convention, not atomic with rejection |
| 5 | Mismatch check runs BEFORE dispatch | dispatch_count=0 | **TESTED**: line 565 (result.is_err()); line 648 (approved_total==0) |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Tolerance formula precision | A — f64, contract formula exactly | **YES** | dispatch_map.rs:206-208 |
| When only contracts OR amount present | A — Skip when contracts None | **YES** | dispatch_map.rs:187 |
| NaN handling | A — Fail-closed (treat as mismatch) | **YES** | dispatch_map.rs:199-204 |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Absolute tolerance instead of relative | **YES** | `test_at920_delta_in_error` (line 525) + epsilon test (line 418) | **YES** |
| Check tolerance but forget Degraded | **YES** | `test_at920_mismatch_caller_sets_degraded_and_blocks_open` (line 596) | **YES** |
| Set Degraded but still dispatch | **YES** | `test_at920_no_dispatch_on_mismatch` (line 565) | **YES** |
| Use wrong reject reason | **YES** | `test_at920_mismatch_rejected` (line 331-336): pattern matches `ContractsAmountMismatch` | **YES** |

## D) DESIGN RISK NOTES

- **PRD_FIX**: PRD says `UnitMismatch` but code/contract use `ContractsAmountMismatch`.
- **IMPORTANT**: validate_and_dispatch has **zero production callsites**. Guard is built and tested but not wired in. Test at line 586-593 documents this with TODO(AT-920-PROD).
- **IMPORTANT**: RiskState::Degraded is caller convention, not enforced by the function.
- **INFO**: Tolerance boundary (delta == 0.001 passes) uses `>` not `>=`. Matches contract.
- **INFO**: contract_multiplier=0.0 not tested at dispatch level (upstream catches).

## E) REMEDIATION PLAN

```
[PRD_FIX]   GAP-S1007-1: PRD reason_codes "UnitMismatch" → "ContractsAmountMismatch". P2.
[INFO]      GAP-S1007-2: validate_and_dispatch has zero production callsites. P1.
[INFO]      GAP-S1007-3: RiskState::Degraded is caller convention. P1.
[INFO]      GAP-S1007-4: contract_multiplier=0.0 not tested at dispatch level. P2.
```

## F) SCOPE CHECK

All scope.touch files exist. Minor drift: AT-920 tests consolidated in test_dispatch_map.rs rather than split with test_order_size.rs.

```
READY FOR SELF_REVIEW
```
