# S0-003 Reconciliation Audit: Break-Glass Runbook + Drill

> Auditor: R1 Reconciliation Auditor (read-only)
> Date: 2026-02-24
> Story: S0-003 — P0-D Break-Glass Runbook + Drill
> Risk Rating: HIGH (last-resort safety mechanism)
> Status: passes=true, enforcing_contract_ats=[], enforcement_point=""

---

## A) GATE RESULT

```
GATE: GO (conditional)
Reason: Core Kill enforcement is mechanically sound — TRIP and NON-TRIP tests
  exist and prove causal dispatch blocking. However, multiple premortem debt
  items remain open (drill version binding, deployment topology gap, trigger
  mechanism mismatch). These are acceptable for Phase 0 maturity but MUST be
  tracked. Conditional on remediation items below being filed.
READ_ONLY_VIOLATION: NONE
```

---

## B) AT AUDIT TABLE (Runtime Tests as Enforcement)

No formal `enforcing_contract_ats` exist for this story. The two `implementation_tests` serve as the sole automated enforcement. Audited below:

### Test 1: `test_break_glass_kill_blocks_open_allows_reduce_runtime`

**File:** `/Users/admin/Desktop/opus-trader/crates/soldier_infra/tests/test_phase0_runtime.rs`
**Lines:** 315-358

| Aspect | Finding | Cite |
|--------|---------|------|
| **TRIP (OPEN blocked under Kill)** | PROVEN. Calls `dispatch-check --intent OPEN --mode KILL`, asserts exit code 1, `ok=false`, `reason="kill_mode_blocks_open"`. | Lines 320-334 |
| **NON-TRIP (CLOSE/REDUCE permitted under Kill)** | PROVEN. Calls `dispatch-check --intent REDUCE_ONLY --mode KILL`, asserts exit code 0, `ok=true`, `reason="kill_mode_allows_risk_reduction"`. | Lines 337-357 |
| **Causal proof** | YES. Reason codes are Kill-specific (`kill_mode_blocks_open` vs `kill_mode_allows_risk_reduction`), not generic reject codes. The `_dispatch_decision` function at `stoic-cli:884-896` returns these specific strings only when `mode == "KILL"`. | `stoic-cli:886-889` |
| **Fail-closed** | YES. The `_dispatch_decision` function defaults to `False, "unknown_mode"` for any unrecognized mode (`stoic-cli:896`). The `_default_runtime_state` function defaults unknown mode strings to `"KILL"` (`stoic-cli:165-166`). | `stoic-cli:165-166, 896` |
| **Isolation** | YES. This test isolates the dispatch authorization decision independent of runtime state. It exercises only the `dispatch-check` subcommand which evaluates `_dispatch_decision()` directly. | Lines 315-358 |

**Verdict: PASS** -- Both TRIP and NON-TRIP with causal Kill-specific reason codes.

### Test 2: `test_break_glass_command_path_runtime`

**File:** `/Users/admin/Desktop/opus-trader/crates/soldier_infra/tests/test_phase0_runtime.rs`
**Lines:** 490-633

| Aspect | Finding | Cite |
|--------|---------|------|
| **Command path (emergency kill)** | PROVEN. Calls `emergency kill --reason "runtime e2e drill"`, asserts exit 0, `trading_mode="KILL"`, `is_trading_allowed=false`, `pending_orders=0`. | Lines 534-549 |
| **Queue flush on Kill** | PROVEN. Seeds 3 pending orders via `simulate-open` (lines 506-525), verifies 3 pending (lines 528-531), then triggers `emergency kill`, asserts `pending_orders=0`. | Lines 528-549 |
| **Status confirmation after Kill** | PROVEN. Calls `status --format json` after kill, confirms `trading_mode="KILL"`, `is_trading_allowed=false`, `pending_orders=0`. | Lines 552-567 |
| **OPEN blocked post-Kill** | PROVEN. Calls `simulate-open` after kill, asserts exit 1, `result="BLOCKED"`. | Lines 570-589 |
| **Risk reduction path** | PROVEN. Transitions to `REDUCE_ONLY` via `emergency reduce-only`, then calls `simulate-close --dry-run`, asserts `result="ACCEPTED"`. | Lines 592-630 |
| **TRIP** | YES. Multiple: (1) queued orders flushed to 0, (2) OPEN blocked post-Kill, (3) mode transitions to KILL. | Lines 534-589 |
| **NON-TRIP** | YES. Risk reduction via REDUCE_ONLY + simulate-close is permitted. | Lines 592-630 |
| **End-to-end** | YES. Full command path: seed orders -> kill -> verify flush -> verify block -> reduce-only -> verify close. | Lines 490-633 |

**Verdict: PASS** -- Comprehensive e2e test with both TRIP and NON-TRIP, causal proof via result codes.

### Summary AT Audit Table

| Test function | What it proves | Causal proof? | Fail-closed? | S5 blocked? | Verdict |
|---|---|---|---|---|---|
| `test_break_glass_kill_blocks_open_allows_reduce_runtime` | Kill blocks OPEN dispatch AND permits REDUCE_ONLY dispatch | YES (Kill-specific reason codes) | YES (unknown_mode -> False) | Partially (see S5 table below) | PASS |
| `test_break_glass_command_path_runtime` | Full command path: seed -> kill -> flush -> block -> reduce-only -> close | YES (result codes + state assertions) | YES (multiple error paths -> KILL default) | Partially (see S5 table below) | PASS |

---

## C) PREMORTEM CROSS-REFERENCE

### S2 Assumptions

| # | Assumption | Validated? | Evidence | Finding |
|---|-----------|------------|----------|---------|
| 1 | Kill mode actually blocks OPEN intents at runtime | YES | `test_break_glass_kill_blocks_open_allows_reduce_runtime` (lines 320-334): exit 1, `reason=kill_mode_blocks_open`. Enforcement at `stoic-cli:886-889`. | VALIDATED |
| 2 | External command path to trigger Kill exists | YES | `test_break_glass_command_path_runtime` (lines 534-542): `emergency kill` command triggers KILL mode. Enforcement at `stoic-cli:518-620` (`_cmd_emergency`). | VALIDATED -- but mechanism is CLI-based, not file-sentinel as premortem preferred. See Decision analysis. |
| 3 | Drill exercises real command path (not mocked) | PARTIAL | Drill evidence (`drill.md`) documents `./stoic-cli emergency kill --reason "drill"` which matches the CLI path tested. The `stoic-cli` is a Python script, not a compiled binary, so "real" vs "mocked" distinction is less clear. The drill was against STAGING (drill.md:4) but no commit hash or build_id recorded. | PARTIAL -- no version binding evidence. |
| 4 | Runbook executable by panicked operator under stress | PARTIAL | Runbook has Quick Reference Card (runbook.md:148-173), explicit commands, Method A/B fallback. Drill was executed by `drill_operator` with `safety_witness` present (drill.md:6-7, 60-64). | PARTIAL -- generic names suggest template, not real operator names. |
| 5 | Risk-reducing dispatches remain available under Kill | YES | `test_break_glass_command_path_runtime` (lines 592-630): transitions to REDUCE_ONLY, `simulate-close` returns ACCEPTED. `test_break_glass_kill_blocks_open_allows_reduce_runtime` (lines 337-357): REDUCE_ONLY intent allowed under KILL mode. | VALIDATED |
| 6 | Runbook's "verify" step checks inflight/queued orders | PARTIAL | Runbook Verification table (runbook.md:71-75) includes `orders --pending` (empty list), `status --detailed` (orders_in_flight: 0), `status` (trading_mode: KILL). This covers local state. | PARTIAL -- does not include checking exchange-side open orders (only local state). See premortem S2#6. |

### S4 Decisions

| Decision | Chosen | Implemented? | Evidence | Finding |
|----------|--------|-------------|----------|---------|
| What constitutes valid drill? | Option A (test harness) + Option B (ideal) | Option A only | Drill ran against STAGING env using `stoic-cli` Python CLI. No evidence of live exchange connectivity. The implementation_tests prove the mechanical path in a test harness. | ACCEPTABLE for Phase 0. The drill exercises the real CLI binary against persistent state, which is more than unit-test-level but less than full production. |
| Break-glass trigger mechanism | File sentinel (Option A) preferred | NOT file sentinel -- CLI command implemented instead | Runbook uses `./stoic-cli emergency kill` (runbook.md:31-33). `stoic-cli` writes to runtime state JSON file (`stoic-cli:284-309`). The actual mechanism is a CLI that writes JSON state, not a file sentinel. | **MISMATCH**: Premortem chose file sentinel as preferred; implementation uses CLI -> JSON state file. This is actually BETTER for the use case (structured command with reason logging, atomic writes, locking), but the premortem's verification gate (S4: "if mechanism differs, update decision with rationale") was NOT explicitly closed. |
| Kill latency time-bound | Within 1 tick (Option A) | Within 1 CLI invocation | Kill takes effect immediately upon `emergency kill` command completion. `stoic-cli` writes state synchronously with fsync. Next dispatch check reads the state file. Drill evidence shows 150ms from command to KILL engaged (drill.md:16-18: 23:44:05.500 -> 23:44:05.650). | VALIDATED for Phase 0. CLI-immediate is effectively within-1-tick since the state file is the authority. |
| Runbook audience | Developer-level (Option A) | Developer-level | Commands require SSH/terminal access, knowledge of `stoic-cli` location, understanding of trading modes. | MATCHES decision. |
| Drill version binding | Drill must include commit hashes | NOT implemented | `drill.md` contains no git commit hash, no build_id, no runbook version reference. | **OPEN DEBT** -- premortem S10 debt register item not resolved. |

### S5 Wrong Implementations

| Acceptance Criterion | Wrong impl identified | Blocked? | Evidence | Finding |
|---|---|---|---|---|
| "has STOP TRADING steps" | Runbook says "Stop trading" with no detail on HOW | BLOCKED | Runbook (runbook.md:30-44) has exact CLI command: `./stoic-cli emergency kill --reason "..."`, followed by status verification, order verification. | BLOCKED -- specific, actionable commands. |
| "has verify no further OPEN risk" | Runbook says "check no new orders" without saying HOW | BLOCKED | Runbook Verification table (runbook.md:71-75) specifies exact commands and expected results: `orders --pending` -> empty list, `status --detailed` -> orders_in_flight: 0. | BLOCKED -- specific commands with expected outputs. |
| "has verify risk reduction possible" | Runbook says "can still close" without proving it | PARTIALLY BLOCKED | Runbook (runbook.md:93-107) documents switching to REDUCE_ONLY + simulate-close dry-run. Drill evidence (drill.md:42-47) shows this path was exercised. But runbook says `simulate-close --dry-run` requires `STOIC_DRILL_MODE=1`, which is a drill-only gate -- in a real emergency, the operator would need actual close capability, not just dry-run simulation. | **WRONG_IMPL_PARTIALLY_UNBLOCKED**: The runbook's risk-reduction verification uses a drill-only command (`simulate-close --dry-run` with `STOIC_DRILL_MODE=1`). In a real emergency, the operator needs to actually close positions, not just simulate. The runbook Step 3 (runbook.md:104-107) acknowledges this: "Use the venue/exchange close workflow" -- but this is vague and not tested. |
| "has escalation + notify" | Runbook says "notify the team" without WHO/HOW/WHEN | BLOCKED | Runbook (runbook.md:124-137) has role table with PagerDuty escalation paths, severity levels with notification channels and timing. | BLOCKED -- specific roles, channels, thresholds. But names are generic placeholders ("Trading On-Call", "Engineering Lead"), not real people. |
| "drill has trigger scenario" | drill.md says "simulated scenario" without details | BLOCKED | Drill (drill.md:7): "Simulated runaway order attempt (100 rapid-fire orders queued)". Drill (drill.md:14-19): timestamps show fault injection, alert, operator intervention. Log excerpt (log_excerpt.txt:8-15) shows the actual rapid-fire order sequence. | BLOCKED -- specific, timestamped scenario. |
| "drill has time to halt" | drill.md says "halt was fast" without measurement | BLOCKED | Drill (drill.md:36): "time_to_halt_sec: 5.7". Log excerpt (log_excerpt.txt:42): "kill_time_ms=5700". | BLOCKED -- specific wall-clock measurement. |
| "drill has observed behavior" | drill.md says "system behaved as expected" | BLOCKED | Drill Verification section (drill.md:23-32): specific checks performed (orders --pending, status, exchange order history). Log shows KILL_ENGAGED, OPEN_BLOCKED, order_queue_flushed. | BLOCKED -- specific observables documented. |
| "log_excerpt proves drill occurred" | log_excerpt from unrelated run | BLOCKED | Log excerpt (log_excerpt.txt) contains: (1) KILL_ENGAGED event with timestamp and reason matching drill.md, (2) OPEN_BLOCKED with reason=KILL_MODE, (3) order_queue_flushed, (4) MODE_TRANSITION from KILL to REDUCE_ONLY, (5) simulate_close result=ACCEPTED, (6) drill_complete with status=PASSED. | BLOCKED -- internally consistent timestamps, Kill-specific events (not ReduceOnly). |
| (Cross-review) Runbook command path mismatch | Runbook says "trigger Kill via `touch /tmp/kill_switch`" but impl uses different path | BLOCKED | Runbook uses `./stoic-cli emergency kill` (runbook.md:31-33). Implementation uses the same command path (`stoic-cli:518-620`). Drill exercises same command (drill.md:16). No file sentinel mismatch because file sentinel was NOT implemented -- CLI path was used instead. | BLOCKED -- runbook, implementation, and drill all use the same CLI command path. |
| (Cross-review) Log shows ReduceOnly not Kill | log_excerpt shows OPEN rejected but under ReduceOnly, not Kill | BLOCKED | Log excerpt (log_excerpt.txt:21-23) explicitly shows `{"event": "KILL_ENGAGED", ...}` and `dispatch OPEN_BLOCKED reason=KILL_MODE`. The rejection reason is Kill-specific. | BLOCKED -- Kill-mode-specific events clearly distinguished. |

**Unblocked wrong impls: 1 (partially)**
- "verify risk reduction possible" relies on drill-only `simulate-close` which is not the real close path. Severity: MEDIUM -- the drill proves the authorization logic works, but does not prove actual exchange close capability.

---

## D) DESIGN RISK NOTES

### D1. Trigger Mechanism: CLI vs File Sentinel

The premortem (S4) chose file sentinel as the preferred trigger mechanism because it works when the process is hung. The implementation uses a CLI command (`stoic-cli emergency kill`) which writes to a JSON state file via atomic write + fsync (`stoic-cli:284-309`).

**Risk analysis:**
- The CLI approach is BETTER than file sentinel for structured logging (reason recorded, timestamps), atomic state transitions (file locking at `stoic-cli:265-273`), and queue flushing (pending orders cleared at `stoic-cli:577-579`).
- HOWEVER, the CLI approach has a failure mode the premortem identified: if the `stoic-cli` Python process cannot start (Python not available, permission denied, missing dependencies), the kill switch is unavailable. The file sentinel approach would still work because any process can `touch` a file.
- **Mitigant:** Runbook Method B (runbook.md:47-63) provides a fallback: revoke API key on exchange dashboard. This is the "kill the process" equivalent for the API.
- **Residual risk:** There is a gap between "CLI unavailable" and "need to revoke exchange API key" -- there is no intermediate fallback like writing a state file manually. An operator who cannot run the CLI but can access the filesystem has no documented recourse.

**Recommendation:** Add a Method C to the runbook: "If CLI is unavailable but filesystem is accessible, manually write KILL state" with the exact JSON payload and file path.

### D2. Latency

Drill evidence shows 5.7 seconds from fault injection to KILL engaged (drill.md:36). However, this includes 3.4 seconds of human reaction time (fault at 23:44:00, operator intervenes at 23:44:05.5). The mechanical latency is 150ms (23:44:05.500 command -> 23:44:05.650 KILL engaged, per drill.md:16-18 and log_excerpt.txt:18-21). This is well within the "within 1 tick" requirement.

### D3. Partial State / Corruption

The `stoic-cli` handles several partial-state scenarios fail-closed:
- **Missing state file:** defaults to ACTIVE, no errors (`stoic-cli:198-199`). This is NOT fail-closed for the break-glass case -- if the state file is deleted after Kill, the system would default back to ACTIVE.
- **Corrupt/unparseable state file:** defaults to KILL (`stoic-cli:203-209`). GOOD -- fail-closed.
- **Schema mismatch (future version):** defaults to KILL (`stoic-cli:221-231`). GOOD -- fail-closed. Tested at lines 1070-1120 of the test file.
- **Null schema_version:** defaults to KILL. Tested at lines 1123-1173 of the test file.
- **Invalid trading_mode string:** defaults to KILL (`stoic-cli:234-241`). GOOD -- fail-closed.
- **Unknown mode in `_default_runtime_state`:** defaults to KILL (`stoic-cli:165-166`). GOOD -- fail-closed.
- **Unknown mode in `_dispatch_decision`:** returns `False, "unknown_mode"` (`stoic-cli:896`). GOOD -- fail-closed.

**CRITICAL FINDING:** Missing state file defaults to ACTIVE, not KILL. If an operator triggers Kill via `emergency kill`, the state file is written. If the state file is subsequently deleted (filesystem issue, cleanup script, container restart without persistent volume), the system silently reverts to ACTIVE. This is a **fail-OPEN** behavior for the break-glass mechanism.

- Test coverage for this: `_load_runtime_state` at `stoic-cli:196-199` returns `_default_runtime_state()` which is ACTIVE. There is no test that specifically verifies "state file deleted after Kill -> system notices and fails closed."
- The `test_break_glass_command_path_runtime` test calls `remove_if_exists(&runtime_state)` at the END (line 632), not during the test. No test verifies behavior when state file disappears mid-session.

### D4. Runbook-Evidence Version Binding

The premortem (S4 decision 5, S10 debt register) explicitly required drill evidence to include:
1. Git commit hash of the runbook at drill time
2. Git commit hash or build_id of the system binary
3. Statement of whether runbook was modified since drill

**None of these are present in drill.md or log_excerpt.txt.** The runbook_snapshot.md is close to the current runbook.md (diff shows only a Dashboard Emergency Action paragraph was added to the main runbook after the snapshot), but there is no explicit version binding.

### D5. Runbook Snapshot Drift

The runbook.md and runbook_snapshot.md differ:
- `runbook.md` has an additional "Dashboard Emergency Action (V1)" section (lines 114-118) not present in `runbook_snapshot.md`.
- This means the runbook has been modified since the drill was executed, and the drill evidence does not reflect the current runbook version.
- The delta is non-material (it adds a V1 feature gate note, not a change to the kill procedure), but it demonstrates the version-binding concern is real.

### D6. `_is_trading_allowed_mode` Only Returns True for ACTIVE

At `stoic-cli:323-324`:
```python
def _is_trading_allowed_mode(mode: str) -> bool:
    return mode == "ACTIVE"
```

This means both KILL and REDUCE_ONLY show `is_trading_allowed=false`. Good for fail-closed, but could confuse operators during REDUCE_ONLY mode where risk-reducing trades ARE allowed.

### D7. No `unwrap()` in Production Paths

The `stoic-cli` is Python, so `unwrap()` is not applicable. The Rust test file (`test_phase0_runtime.rs`) uses `unwrap()` and `expect()` in test helpers (lines 62-67, 72-73) which is acceptable for test code. No `unwrap()` exists in production enforcement paths.

---

## E) REMEDIATION PLAN

| # | Severity | Issue | Remediation | Owner | Target |
|---|----------|-------|-------------|-------|--------|
| R1 | **HIGH** | Missing state file defaults to ACTIVE (fail-OPEN for break-glass). If state file is deleted after Kill, system silently reverts to ACTIVE. (`stoic-cli:198-199`) | Change `_load_runtime_state` to return a warning when state file is missing, and consider whether a missing file after a known Kill transition should fail-closed. At minimum, add a test that verifies behavior when state file is deleted mid-session. | eng | Next slice |
| R2 | **MED** | Drill version binding not implemented. drill.md contains no commit hash, no build_id, no runbook version reference. Premortem debt item not resolved. | Add `runbook_commit`, `system_commit`, and `runbook_modified_since_drill` fields to drill.md. Verify runbook_snapshot.md matches the runbook at drill time. | eng | Next drill |
| R3 | **MED** | Runbook snapshot has drifted from runbook.md (Dashboard Emergency Action section added). No automated gate to detect drift. | Add a CI check or verify.sh step that compares `docs/break_glass_runbook.md` to `evidence/phase0/break_glass/runbook_snapshot.md` and flags drift. Or re-snapshot after each runbook change. | eng | Next slice |
| R4 | **MED** | Risk reduction verification uses drill-only `simulate-close --dry-run` with `STOIC_DRILL_MODE=1`. In a real emergency, operator needs actual close capability. Runbook Step 3 (runbook.md:104-107) is vague on real close procedure. | Document the actual close procedure for each instrument type. Test it in drill. Phase 0 limitation acknowledged but should not persist into Phase 1. | eng | Phase 1 |
| R5 | **LOW** | Runbook missing Method C: "manual state file write" for when CLI is unavailable but filesystem is accessible. Gap between Method A (CLI) and Method B (exchange dashboard). | Add a Method C to runbook.md documenting the exact JSON payload and file path to manually write KILL state. | eng | Next slice |
| R6 | **LOW** | Runbook escalation contacts use placeholder names ("Trading On-Call", "Engineering Lead") not real individuals. Understandable for Phase 0 but reduces drill realism. | Update with real names/handles before production. | ops | Pre-production |
| R7 | **LOW** | No deployment topology documentation in runbook. Premortem failure mode #8 identified this gap. Runbook does not state what environment/topology it is validated against. | Add "Deployment Assumptions" section documenting single-process, local filesystem, Python 3 required. | eng | Next slice |
| R8 | **INFO** | Premortem S4 verification gate ("if mechanism differs from file sentinel, update decision with rationale") was not explicitly closed in any artifact. The CLI mechanism is arguably better, but the decision trail is incomplete. | Document the CLI-vs-sentinel resolution in a postmortem or decision record. No code change needed. | eng | Next recon |

---

## F) SCOPE CHECK

| Scope file (from PRD) | Exists? | Content quality | Finding |
|---|---|---|---|
| `docs/break_glass_runbook.md` | YES | HIGH -- Structured, actionable, Method A/B, verification table, escalation, Quick Reference Card, forbidden actions list, sign-off. | Matches premortem predictions. Good quality for Phase 0. |
| `evidence/phase0/break_glass/runbook_snapshot.md` | YES | HIGH -- Matches runbook.md except for one paragraph (Dashboard Emergency Action). | Minor drift detected (see R3). |
| `evidence/phase0/break_glass/drill.md` | YES | HIGH -- Timestamped actions, verification steps, outcome metrics, REDUCE_ONLY verification, gaps/follow-ups, participant sign-off. | Good quality. Missing version binding (see R2). |
| `evidence/phase0/break_glass/log_excerpt.txt` | YES | HIGH -- Structured log entries with timestamps, events, Kill-specific markers, full lifecycle from pre-drill through REDUCE_ONLY test to drill completion. | Internally consistent. Kill-specific events clearly distinguished from ReduceOnly. |

All 4 scope files exist and have substantive content. Scope matches premortem predictions.

### Non-scope files that ARE enforcement (implementation_tests)

| File | Relation to S0-003 | Finding |
|---|---|---|
| `stoic-cli` (Python) | Contains all enforcement logic: `_dispatch_decision`, `_cmd_emergency`, `_load_runtime_state` | Thoroughly reviewed. Fail-closed on most paths except missing-file default (R1). |
| `crates/soldier_infra/tests/test_phase0_runtime.rs` | Contains both implementation_tests + many additional tests | Tests are comprehensive, well-structured, use causal assertions. |

---

## Premortem S10 Debt Register Resolution

| Debt item | Status | Evidence |
|---|---|---|
| Trigger mechanism: file sentinel vs actual implementation | RESOLVED (implementation chose CLI, not file sentinel) -- but decision trail not explicitly closed | See D1, R8 |
| All 8 acceptance criteria are document-review only | ACCEPTED -- inherent to policy stories | Criteria are subjectively met with good quality |
| Drill fidelity: test harness vs deployed system | ACCEPTED for Phase 0 | Drill ran against STAGING with real CLI (drill.md:4) |
| Drill version binding | **OPEN** -- not resolved | See R2 |
| Cross-story dependency on Kill mode in soldier_core | PARTIALLY RESOLVED | `stoic-cli` implements its own Kill logic (not dependent on soldier_core at Phase 0). soldier_core has `RiskState::Kill` (`open_runtime.rs:112`) which is a separate enforcement chain. |

---

READY FOR SELF_REVIEW
