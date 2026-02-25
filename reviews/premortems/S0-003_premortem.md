# Story Premortem: S0-003

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-003 — P0-D Break-Glass Runbook + Drill
- Contract clause(s): §Phase 0 P0-D ("Create emergency halt procedure and execute recorded drill")
- Acceptance tests: AT-000 (None formally assigned — no `enforcing_contract_ats` in PRD; this is a policy/documentation story)
- Touch scope: `docs/break_glass_runbook.md`, `evidence/phase0/break_glass/runbook_snapshot.md`, `evidence/phase0/break_glass/drill.md`, `evidence/phase0/break_glass/log_excerpt.txt`
- **Risk rating**: HIGH (despite PRD marking "low")
  - This is the **last-resort safety mechanism**. A break-glass runbook that does not actually halt trading, or a drill that does not actually prove halt capability, creates false confidence in the most critical safety escape hatch. If this story passes with a paper-only drill that never exercises real Kill semantics (§2.2.3.6), the entire safety pyramid has an untested foundation.
  - The `implementation_tests` reference Kill mode enforcement (`test_break_glass_kill_blocks_open_allows_reduce_runtime`, `test_break_glass_command_path_runtime`) -- these are testing the mechanical Kill enforcement, but the *runbook* and *drill* must prove the human-in-the-loop path actually works.

## 1) Clause audit (contract → AT traceability)

This story claims **no** `enforcing_contract_ats`. The contract clause P0-D is an operational prerequisite ("Break-Glass Runbook + Drill") in the Phase 0 table, not a numbered normative section with formal ATs.

However, the break-glass mechanism *relies on* Kill mode semantics defined in:
- §2.2.3.6 Kill Semantics (Capital Supremacy Safe, CSP)
- §2.2.3.4 Dispatch Authorization (Non-Negotiable)
- §0.Z.2.2 item F Capital Supremacy Invariant

| AT | Contract S | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| (none claimed) | Phase 0 P0-D | "Create emergency halt procedure and execute recorded drill" | MUST (Non-Negotiable prerequisite) | Yes -- runbook exists + drill evidence |
| (implicit) | §2.2.3.6 | "Kill SHALL mean: No creation of new exposure. Only risk-reducing actions permitted." | MUST | Yes -- implementation_tests cover this |
| (implicit) | §2.2.3.4 | "If TradingMode == Kill: OPEN intents MUST NOT dispatch; ONLY risk-reducing intents MAY dispatch" | MUST | Yes -- test_break_glass_kill_blocks_open_allows_reduce_runtime |

- [x] Every claimed AT traced to a normative clause (none claimed; implicit dependencies noted)
- [x] No informational-only ATs counted as enforcement

**Blind prediction concern:** The story has no formal ATs, so "passing" is based on document review criteria (GIVEN/WHEN/THEN on document contents). This means acceptance is subjective -- a reviewer must judge whether the runbook "has STOP TRADING steps." There is no automated gate. This is the weakest link.

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Kill mode actually blocks OPEN intents at runtime | Kill mode has a bug that still lets OPENs through; runbook says "set Kill" but Kill does not actually work | `test_break_glass_kill_blocks_open_allows_reduce_runtime` (implementation_test) | Depends on test quality |
| 2 | There is a command/signal path to trigger Kill mode from outside the running process (e.g., file touch, signal, API call) | No external trigger mechanism exists; operator must modify code and redeploy to halt | `test_break_glass_command_path_runtime` (implementation_test) | Depends on test quality |
| 3 | The drill actually exercises the real command path, not a simulated/mocked version | Drill uses a mock environment that does not reflect production topology; Kill works in test but not in prod | Drill log excerpt must show real system logs, not synthetic output | Cannot be automated |
| 4 | The runbook is executable by a panicked operator under stress (not just a developer who wrote it) | Steps are too technical, assume unstated context, or require tools not available during an incident | Drill should be executed by someone who did NOT write the runbook | Process check only |
| 5 | Risk-reducing dispatches (CLOSE/HEDGE) remain available under Kill mode so the operator can actually unwind exposure | Kill mode blocks everything including risk-reducing actions, creating a deadlock | §2.2.3.6 Capital Supremacy Invariant; `test_break_glass_kill_blocks_open_allows_reduce_runtime` should verify CLOSE is permitted | Depends on test quality |
| 6 | The runbook's "verify no further OPEN risk" step actually checks for inflight/queued orders, not just TradingMode state | TradingMode is Kill but there are already-dispatched orders in flight that will fill | Runbook must include checking open orders on exchange, not just local state | Document review only |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **Runbook says "set Kill" but Kill does not block OPENs** -- the critical gate (§2.2.3.4 dispatch authorization) has a code path that bypasses the check, or Kill is not wired through to the dispatcher | Drill execution: attempt an OPEN after triggering Kill; check if it dispatches | Implementation test `test_break_glass_kill_blocks_open_allows_reduce_runtime` must prove OPEN dispatch_count == 0 under Kill | Implementation test (if it actually asserts dispatch_count) |
| 2 | **Drill is paper-only** -- drill.md describes a scenario but no actual system was running; log_excerpt.txt is fabricated or from an unrelated run | Log excerpt must contain timestamps, intent IDs, and Kill-mode transition entries that are internally consistent | Require log_excerpt.txt to show: (a) system running, (b) Kill triggered, (c) OPEN rejected, (d) CLOSE permitted -- all with monotonic timestamps | Document review (no automated AT) |
| 3 | **Runbook missing "cancel outstanding OPENs" step** -- Kill blocks new dispatches but orders already on the exchange continue to fill; runbook does not tell operator to cancel them | Review runbook for §2.2.3.4.1 Non-Active OPEN Cancellation coverage | Runbook must include: "verify all outstanding OPEN orders are cancelled" as a separate step from "set Kill" | Acceptance criterion "has STOP TRADING steps" (vague) |
| 4 | **Command path does not exist or is not documented** -- the runbook says "trigger Kill via X" but X does not exist, or requires SSH access that is unavailable during a real emergency | `test_break_glass_command_path_runtime` should prove the command path works | Drill must exercise the exact command path documented in the runbook | Implementation test + drill evidence |
| 5 | **Kill mode blocks risk-reducing containment** -- a bug in dispatch authorization blocks ALL dispatches under Kill, violating Capital Supremacy (§2.2.3.6) and leaving the operator with exposure they cannot reduce | Implementation test must verify CLOSE/HEDGE dispatches are permitted under Kill | `test_break_glass_kill_blocks_open_allows_reduce_runtime` name implies it tests this ("allows_reduce") | Implementation test (name suggests coverage) |
| 6 | **Network partition prevents operator from reaching the system** -- the emergency is caused by (or coincides with) a network partition; the operator cannot SSH to the server, access the filesystem, or reach any API. The runbook assumes reachability but does not provide a fallback. | Drill should include a "cannot reach system" scenario; runbook must document out-of-band fallback | Runbook MUST include fallback steps for when the system is unreachable: (a) log into exchange dashboard directly and disable/revoke API key, (b) contact exchange support. These are exchange-side kill switches that do not require system access. | No automated AT (process/runbook review) |
| 7 | **Partial Kill propagation** -- Kill mode is correctly set for the primary trading loop, but a secondary component (e.g., a reconnection handler that re-subscribes and triggers order placement, a position sync job, or a scheduled rebalance task) continues to create exposure because it does not check TradingMode. The operator believes trading is halted but a subsystem continues dispatching. | Implementation tests should verify Kill propagates to ALL dispatch paths, not just the primary loop. Review code for any dispatch path that does not consult PolicyGuard. | §2.2.3.4 requires "Every network dispatch attempt MUST consult PolicyGuard immediately before dispatch." If any dispatch path bypasses PolicyGuard, it is a contract violation regardless of this story. The runbook should include a verification step: "confirm /status shows Kill AND no dispatches are occurring (check logs for dispatch events post-Kill)." | Implementation test coverage of all dispatch paths (outside this story's touch scope; see §8 cross-story dependency) |
| 8 | **Drill passes in DEV but runbook fails in PROD due to different deployment topology** -- the command path works on a single-process dev machine, but production has multiple processes, containers, or a different filesystem layout. The file sentinel path differs, or the process namespace prevents the sentinel from being visible to the trading process. | Runbook must document deployment-topology assumptions (single process? container? what filesystem paths are available?). Drill evidence should note the topology it was executed against. | For Phase 0 (single-process, developer-operated), this is an accepted limitation. The runbook MUST include a "deployment assumptions" section stating the topology it is validated against. When deployment topology changes, the drill MUST be re-executed. | No automated AT (tracked in debt register as drill-fidelity item) |

## 4) Open decisions (resolve before coding)

### Decision: What constitutes a valid "drill"?
- **What is ambiguous / missing**: P0-D says "execute recorded drill proving halt capability" but does not define minimum fidelity. Is a unit test sufficient? Must it be a running instance? Must it be on testnet with real exchange connectivity?
- **Evidence**: `specs/CONTRACT.md` Phase 0 table, P0-D: "Create emergency halt procedure and execute recorded drill" (line ~129). PRD `human_blocker.recommended`: "Execute drill in DEV/STAGING before marking done."
- **Options**:
  1. Option A — Drill runs against a full integration test harness (Rust test binary with mocked exchange) -- proves the Kill command path and dispatch blocking work end-to-end in code
  2. Option B — Drill runs against a live DEV/STAGING instance with (paper) exchange connectivity -- proves the command path works in a deployed environment
  3. Option C — Drill is purely a walkthrough of the runbook with no live system -- proves the runbook is readable but not that the mechanism works
- **Chosen**: A (minimum) + B (ideal) -- The implementation_tests already cover Option A. The drill.md should document exercising the real command path against at least a test harness. Option C alone is unacceptable for a safety-critical escape hatch.
- **Why not others**: Option C creates false confidence -- a runbook that has never been executed against a real system is theater, not safety.
- **Scope control**:
  - What we're NOT doing yet: full production drill with live exchange (that's a later maturity milestone)
  - What unblocks us if this choice is wrong: the implementation_tests provide a mechanical backstop even if the drill is weak

### Decision: Break-glass trigger mechanism
- **What is ambiguous / missing**: The contract does not specify HOW Kill is triggered externally (file-based sentinel? API endpoint? signal? environment variable?). The runbook must document a specific mechanism.
- **Evidence**: `implementation_tests` includes `test_break_glass_command_path_runtime` which implies some command path exists. §2.2.3.6 defines Kill semantics but not the external trigger.
- **Options**:
  1. Option A — File sentinel (e.g., touch `/tmp/kill_switch` or a config file path) -- simple, works without API, survives process restart
  2. Option B — API endpoint (POST /api/v1/kill) -- requires the system to be responsive, which may not hold during an emergency
  3. Option C — Unix signal (SIGUSR1 or similar) -- requires PID knowledge, does not survive restart
- **Chosen**: **Option A (file sentinel) is the preferred mechanism**, pending verification against `test_break_glass_command_path_runtime` during implementation. Rationale: the break-glass trigger must work when the system is unhealthy (the most common reason to invoke it). A file sentinel is external to the process -- it works when the process is hung, does not require the HTTP stack to be responsive, and survives process restarts. If the implementation uses a different mechanism, the runbook MUST match, and the implementer MUST justify why a non-file mechanism is preferable for a last-resort safety escape.
- **Why not others**: Option B (API) fails precisely when it is needed most -- when the process is hung or the HTTP stack is unresponsive. Option C (signal) requires knowing the PID, does not survive restarts, and is fragile in container environments where PID 1 may be an init process. Both are unsuitable as the sole trigger for a last-resort mechanism.
- **Scope control**:
  - What we're NOT doing yet: redundant trigger mechanisms (defense in depth for the trigger itself)
  - What unblocks us if this choice is wrong: the simplest fallback is always "kill the process" (SIGKILL), which is crude but effective
  - **Verification gate**: During implementation, if the actual trigger mechanism differs from file sentinel, the implementer must update this decision with the rationale and re-evaluate the failure modes

### Decision: Kill latency time-bound
- **What is ambiguous / missing**: The contract says Kill SHALL block new exposure, but does not specify how quickly Kill must take effect after the trigger. If Kill takes 30 seconds to propagate, the operator has a false sense of safety while orders continue to dispatch.
- **Evidence**: §2.2.3.4 Dispatch Authorization says "Every network dispatch attempt MUST consult PolicyGuard immediately before dispatch (hot path check)." This implies Kill takes effect at the next tick boundary -- the latency is bounded by the tick interval.
- **Options**:
  1. Option A — Kill takes effect within 1 tick (next PolicyGuard check)
  2. Option B — Kill takes effect within a fixed wall-clock bound (e.g., 500ms)
  3. Option C — No latency requirement (Kill eventually takes effect)
- **Chosen**: A -- Kill must take effect by the next PolicyGuard dispatch check. The drill evidence MUST include wall-clock time from trigger to confirmed halt. The acceptance threshold is: Kill effective within 1 tick interval (or 1 second, whichever is shorter).
- **Why not others**: Option C is unacceptable for a safety mechanism. Option B imposes a wall-clock requirement that may not align with the tick-based architecture. Option A is the natural boundary given §2.2.3.4's "immediately before dispatch" requirement.
- **Scope control**:
  - What we're NOT doing yet: sub-millisecond Kill guarantees or interrupt-based preemption
  - What unblocks us if this choice is wrong: the tick interval itself is the bounding factor; if the tick is too slow, that is a system-wide performance issue, not a Kill-specific one

### Decision: Runbook audience
- **What is ambiguous / missing**: Is the runbook for a developer/operator who understands the system internals, or for a non-technical on-call person?
- **Evidence**: PRD `human_blocker`: "Drill requires human execution and observation" -- implies a human operator. Contract P0-D: "emergency halt procedure" -- implies time pressure.
- **Options**:
  1. Option A — Developer-level runbook (assumes SSH access, knowledge of system architecture)
  2. Option B — Operator-level runbook (step-by-step, no assumed knowledge beyond "can access the server")
- **Chosen**: A (for Phase 0) -- at this stage, the developer IS the operator. But the runbook must be explicit enough that a different developer could execute it.
- **Why not others**: Option B requires operational maturity not yet built.
- **Scope control**:
  - What we're NOT doing yet: PagerDuty/alerting integration, one-click kill buttons
  - What unblocks us if this choice is wrong: runbook can be simplified/expanded later

### Decision: Drill version binding
- **What is ambiguous / missing**: The drill evidence (drill.md, log_excerpt.txt) must reference a specific version of the runbook and the system code. If the drill was run against v0.1 but the current system is v0.8 with different Kill semantics, the drill evidence is stale.
- **Evidence**: Agent A cross-review: "Log excerpt proves drill but from a different system version." Agent C cross-review: "wrong impl: drill.md documents a drill that happened, but the drill used a different version of the runbook than what is committed."
- **Chosen**: Drill evidence MUST include: (a) the git commit hash of the runbook at the time of the drill, (b) the git commit hash or build_id of the system binary exercised, and (c) a statement of whether the committed runbook has been modified since the drill. If the runbook is modified after the drill, the drill MUST be re-executed or the delta explicitly justified as non-material.
- **Why**: Without version binding, drill evidence decays silently. A drill run against a previous version of the runbook or system proves nothing about the current version.
- **Scope control**:
  - What we're NOT doing yet: automated CI re-drill on runbook changes
  - What unblocks us if this choice is wrong: re-running the drill is cheap; the version binding just makes staleness visible

- [x] No unresolved decisions remain (trigger mechanism resolved to file sentinel preferred; latency resolved to within-1-tick; version binding resolved)
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

The story has no formal ATs (no `enforcing_contract_ats`). The acceptance criteria are document-content checks. Analyzing wrong implementations for each acceptance criterion:

| Acceptance Criterion | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| "has STOP TRADING steps" | Runbook says "Step 1: Stop trading" with no detail on HOW | A step that says "stop trading" without specifying the command/mechanism is not actionable under stress | Tighten: runbook must include the exact command/file/signal to trigger Kill, and the expected system response |
| "has verify no further OPEN risk" | Runbook says "check that no new orders are being placed" without saying HOW to check | Operator has no way to verify; they assume it worked | Tighten: must specify how to query open orders (exchange API or system endpoint) and expected result (empty list) |
| "has verify risk reduction possible" | Runbook says "you can still close positions" without proving it | Under Kill mode, CLOSE might actually be blocked by a bug | Tighten: drill must demonstrate a CLOSE dispatch succeeding under Kill mode |
| "has escalation + notify" | Runbook says "notify the team" without specifying WHO, HOW, or WHEN | In a real emergency, "notify the team" is useless without contact info and channels | Tighten: must include specific names/roles, communication channels, and escalation thresholds |
| "drill has trigger scenario" | drill.md says "we simulated a scenario" without describing what was triggered or why | A vague scenario does not prove anything specific was tested | Tighten: must specify the exact condition that warranted break-glass (e.g., "runaway margin utilization exceeding mm_util_kill") |
| "drill has time to halt" | drill.md says "halt was fast" without a measurement | No objective evidence of halt latency | Tighten: must include wall-clock time from trigger to confirmed halt (e.g., "Kill triggered at T+0, last OPEN rejected at T+200ms") |
| "drill has observed behavior" | drill.md says "system behaved as expected" | Vague confirmation bias; does not describe what was actually observed | Tighten: must list specific observable effects (OPENs blocked, CLOSEs permitted, mode_reasons populated, /status reflects Kill) |
| "log_excerpt proves drill occurred" | log_excerpt.txt contains system logs but from a normal run, not a drill | Logs exist but do not show Kill mode transition or OPEN rejection | Tighten: log must contain Kill-mode transition line AND at least one OPEN rejection line |

**Additional wrong implementations (from cross-review):**

| Acceptance Criterion | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| "has STOP TRADING steps" | Runbook says "trigger Kill via `touch /tmp/kill_switch`" but the implementation actually reads a different path (e.g., `/var/soldier/kill`) | The runbook has a concrete command (passes "has steps" check) but the command is wrong. The operator follows the runbook and nothing happens. | Tighten: drill MUST exercise the exact command documented in the runbook. If the drill succeeds, the command is correct. The drill log must show the same command/path as the runbook. |
| "log_excerpt proves drill occurred" | log_excerpt.txt shows OPEN rejection, but the system was in ReduceOnly (not Kill). ReduceOnly also blocks OPENs (§2.2.3.4). The reviewer sees "OPEN rejected" and assumes Kill was tested. | The log does not distinguish between Kill-rejection and ReduceOnly-rejection. The drill "proves" Kill capability but actually tested ReduceOnly. | Tighten: log_excerpt must contain an explicit Kill-mode transition entry (e.g., `trading_mode=Kill`) AND the OPEN rejection reason must be Kill-specific, not a generic "OPEN blocked" message. |

- [x] Every acceptance criterion has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened criterion or new check
- [ ] No criterion remains where a wrong impl is easier than the correct one (CONCERN: all criteria are subjective document reviews with no automated enforcement; a wrong impl IS easier than correct for every single one)

## 6) Proof plan (AT → enforcement → tests)

> **Proof graph (v1.7)**: This section's data feeds `proof_graph.json`. After implementation, run
> `python3 python/proof_graph/scaffold.py <STORY_ID>` to generate the skeleton, then fill in
> verdicts, test names, and wiring status. The validator (`validate.py --strict`) enforces
> consistency at pass-flip time. See `python/proof_graph/` for schema details.

This story has no formal ATs. The `implementation_tests` are the closest thing to enforcement:

| Implementation Test | What it proves | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-------|-----------|-----------------|-----------|
| `test_break_glass_kill_blocks_open_allows_reduce_runtime` | Kill mode blocks OPEN dispatch AND permits CLOSE/HEDGE dispatch | Yes (Kill active --> OPEN blocked) | Yes (Kill active --> CLOSE permitted) | `dispatch_count` (predict: OPEN=0, CLOSE>=1) | Yes (isolates Kill dispatch authorization) |
| `test_break_glass_command_path_runtime` | External command triggers Kill mode transition | Yes (command sent --> mode transitions to Kill) | Unclear | Mode state change | Unclear (may overlap with above) |

**Blind predictions about these tests (without reading them):**

1. `test_break_glass_kill_blocks_open_allows_reduce_runtime`:
   - PREDICT: Sets TradingMode to Kill, submits an OPEN intent, asserts it is rejected (dispatch_count == 0). Then submits a CLOSE intent, asserts it is dispatched (dispatch_count == 1).
   - RISK: Test may not verify the reject_reason is specifically Kill-related (vs. some other gate catching it).
   - RISK: Test may not verify that the OPEN cancellation loop (§2.2.3.4.1) is triggered.

2. `test_break_glass_command_path_runtime`:
   - PREDICT: Sends a command (file write? signal? API call?) and asserts the system transitions to Kill.
   - RISK: Test may use a mock command path that does not match the real production trigger mechanism.
   - RISK: Test may not verify the transition is visible via /status or logging.

**Document-based acceptance has no enforcement point.** The 8 acceptance criteria are all "WHEN reviewed THEN has X" -- meaning a human must review. There is no automated gate that prevents a vacuous runbook from passing.

- [x] Every safety-critical AT has TRIP + NON-TRIP (implementation_tests cover the mechanical path)
- [ ] Every test proves causality (not just existence) -- CANNOT VERIFY BLIND; flagged
- [x] Each AT isolates one clause (the two tests appear to isolate different aspects)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix -- the 8 document-review criteria are all CLAIMED-NOT-PROVEN in the automated sense

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: If the break-glass mechanism does not work when needed, the system continues placing orders during an emergency. The worst case is unlimited loss bounded only by account equity and exchange-level liquidation. This is the scenario where ALL other safety mechanisms have already failed (this is the last resort), so the exposure could be at maximum capacity.
- **Fail-closed cap on loss**: The break-glass itself IS the fail-closed cap. If it fails, there is no automated backstop beyond exchange-level liquidation and account equity limits. Manual intervention would be: kill the process (SIGKILL/SIGTERM), revoke API keys on the exchange dashboard, or contact exchange support.
- **Drift metric**: "Time since last break-glass drill" -- if > N months, confidence in the mechanism decays. No runtime metric exists for this (it's an operational process).
- **Loss boundary**: Kill mode (§2.2.3.6) is the boundary: no new exposure, only risk-reducing actions. If Kill does not work, the boundary is "kill the process" (crude but effective). If the process cannot be killed, the boundary is "revoke API keys on exchange."
- **Rollback plan**: The runbook and drill evidence are documentation artifacts. "Rolling back" means deleting the documents, which does not affect system behavior. The real concern is: if the break-glass mechanism itself is broken, the rollback is "fix the code that implements Kill mode," which is a different story's scope (Kill mode enforcement is in soldier_core/soldier_infra, not in this story's touch scope).

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: Kill mode dispatch authorization (§2.2.3.4, §2.2.3.6). This story documents how to trigger Kill but does not implement Kill itself -- Kill enforcement is in soldier_core. The story's implementation_tests exercise Kill enforcement in soldier_infra integration tests.
- **If conflict with CONTRACT.md**: No conflict. P0-D is an explicit Phase 0 prerequisite. The runbook must be consistent with §2.2.3.6 Kill Semantics -- specifically, Kill must NOT mean "no dispatch of any kind" (Capital Supremacy). The runbook must reflect that CLOSE/HEDGE remain permitted.
- Files with recent churn or shared ownership: `docs/break_glass_runbook.md` (new file, no churn). `crates/soldier_infra/tests/test_phase0_runtime.rs` (shared with other Phase 0 stories -- high churn risk; multiple stories add tests to this file).
- Struct fields I'm assuming exist (verify before coding): Whatever struct/enum represents the break-glass command (file sentinel path? kill switch config field?). Cannot verify blind.
- State machine transitions affected: TradingMode transition to Kill via external command. This must be consistent with the axis resolver (§2.2.3) -- the break-glass command must be an input to one of the three axes (likely the "worst-of" axis or a direct override).

**Cross-story dependencies (explicit):**

This story's safety claim depends on code entirely outside its touch scope. These dependencies are documented here so that failures in upstream stories are recognized as S0-003 risks:

| Dependency | What S0-003 needs from it | Upstream owner | Risk if upstream breaks |
|------------|--------------------------|----------------|------------------------|
| Kill mode dispatch authorization (`soldier_core`) | §2.2.3.4: OPEN blocked, CLOSE/HEDGE permitted under Kill | soldier_core (not an S0 story; pre-existing implementation) | S0-003's runbook says "set Kill" but Kill does not work. The runbook becomes false documentation. Implementation tests (`test_break_glass_kill_blocks_open_allows_reduce_runtime`) are the ONLY bridge verifying this. |
| TradingMode enum and axis resolver (`soldier_core`) | §2.2.3.3: TradingMode resolution correctly maps break-glass input to Kill | S0-004 scaffolds TradingMode data model; axis resolver is in soldier_core | If TradingMode enum changes variant names or the axis resolver does not accept the break-glass input, S0-003's implementation_tests may not compile or may test the wrong code path. |
| /status endpoint (`soldier_infra`) | Operator must be able to verify Kill took effect via observable output | S0-004 (health scaffolding), S8-008 (HTTP wiring) | If /status does not include `trading_mode` in its output, the runbook's "verify Kill is active" step has no observable endpoint. The operator must fall back to log inspection. |
| Non-Active OPEN Cancellation (§2.2.3.4.1) | Kill triggers cancellation of outstanding OPEN orders on the exchange | soldier_core dispatch logic | If the cancellation loop is not implemented, Kill blocks NEW dispatches but existing orders on the exchange continue to fill. The runbook's "verify no further OPEN risk" step must account for this. |

**Key implication**: S0-003 cannot independently guarantee its safety claim. If the Kill mode implementation in soldier_core has a bug, S0-003's runbook is false documentation regardless of how well the runbook itself is written. The implementation_tests are the sole automated verification that the upstream code behaves correctly.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (no postmortem artifacts found for S0 stories)
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A
- What will slow me down: The hybrid nature of this story -- it is partly documentation (runbook, drill evidence) and partly runtime enforcement (implementation_tests). The documentation part has no automated gate, so quality depends entirely on reviewer diligence. The implementation_tests are in `crates/soldier_infra/tests/test_phase0_runtime.rs`, a file shared across Phase 0 stories, which could have merge conflicts or dependency entanglement.
- Exploit: Focus on making the implementation_tests airtight (they are the only automated proof). Accept that the document-review criteria are inherently subjective and mitigate by being maximally specific in the runbook (exact commands, expected outputs, verification steps).
- Smallest fix that prevents it next time: Create a machine-readable runbook schema (YAML/JSON) that can be validated automatically, so "has STOP TRADING steps" becomes a parseable assertion rather than a human judgment call.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW (justified despite HIGH risk rating)**: The HIGH risk rating reflects the *consequence* of failure (last-resort safety mechanism). The YELLOW stoplight reflects the *state of preparedness*: all decisions are now resolved (trigger mechanism: file sentinel preferred; latency: within-1-tick; version binding: required), all identified failure modes have mitigations, and all debt has owners and target slices. The stoplight would be RED if the trigger mechanism were still unresolved, but the resolution in §4 (file sentinel preferred, with verification gate at implementation) moves this to YELLOW. The remaining risk is that the preferred mechanism may differ from the actual implementation -- this is tracked as HIGH-severity debt with a concrete verification gate.

**Deferral Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Break-glass trigger mechanism: file sentinel preferred but must be verified against implementation | **HIGH** | Blind premortem cannot confirm the actual command path matches the preferred mechanism. If the implementation uses a non-file trigger (API/signal), the failure modes change significantly. This is the most critical pending item for the last-resort safety mechanism. | S0-003 implementer | S0-003 (resolve during implementation) | Verify `test_break_glass_command_path_runtime` tests the mechanism documented in the runbook. If mechanism differs from file sentinel, re-evaluate failure modes and update runbook accordingly. |
| All 8 acceptance criteria are document-review only (no automated gate) | MED | Inherent to policy/documentation stories; no way to automate "runbook quality" in Phase 0 | S0-003 reviewer | Future (post-Phase 0) | Consider machine-readable runbook schema; add drill-replay CI job |
| Drill fidelity: may be against test harness, not deployed system | LOW | Phase 0 maturity does not yet have deployment infrastructure for staging drills | S0-003 implementer | Post-Phase 0 | Add staging drill as part of pre-production readiness checklist |
| Drill version binding: drill evidence must include commit hashes for runbook and system binary | MED | No mechanism currently enforces version binding between drill evidence and current code | S0-003 implementer | S0-003 (enforce during implementation) | Drill.md must include git commit hash of runbook and build_id/commit of system exercised |
| Cross-story dependency on Kill mode correctness in soldier_core | MED | Kill enforcement is outside S0-003's touch scope; implementation_tests are the only bridge | S0-003 implementer + soldier_core maintainer | S0-003 (verify via implementation_tests) | Implementation_tests must exercise actual Kill dispatch authorization, not mocks |

YELLOW with untracked items (no target slice) = RED. All items above have target slices.

**Exit criteria (definition of done, before I start):**
- [x] S1 clause audit: every AT traced to normative clause (no formal ATs; implicit dependencies documented)
- [x] S2 all requirements validated or killed (6 requirements identified; 3 covered by implementation_tests, 3 require process/review checks)
- [x] S3 all failure modes have detection + mitigation (8 failure modes with mitigations, including environmental failure modes)
- [x] S4 all decisions resolved, grounded in evidence (trigger mechanism resolved to file sentinel preferred; latency resolved to within-1-tick; version binding resolved)
- [x] S5 wrong impl gate: every acceptance criterion has wrong impl identified and tightening proposed
- [x] S6 proof plan: implementation_tests provide TRIP + NON-TRIP for Kill enforcement; document criteria are inherently CLAIMED-NOT-PROVEN (tracked in register)
- [x] S7 loss_mode documented with fail-closed boundary + rollback plan
- [x] S8 conflict scan clean (no CONTRACT.md conflicts; cross-story dependencies explicitly documented)
- [x] No new unresolved items without owner + target slice
