# Story Premortem: S1-008

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-008 — OrderSize discovery
- Contract clause(s): §1.0 Instrument Units & Notional Invariants (Deribit Quantity Contract)
- Acceptance tests: AT-277, AT-920 (informational references — discovery feeds future stories, no enforcement in this story)
- Touch scope: `docs/order_size_discovery.md` (documentation only)
- **Risk rating**: LOW
  - Discovery/documentation only — no code changes, no runtime behavior, no safety gates touched.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-277 | §1.0 Dispatcher Rules | "Given: instrument_kind=option with qty_coin=0.3... When: the dispatcher maps request fields. Then: outbound option uses amount=qty_coin=0.3, qty_usd is unset; outbound perp uses amount=30_000 (USD)..." | MUST | Yes — but tested in implementation story, not this discovery story |
| AT-920 | §1.0 Dispatcher Rules | "Given: contracts and amount are provided and mismatch beyond contracts_amount_match_tolerance. When: the dispatcher validates sizing before dispatch. Then: the intent is rejected with Rejected(ContractsAmountMismatch) and no dispatch occurs." | MUST | Yes — but tested in implementation story, not this discovery story |

Note: This story references these ATs to scope the discovery report. The ATs themselves are enforced and tested in S1-004/S1-005 (canonical sizing, dispatcher amount mapping) for AT-277 and S1-007 (dispatcher mismatch rejection) for AT-920. This story produces a document, not enforcement.

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The current codebase has some form of order sizing logic to discover | If no sizing logic exists yet, the discovery report simply says "not yet implemented" | Report content review | N/A — discovery |
| 2 | CONTRACT.md §1.0 OrderSize struct definition is stable | If contract changes, discovery report becomes stale | Report references contract anchors for traceability | Pre-req |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Discovery report omits a contract-required field from the OrderSize struct (contracts, qty_coin, qty_usd, notional_usd) | Implementation story misses a field; canonical sizing incomplete | Report checklist enumerates every OrderSize field from CONTRACT.md and flags present/missing | Future AT-277 |
| 2 | Report fails to distinguish instrument-kind-specific field population rules (e.g., options populate qty_coin, perps populate qty_usd) | Wrong field populated for a given instrument kind at implementation time | Report must include per-instrument-kind field population matrix | Review gate |
| 3 | Report is written but never read before implementation | Discovery value lost | PRD dependencies link S1-004/S1-005/S1-007 back to this report | Process |
| 4 | Report conflates field derivation rules with outbound dispatch mapping (S1-009 territory) | Scope overlap; duplicate/conflicting analysis | Scope guard: "OrderSize struct fields and canonical sizing rules only — not outbound amount selection" | Review gate |
| 5 | Report lists fields but omits the derivation invariants (e.g., notional_usd = qty_coin * index_price) | Fields present but sizing rules not captured; implementation may populate fields without enforcing invariants | Report must list each derivation formula alongside the field | Future AT-277 |

## 4) Open decisions (resolve before coding)

### Decision: Report format and depth
- **What is ambiguous / missing**: How detailed should the gap analysis be? Line-by-line code audit vs. high-level summary?
- **Evidence**: PRD acceptance criteria say "lists current fields, call sites, and gaps vs the contract OrderSize struct" and "names the minimal implementation diff."
- **Options**:
  1. Option A — High-level summary: list contract fields, note which exist/missing, propose tests. Quick to write.
  2. Option B — Deep code audit: trace every call site, annotate each with contract compliance. Thorough but slow.
- **Chosen**: A — High-level summary with explicit gap list is sufficient for a discovery story.
- **Why not others**: Option B is implementation-level analysis better done during the implementation story itself.
- **Scope control**:
  - What we're NOT doing yet: Writing any code, changing any types, adding any tests.
  - What unblocks us if this choice is wrong: The implementation stories (S1-004/S1-005) do their own detailed analysis.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-277 | Report lists OrderSize fields but omits instrument-kind-specific population rules (which fields are set for options vs perps vs futures) | Implementation populates wrong fields for a given instrument kind | Report must include per-instrument-kind field population table with evidence from codebase or "not yet implemented" |
| AT-920 | Report mentions mismatch rejection in passing without detailing the contracts/amount consistency invariant | Mismatch check scope not surfaced; S1-009 (dispatch mapping) or S1-007 (mismatch rejection) may miss it | Report must flag AT-920 as "out of scope for struct discovery — see S1-009/S1-007" with explicit handoff |

Note: Since this is a discovery story, the "wrong impl" is a misleading or incomplete report rather than incorrect code.

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-277 | None (discovery) | `test -f docs/order_size_discovery.md` + content grep | N/A | N/A | File existence + content check | Yes |
| AT-920 | None (discovery) | `rg -n "OrderSize" docs/order_size_discovery.md` | N/A | N/A | Content check | Yes |

Note: This story has no runtime enforcement. The proof is that the document exists and addresses the right topics. Actual AT enforcement happens in the implementation stories.

- [x] Every safety-critical AT has TRIP + NON-TRIP — N/A (no safety-critical enforcement in this story)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: None. This story produces a document. No runtime behavior, no trading logic.
- **Fail-closed cap on loss**: N/A — documentation only.
- **Drift metric**: N/A.
- **Loss boundary**: N/A.
- **Rollback plan**: Delete `docs/order_size_discovery.md` if report is misleading.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None — read-only analysis, no code changes.
- **If conflict with CONTRACT.md**: No conflict possible — this story reads the contract, doesn't modify it.
- Files with recent churn or shared ownership: None — creates a new doc file.
- Struct fields I'm assuming exist: OrderSize struct (reading existing code, not modifying).
- State machine transitions affected: None.

## 9) Constraint I expect to hit
- What will slow me down: If the codebase has no existing OrderSize logic, the discovery report is mostly "not yet implemented."
- Exploit: Frame the report as "contract requirements vs. current state (even if empty)" — the gap list is the value.
- Smallest fix that prevents it next time: Template the discovery report format so future discovery stories are consistent.

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
