# Story Premortem: S6-013

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> Premortem Schema: v2
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: `S6-013` / `UPGRADE-1B-PR4` share execution tail + runtime reject-code ownership cleanup.
- Contract clause(s): `specs/CONTRACT.md` `AT-909`, `AT-910`, `AT-911`, `CSP.3 RecordedBeforeDispatch (WAL)`.
- Acceptance tests: AT-909, AT-910, AT-911
- Touch scope: `crates/soldier_core/src/execution/{engine.rs,open_runtime.rs,pipeline.rs,orchestration_tail.rs}`, runtime/engine unit tests, and the PR1 upgrade doc snippet.
- **Risk rating**: MED
  - HIGH if touching: persistence/replay/idempotency, order placement/funds movement,
    risk limits, auth/keys, or anything that can silently weaken gates.

## Trading Risk Hard Gate

Before implementation, prove this change cannot create avoidable loss, cannot silently block
valid profit, and is the simplest fail-closed design satisfying the contract.

Hard-gate questions — must be answered before implementation starts.
If any answer is NO, UNKNOWN, or NOT PROVEN, implementation is blocked until the gap is resolved or explicitly escalated.

- Loss prevention:
  Have I proven that this change cannot directly or indirectly create avoidable loss through incorrect orders, widened risk, blocked reductions, stale decisions, reconciliation drift, duplicate actions, or fail-open behavior?
- Profit preservation:
  Have I proven that this change will not silently block valid profit by rejecting good trades, delaying valid actions, degrading signal quality, misclassifying intent, or creating unnecessary operational friction?
- Best design choice:
  Is this the safest and simplest design currently available for this feature, given the contract, expected edge, and operational constraints?
- Better alternative check:
  Did I actively test whether there is a simpler or safer implementation that achieves the same goal with fewer moving parts, less hidden coupling, and lower error surface?
- Failure-path correctness:
  Does the design remain correct under bad inputs, stale state, retries, partial failures, exchange/API errors, replay, restart, and reconciliation?
- Fail-closed enforcement:
  When uncertain, missing data, or inconsistent state occurs, does the system fail closed in a way that protects capital and preserves the ability to reduce risk?
- Proof, not belief:
  Can each critical claim above be tied to a specific contract clause, enforcement point, and verification artifact rather than intuition or prose?

Required answer format:
- Answer: YES / NO / UNKNOWN
- Why: one sentence
- Proof: contract clause(s), enforcement file(s), test/vector/artifact
- Gap ID: required when answer is NO or UNKNOWN

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | YES | The cleanup removes stale reject-code authority and keeps OPEN fail-closed behavior in the runtime-owned sidecar before any dispatch path is reached. | `AT-910`, `AT-911`, `CSP.3`; `crates/soldier_core/src/execution/open_runtime.rs`; `cargo test -p soldier_core open_runtime -- --nocapture` | |
| Profit preservation | YES | Runtime-side reject metadata now survives inventory-skew and override paths, preventing false runtime-step attribution that could over-block valid diagnosis or follow-up handling. | `AT-909`, `AT-910`, `AT-911`; `crates/soldier_core/src/execution/engine.rs`; `cargo test -p soldier_core engine_decision -- --nocapture` | |
| Best design choice | YES | A single runtime-output authority plus a neutral shared tail is simpler than parallel input/output sidecars or pipeline-shaped helper reuse. | `CSP.3`; `crates/soldier_core/src/execution/orchestration_tail.rs`; review artifact `artifacts/story/UPGRADE-1B-PR4/self_review/REVIEW_STACK.md` | |
| Better alternative check | YES | The review explicitly considered and then removed the dead public sidecar and the pipeline-shaped helper as simpler/safer corrections. | `artifacts/story/UPGRADE-1B-PR4/self_review/REVIEW_STACK.md`; `crates/soldier_core/src/execution/engine.rs`; `crates/soldier_core/src/execution/pipeline.rs` | |
| Failure-path correctness | YES | Pending-exposure, global-budget, unknown-liquidity-detail, and inventory-skew reject paths now all preserve deterministic reject-code and runtime-step evidence. | `AT-909`, `AT-910`, `AT-911`; `crates/soldier_core/src/execution/open_runtime_wiring_tests.rs`; `cargo test -p soldier_core open_runtime -- --nocapture` | |
| Fail-closed enforcement | YES | The shared-tail extraction preserves the same chokepoint gate order and `RecordedBeforeDispatch` requirement while only moving helper ownership. | `CSP.3 RecordedBeforeDispatch (WAL)`; `crates/soldier_core/src/execution/orchestration_tail.rs`; `cargo test -p soldier_core pipeline -- --nocapture` | |
| Proof, not belief | YES | Every claimed safety outcome is tied to concrete execution files and targeted soldier_core test runs captured in the review stack and follow-up commands. | `plans/prd.json S6-013`; `artifacts/story/UPGRADE-1B-PR4/self_review/REVIEW_STACK.md`; cargo test artifacts named above | |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)

For each `enforcing_contract_ats` claimed by this story, find the AT in `specs/CONTRACT.md`,
extract the normative clause, and classify. Skip informational clauses.

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-909 | §1.3 Liquidity Gate | Missing/stale L2 for OPEN must reject deterministically with liquidity-gate reason and no dispatch. | MUST | Yes |
| AT-910 | §1.4.2.1 Pending exposure reservation | Reservation overfill must reject OPEN and no dispatch occurs. | MUST | Yes |
| AT-911 | §1.4.2.2 Global exposure budget | Correlation-aware budget breach must reject OPEN and no dispatch occurs. | MUST | Yes |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | OPEN reject-code authority is runtime-output owned only. | Caller updates a dead input sidecar and engine maps the wrong code. | `engine_open_inventory_skew_reject_maps_runtime_step` and liquidity fallback mapping tests | Yes |
| 2 | Shared-tail extraction is behavior-preserving. | Pipeline or OPEN runtime diverges on chokepoint verdict/reject-code translation. | `cargo test -p soldier_core pipeline -- --nocapture` and `cargo test -p soldier_core open_runtime -- --nocapture` | Yes |
| 3 | Override branches must stamp cascade skip codes explicitly. | Pending/global reject paths lose downstream provenance and hide why pricer/net-edge did not run. | `test_unregistered_instrument_rejected_through_runtime` | Yes |

## 3) Top 5 failure modes
For each enforcement-point input/intermediate, run the fail-closed 6-category sweep:
`Missing/None`, `NaN/Inf`, `Negative`, `Out-of-domain`, `Corrupt/garbage`, `Narrowing casts`.

| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Unknown liquidity detail falls back to a hard-coded reason code | Engine reject-code mapping test fails when output-side code differs | Runtime uses `OpenRuntimeOutput.gate_reject_codes` as the sole fallback authority | AT-909 |
| 2 | Pending exposure or global budget override drops downstream cascade skip codes | OPEN wiring tests observe missing `GateCascadeSkip` on net-edge/pricer | Runtime stamps all override sidecars before the shared tail runs | AT-910, AT-911 |
| 3 | Inventory-skew reject loses adjusted min-edge metadata | Engine maps to generic net-edge gate instead of runtime inventory-skew step | Runtime preserves `adjusted_min_edge_usd` and exact `NetEdgeTooLow` sidecar | AT-909 |
| 4 | Shared-tail extraction changes `RecordedBeforeDispatch` semantics | Pipeline/open-runtime test suites diverge or OPEN dispatch path gains a pre-WAL side effect | Neutral helper wraps existing chokepoint/WAL behavior only; no dispatch code moved | CSP.3 |
| 5 | Public doc or facade still advertises the dead input sidecar | Future callers populate the wrong field and assume it matters | Remove field from public input type and update doc snippet | AT-909 |

- [x] 6-category fail-closed sweep completed for each enforcement input/intermediate
- [x] Each category has explicit detection + mitigation, or is marked N/A with rationale

## 4) Open decisions (resolve before coding)

### Decision: canonical story ID vs PR4 alias
- **What is ambiguous / missing**: Review tooling referred to `UPGRADE-1B-PR4`, but `plans/prd.json` only accepts canonical `S{slice}-{NNN}` story IDs.
- **Evidence** (file + anchor or snippet): `plans/prd_schema_check.sh` enforces `id format must be S{slice}-{NNN}`.
- **Options**:
  1. Option A — Add a non-canonical PRD item `UPGRADE-1B-PR4`; blast radius: schema/lint failure; verification: none because gate would fail.
  2. Option B — Add canonical `S6-013` and embed the `UPGRADE-1B-PR4` alias in the story text/premortem; blast radius: none beyond one new story; verification: `./plans/prd_gate.sh` and `bash plans/premortem_gate.sh S6-013`.
- **Chosen**: (B) — deciding factor: preserves repo schema validity while restoring traceability for the PR4 label.
- **Why not others**: Non-canonical IDs are rejected before the PRD can be trusted.
- **Scope control**:
  - What we're NOT doing yet (subordinate): changing workflow tooling to support alternate story ID families.
  - What unblocks us if this choice is wrong (elevate): add explicit alias support to PRD/workflow schemas in a separate workflow story.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)
- [x] If ambiguity remains, mark blocked (`needs_human_decision=true` in `plans/prd.json`) and STOP

## 5) Wrong implementation gate
For EACH AT claimed by this story:

| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-909 | Always map unknown liquidity detail to `LiquidityGateNoL2` | Y | Ignores runtime-produced reject-code provenance and hides future liquidity reasons | Strengthened `open_runtime_unknown_liquidity_detail_falls_back_to_gate_reject_codes` with a second code |
| AT-910 | Reject pending-exposure path but omit downstream `GateCascadeSkip` sidecars | Y | The business reject happens, but causality/provenance is incomplete | `test_unregistered_instrument_rejected_through_runtime` now asserts liquidity/net-edge/pricer sidecars |
| AT-911 | Global-budget or inventory-skew path returns the right verdict but no runtime-step provenance | Y | Engine can surface the wrong step and degrade operator diagnosis | `engine_open_inventory_skew_reject_maps_runtime_step` and runtime wiring assertions pin the step and sidecar |

- [x] Every AT has at least one wrong impl identified
- [x] Any wrong impl marked "Y" (easier) is the highest-priority tightening test
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

> **Proof graph (v2)**: This section's data feeds `proof_graph.json`. After implementation, run
> `python3 python/proof_graph/init.py <STORY_ID> --premortem-path reviews/premortems/<STORY_ID>_premortem.md` to generate the skeleton, then fill in
> verdicts, test names, and wiring status. The validator (`validate.py --strict`) enforces
> consistency at pass-flip time. See `python/proof_graph/` for schema details.

For each AT, map the full proof chain. Safety-critical ATs MUST have both TRIP and NON-TRIP.

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-909 | `open_runtime_to_decision()` fallback mapping via `OpenRuntimeOutput.gate_reject_codes` | `crates/soldier_core/src/execution/engine_decision_tests.rs::open_runtime_unknown_liquidity_detail_falls_back_to_gate_reject_codes` | Yes | Yes | reject_reason | Yes |
| AT-910 | Pending exposure override in `build_open_order_intent_runtime()` | `crates/soldier_core/src/execution/open_runtime_wiring_tests.rs::test_unregistered_instrument_rejected_through_runtime` | Yes | Yes | reject_reason | Yes |
| AT-911 | Global budget override + shared-tail preservation in `build_open_order_intent_runtime()` / `run_orchestration_tail()` | `cargo test -p soldier_core open_runtime -- --nocapture` and `cargo test -p soldier_core pipeline -- --nocapture` | Yes | Yes | reject_reason | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: OPEN runtime cleanup regresses reject-code authority or shared-tail semantics, causing a risk-increasing OPEN path to lose fail-closed gating or produce misleading reject diagnostics.
- **Fail-closed cap on loss** (what restricts exposure): DispatcherChokepoint plus `RecordedBeforeDispatch` still gate OPEN dispatch, and targeted tests trip before code can silently drift.
- **Drift metric** (exact metric/counter name, or `NONE` — justify): `gate_sequence_total`
- **Loss boundary** (ReduceOnly? Kill? Position limit? Time bound?): OPEN remains bounded by Pending Exposure, Global Budget, Margin Gate, and `RecordedBeforeDispatch`.
- **Rollback plan** (how to revert if it fails): revert `4735a454` and re-run the targeted soldier_core test set before reattempting the cleanup slice.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: OPEN runtime reject-code ownership; pending/global override causality; inventory-skew runtime-step mapping; shared chokepoint tail ownership; `RecordedBeforeDispatch` preservation.
- **If conflict with `specs/CONTRACT.md`**: STOP — do not proceed until resolved
- **If touching `specs/CONTRACT.md`**: run `plans/check_contract_change_ledger.sh`; missing ledger row = BLOCKED
- **If touching workflow/harness paths** (`plans/*`, `specs/WORKFLOW_CONTRACT.md`, `plans/workflow_contract_map.json`): verify workflow-rule alignment; run `./plans/workflow_contract_gate.sh` when applicable
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/open_runtime.rs`, `crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_core/src/execution/engine.rs`
- Struct fields I'm assuming exist (verify before coding): `OpenRuntimeOutput.gate_reject_codes`, `OpenRuntimeOutput.adjusted_min_edge_usd`, `GateRejectCodes.net_edge_gate`
- State machine transitions affected: none beyond OPEN pre-dispatch reject classification

## 9) Constraint I expect to hit

> The supervisor injects the prior postmortem path. Read section 8 (Next-Story Startup Note).

Prior Postmortem: NONE
Reused Guardrail: NONE

- Carry-forward from prior postmortem (paste startup note): none
- What will slow me down: proving that a cleanup-only refactor still preserves the execution chokepoint invariants without broad re-verification.
- Exploit (workaround for this story): use the existing targeted soldier_core suites (`engine_decision`, `open_runtime`, `pipeline`) and the review-stack artifact as focused proof.
- Smallest fix that prevents it next time: create a canonical PRD story/premortem at the same time the cleanup slice is branched so review tooling never loses the mapping.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no `specs/CONTRACT.md` conflicts)
- [x] No new debt without `gap_id` + owner + target slice
