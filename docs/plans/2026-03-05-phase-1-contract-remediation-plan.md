# Phase 1 Contract Remediation Plan

**Date:** 2026-03-05
**Scope:** Phase 1 only
**Objective:** Remove the Phase 1 `NO-GO` by fixing the Phase 1 blocking gaps and the tightly-coupled hardening needed to make the new rules enforceable and provable.

## Summary

- Goal: remove the Phase 1 `NO-GO` by fixing the blocking gaps and the tightly-coupled hardening required to make the new rules real.
- Delivery shape: two remediation lanes that can run mostly independently, then one final alignment pass.
- Boundary choice: stay Phase 1 only, patch the contract boundary in `specs/CONTRACT.md`, and update only the directly conflicting `plans/prd.json` acceptance/AT mappings needed to keep source-of-truth alignment without renumbering or re-slicing stories.

## Key Changes

### Lane A: Execution Safety and Profitability

- Rewrite `specs/CONTRACT.md` Section 1.3 so missing/stale L2 blocks `OPEN` only.
- Require risk-reducing `CLOSE/HEDGE/replace` to stay legal under degraded L2 by using the deterministic §3.1 fallback price ladder, bounded to strictly positive monotonic risk-reducing size, and to fail closed only when no valid §3.1 fallback source exists.
- Add the fee-cache carveout at the live `FeeCacheCheck` chokepoint: hard-stale fee cache blocks `OPEN` only, while `CLOSE/HEDGE/CANCEL` remain legal unless `Kill` applies. This is a targeted Gate 5 gate-shape change, not a redesign of the fee evaluator itself.
- Make the OPEN chokepoint order normative in the contract:
  `DispatchAuth -> Preflight -> Quantize -> DispatchConsistency -> FeeCache/Policy -> Expiry -> Liquidity -> NetEdge -> Pricer -> RecordedBeforeDispatch`.
- Require early exit on first reject and no side effects before `RecordedBeforeDispatch`.
- Refactor the OPEN pipeline so the Liquidity evaluation that authorizes the order produces the `expected_slippage_usd` consumed by Net Edge, instead of letting Liquidity and Net Edge read independently pre-populated caller inputs.
- Make Net Edge the sole profitability eligibility gate; Pricer becomes a pure limit-price constructor over already-authorized inputs, and any post-Net-Edge Pricer reject for missing/invalid numerics remains a safety reject rather than a profitability reject.
- Keep Phase 1 linked-order handling on the explicit fail-closed capability model already in the contract: default reject any non-null `linked_order_type`, preserve `linked_orders_supported == false` / `ENABLE_LINKED_ORDERS_FOR_BOT == false` as the defaults, and do not introduce a new supported linked-order path in this remediation.
- Enumerate the full liquidity reject taxonomy in the contract so each branch has a deterministic reason code.

### Lane B: Identity, Replay, and Recovery

- Make `amount_semantics` the authoritative sizing and amount-field-selection branch in the contract, explicitly define the venue metadata fields required to derive it, and wire that derivation into the production normalization/dispatch path rather than leaving it in test-only helpers. `InstrumentKind`/product-family metadata remains in place for non-sizing dispatch rules such as expiry behavior, linked-order capability checks, and other option-specific constraints.
- Clarify and align the hash contract to the existing integer-only identity model: hash `qty_steps` and `price_ticks`, never `qty_q` or `limit_price_q` directly.
- Tighten canonical `s4` rules: exact full-identity match for canonical labels, legacy-only fallback for non-canonical labels, explicit token-width/charset validation, and deterministic reject/degrade behavior.
- Replace the recovered-unsent OPEN rule so replayed WAL state is never enough to create new OPEN exposure; only fresh post-restart regeneration may do that.
- Add enforced startup latch semantics: runtime starts unconditionally with `RESTART_RECONCILE_REQUIRED` before any OPEN-capable path is reachable, independent of `replay_outcome.in_flight_count`; opens stay blocked until reconcile completes, and ACK evidence found during reconcile must suppress resend.
- Compose the new ACK-recovery rule with the existing §2.2.4 latch lifecycle: startup sets `RESTART_RECONCILE_REQUIRED` before replay can expose any OPEN-capable path, unresolved replay evidence keeps the latch set, and only a reconciliation pass that satisfies the current success criteria may clear it.
- Rewrite trade-id dedupe with atomic "trade_id + state apply" durability as the primary implementation target. Only if that atomic path proves infeasible within this Phase 1 slice may the implementation fall back to an explicit `apply_pending` recovery path before duplicate suppression may NOOP later events.
- Update the Phase 1 contract sections and directly conflicting PRD acceptance text so restart/replay safety is explicitly part of the Phase 1 remediation target without changing story numbering or slice layout.

## Important Interface and Type Changes

- Contract introduces `amount_semantics` as the normative execution-sizing discriminator for canonical sizing and outbound amount-field selection, while preserving product-family metadata for non-sizing rules.
- `intent_hash` contract text is aligned to the existing integer `qty_steps` / `price_ticks` identity inputs rather than float-based wording.
- Canonical label matching changes from heuristic-capable primary flow to exact canonical identity with legacy-only fallback.
- Recovery contract adds unconditional `RESTART_RECONCILE_REQUIRED` startup latch semantics and atomic-first trade-id fill-recovery semantics, with `apply_pending` reserved as an explicit fallback path if needed.
- Profitability contract changes so Net Edge authorizes and Pricer only prices, while Pricer invalid-input failures stay classified as fail-closed safety rejects.

## Test Plan

- Add or update proof tests so missing/stale L2 rejects `OPEN` but preserves at least one legal risk-reducing dispatch path through the §3.1 fallback ladder.
- Add proof that partial-depth `CLOSE/HEDGE` clamps to a strictly positive monotonic risk-reducing size (`dispatch_count >= 1`, `size > 0`, `size <= current_position`) instead of rejecting when some valid fallback liquidity exists.
- Add dedicated chokepoint tests proving hard-stale fee state blocks `OPEN` at `FeeCacheCheck` but does not block `CLOSE/HEDGE/CANCEL` unless `Kill` already constrains the action; fee staleness must not become an additional blocker on top of Kill for risk reduction, and the proof target is the Gate 5 chokepoint rather than the fee evaluator in isolation.
- Add a single-chokepoint proof test showing the exact OPEN gate trace order and proving the pipeline-owned Liquidity evaluation directly produces the `expected_slippage_usd` value consumed by Net Edge.
- Add realistic metadata-fixture tests for `amount_semantics` derivation, including contradictory/missing-field fail-closed cases and proof that the production dispatch path uses the derived value for amount-field selection while option/future/perp-specific preflight, expiry, and capability rules still branch on product-family metadata.
- Add hash determinism tests proving equivalent float inputs that quantize to the same steps/ticks yield identical hashes and different `qty_steps` / `price_ticks` yield different hashes.
- Add canonical-label schema tests for wrong prefix, wrong widths, invalid characters, and invalid `leg_idx`.
- Add canonical-label recovery tests proving exact full-identity match is mandatory for `s4` labels and ambiguity degrades instead of heuristically matching.
- Add a restart test proving recorded-but-unsent `OPEN` survives replay with dispatch count still `0`; replay alone is audit/reconcile input only, and only a fresh post-restart strategy evaluation may authorize a new OPEN dispatch.
- Add a replay NON-TRIP proving a WAL-recorded `CLOSE/HEDGE` intent (`reduce_only == true`) remains classified as non-OPEN during replay/reconciliation and is not suppressed by the OPEN-only recovered-unsent rule.
- Add a startup-latch + ACK-recovery composition test proving `RESTART_RECONCILE_REQUIRED` is set unconditionally before replay can reach any OPEN-capable dispatch path, unresolved replay evidence keeps the latch set, reconcile-found ACK evidence records `ack_ts`, advances TLSM without resending, and the latch clears only when the existing reconcile success criteria are satisfied.
- Add a Pricer fail-closed test proving missing/unparseable/NaN pricing inputs still reject deterministically even after Net Edge becomes the sole profitability eligibility gate, and that these rejects remain classified as Pricer safety/numeric failures rather than profitability failures.
- Add a trade-id crash-mid-apply test proving the preferred atomic path converges exactly once after restart or duplicate replay; if the implementation must use `apply_pending`, add the equivalent recovery proof for that fallback path as part of the same change.
- Treat the contract/spec validators inside `./plans/verify.sh quick` as the precondition for each lane checkpoint; any manual checkpoint reruns should preserve that validator-first ordering before focused Rust suites.
- After the validator-first checkpoint passes, run focused Rust tests for the touched `soldier_core` and `soldier_infra` contract suites as the next feedback layer.
- Run `./plans/verify.sh quick` after Lane A and again after Lane B as the canonical contract/spec validation checkpoint; it already runs the standalone contract validators against `specs/CONTRACT.md` (`check_contract_crossrefs`, `check_arch_flows`, `check_state_machines`, `check_global_invariants`, `check_time_freshness`, `check_crash_matrix`, `check_crash_replay_idempotency`, `check_reconciliation_matrix`, and `check_csp_trace`).
- Run a final alignment-pass `./plans/verify.sh quick` once both lanes are merged.
- Finish with `./plans/verify.sh full`.
- Treat `./plans/contract_check.sh` and `./plans/contract_review_validate.sh` as review-artifact helpers only. They are not stand-alone contract validators and should be used only from the workflow that supplies `CONTRACT_REVIEW_OUT` or the review JSON path they require.

## Assumptions and Defaults

- This plan fixes the Phase 1 blocking set plus the tightly-coupled hardening items that share the same touchpoints and proof bundle: `G3-S4SCHEMA`, `G6-FEEPROOF`, and the Phase 1 linked-order gate-shape clarification. It does not claim to land every hardening item from the broader audit.
- If a contract anchor or AT title must change, only patch broken references; do not re-phase the backlog here.
- `AmountSemantics` governs canonical sizing and outbound amount-field selection only; product-family constraints remain under `InstrumentKind`/`InstrumentFamily` and are not collapsed into a 2-way sizing enum.
- Risk-reducing actions always take precedence over data-quality or profitability gates.
- Canonical `s4` labels are treated as strict identity artifacts, not heuristic hints.
- Replay/WAL state is audit and reconciliation input, not independent authorization to create fresh OPEN risk.
- Startup OPEN blocking is unconditional on boot: replay outcome is reconciliation input and diagnostics, not the condition that turns the startup latch on.
- Atomic trade-id durability is the preferred implementation path for this slice; `apply_pending` is an explicit fallback only if the same exactly-once proof cannot be met atomically within Phase 1.
- After Net Edge becomes the sole profitability gate, Pricer still fails closed on bad numerics and those rejects are treated as safety failures, not as implicit evidence that the order was unprofitable.
- Hardening items are batched into the same lane only when they share the same touchpoints and proof bundle; otherwise they stay as explicit follow-on tasks inside the lane order above.

## Phase 2 Follow-Up Handoff

- Use `docs/plans/2026-03-05-phase-1-contract-audit-followup.md` as the canonical shortlist for contract-tightening items intentionally kept out of this Phase 1 remediation lane.
- Pull `FUP-001` through `FUP-005` into the next Phase 2 contract-tightening pass first, then fold `FUP-006` if Inventory Skew semantics are already open.
- Keep `FUP-007` and `FUP-008` as independent hardening unless they can land without reopening the Phase 1 blocker set above.
- The authoritative verdict and blocking-gap analysis remain in `reviews/reconciliations/slice1/PHASE1_CONTRACT_LOSS_RISK_AUDIT_2026-03-05.md`; this handoff only captures deferred follow-up scope.
