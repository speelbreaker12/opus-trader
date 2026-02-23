---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INFRA_reconciliation.md
story_id: S1-008
story_title: "OrderSize discovery"
gate_result: GO
story_verdict: RECONCILED (DEFERRED - discovery only, no gaps)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-008 (OrderSize discovery)

## A) GATE RESULT

```
GATE: GO
Reason: STOPLIGHT GREEN. Discovery document exists with contract-aligned content.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Dispatcher Rules | None (discovery story) | docs/order_size_discovery.md exists; line 58: "AT-277: option uses amount=qty_coin, perp uses amount=qty_usd; option qty_usd unset; mismatches rejected." | N/A — discovery doc, not enforcement | N/A | Yes — report includes per-instrument-kind field population table (lines 36-42) | Yes | **DEFERRED** (enforcement in S1-004/S1-005) |
| AT-920 | §1.0 Dispatcher Rules | None (discovery story) | docs/order_size_discovery.md exists; line 59: "AT-920: contracts/amount mismatch beyond tolerance → Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded." | N/A — discovery doc, not enforcement | N/A | Yes — report includes tolerance formula (line 48), mismatch rejection (line 70), and explicit handoff note for S1-007 | Yes | **DEFERRED** (enforcement in S1-007) |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Codebase has some OrderSize logic | Report content review | PASS — report correctly identifies "None" (docs/order_size_discovery.md:10: "Crates were reset to empty scaffolding") and proceeds with gap analysis |
| 2 | CONTRACT.md §1.0 is stable | Report references contract anchors | PASS — report references AT-277, AT-920, and cites contract fields explicitly |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Report format: High-level summary (Option A) | A — high-level with gap list | Yes | docs/order_size_discovery.md:61-73 (gap list), lines 76-88 (required tests table), lines 92-110 (minimal diff). Matches "high-level summary with explicit gap list." |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| AT-277: Omit per-instrument-kind population rules | Yes (content) | docs/order_size_discovery.md:36-42 — per-instrument-kind canonical field table | Yes — table enumerates option/linear_future vs perpetual/inverse_future |
| AT-920: Mention mismatch in passing without detail | Yes (content) | docs/order_size_discovery.md:44-49 — full contracts/amount consistency section with formula, tolerance, epsilon | Yes — details the full check, not just a passing mention |

## D) DESIGN RISK NOTES

- **INFO**: The report correctly identifies "Everything is a gap" (line 63) since crates were reset. This is expected for a discovery story against a clean slate.
- **INFO**: Report lists 9 required tests for S1-004 (lines 76-88), which provides strong traceability for the implementation story.

## E) REMEDIATION PLAN

```
[INFO] Discovery doc complete — all contract fields enumerated, gaps identified, tests proposed.
[INFO] No enforcement in this story — all AT enforcement deferred to S1-004/S1-005/S1-007.
```

No P0/P1/P2 issues found.

## F) SCOPE CHECK

| File (premortem §0) | Exists? | Notes |
|---------------------|---------|-------|
| docs/order_size_discovery.md | Yes | 111 lines, covers OrderSize struct, canonical unit rules, gaps, required tests |

Scope drift: None.

```
READY FOR SELF_REVIEW
```
