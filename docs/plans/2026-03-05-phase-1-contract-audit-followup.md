# Phase 1 Contract Audit Follow-Up

**Date:** 2026-03-05
**Purpose:** Capture the useful contract-patch ideas from `artifacts/LOSS_RISK_CONTRACT_AUDIT_PHASE1.md` without inheriting that artifact's verdict or unsupported proof claims.

## Scope Rule

- Use this checklist only as a follow-up patch shortlist.
- Do not use `artifacts/LOSS_RISK_CONTRACT_AUDIT_PHASE1.md` as the authority for Phase 1 pass/block decisions.
- Keep `reviews/reconciliations/slice1/PHASE1_CONTRACT_LOSS_RISK_AUDIT_2026-03-05.md` as the current audit source of truth.

## Recommended Follow-Up Patches

| ID | Priority | Phase | Patch | Why keep it |
|---|---|---|---|---|
| FUP-001 | High | Phase 2 | Session-aware emergency close dispatch path | Prevents stranded exposure when session termination is itself the reason containment must run. |
| FUP-002 | High | Phase 2 | CP-001 latch maximum hold bound with explicit stuck-latch alerting | Preserves fail-closed behavior while preventing silent indefinite profit block. |
| FUP-003 | High | Phase 2 | CP-001 per-instrument scope for instrument-local gap reasons | Reduces blast radius so one instrument gap does not block unaffected instruments. |
| FUP-004 | High | Phase 2 | Kill corroboration timeout that degrades to `ReduceOnly` instead of hanging | Removes an ambiguous waiting state from non-capital Kill triggers. |
| FUP-005 | High | Phase 2 | Hedge partial-fill continuation and residual-exposure alerting | Prevents the hedge fallback path from leaving untracked residual naked delta. |
| FUP-006 | Medium | Phase 2 | Inventory Skew stale-position guard | Forces OPEN fail-closed on stale `current_delta` while preserving CLOSE/HEDGE paths. |
| FUP-007 | Medium | Phase 1/2 hardening | Minimum profitable trade-size guard tied to fee floor | Prevents structurally loss-making tiny trades from passing edge checks. |
| FUP-008 | Medium | Phase 1/2 hardening | Conservative margin-source rule plus margin staleness fail-closed behavior | Prevents OPEN authorization from relying on the more optimistic or stale margin view. |

## Deferred Hardening Candidates

- Persist churn circuit-breaker counters across restarts.
- Define `atomic_qty_epsilon` relative to instrument metadata instead of a global constant.
- Add an explicit terminal-state AT for "all containment paths exhausted".

## Triage Order

1. Pull `FUP-001` through `FUP-005` into the next Phase 2 contract-tightening pass.
2. Fold `FUP-006` into the same pass if Inventory Skew semantics are being edited.
3. Treat `FUP-007` and `FUP-008` as contract hardening that can land independently if they do not reopen the Phase 1 remediation lane.
