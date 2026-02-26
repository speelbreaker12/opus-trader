# Story Premortem: S1-009

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-009 — Dispatcher mapping discovery
- Contract clause(s): §1.0 Dispatcher Rules (Deribit request mapping)
- Acceptance tests: AT-277, AT-920 (informational references — discovery feeds future stories, no enforcement in this story)
- Touch scope: `docs/dispatch_map_discovery.md` (documentation only)
- **Risk rating**: LOW
  - Discovery/documentation only — no code changes, no runtime behavior, no safety gates touched.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-277 | §1.0 Dispatcher Rules | "Given: instrument_kind=option with qty_coin=0.3... When: the dispatcher maps request fields. Then: outbound option uses amount=qty_coin=0.3, qty_usd is unset; outbound perp uses amount=30_000 (USD)..." | MUST | Yes — but tested in implementation story, not this discovery story |
| AT-920 | §1.0 Dispatcher Rules | "Given: contracts and amount are provided and mismatch beyond contracts_amount_match_tolerance. When: the dispatcher validates sizing before dispatch. Then: the intent is rejected with Rejected(ContractsAmountMismatch) and no dispatch occurs." | MUST | Yes — but tested in implementation story, not this discovery story |

Note: Same ATs as S1-008 but scoped to dispatcher mapping (how outbound amount fields are chosen) rather than OrderSize struct fields. The ATs are enforced in S1-004/S1-005 (canonical sizing, dispatcher amount mapping) for AT-277 and S1-007 (dispatcher mismatch rejection) for AT-920.

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The current codebase has some dispatcher/order-sending logic to discover | If no dispatch logic exists yet, the report says "not yet implemented" | Report content review | N/A — discovery |
| 2 | CONTRACT.md §1.0 Dispatcher Rules are stable | If contract changes, discovery report becomes stale | Report references contract anchors for traceability | Pre-req |
| 3 | S1-008 (OrderSize discovery) and S1-009 have clear scope boundaries | Overlapping reports cause confusion | S1-008 covers OrderSize struct fields; S1-009 covers dispatcher mapping (outbound amount selection) | Scope guard |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Report omits the outbound amount field selection rule for one or more instrument_kind variants (e.g., options use qty_coin, perps use qty_usd) | Dispatcher sends wrong amount field for that instrument kind | Report must enumerate every instrument_kind and its outbound amount field with contract evidence | Future AT-277 |
| 2 | Report covers amount selection but omits reduce_only mapping (how reduce_only flag affects the outbound request) | Reduce-only orders dispatched with wrong parameters | Report must include a reduce_only mapping section showing how the flag translates to outbound fields | Future AT-277 |
| 3 | Report omits the contracts/amount consistency check and its tolerance value (contracts_amount_match_tolerance) | Mismatch rejection gap not surfaced; S1-007 implementation may use wrong tolerance | Report must detail the mismatch check: formula, tolerance value, and rejection outcome per AT-920 | Future AT-920 |
| 4 | Report is written but never read before dispatcher implementation | Discovery value lost | PRD dependency chain links S1-004/S1-005/S1-007 back to this discovery | Process |
| 5 | Report conflates OrderSize struct field definitions (S1-008 territory) with outbound dispatch mapping | Scope overlap; duplicate/conflicting analysis | Scope guard: "outbound dispatch mapping and consistency checks only — not OrderSize struct fields" | Review gate |

## 4) Open decisions (resolve before coding)

### Decision: Scope boundary with S1-008
- **What is ambiguous / missing**: Both S1-008 and S1-009 reference AT-277 and AT-920. Where does OrderSize discovery end and dispatcher mapping discovery begin?
- **Evidence**: PRD S1-008 says "OrderSize and sizing invariants only." PRD S1-009 says "dispatcher mapping only."
- **Options**:
  1. Option A — S1-008 covers the OrderSize struct (fields, derivation, invariants). S1-009 covers the dispatcher (how outbound `amount` is chosen per instrument_kind, mismatch rejection).
  2. Option B — Merge both into one report. Violates PRD scope.
- **Chosen**: A — Clean separation matching PRD scope.
- **Why not others**: Option B violates the PRD's explicit scoping of two separate discovery documents.
- **Scope control**:
  - What we're NOT doing yet: Writing any code, changing dispatch logic, adding tests.
  - What unblocks us if this choice is wrong: Both reports can be updated before implementation begins.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-277 | Report lists which amount field to send per instrument_kind but omits edge cases (e.g., what happens when qty_coin is zero for an option, or when both qty_coin and qty_usd are populated for a perp) | Dispatcher handles happy path but crashes or sends wrong value on edge inputs | Report must enumerate edge cases per instrument_kind and flag "current handling vs contract requirement" for each |
| AT-920 | Report mentions mismatch rejection but doesn't trace the full check flow: who computes contracts * contract_size, who compares to amount, where tolerance is applied | Implementation may place the check in the wrong layer or skip tolerance | Report must include a proposed check-flow diagram: input fields -> computation -> comparison -> tolerance -> reject/accept |

Note: Since this is a discovery story, "wrong impl" = misleading or incomplete report.

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-277 | None (discovery) | `test -f docs/dispatch_map_discovery.md` + content grep | N/A | N/A | File existence + content check | Yes |
| AT-920 | None (discovery) | `rg -n "dispatch" docs/dispatch_map_discovery.md` | N/A | N/A | Content check | Yes |

Note: No runtime enforcement in this story. Proof is document existence and topical coverage. Actual AT enforcement happens in implementation stories.

- [x] Every safety-critical AT has TRIP + NON-TRIP — N/A (no safety-critical enforcement in this story)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: None. This story produces a document. No runtime behavior, no trading logic.
- **Fail-closed cap on loss**: N/A — documentation only.
- **Drift metric**: N/A.
- **Loss boundary**: N/A.
- **Rollback plan**: Delete `docs/dispatch_map_discovery.md` if report is misleading.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None — read-only analysis, no code changes.
- **If conflict with CONTRACT.md**: No conflict possible — this story reads the contract, doesn't modify it.
- Files with recent churn or shared ownership: None — creates a new doc file.
- Struct fields I'm assuming exist: None (discovery reads existing code).
- State machine transitions affected: None.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: NONE

- What will slow me down: If no dispatcher logic exists yet, the "current logic" section is empty.
- Exploit: Frame the report as "contract requirements vs. current state (even if empty)" — the gap list is the deliverable.
- Smallest fix that prevents it next time: Template the discovery report format so it works for both "code exists" and "code doesn't exist yet" scenarios.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- **GREEN**: All gates pass, proof plan complete, no unresolved ambiguities. This is a documentation-only story with no runtime risk.

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
