---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INFRA_reconciliation.md
story_id: S1-009
story_title: "Dispatcher mapping discovery"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (DEFERRED - discovery, GAP-009-1 P2)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-009 (Dispatcher mapping discovery)

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN. Discovery document exists with contract-aligned content.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Dispatcher Rules | None (discovery story) | docs/dispatch_map_discovery.md exists; line 51: "AT-277: option uses amount=qty_coin (coin), perp uses amount=qty_usd (USD); option qty_usd unset; mismatches rejected" | N/A — discovery doc | N/A | Yes — report enumerates per-instrument-kind outbound amount field (lines 26-33) and edge cases in gaps (lines 56-67) | Yes | **DEFERRED** (enforcement in S1-005) |
| AT-920 | §1.0 Dispatcher Rules | None (discovery story) | docs/dispatch_map_discovery.md exists; line 52: "AT-920: contracts/amount mismatch beyond tolerance → Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded" | N/A — discovery doc | N/A | Yes — report details tolerance formula (lines 37-38), mismatch check flow (lines 82-89), and proposed tests | Yes | **DEFERRED** (enforcement in S1-007) |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Codebase has dispatch logic | Report content review | PASS — report correctly says "None" (docs/dispatch_map_discovery.md:10-11) and provides gap analysis |
| 2 | CONTRACT.md §1.0 Dispatcher Rules stable | Report references anchors | PASS — report references AT-277, AT-920 with full contract citation |
| 3 | S1-008 and S1-009 have clear scope boundaries | Scope guard in reports | PASS — S1-008 covers OrderSize struct fields; S1-009 covers dispatcher outbound mapping |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Scope boundary with S1-008 | A — clean separation | Yes | docs/dispatch_map_discovery.md:5-6 scopes to "Dispatcher amount mapping for Deribit requests"; docs/order_size_discovery.md:5 scopes to "OrderSize struct, sizing invariants" |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-277: Omit edge cases (zero qty_coin for options, both fields populated for perps) | Partially | docs/dispatch_map_discovery.md:63 lists edge cases as wrong impl concern, but gap list (lines 56-67) includes "Rejection for invalid index_price <= 0" without explicitly enumerating all edge case scenarios per instrument_kind | Partial — edge cases are acknowledged but not exhaustively listed in a per-kind table |
| AT-920: Omit full check-flow tracing | Yes | docs/dispatch_map_discovery.md:109-117 — S1-007 section details full check flow | Yes |

## D) DESIGN RISK NOTES

- **P2**: The premortem §5 identifies "Report lists which amount field to send per instrument_kind but omits edge cases" as a wrong impl. The report does mention edge cases (index_price <= 0 on line 67) but doesn't have a comprehensive per-kind edge case table as the tightening suggests.

## E) REMEDIATION PLAN

```
[INFO] Discovery doc complete — dispatcher mapping rules, mismatch rejection, reduce_only all covered.
[INFO] No enforcement in this story — AT enforcement deferred to S1-005/S1-007.
[PRD_FIX] GAP-009-1: P2 — Per-instrument-kind edge case table could be more exhaustive.
```

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| docs/dispatch_map_discovery.md | Yes | 127 lines |

Scope drift: None.

```
READY FOR SELF_REVIEW
```
