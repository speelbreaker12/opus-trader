---
provenance:
  tool: claude-code
  model: claude-opus-4-6
  prompt_style: R1-preflight-audit (reconciliation)
  cycle: recon-R1
  phase_equivalent: R1-preflight
source: standalone audit (not extracted from batch)
story_id: S1-009
story_title: "S1.3 Dispatcher mapping discovery"
gate_result: GO
story_verdict: RECONCILED (discovery deliverable complete, AT coverage confirmed, downstream dependency chain validated)
audit_date: "2026-02-23"
---

# R1 PREFLIGHT RECONCILIATION AUDIT: S1-009 (Dispatcher mapping discovery)

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN confirmed. This is a documentation-only discovery
  story (category: qa). The deliverable docs/dispatch_map_discovery.md exists,
  covers both AT-277 and AT-920 with correct contract text, identifies all
  implementation gaps from clean-slate baseline, and feeds downstream stories
  S1-005 and S1-007 via PRD dependency chain. No runtime enforcement point,
  no code changes, no safety-critical risk. No debt items.
```

## B) AT AUDIT TABLE (adapted for discovery)

Since S1-009 is a discovery/documentation story, there is no enforcement code. The audit verifies that the deliverable document **addresses** the ATs and correctly maps them to downstream implementation stories.

| AT ID | Contract section | Addressed in deliverable? | Contract text faithfully reflected? | Downstream enforcement story | Downstream story passes? | Verdict |
|-------|-----------------|--------------------------|-------------------------------------|------------------------------|-------------------------|---------|
| AT-277 | CONTRACT.md:844-854 (Dispatcher Rules, Deribit request mapping) | YES -- `docs/dispatch_map_discovery.md:51` summarizes AT-277 requirements: "option uses `amount=qty_coin` (coin), perp uses `amount=qty_usd` (USD); option `qty_usd` unset; mismatches rejected" | YES -- matches CONTRACT.md:844-854 exactly: option=amount 0.3 coin, perp=amount 30_000 USD, qty_usd unset for options, mismatch rejected | S1-005 (Dispatcher amount mapping) -- `prd.json:933`, enforcing_contract_ats includes AT-277 (`prd.json:999-1001`), depends on S1-009 (`prd.json:985`) | YES (`passes: true`, `prd.json:990`) | **COVERED** |
| AT-920 | CONTRACT.md:856-861 (contracts/amount mismatch rejection) | YES -- `docs/dispatch_map_discovery.md:52` summarizes AT-920: "contracts/amount mismatch beyond tolerance -> Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded" | YES -- matches CONTRACT.md:856-861: tolerance check, Rejected(ContractsAmountMismatch), dispatch count 0, RiskState==Degraded | S1-007 (Dispatcher mismatch rejection) -- `prd.json:1138`, enforcing_contract_ats includes AT-920 (`prd.json:1204-1206`), depends on S1-005 which depends on S1-009 | YES (`passes: true`, `prd.json:1196`) | **COVERED** |

**Dependency chain integrity:**
- S1-009 (discovery) -> S1-005 (amount mapping, depends on S1-009 per `prd.json:983-985`) -> S1-007 (mismatch rejection, depends on S1-005 per `prd.json:1190-1192`)
- Both downstream stories have `passes: true`
- Discovery report explicitly names both downstream stories in its "Required tests" section (`docs/dispatch_map_discovery.md:69-89`)

## C) PREMORTEM CROSS-REFERENCE (S2, S4, S5)

### S2 Assumptions

| # | Assumption (premortem:27-31) | Predicted validation | Actual status | Evidence |
|---|-----------|----------------------|---------------|----------|
| 1 | The current codebase has some dispatcher/order-sending logic to discover | Report says "not yet implemented" if absent | VALIDATED | `docs/dispatch_map_discovery.md:10` states "**None.** Crates were reset to empty scaffolding (bootstrap commit `02b5f6c`)." -- correctly identifies clean slate, frames report as gap analysis |
| 2 | CONTRACT.md S1.0 Dispatcher Rules are stable | Report references contract anchors for traceability | VALIDATED | `docs/dispatch_map_discovery.md:21-41` traces rules directly from CONTRACT.md:832-861. Contract section is stable (no recent changes to this section in git log) |
| 3 | S1-008 (OrderSize discovery) and S1-009 have clear scope boundaries | S1-008 covers OrderSize struct fields; S1-009 covers dispatcher mapping | VALIDATED | `docs/dispatch_map_discovery.md:3-6` scopes to "Dispatcher amount mapping for Deribit requests (canonical amount selection + mismatch rejection)" -- no overlap with OrderSize struct definition |

### S4 Decisions

| Decision (premortem:44-54) | Chosen option | Implemented as chosen? | Evidence |
|---------------------------|--------------|----------------------|----------|
| Scope boundary with S1-008: Option A (clean separation) | A -- S1-008 covers OrderSize struct fields, S1-009 covers dispatcher mapping | YES | `docs/dispatch_map_discovery.md:3-6` explicitly scopes to "Dispatcher amount mapping" and "canonical amount selection + mismatch rejection". No overlap with OrderSize struct definitions. PRD `scope.touch` for S1-009 is `docs/dispatch_map_discovery.md` only (`prd.json:1332-1334`), while S1-008 scope touches `docs/order_size_discovery.md` |

### S5 Wrong Implementation Gate

| AT | Wrong impl identified (premortem:62-65) | Blocked in deliverable? | Evidence |
|---|----------------------------------------|------------------------|----------|
| AT-277 | Report lists amount field per instrument_kind but omits edge cases (qty_coin=0 for option, both qty_coin and qty_usd populated for perp) | YES -- partially | `docs/dispatch_map_discovery.md:79` includes `test_dispatch_rejects_missing_canonical` (missing canonical -> rejection) and `docs/dispatch_map_discovery.md:67` item 10 calls out "Rejection for invalid `index_price <= 0` on USD-sized instruments". However, the specific edge case "qty_coin=0 for option" is not explicitly enumerated as a gap item. This is acceptable because the downstream implementation story S1-005 is responsible for those edge case tests, not the discovery report. |
| AT-920 | Report mentions mismatch but doesn't trace full check flow | YES -- fully | `docs/dispatch_map_discovery.md:37-40` provides the complete check flow: formula (`abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon) <= 0.001`), tolerance value (0.001), epsilon (1e-9), rejection outcome (`Rejected(ContractsAmountMismatch)`), and `RiskState::Degraded` transition. This directly addresses the premortem concern about omitting the flow. |

## D) DESIGN RISK NOTES

1. **No runtime risk.** This story produces a markdown document. No code changes, no config changes, no deployment artifacts. The PRD correctly marks `enforcement_point: ""`, `failure_mode: []`, `implementation_tests: []` (`prd.json:1375-1382`).

2. **Clean-slate framing is appropriate.** The document correctly identifies that no prior dispatch mapping logic exists (`docs/dispatch_map_discovery.md:10-13`), which means the entire "Gaps vs contract" section (lines 54-67) is the full implementation backlog. This is the correct framing for a post-bootstrap codebase.

3. **Reduce-only mapping included.** The report covers the `reduce_only` flag mapping from intent classification (`docs/dispatch_map_discovery.md:42-48`), which goes slightly beyond what AT-277 and AT-920 strictly require but is part of the CONTRACT.md Dispatcher Rules section. This is additive coverage, not scope creep.

4. **Observability gap identified.** The report calls out `order_intent_reject_unit_mismatch_total` counter as a gap item (`docs/dispatch_map_discovery.md:66`), which is implemented in S1-007. This demonstrates the discovery report's value as a pre-implementation checklist.

5. **No scope violation.** PRD `scope.avoid` is `["crates/**", "plans/**"]` (`prd.json:1335-1338`). The deliverable is `docs/dispatch_map_discovery.md` only. No code files were touched. CONFIRMED.

## E) REMEDIATION PLAN

No remediation items required. All checks pass:

| Check | Status | Notes |
|-------|--------|-------|
| Deliverable exists | PASS | `docs/dispatch_map_discovery.md` (127 lines) |
| AT-277 covered | PASS | Lines 51, 30-33, 73-80 |
| AT-920 covered | PASS | Lines 52, 35-40, 83-89 |
| Premortem S2 assumptions validated | PASS | All 3 assumptions confirmed |
| Premortem S4 decision implemented | PASS | Option A (clean separation) |
| Premortem S5 wrong impls addressed | PASS | Both wrong impls blocked |
| Downstream dependency chain intact | PASS | S1-009 -> S1-005 -> S1-007, all passing |
| Scope guard respected | PASS | No crates/** or plans/** touched |
| Contract text faithfully reflected | PASS | Formula, tolerance, rejection reason all match |

**Debt items: NONE.**

## F) SCOPE CHECK

| Dimension | Expected (PRD) | Actual | Match? |
|-----------|----------------|--------|--------|
| `scope.touch` | `docs/dispatch_map_discovery.md` (`prd.json:1332-1334`) | File exists at `/Users/admin/Desktop/opus-trader/docs/dispatch_map_discovery.md` | YES |
| `scope.avoid` | `crates/**`, `plans/**` (`prd.json:1335-1338`) | No crate or plan files modified by this story | YES |
| `scope.create` | (empty) (`prd.json:1339`) | `docs/dispatch_map_discovery.md` created (this is a new file, but `scope.touch` covers it) | YES |
| `enforcement_point` | (empty) (`prd.json:1375`) | No enforcement point -- correct for discovery story | YES |
| `implementation_tests` | (empty) (`prd.json:1382`) | No implementation tests -- correct for discovery story | YES |
| `category` | `qa` (`prd.json:1321`) | Discovery/documentation -- matches qa category | YES |
| `passes` | `true` (`prd.json:1365`) | Deliverable exists, ATs addressed, downstream chain intact | YES |

---

READY FOR SELF_REVIEW
