---
project: "[[Autoresearch]]"
date: 2026-03-17
type: debrief
---

## What Shipped

Applied 16 accepted proposals from autoresearch phase3 run `phase2-mar17-20260317_141745-bb818649` to `specs/CONTRACT.md`.

## Changes

- 11 new acceptance tests (AT-PROP-100 through AT-PROP-205)
- 2 SHALL→MUST mechanical fixes (lines 412, 513)
- CSP-063 cross-reference dedup for Recovery/Matching Rule
- AT-1243→AT-1253 renumber (duplicate ID fix)
- 3 new RejectReasonCode entries (TradingModeBlockedOpen, MarginHeadroomInputMissing added to registry)
- AT-931 pass criteria tightened to reference specific reject code
- New inputs: bunker_mode_last_update_ts_ms, cortex_override critical input rule
- New staleness rules: account_summary_max_age_ms (5000ms), bunker_mode_max_age_ms (10000ms)
- Inventory Skew SELL formula made precise with inventory_skew_sell_floor parameter

## Rejected (3)

- P-209: Already covered by parenthetical qualifier + cooldown pattern
- P-400/P-401: Fixture-only proposals, not CONTRACT.md

## Phase 2 Reversions (pre-existing working tree)

Reverted AT-1247..AT-1252 and CCL-2026-03-16-01 ledger entry. Removed global cooldown scope paragraph, Profile:ALL tags, simplified hedge fallback text in 3.1.

## Constraint

Contract hash verified before apply (`d7ab68a8...` matched proposals_index). All edits applied by semantic section lookup, not line numbers.
