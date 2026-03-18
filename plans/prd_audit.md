# PRD Audit Report

**Project:** StoicTrader
**PRD SHA256:** `6a7f5dc2706b2d39139bd29bef923d165dcf0152af2b365f5babfec6f1c2390a`
**Audit Scope:** full
**Date:** 2026-02-19

## Summary

| Metric | Count |
|--------|-------|
| Items Total | 104 |
| Items PASS | 104 |
| Items FAIL | 0 |
| Items BLOCKED | 0 |
| Must Fix Count | 0 |

## MUST FIX

- None. All 104 items pass required schema, acceptance, steps, verify, scope, and dependency checks.

## RISK

- 3 forward dependencies within Slice 1 (S1-002->S1-011, S1-004->S1-008, S1-005->S1-009) - acceptable as within-slice priority ordering but could cause confusion
- Many contract_refs use free-text section names rather than stable CSP-xxx/AT-xxx anchors, making automated traceability fragile
- Unresolved contract_refs in 29 items use section heading text that doesn't exactly match CONTRACT.md digest key_map - likely valid but not machine-verifiable
- Unresolved plan_refs in 33 items use IMPLEMENTATION_PLAN.md path-style refs that don't exactly match plan digest key_map

## Improvements

- Standardize contract_refs to use AT-xxx or CSP-xxx anchors instead of free-text section names for automated traceability
- Standardize plan_refs to use exact section headings from IMPLEMENTATION_PLAN.md for machine-verifiable resolution
- Add partial_coverage_notes for items that reference ATs they only partially prove (per schema_notes)
- Add observability.metrics to items currently missing them (many Slice 7+ items have empty metrics)
- Consider adding implementation_tests to items that have empty arrays (especially infra/policy items)
- Add failure_mode arrays to execution/risk items that currently have empty failure_mode (most items)
- Slice 1 forward dependencies should be reordered so dependent items appear after their dependencies in the items array

## Per-Item Audit Table

| ID | Status | Top 2 Reasons | Top Fix |
|-----|--------|---------------|---------|
| S0-000 | PASS | All checks passed | - |
| S0-001 | PASS | All checks passed | - |
| S0-002 | PASS | All checks passed | - |
| S0-003 | PASS | All checks passed | - |
| S0-004 | PASS | Unresolved contract refs: ['§7.0 Owner Control Plane Endpoints (Read-Only, Owner | - |
| S0-005 | PASS | Unresolved contract refs: ['§2.2 PolicyGuard'] | - |
| S1-001 | PASS | All checks passed | - |
| S1-002 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-003 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-004 | PASS | Unresolved contract refs: ['CONTRACT.md OrderSize struct (MUST implement):'] | - |
| S1-005 | PASS | Unresolved contract refs: ['CONTRACT.md Dispatcher Rules (Deribit request mappin | - |
| S1-006 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-007 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-008 | PASS | Unresolved contract refs: ['CONTRACT.md OrderSize struct (MUST implement):'] | - |
| S1-009 | PASS | Unresolved contract refs: ['CONTRACT.md Dispatcher Rules (Deribit request mappin | - |
| S1-010 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-011 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S1-012 | PASS | All checks passed | - |
| S1-013 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units + Disp | - |
| S2-000 | PASS | All checks passed | - |
| S2-001 | PASS | All checks passed | - |
| S2-002 | PASS | Unresolved contract refs: ['CONTRACT.md §1.1 Labeling & Idempotency Contract'] | - |
| S2-003 | PASS | All checks passed | - |
| S2-004 | PASS | Unresolved contract refs: ['CONTRACT.md RejectReasonCode registry (intent‑level  | - |
| S3-000 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md §Slice 3 — Order‑Type Preflight \ | - |
| S3-001 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md §Slice 3 — Order‑Type Preflight \ | - |
| S3-002 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md §Slice 3 — Order‑Type Preflight \ | - |
| S4-000 | PASS | Unresolved contract refs: ['CONTRACT.md §2.4.1 WAL Writer Isolation (Hot Loop Pr | - |
| S4-001 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md §Slice 4 — Durable WAL \\+ TLSM \ | - |
| S4-002 | PASS | Unresolved plan refs: ['IMPLEMENTATION_PLAN.md §Slice 4 — Durable WAL \\+ TLSM \ | - |
| S4-003 | PASS | Unresolved contract refs: ['CONTRACT.md §2.4.1 WAL Writer Isolation (Hot Loop Pr | - |
| S5-000 | PASS | Unresolved contract refs: ['CONTRACT.md §1.3 Pre-Trade Liquidity Gate (Do Not Sw | - |
| S5-001 | PASS | Unresolved contract refs: ['CONTRACT.md §4.2 Fee-Aware Execution'] | - |
| S5-002 | PASS | Unresolved contract refs: ['CONTRACT.md §1.4.1 Net Edge Gate (Fees + Expected Sl | - |
| S5-003 | PASS | Unresolved contract refs: ['CONTRACT.md §1.4 Fee-Aware IOC Limit Pricer (No Mark | - |
| S5-004 | PASS | Unresolved contract refs: ['CONTRACT.md §1.4.1 Net Edge Gate (Fees + Expected Sl | - |
| S6-000 | PASS | Unresolved contract refs: ['1. Execution Architecture: The "Atomic Group" (Real- | - |
| S6-001 | PASS | Unresolved plan refs: ['Phase 1 — Foundation (Panic‑Free Deterministic Intents)' | - |
| S6-002 | PASS | Unresolved plan refs: ['Phase 1 — Foundation (Panic‑Free Deterministic Intents)' | - |
| S6-003 | PASS | Unresolved plan refs: ['Phase 1 — Foundation (Panic‑Free Deterministic Intents)' | - |
| S6-004 | PASS | Unresolved plan refs: ['Phase 1 — Foundation (Panic‑Free Deterministic Intents)' | - |
| S6-005 | PASS | Unresolved plan refs: ['Phase 1 — Foundation (Panic‑Free Deterministic Intents)' | - |
| S6-006 | PASS | Unresolved contract refs: ['2.4 — WAL / intent ledger (RecordedBeforeDispatch)'] | - |
| S6-007 | PASS | Unresolved contract refs: ['CONTRACT.md Inventory skew gate'] | - |
| S6-008 | PASS | Unresolved contract refs: ['CONTRACT.md Pending exposure reservation'] | - |
| S6-009 | PASS | Unresolved contract refs: ['CONTRACT.md Global exposure budget (corr buckets)'] | - |
| S6-010 | PASS | Unresolved contract refs: ['CONTRACT.md Margin headroom gate'] | - |
| S7-000 | PASS | All checks passed | - |
| S7-001 | PASS | All checks passed | - |
| S7-002 | PASS | All checks passed | - |
| S7-003 | PASS | All checks passed | - |
| S7-004 | PASS | All checks passed | - |
| S7-005 | PASS | All checks passed | - |
| S7-011 | PASS | All checks passed | - |
| S8-001 | PASS | Unresolved plan refs: ['S8.2 — Runtime F1 gate (HARD): artifacts/F1_CERT.json'] | - |
| S8-002 | PASS | All checks passed | - |
| S8-003 | PASS | All checks passed | - |
| S8-004 | PASS | All checks passed | - |
| S8-005 | PASS | All checks passed | - |
| S8-006 | PASS | Unresolved plan refs: ['S8.7 — Endpoint: POST /api/v1/emergency/reduce_only (exi | - |
| S8-008 | PASS | All checks passed | - |
| S8-009 | PASS | All checks passed | - |
| S8-010 | PASS | All checks passed | - |
| S8-011 | PASS | All checks passed | - |
| S8-012 | PASS | All checks passed | - |
| S8-013 | PASS | All checks passed | - |
| S8-014 | PASS | All checks passed | - |
| S8-019 | PASS | All checks passed | - |
| S9-000 | PASS | All checks passed | - |
| S9-001 | PASS | Unresolved plan refs: ['S9.2 — 10028/too_many_requests => Kill + reconnect + rec | - |
| S9-002 | PASS | All checks passed | - |
| S9-003 | PASS | All checks passed | - |
| S9-004 | PASS | All checks passed | - |
| S9-005 | PASS | All checks passed | - |
| S9-009 | PASS | All checks passed | - |
| S9-010 | PASS | All checks passed | - |
| S9-011 | PASS | All checks passed | - |
| S9-012 | PASS | All checks passed | - |
| S9-013 | PASS | All checks passed | - |
| S10-000 | PASS | All checks passed | - |
| S10-001 | PASS | All checks passed | - |
| S10-002 | PASS | All checks passed | - |
| S10-003 | PASS | All checks passed | - |
| S10-004 | PASS | All checks passed | - |
| S10-006 | PASS | All checks passed | - |
| S10-007 | PASS | All checks passed | - |
| S10-008 | PASS | All checks passed | - |
| S11-000 | PASS | All checks passed | - |
| S11-001 | PASS | All checks passed | - |
| S11-002 | PASS | All checks passed | - |
| S11-003 | PASS | All checks passed | - |
| S12-000 | PASS | All checks passed | - |
| S12-001 | PASS | All checks passed | - |
| S12-002 | PASS | All checks passed | - |
| S13-000 | PASS | All checks passed | - |
| S13-002 | PASS | All checks passed | - |
| S13-003 | PASS | All checks passed | - |
| S13-004 | PASS | All checks passed | - |
| S13-005 | PASS | All checks passed | - |
| S13-006 | PASS | All checks passed | - |
| S13-008 | PASS | All checks passed | - |
| S14-000 | PASS | Unresolved contract refs: ['§8.1 Measurable Metrics (PASS/FAIL)', '§8.2 Minimum  | - |
| S14-001 | PASS | Unresolved plan refs: ['Slice 14 — GOP Optimization Cycle (Contract §5.1)'] | - |
| S14-002 | PASS | Unresolved plan refs: ['Slice 14 — GOP Optimization Cycle (Contract §5.1)'] | - |

---
*Generated by PRD Auditor (full scope)*