# Phase 1 Contract Remediation Plan

**Date:** 2026-03-05
**Scope:** Phase 1 only
**Objective:** Remove the Phase 1 `NO-GO` by fixing the blocking and hardening gaps in the contract and landing the minimum enforcement/proving artifacts that make the new rules real.

## Summary

- Goal: remove the Phase 1 `NO-GO` by fixing the blocking and hardening gaps in the contract and landing the minimum enforcement/proving artifacts that make the new rules real.
- Delivery shape: two remediation lanes that can run mostly independently, then one final alignment pass.
- Boundary choice: stay Phase 1 only, and fix the contract boundary in `specs/CONTRACT.md` without re-slicing `plans/prd.json` in this plan.

## Key Changes

### Lane A: Execution Safety and Profitability

- Rewrite `specs/CONTRACT.md` Section 1.3 so missing/stale L2 blocks `OPEN` only.
- Require risk-reducing `CLOSE/HEDGE/replace` to stay legal under degraded L2 by using the best valid price source available, bounded to monotonic risk-reducing size, and to fail closed only when no valid price source exists.
- Make the OPEN chokepoint order normative in the contract:
  `DispatchAuth -> Preflight -> Quantize -> DispatchConsistency -> FeeCache/Policy -> Expiry -> Liquidity -> NetEdge -> Pricer -> RecordedBeforeDispatch`.
- Require early exit on first reject and no side effects before `RecordedBeforeDispatch`.
- Bind `expected_slippage_usd` consumed by Net Edge to the same liquidity evaluation that authorizes the order.
- Make Net Edge the sole profitability eligibility gate; Pricer becomes a pure limit-price constructor over already-authorized inputs.
- Simplify Phase 1 linked-order behavior to unconditional reject for any non-null `linked_order_type`.
- Enumerate the full liquidity reject taxonomy in the contract so each branch has a deterministic reason code.

### Lane B: Identity, Replay, and Recovery

- Make `amount_semantics` the authoritative sizing/dispatch branch in the contract and explicitly define the venue metadata fields required to derive it.
- Change the hash contract to integer-only identity: hash `qty_steps` and `price_ticks`, never `qty_q` or `limit_price_q` directly.
- Tighten canonical `s4` rules: exact full-identity match for canonical labels, legacy-only fallback for non-canonical labels, explicit token-width/charset validation, and deterministic reject/degrade behavior.
- Replace the recovered-unsent OPEN rule so replayed WAL state is never enough to create new OPEN exposure; only fresh post-restart regeneration may do that.
- Add enforced startup latch semantics: runtime starts with `RESTART_RECONCILE_REQUIRED`, opens stay blocked until reconcile completes, and ACK evidence found during reconcile must suppress resend.
- Rewrite trade-id dedupe to require either atomic "trade_id + state apply" durability or an explicit `apply_pending` recovery path before duplicate suppression may NOOP later events.
- Update the Phase 1 contract section so restart/replay safety is explicitly part of the Phase 1 remediation target, while leaving PRD story layout unchanged in this plan.

## Important Interface and Type Changes

- Contract introduces `amount_semantics` as the normative execution-sizing discriminator.
- `intent_hash` contract input changes from quantized floats to integer `qty_steps` and `price_ticks`.
- Canonical label matching changes from heuristic-capable primary flow to exact canonical identity with legacy-only fallback.
- Recovery contract adds `RESTART_RECONCILE_REQUIRED` latch semantics and `apply_pending` fill-recovery semantics.
- Profitability contract changes so Net Edge authorizes and Pricer only prices.

## Test Plan

- Add or update proof tests so missing/stale L2 rejects `OPEN` but preserves at least one legal risk-reducing dispatch path.
- Add proof that partial-depth `CLOSE/HEDGE` clamps risk-reducing size instead of rejecting when some valid liquidity exists.
- Add proof that hard-stale fee state blocks `OPEN` but does not block `CLOSE/HEDGE/CANCEL` unless `Kill` applies.
- Add realistic metadata-fixture tests for `amount_semantics` derivation, including contradictory/missing-field fail-closed cases.
- Add hash determinism tests proving equivalent float inputs that quantize to the same steps/ticks yield identical hashes and different steps/ticks yield different hashes.
- Add canonical-label schema tests for wrong prefix, wrong widths, invalid characters, and invalid `leg_idx`.
- Add canonical-label recovery tests proving exact full-identity match is mandatory for `s4` labels and ambiguity degrades instead of heuristically matching.
- Add crash/restart tests for recorded-but-unsent OPEN not auto-dispatching, startup latch blocking opens pre-reconcile, lost ACK being recovered without resend, and crash-mid-fill with `trade_id` persisted still converging exactly once via atomic apply or `apply_pending`.
- Run contract validation plus focused Rust tests first, then repo verification at the end:
  `./plans/contract_check.sh`,
  `./plans/contract_review_validate.sh`,
  focused `cargo test` for `soldier_core` and `soldier_infra` contract suites,
  then `./plans/verify.sh quick` and `./plans/verify.sh full`.

## Assumptions and Defaults

- This plan fixes all Phase 1 blockers and hardening items together, but does not renumber or move PRD stories.
- If a contract anchor or AT title must change, only patch broken references; do not re-phase the backlog here.
- Risk-reducing actions always take precedence over data-quality or profitability gates.
- Canonical `s4` labels are treated as strict identity artifacts, not heuristic hints.
- Replay/WAL state is audit and reconciliation input, not independent authorization to create fresh OPEN risk.
- Hardening items are batched into the same lane only when they share the same touchpoints and proof bundle; otherwise they stay as explicit follow-on tasks inside the lane order above.
