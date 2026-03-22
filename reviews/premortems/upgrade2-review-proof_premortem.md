# Story Premortem: upgrade2-review-proof

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> Premortem Schema: v2
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: upgrade2-review-proof -- retroactive proof slice for the already-implemented Upgrade 2 telemetry follow-up on branch `upgrade2`
- Contract clause(s): `specs/CONTRACT.md` §1.1.1 (AT-908, AT-926), §1.4.2.1 (AT-225, AT-910), §1.4 Inventory Skew clauses (AT-043, AT-922, AT-030), §1.4.4 (AT-916), `CSP.3.2 WAL Degradation Semantics`
- Acceptance tests: AT-916, AT-908, AT-926, AT-043, AT-922, AT-030, AT-225, AT-910
- Touch scope: `reviews/premortems/upgrade2-review-proof_premortem.md`; reviewed implementation at `upgrade2` head `912a2efa` spans `crates/soldier_core/src/execution/{preflight.rs,post_only_guard.rs,build_order_intent.rs,routing.rs,gate.rs,quantize.rs,pricer.rs,inventory_skew.rs}`, `crates/soldier_core/src/risk/{margin_gate.rs,pending_exposure.rs,exposure_budget.rs}`, and `plans/lint_graybox_telemetry.sh`
- **Risk rating**: HIGH
  - The companion branch does not change runtime behavior, but the implementation under proof touches preflight fail-closed behavior, dispatch/WAL degradation semantics, and multiple risk gates. A bad proof could falsely certify a merge-ready safety slice.

## Trading Risk Hard Gate

Before implementation, prove this change cannot create avoidable loss, cannot silently block
valid profit, and is the simplest fail-closed design satisfying the contract.

Hard-gate questions — must be answered before implementation starts.
If any answer is NO, UNKNOWN, or NOT PROVEN, implementation is blocked until the gap is resolved or explicitly escalated.

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | YES | The companion branch adds proof only; the reviewed runtime diff still preserves fail-closed rejects for preflight, quantize, inventory skew, and pending exposure. | `specs/CONTRACT.md` §1.4.4 AT-916, §1.1.1 AT-908/AT-926, §1.4 Inventory Skew AT-043/AT-922/AT-030, §1.4.2.1 AT-225/AT-910; `crates/soldier_core/src/execution/preflight_tests.rs`; `crates/soldier_core/src/execution/quantize_tests.rs`; `crates/soldier_core/src/execution/inventory_skew_tests.rs`; `crates/soldier_core/src/risk/pending_exposure.rs` tests | |
| Profit preservation | YES | The reviewed changes are telemetry/plumbing fixes plus one missing preflight reject test, and the non-trip paths for preflight, quantize, inventory skew, and WAL degradation remain explicitly covered. | `crates/soldier_core/src/execution/preflight_tests.rs`; `crates/soldier_core/src/execution/quantize_tests.rs`; `crates/soldier_core/src/execution/inventory_skew_tests.rs`; `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs`; review artifact `artifacts/story/upgrade2/self_review/20260321T172737Z_self_review.md` | |
| Best design choice | YES | A companion proof branch is safer than widening PR #228 because it isolates proof assets without rewriting or rebasing the already-reviewed runtime diff. | Active project scope in `obsidian/Projects/Upgrade 2 Telemetry Completion.md`; companion branch/project scope in `obsidian/Projects/Upgrade 2 Review Proof.md` | |
| Better alternative check | YES | Local-only proof would be ephemeral and widening the open PR would violate the repo's scope rules, so the companion branch is the least risky durable option. | `AGENTS.md` project-scope rules; project note mismatch observed on `upgrade2`; user-selected direction captured in session | |
| Failure-path correctness | YES | The reviewed runtime diff explicitly targeted previously open failure paths: preflight/post-only wrapper leakage, graybox inline metric mutation, wrapper bypasses, and `no_gate_configured` WAL visibility. | `crates/soldier_core/src/execution/preflight.rs`; `plans/lint_graybox_telemetry.sh`; `crates/soldier_core/src/execution/routing.rs`; `crates/soldier_core/src/execution/dispatch_chokepoint_contract_tests.rs` | |
| Fail-closed enforcement | YES | The reviewed gates still reject or no-op safely under invalid metadata, missing delta limits, over-budget reservations, and post-only crossing, while CSP.3.2 still allows risk-reducing intents through WAL degradation. | `specs/CONTRACT.md` §1.1.1, §1.4.2.1, §1.4.4, `CSP.3.2`; `crates/soldier_core/src/execution/build_order_intent.rs`; `crates/soldier_core/src/execution/routing.rs`; relevant tests in `preflight_tests.rs`, `quantize_tests.rs`, `inventory_skew_tests.rs`, and `pending_exposure.rs` | |
| Proof, not belief | YES | Mutation-grade `/devils-advocate` proof is complete and companion PR #232 carries the summary back into the `upgrade2` lineage without widening PR #228. | `artifacts/story/upgrade2-review-proof/self_review/20260321T185909Z_devils_advocate.md`; `artifacts/story/upgrade2-review-proof/self_review/20260321T185909Z_self_review.md`; PR #232 body; PR #228 comment linking #232 | |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-916 | §1.4.4 | `post_only == true` and crossing the book must reject with `Rejected(PostOnlyWouldCross)` before dispatch. | MUST | Yes |
| AT-908 | §1.1.1 | OPEN intent with `qty_q < min_amount` after quantization must reject with `Rejected(TooSmallAfterQuantization)` and no dispatch. | MUST | Yes |
| AT-926 | §1.1.1 | OPEN intent with missing/unparseable instrument metadata must reject with `Rejected(InstrumentMetadataMissing)` and no dispatch. | MUST | Yes |
| AT-043 / AT-922 | §1.4 Inventory Skew | Missing/unparseable `delta_limit` must fail closed and reject with `Rejected(InventorySkewDeltaLimitMissing)` with no dispatch. | MUST | Yes |
| AT-030 | §1.4 Inventory Skew | `inventory_bias = 1.0` with `inventory_skew_tick_penalty_max = 3` must shift exactly 3 ticks. | MUST | Yes |
| AT-225 / AT-910 | §1.4.2.1 PendingExposure | Reservation must reject over-budget intents before dispatch and must never overfill shared exposure budget. | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Moving instance-metric mutation into observer sinks does not change runtime allow/reject decisions or reject reasons. | A sink refactor could silently drop an event, lose a reject reason, or stop incrementing wrapper-visible counters. | Graybox + wrapper parity tests in `preflight_tests.rs`, `quantize_tests.rs`, `inventory_skew_tests.rs`, `margin_gate_tests.rs`, and `pending_exposure.rs` tests. | YES |
| 2 | Replacing the routing no-gate direct bump/log path with `emit_wal_nonblocking_allowed(...)` preserves CSP.3.2 semantics and the legacy source labels. | A helper mismatch could either block a risk-reducing intent or emit the wrong WAL visibility diagnostic. | `crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs`; `crates/soldier_core/src/execution/dispatch_chokepoint_contract_tests.rs`; `specs/CONTRACT.md` `CSP.3.2`. | YES |
| 3 | A proof-only companion branch can produce durable review context without yet changing PR #228 itself. | If the proof assets never flow back to the runtime branch, the companion branch only proves a local review exercise and not a merge-ready state. | Companion PR #232 into `upgrade2`; PR #228 comment linking #232; mutation summary copied into PR text because `artifacts/story/` is gitignored. | YES |

## 3) Top 5 failure modes
For each enforcement-point input/intermediate, run the fail-closed 6-category sweep:
`Missing/None`, `NaN/Inf`, `Negative`, `Out-of-domain`, `Corrupt/garbage`, `Narrowing casts`.

| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | `preflight_intent_with_events(...)` calls `check_post_only(...)` and leaks post-only wrapper counters/metric lines through graybox preflight. | Graybox preflight test sees `post_only_reject_total()` change or metric lines emitted. | Route through `check_post_only_with_events(...)` with `NoopEvents`; map crossing back to `PreflightReject::PostOnlyWouldCross` only. | AT-916 |
| 2 | A `_with_events(...)` seam mutates `metrics.record_*()` inline or calls its plain wrapper sibling, making graybox seams telemetry-impure again. | `plans/lint_graybox_telemetry.sh` or `plans/tests/test_lint_graybox_telemetry.sh` fails. | Keep mutation in observer sinks and ban wrapper bypasses in lint. | Guardrail for AT-908/AT-926/AT-043/AT-922/AT-225/AT-910 proof purity |
| 3 | `routing.rs` logs or bumps WAL nonblocking directly for `no_gate_configured`, bypassing the chokepoint sink and drifting source labels. | Static chokepoint contract test finds forbidden direct bump/log string; runtime review sees mismatched source labels. | Emit through `build_order_intent::emit_wal_nonblocking_allowed(...)` so production sink owns both counter and warning. | `CSP.3.2` |
| 4 | Observer-sink refactor preserves runtime rejects but drops wrapper-visible metric/tracing behavior, causing operators to lose diagnostics while tests still pass on return values. | Wrapper metric-line tests fail or runtime metric lines no longer contain expected structured labels. | Keep `Production*Events` adapters wired to the legacy bump/tracing helpers and preserve existing wrapper tests. | AT-908 / AT-926 / AT-043 / AT-922 / AT-225 / AT-910 wrapper tests |
| 5 | Proof branch diverges from `upgrade2` head, so the premortem and rerun review no longer describe the code under PR #228. | HEAD mismatch between companion branch baseline and reviewed runtime branch. | Keep companion branch based on `912a2efa`; record reviewed head explicitly in artifacts and use companion PR #232 against `upgrade2` instead of rebasing runtime code on this branch. | Reviewed-head pinning containment |

- [x] 6-category fail-closed sweep completed for each enforcement input/intermediate
- [x] Each category has explicit detection + mitigation, or is marked N/A with rationale

## 4) Open decisions (resolve before coding)

### Decision: Proof location for the missing premortem
- **What is ambiguous / missing**: The runtime branch `upgrade2` already has an open PR and its declared project scope does not include `reviews/premortems/*`.
- **Evidence** (file + anchor or snippet): `obsidian/Projects/Upgrade 2 Telemetry Completion.md` frontmatter `scope_paths`; missing premortem noted in that project's 2026-03-21 log.
- **Options**:
  1. Option A — Widen PR #228 and add premortem there; fastest path but violates the repo's project-scope rule for this branch.
  2. Option B — Create a companion branch with a new project note and keep proof-only assets there; slower, but it preserves PR #228's scope and still creates durable proof artifacts.
  3. Option C — Create the premortem locally only and never commit it; fastest local retry, but no durable review record.
- **Chosen**: B — deciding factor: durable proof without widening the active runtime PR.
- **Why not others**: Option A violates the current project scope; Option C creates ephemeral proof that does not survive handoff.
- **Scope control**:
  - What we're NOT doing yet (subordinate): rebasing or retargeting PR #228.
  - What unblocks us if this choice is wrong (elevate): create a dedicated follow-up PR from this companion branch into `upgrade2`.

### Decision: How much of the runtime diff this premortem owns
- **What is ambiguous / missing**: The reviewed runtime branch touched multiple original execution/risk stories, but the proof gap is narrow: missing slice-level premortem and review-proof context.
- **Evidence** (file + anchor or snippet): reviewed diff at `upgrade2` head `912a2efa`; non-passing self-review artifact under `artifacts/story/upgrade2/self_review/`.
- **Options**:
  1. Option A — Attempt a full new story decomposition and assign every touched runtime file back to one original story.
  2. Option B — Treat this as a retroactive proof slice that owns the follow-up review concerns while citing the already-implemented runtime head and its proving tests.
- **Chosen**: B — deciding factor: the gap is review-proof completeness, not new runtime ownership.
- **Why not others**: Option A is ceremony-heavy and does not improve the actual safety proof for the current branch head.
- **Scope control**:
  - What we're NOT doing yet (subordinate): rewriting historical story ownership for the underlying runtime code.
  - What unblocks us if this choice is wrong (elevate): split the proof slice by original story family and rerun review per story.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)
- [x] If ambiguity remains, mark blocked (`needs_human_decision=true` in `plans/prd.json`) and STOP

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-916 | `preflight_intent_with_events(...)` calls `check_post_only(...)` instead of `check_post_only_with_events(...)`. | Y | Graybox preflight leaks post-only wrapper counters and metric lines, so the seam is no longer telemetry-pure. | `test_preflight_graybox_post_only_crossing_emits_reject_event_without_global_side_effects`; wrapper-bypass rule in `plans/lint_graybox_telemetry.sh`. |
| AT-908 / AT-926 | `_with_events(...)` bodies mutate `metrics.record_*()` inline, keeping runtime returns correct but making the graybox proof cosmetic. | Y | The code appears seam-converted while still mutating instance telemetry in the leaf body. | Inline-mutation ban plus fixture in `plans/tests/test_lint_graybox_telemetry.sh`; parity tests in `quantize_tests.rs`. |
| AT-043 / AT-922 / AT-030 | Inventory skew sink refactor drops `Allowed` or `InventorySkewDeltaLimitMissing` event accounting while still returning the right `InventorySkewResult`. | N | Operators lose wrapper metrics/tracing even though return values remain right. | Graybox success/reject tests and wrapper metric-line test in `inventory_skew_tests.rs`. |
| AT-225 / AT-910 | Pending exposure sink refactor emits the same result but stops surfacing reject/idempotent event context or wrapper metrics. | N | Budget protection still blocks dispatch, but review/debug evidence degrades and future proof claims become weaker. | Graybox reject/context tests plus wrapper structured metric-line test in `pending_exposure.rs` tests. |
| `CSP.3.2` | `routing.rs` keeps a direct no-gate bump/log path instead of routing through the chokepoint sink. | Y | The nonblocking WAL diagnostic splits ownership between routing and chokepoint, making source-tag drift and future bypasses easier. | Static chokepoint test `test_routing_no_gate_configured_uses_chokepoint_event_sink`; wrapper/source-label assertions in `build_order_intent_gate_ordering_tests.rs`. |

- [x] Every AT has at least one wrong impl identified
- [x] Any wrong impl marked "Y" (easier) is the highest-priority tightening test
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

> **Proof graph (v2)**: This section's data feeds `proof_graph.json`. After implementation, run
> `python3 python/proof_graph/init.py <STORY_ID> --premortem-path reviews/premortems/<STORY_ID>_premortem.md` to generate the skeleton, then fill in
> verdicts, test names, and wiring status. The validator (`validate.py --strict`) enforces
> consistency at pass-flip time. See `python/proof_graph/` for schema details.

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-916 | `crates/soldier_core/src/execution/preflight.rs` via `check_post_only_with_events(...)` | `test_preflight_graybox_post_only_crossing_emits_reject_event_without_global_side_effects`; `test_preflight_graybox_post_only_non_crossing_emits_no_events_or_global_side_effects` | Yes | Yes | `reject_reason` + no global metric side effects | Yes |
| AT-908 | `crates/soldier_core/src/execution/quantize.rs` too-small reject path | `test_quantize_graybox_emits_reject_event_without_global_side_effects`; `test_quantize_graybox_success_emits_no_events_or_global_side_effects`; existing AT-908 tests in `quantize_tests.rs` section | Yes | Yes | `reject_reason` + no dispatch values | Mostly |
| AT-926 | `crates/soldier_core/src/execution/quantize.rs` metadata-missing reject path | Existing AT-926 tests in `quantize_tests.rs` metadata section; `test_quantize_graybox_success_emits_no_events_or_global_side_effects` | Yes | Yes | `reject_reason` | Mostly |
| AT-043 / AT-922 / AT-030 | `crates/soldier_core/src/execution/inventory_skew.rs` | `test_inventory_skew_missing_delta_limit_fails_closed`; `test_inventory_skew_graybox_emits_reject_event_without_global_side_effects`; `test_inventory_skew_tick_penalty_max_is_exactly_3_ticks_at_bias_1_0`; `test_inventory_skew_graybox_success_emits_no_events_or_global_side_effects` | Yes | Yes | `reject_reason` or exact adjusted value | Yes |
| AT-225 / AT-910 | `crates/soldier_core/src/risk/pending_exposure.rs` reservation guard | `test_reserve_graybox_reject_emits_event_without_global_side_effects`; `test_cross_instrument_collision_graybox_preserves_event_context`; existing concurrent reserve tests in `pending_exposure.rs` | Yes | Yes | `reject_reason` + dispatch blocked | Mostly |

Causality proof must be one of: `dispatch_count`, `reject_reason`, `latch_reason`, `mode_transition`, `cortex_override`.

If a test exists in `implementation_tests[]` but doesn't prove the AT → mark **CLAIMED-NOT-PROVEN**.
If 2+ ATs interact (e.g., reservation + exposure limit) → require a combined AT or note its absence.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: a false PASS on the companion proof slice could let PR #228 be treated as merge-ready while a telemetry seam still leaks wrapper side effects or loses fail-closed diagnostics in preflight, risk, or WAL degradation handling.
- **Fail-closed cap on loss** (what restricts exposure): the reviewed runtime diff still preserves the underlying reject/allow decisions; the remaining risk is proof quality and operational visibility, not a newly introduced allow-open path.
- **Drift metric** (exact metric/counter name, or `NONE` — justify): `NONE` on this branch because it changes proof assets only; drift is instead detected by rerunning the review artifact against the pinned runtime head and by `plans/lint_graybox_telemetry.sh`.
- **Loss boundary** (ReduceOnly? Kill? Position limit? Time bound?): bounded to review integrity unless the referenced runtime head changes; the companion branch itself does not widen live trading permissions.
- **Rollback plan** (how to revert if it fails): drop the companion proof branch and keep PR #228 in its current explicit non-passing review state; do not use this branch's artifacts as gate evidence.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: AT-916 preflight reject causality; AT-908/AT-926 quantize reject causality; AT-043/AT-922/AT-030 inventory skew fail-closed and exact tick adjustment; AT-225/AT-910 pending exposure reservation reject causality; `CSP.3.2` WAL degradation permissiveness for risk-reducing intents.
- **If conflict with `specs/CONTRACT.md`**: STOP — do not proceed until resolved.
- **If touching `specs/CONTRACT.md`**: not in scope.
- **If touching workflow/harness paths** (`plans/*`, `specs/WORKFLOW_CONTRACT.md`, `plans/workflow_contract_map.json`): this slice may emit review artifacts that reference `plans/lint_graybox_telemetry.sh`, but it does not change workflow enforcement.
- Files with recent churn or shared ownership: `obsidian/Projects/Upgrade 2 Telemetry Completion.md`; `reviews/premortems/*`; `artifacts/story/upgrade2*`; any future attempt to merge proof assets back into `upgrade2`.
- Struct fields I'm assuming exist (verify before coding): `PreflightReject::PostOnlyWouldCross`; `WalNonblockingSource::NoGateConfigured`; `PendingExposureEvent::ReserveRejected`; `InventorySkewRejectReason::InventorySkewDeltaLimitMissing`.
- State machine transitions affected: none on this branch; referenced runtime semantics still rely on existing preflight/risk/disptach state transitions in `upgrade2`.

## 9) Constraint I expect to hit

> The supervisor injects the prior postmortem path. Read section 8 (Next-Story Startup Note).

Prior Postmortem: NONE
Reused Guardrail: Keep proof assets on a dedicated scope when the runtime PR is already open and project-locked.

- Carry-forward from prior postmortem (paste startup note): none
- What will slow me down: proving enough of the runtime safety surface from a proof-only companion branch without pretending the companion branch itself changed runtime behavior.
- Exploit (workaround for this story): anchor every claim to the pinned `upgrade2` head `912a2efa`, cite concrete tests and artifacts, and keep this branch proof-only.
- Smallest fix that prevents it next time: require a slice premortem before the runtime follow-up branch is opened, not after the PR scope is already locked.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- **GREEN**: All gates pass, proof plan complete, no unresolved ambiguities
- **YELLOW**: All non-ambiguity gaps explicitly deferred in Debt Register below
- **RED**: Unresolved gates or unresolved ambiguity — do not implement

**Debt Register**:

None. Mutation-grade proof completed in `20260321T185909Z_devils_advocate.md`, and companion PR #232 now attaches the proof slice to PR #228's branch lineage.

YELLOW with untracked debt (missing `gap_id` or target slice) = RED.
Unresolved ambiguity/design choice = RED (set `needs_human_decision=true` and stop).

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no `specs/CONTRACT.md` conflicts)
- [x] No new debt without `gap_id` + owner + target slice
