# Roadmap (Merged + Hardened) — Automated Crypto Options Trading System
_Last updated: February 12, 2026_

This document merges:
- Your phase-based roadmap with strong mechanical safety guarantees (Phases 1–4). 
- The strategic structure: constraint-first scheduling (TOC), environment ladder, and deployment/testing gates.

> **Contract + Implementation Plan remain the source of truth for requirements.** This roadmap is the human-readable control layer.

---

## Document precedence (normative)

1. `specs/CONTRACT.md`
2. `specs/IMPLEMENTATION_PLAN.md`
3. Phase checklist blocks (`docs/PHASE0_CHECKLIST_BLOCK.md`, `docs/PHASE1_CHECKLIST_BLOCK.md`, and phase-specific successors)
4. `docs/ROADMAP.md`

If a lower-precedence document conflicts with a higher-precedence one, the higher-precedence document wins and roadmap/plan text must be corrected before phase sign-off.

---

## 0) How to read this roadmap

- Each phase is an **outcome** that unlocks a **permission** (what we are allowed to do next).
- “Done” means the **exit criteria** are met and the **evidence pack** exists (tests + artifacts + metrics).
- Strategy work is allowed, but it **cannot outrun** the constraint: execution correctness + risk + observability.

---

## 1) The Constraint (TOC “Drum”)

The limiting factor is **not** strategy ideas.  
The constraint is almost always:

1) **Correctness of execution** (no duplicates, no illegal orders, no silent mismatches)  
2) **Risk containment** (system can always reduce exposure under bad conditions)  
3) **Observability & evidence** (we can explain and replay what happened)  

So the roadmap protects the constraint:
- small batches (minimum WIP)
- hard gates (no “soft done”)
- buffers around integration + testing

---

## 2) Release Ladder (where each phase runs)

**DEV → STAGING → PAPER → MICRO-LIVE (canary) → PROD (scaled)**

**Permissions**
- **DEV/STAGING:** anything, but never real money.
- **PAPER:** real market data, simulated fills (or exchange paper), no real money.
- **MICRO-LIVE:** real money, tiny caps, automatic rollback, human-supervised.
- **PROD:** only after stability + evidence gates.

### Stage terminology map (roadmap vs gates)

Use this table for interpretation only. Automated release/certification gates MUST use the canonical contract terms.

| Intent | Roadmap term | Contract/Cert term | Plan term |
|---|---|---|---|
| Non-capital evidence run | PAPER | Shadow | Shadow |
| Limited canary deployment | MICRO-LIVE | Testnet (micro-canary gate stage) | Canary |
| Scaled production | PROD | Live | Full |

### Profile compliance gates (CSP/GOP/FULL)

- `/status` must publish `supported_profiles` and `enforced_profile` with profile-consistent fields.
- Runtime safety baseline is CSP; when `enforced_profile == CSP`, GOP-only subsystem failures are surfaced but not allowed to drive CSP safety decisions.
- CI profile isolation gates are mandatory before claiming profile-complete milestones:
  - `build:csp_only`
  - `test:csp_only`
  - `test:gop`
- Phase completion claims must cite evidence for profile isolation behavior, not only feature implementation.

---

## 3) One-page Executive Table (Outcome + Permission)

| Phase | Name | What’s true at the end (plain language) | Permission unlocked | Where it must run |
|---:|---|---|---|---|
| 0 | Launch Policy & Ops Baseline | We agree on risk limits, modes, keys, and how incidents are handled. | We can run safely in DEV/STAGING without ambiguity. | DEV/STAGING |
| 1 | Foundation (“Never Panic, Never Duplicate”) | The system is mechanically prevented from sending illegal/duplicate orders or sizing wrong silently. | Safe dry-run + restart/replay testing. | DEV/STAGING |
| 2 | Guardrails (“Contain Damage Automatically”) | If we get exposed, the system can always contain/reduce exposure automatically under exchange/infrastructure failures. | **Paper trading** is allowed. **Micro-live** is allowed only after paper gates and the CSP certification gate pass (CSP_ONLY CI + runtime F1 binding + `/status` profile fields + CSP safety acceptance). | STAGING/PAPER |
| 3 | Data Loop (“Make Every Outcome Explainable”) | Every trade is explainable, attributable, and replayable with measurable coverage. | We can iterate strategy with evidence and regression tests. | PAPER/MICRO-LIVE |
| 4 | Live Fire Controls (“Change Nothing Unsafely”) | No risky change reaches production without replay proof + controlled rollout + rollback. | Scaled production with safe evolution. | MICRO-LIVE/PROD |

---

# Phase 0 — Launch Policy & Ops Baseline (Prerequisite)

### Outcome (non-coder version)
Before we argue about features, we lock the **rules of the game**: what the bot is allowed to do, what “unsafe” means, and how we respond when things go wrong.

### Delivered artifacts
- **Launch Policy** (`docs/launch_policy.md`) — allowed venues/instruments, max position, max daily loss, max order rate, environments.
- **Machine Policy Config + Loader** (`config/policy.json`, `tools/policy_loader.py`) — strict runtime-readable policy baseline.
- **Environment Matrix** (`docs/env_matrix.md`) — separate keys/accounts per env, permissions, secret storage.
- **Keys & Secrets** (`docs/keys_and_secrets.md`) — key creation rules, rotation plan, LIVE key protection.
- **Break-Glass Runbook** (`docs/break_glass_runbook.md`) — kill switch steps, verify no open risk, escalation.
- **Health + Owner Status** (`docs/health_endpoint.md`) — minimal command surface to check liveness and authority state.
- **Repo layout + verify harness baseline** (`plans/verify.sh`, `plans/verify_fork.sh`, `specs/WORKFLOW_CONTRACT.md`) — canonical workflow paths and deterministic verification entrypoint are defined and executable.

### Exit criteria (evidence pack)
- All docs above exist with required content
- `evidence/phase0/` contains snapshots + drill record + key scope probe (see `docs/PHASE0_CHECKLIST_BLOCK.md` for canonical structure)
- A recorded **break-glass drill** proving: halt triggered → no further OPENs → risk reduction still possible
- A recorded **key-scope probe** (`key_scope_probe.json`) proving keys are least-privilege
- Minimal commands that expose: `ok`, `build_id`, `contract_version`, `trading_mode`, `is_trading_allowed`
- Strict policy loader validation passes for `config/policy.json`
- Canonical verification path guard passes: `plans/verify.sh` remains a thin wrapper to `plans/verify_fork.sh`

---

## Phase 0 Addendum — Canonical Checklist

Canonical source: `docs/PHASE0_CHECKLIST_BLOCK.md`

Decision input policy (drift control):
- Use `docs/PHASE0_CHECKLIST_BLOCK.md` and `docs/ROADMAP.md` for Phase 0 decisions.
- Treat prior merged roadmap text as historical context in git history only.

Use that file for:
- required evidence pack structure,
- P0-A through P0-E unblock conditions,
- binary owner sign-off questions,
- explicit Phase 0 non-goals.

### Phase 0 Health/Status Enforcement Scope (clarification)

- In Phase 0, `tools/phase0_meta_test.py` (via `./plans/verify.sh`) enforces both health documentation/evidence (`docs/health_endpoint.md`, `evidence/phase0/health/health_endpoint_snapshot.md`) and executable behavior of `./stoic-cli health` + `./stoic-cli status`.
- Executable behavior is checked in CI with deterministic pass/fail paths:
  - healthy path: exit code `0` with required fields (`ok`, `build_id`, `contract_version`, `trading_mode`, `is_trading_allowed`)
  - forced-unhealthy path: exit code `1` with explicit policy-load error and fail-closed status (`trading_mode=KILL`, `is_trading_allowed=false`)

---

# Phase 1 — Foundation
### “Never Panic, Never Duplicate”

## Phase 1 Canonical Inputs

Canonical source: `docs/PHASE1_CHECKLIST_BLOCK.md`

Decision input policy (drift control):
- Use `docs/PHASE1_CHECKLIST_BLOCK.md` and `docs/ROADMAP.md` for Phase 1 decisions.
- Treat `specs/CONTRACT.md` and `specs/IMPLEMENTATION_PLAN.md` as supporting references; do not use drift-prone excerpt/bundle files as normative inputs.

## Definition of Done (Phase 1)

### 1) Delivered artifacts (merged)
- A **single, enforced dispatch chokepoint** — exactly one module may call the exchange client.
- A **durable intent ledger (WAL)** + replay logic.
- Deterministic:
  - instrument classification
  - sizing units + quantization
  - intent hashing
  - label generation
- Explicit `s4` label contract is enforced:
  - outbound format: `s4:{sid8}:{gid12}:{li}:{ih16}`
  - Deribit hard limit `label <= 64` chars with **no truncation**
  - overflow semantics: `Rejected(LabelTooLong)` before dispatch + `RiskState::Degraded`
  - deterministic parser/disambiguation behavior covered by AT-216, AT-217, AT-041, AT-921
- Preflight guards that **hard-reject** illegal orders (market/stop/linked/post-only crossing, etc.).
- Deribit Venue Facts Addendum enforcement is artifact-backed and CI-gated (evidence check failure blocks build).
- “Pre-dispatch gates” wired before any exchange call:
  - liquidity gate (data must be good enough)
  - fee staleness gate
  - If you have any "edge/profitability" gate: it MUST be explicitly labeled as **policy** (not execution safety), MUST NOT block risk-reducing orders (i.e., orders that close/reduce positions), and MUST be versioned + tested.
- A runnable verification harness (e.g., `plans/verify.sh`) that fails the build on contract violations.
- **Baseline observability**: structured logs + metrics with a `run_id` and `intent_id`.

### 2) System guarantees
- **Idempotency is absolute:** crash/restart/reconnect cannot duplicate orders.
- **No OPEN risk can be created** when:
  - WAL enqueue fails
  - sizing metadata is stale/missing
  - RiskState ≠ Healthy

> **RiskState definition (Phase 1 minimum):** `Healthy | Degraded`. Phase 2 may extend this.
> Required test: `test_riskstate_not_healthy_blocks_open` — asserts OPEN intents are rejected when RiskState = Degraded.
- **All outbound orders are deterministic:** same inputs → same intent hash/label → same behavior.
- **No illegal order reaches the exchange API.**

### 3) Operational meaning
- Safe to run in:
  - unit tests
  - restart/replay loops
  - dry-run environments
- You cannot accidentally over-size, double-send, or mis-classify exposure.

### 4) Explicitly NOT done yet
- No multi-leg atomic execution.
- No TradingMode / PolicyGuard.
- No emergency flattening logic (automated position liquidation is Phase 2; Phase 1 only ensures risk-reducing orders can pass through gates).
- No full `/status` endpoint/schema (Phase 0 includes minimal owner status fields only).
- No evidence/attribution/replay governance.

### Acceptance artifacts (what “proof” looks like)
- **Tests**
  - determinism tests for hashing/quantization/labels
  - label contract tests for `s4` parse/overflow/disambiguation semantics
  - WAL crash-replay tests (no duplicate dispatch)
  - illegal order rejection tests
- **Operational proof**
  - a restart loop test that runs 100+ cycles with zero duplicates
  - metrics: `duplicate_dispatch_count == 0`, `illegal_order_attempts == 0`

**Required evidence:**
- `evidence/phase1/restart_loop/restart_100_cycles.log` **(AUTO artifact)** — test output showing 100+ restart cycles with `duplicate_dispatch_count == 0`.

---

## Phase 1 Addendum — Final Hardening Checklist (AUTO/MANUAL, Ungameable)

**Rule:** Phase 1 is DONE only if every item below is satisfied with its required evidence.
**Evidence pack root:** `evidence/phase1/`

### Evidence pack contents (required):

- `evidence/phase1/README.md` **(MANUAL)** — 1 page: what was proven, what failed, what remains risky.
- `evidence/phase1/ci_links.md` **(MANUAL)** — links to CI runs for each AUTO gate (or build IDs).

---

### P1-A — Single Dispatch Chokepoint Proof (No Bypass Paths)

**Goal:** Exactly one module/function may dispatch an exchange order. No direct exchange-client calls elsewhere.

**MANUAL evidence (artifact required):**

`docs/dispatch_chokepoint.md` must include:
- The exact module + function name that dispatches orders
- The exact exchange client type used
- Normative statement: "No other module may call the exchange client directly."

**AUTO gates (CI tests, binary):**

- `test_dispatch_chokepoint_no_direct_exchange_client_usage`
  - Pass iff exchange client cannot be imported/constructed outside chokepoint module (AST/static preferred; grep acceptable as stopgap).
- `test_dispatch_visibility_is_restricted`
  - Pass iff dispatch function is not public beyond intended package boundary (e.g., `pub(crate)` / package-private).

**Unblock condition:**
AUTO: both tests green **AND** MANUAL: `docs/dispatch_chokepoint.md` present and accurate.

---

### P1-B — Determinism Snapshot Test (Same Inputs ⇒ Same Intent Bytes)

**Goal:** Determinism is proven before strategy exists.

**AUTO gates:**

- `test_intent_determinism_same_inputs_same_hash`
  - Uses fixed inputs + injected/frozen clock
  - Asserts identical serialized intent bytes or identical intent hash across:
    - two runs
    - restart
    - map iteration reorder

**Required evidence:**

- `evidence/phase1/determinism/intent_hashes.txt` **(AUTO artifact)** — test output showing equal hashes across runs.

**Unblock condition:**
AUTO: test green + artifact emitted.

---

### P1-C — No Partial Side Effects on Rejection

**Goal:** If any Phase-1 gate rejects an intent, persistent state does not change (except counters/logs).

**AUTO gates:**

- `test_rejected_intent_has_no_side_effects`
  - Asserts all:
    - WAL unchanged (or no committed entry)
    - no open orders created
    - no position deltas
    - no pending exposure increments

**Required evidence:**

- `evidence/phase1/no_side_effects/rejection_cases.md` **(MANUAL)** — list of at least 3 rejection cases exercised (e.g., missing config, invalid instrument meta, quantization fail) and links to CI logs.

**Unblock condition:**
AUTO: test green **AND** MANUAL: rejection cases doc exists.

---

### P1-D — intent_id / run_id Propagation Contract

**Goal:** Forensic traceability exists before dashboards.

**AUTO gates:**

- `test_intent_id_propagates_to_logs_and_metrics`
  - Triggers a rejected intent
  - Collects logs/metrics from the intent span
  - Asserts every relevant log/metric includes the same `intent_id` (and `run_id`)

**Required evidence:**

- `evidence/phase1/traceability/sample_rejection_log.txt` **(AUTO artifact)** — captured logs from the test run.

**Unblock condition:**
AUTO: test green + artifact emitted.

---

### P1-E — Gate Ordering Constraints (Invariants, Not Brittle Full Order)

**Goal:** Prevent semantic drift via "refactors."

**MANUAL evidence:**

`docs/intent_gate_invariants.md` **(MANUAL)** — must state these as normative:
- All reject-only gates run before any persistent side effects
- WAL commit/durable record happens before dispatch
- No refactor may introduce side effects prior to final accept/commit point

**AUTO gates:**

- `test_gate_ordering_constraints`
  - Instruments gate events and side-effect events
  - Fails if any constraint is violated

**Unblock condition:**
AUTO: test green **AND** MANUAL: invariants doc present.

---

### P1-F — Fail-Closed Defaults for Missing Config

**Goal:** Missing config must never degrade into "safe-looking defaults."

**MANUAL evidence:**

- `docs/critical_config_keys.md` **(MANUAL)** — short list of Phase-1 critical keys.

**AUTO gates:**

- `test_missing_config_fails_closed`
  - For each critical key removed:
    - intent rejected
    - no persistent side effects (must reuse P1-C assertions)
    - deterministic enumerated reject reason (no free text)

**Required evidence:**

- `evidence/phase1/config_fail_closed/missing_keys_matrix.json` **(AUTO artifact)** — per key: PASS/FAIL + reject reason code.

**Unblock condition:**
AUTO: test green + matrix emitted **AND** MANUAL: critical keys doc exists.

---

### P1-G — Minimal Crash-Mid-Intent Proof (Foundation Crash Safety)

**Goal:** If process crashes mid-intent before dispatch, restart does not cause:
- duplicate dispatch
- ghost state
- unsafe opens

**AUTO preferred gate:**

- `test_crash_mid_intent_no_duplicate_dispatch`

**If AUTO is not feasible yet (MANUAL fallback allowed only once):**

`evidence/phase1/crash_mid_intent/drill.md` **(MANUAL)** must include:
- trigger ("killed process at step X before dispatch")
- restart steps
- proof logs showing:
  - no dispatch occurred
  - no persistent side effects beyond counters/logs
  - restart does not create duplicates

**Unblock condition:**
AUTO: test green **OR** MANUAL: `drill.md` exists with recorded proof.

---

### Phase 1 Owner Sign-Off (Binary)

At end of Phase 1, answer **YES/NO** with linked evidence from `evidence/phase1/`:

1. Can any code path dispatch an exchange order without the chokepoint?
2. With identical frozen inputs, do we get identical intent bytes/hashes across restart?
3. Can a rejected intent leave behind any persistent state (WAL/orders/positions/exposure)?
4. Are all intent-handling logs traceable by a single `intent_id`?
5. If a required config key is missing, does the system refuse to trade (fail-closed) with an enumerated reject reason?

**If any answer is "I think so," Phase 1 is NOT DONE.**

---

### Explicit Phase 1 Non-Goals (Do Not Backport)

- ❌ No full `/status` endpoint/schema
- ❌ No TradingMode logic beyond minimal gating
- ❌ No replay/evidence/certification loop
- ❌ No dashboards/owner UI
- ❌ No broad chaos suite (only the minimal crash-mid-intent proof above)

---

# Phase 2 — Guardrails
### “Contain Damage Automatically”

## Definition of Done (Phase 2)

### 1) Delivered artifacts (merged)
- **Atomic Group Executor** for multi-leg logic with:
  - first-fail detection
  - ≤2 rescue attempts
  - deterministic emergency close + hedge fallback
- **PolicyGuard** as the *single* TradingMode authority (monotonic; no subsystem can re-enable risk).
- **Policy Fallback Ladder (Dead Man's Switch)** is explicit and monotonic: `Active -> ReduceOnly -> Kill` with deterministic reason codes.
- Runtime enforcement of:
  - `REDUCE_ONLY`
  - `KILL`
  - `OpenPermissionLatch` (explicit permission to create new exposure)
- **Reconciliation loop**:
  - WebSocket gap detection + REST reconciliation
  - zombie sweeper for ghost orders/orphan fills
  - **position/accounting correctness** (system knows what it owns vs what it thinks it owns)
- Rate-limit circuit breaker (429 / exchange-specific errors).
- Read-only control plane:
  - `GET /api/v1/status`
  - `GET /api/v1/health`
  - `POST /api/v1/emergency/reduce_only`
- `/status` contract fields for profile isolation are present and validated:
  - `supported_profiles`
  - `enforced_profile`
- **Runtime F1 safety gate active in PolicyGuard**:
  - missing/stale/invalid/mismatched `F1_CERT` => at most `ReduceOnly` (OPEN blocked; containment still permitted)

### 2) System guarantees
- **Capital supremacy invariant:** if exposure exists, at least one risk-reducing action is always permitted.
- **Mixed fills never persist:** partial/asymmetric execution triggers containment.
- **TradingMode is monotonic and authoritative:** once risk is blocked, it stays blocked until explicit operator action.
- **External failures are survivable:** rate limits, disconnects, websocket gaps, maintenance windows.
- **F1 is enforced as runtime safety input:** cert failures cannot be deferred to deployment governance.

### 3) Operational meaning
- Operators no longer need to react instantly to incidents.
- `/status` explains *why* the system is blocked/reduced.

> **Roadmap correction:** “Live with real money” should be **Micro-live only after PAPER gates pass**, not immediately at Phase 2 completion.

### 4) Explicitly NOT done yet
- No Truth Capsules / Decision Snapshots.
- No replay gatekeeper / canary automation.
- No self-improvement loop.

### Acceptance artifacts
- **Fault-injection tests** (staging):
  - disconnect mid-flight
  - rate-limit storms
  - websocket gap + late fills
  - partial fill on leg A, reject on leg B
  - crash/restart mid-flight (process kill + restart)
  - stale-data / liquidity-gate triggers (data becomes unusable)
  - clock drift / time sync fault (forces halt of new risk)
  - exchange maintenance / trading halted response

  **Minimum chaos requirement:** execute and record **≥8** injected fault scenarios (the list above is the baseline) and verify correct TradingMode transitions + containment outcomes.
- **Paper trading gate**
  - micro-live caps are defined in policy and enforced (tiny size; cannot be silently raised)
  - run at least 10 trading days (or 14 calendar days) paper with:
    - zero unreconciled positions
    - zero duplicate dispatches
    - bounded “containment events” with clear reasons
- **Mandatory CSP certification gate before any micro-live capital**
  - CI profile isolation: `build:csp_only` + `test:csp_only` are green (and profile matrix evidence is recorded)
  - runtime F1 binding gate is proven fail-closed for mismatch on `build_id`, `runtime_config_hash`, and `contract_version`
  - `/status` profile fields are correct (`supported_profiles`, `enforced_profile`)
  - CSP safety acceptance is green for reconciliation, emergency containment, and OpenPermissionLatch
- **Operational proof**
  - `/status` shows mode transitions correctly under fault tests
- A non-technical owner can read `/status` and identify **TradingMode + reason code** in **≤5 seconds** (no engineer translation).

---

# Phase 3 — Data Loop
### “Make Every Outcome Explainable”

## Definition of Done (Phase 3)

### 1) Delivered artifacts (merged)
- **Truth Capsule** written *before* dispatch (what we knew + what we intended).
- **Decision Snapshot** (decision-time market state, e.g., L2 top-N) linked to every dispatched order.
- Full **trade attribution** (slippage, fees, timing, opportunity cost if relevant).
- Time-drift gate (clock correctness enforced) — move earlier if strategy is time-sensitive.
- chrony/NTP discipline is documented and operationally health-checked (time-drift gate dependency).
- Deterministic **fill simulator** (for replay + regression).
- Shadow mode writes the same evidence schema as live (`mode=shadow|live`) for replay parity.
- Slippage calibration with safe default penalty.
- (Optional) full tick/L2 archive writer with rolling 72h retention for deep diagnostics (Decision Snapshots remain required).
- (Optional) options-surface stability gates (SVI/no-arb) if your strategy depends on them.

### 2) System guarantees
- **Every order is explainable:** what was known, decided, and what happened.
- **Replay is mechanically valid:** snapshot coverage ≥ 95% is measurable.
- **Logging cannot stall trading:** bounded queues; fail-closed for risk creation.
- **Bad data halts risk creation**, not containment.

### 3) Operational meaning
- You can answer “why did we lose money” with evidence, not guesses.
- You can run regression tests to prevent “we changed something and didn’t notice.”

### 4) Explicitly NOT done yet
- No automated rollout governance.
- No canary ladder automation (Phase 4).

### Acceptance artifacts
- Evidence store (db/files) with:
  - `truth_capsules`
  - `decision_snapshots`
  - `trade_attribution`
- Metrics/dashboard:
  - snapshot coverage %
  - slippage distribution vs expected
  - time drift
- Replay report:
  - same inputs → same decisions (within defined tolerances)
- Adversarial replay pack:
  - defined stress scenarios are included and pass (e.g., vol spike, illiquidity/wide spreads, late fills, exchange outage/gap)
  - coverage thresholds are met on those scenarios (not just “average days”)
- Operations evidence:
  - chrony/NTP health checks are recorded for phase runs
  - shadow-mode replay outputs are schema-compatible with live outputs
  - if full tick/L2 archives are enabled, retention is validated at 72h with watermark behavior

---

# Phase 4 — Live Fire Controls
### “Change Nothing Unsafely”

## Definition of Done (Phase 4)

### 1) Delivered artifacts (merged)
- **Replay Gatekeeper**:
  - snapshot coverage hard gate
  - realism penalty
  - drawdown + profitability constraints
- **Canary rollout system**:
  - Shadow → Micro-live → Full
  - automatic rollback + ReduceOnly cooldown
- **ExecutionStyle lock:** `Sniper` (IOC limit-only) is enforced for live-fire rollout unless a contract amendment explicitly changes it.
- Disk retention + watermark enforcement (evidence cannot silently disappear), with explicit defaults:
  - pause full tick/L2 archives at `80%` disk usage
  - force `ReduceOnly` at `85%`
  - force `Kill` at `92%`
  - default retention: tick/L2 `72h`; Decision Snapshots `30d` (never violating replay-window minimum)
- **F1 Certification pipeline** (name optional): CI-generated artifact + promotion gate that binds build + config + contract version (runtime enforcement is already active from Phase 2).
- Release-gate scoreboard for contract metrics (including `atomic_naked_events`, `429_count_5m`, `10028_count_5m`) is wired into promotion decisions.
- Human approval latch for risk-increasing changes.

### 2) System guarantees
- No unsafe policy reaches production, even if it looks profitable.
- Evidence loss blocks risk creation.
- Disk exhaustion cannot corrupt trading behavior.
- Human approval required for risk-increasing changes.

### 3) Operational meaning
- The system can evolve without relying on human vigilance.

### Acceptance artifacts
- Canary tests: abort + rollback work for every abort condition.
- Certification artifact produced in CI, verified by promotion gates, and validated against the already-active runtime F1 gate.
- Release-gate scoreboard artifact proves threshold evaluation for `atomic_naked_events`, `429_count_5m`, `10028_count_5m`, and related contract metrics.
- Retention/watermark tests prove 80/85/92 transitions plus replay-window-safe Decision Snapshot retention.
- Governance artifact: approvals recorded for risk-increasing changes.
- Governance rule: risk-increasing approvals are **limited in scope and frequency**; bulk/cumulative changes require separate review (prevents approval fatigue).
- Production SLOs defined and met for **at least 14 calendar days** before scaling.

---

## Cross-cutting: Strategy Work (allowed, but boxed in)

Strategy can be built at any time **as long as**:
- It can only produce **order intents** (never direct exchange calls).
- It cannot bypass PolicyGuard / RiskState.
- Every decision is attributable to inputs (Phase 3 evidence model).

**Minimum strategy deliverables before any micro-live**
- Strategy interface contract
- A regression backtest/replay suite (“same data → same outputs”)
- Guardrails around parameter changes (config versioning + approvals)

---

## Weaknesses found in the current roadmap (and fixes)

1) **Paper policies without binding are gameable.**  
   Fix: require machine-readable policy enforcement + at least one recorded **break-glass drill** (Phase 0).

2) **Ambiguous “optional” gates invite debate later (and real money sooner).**  
   Fix: any edge/profitability gate must be explicitly labeled **policy**, cannot block emergency close/`REDUCE_ONLY`, and must be tested (Phase 1).

3) **Paper trading without chaos is false confidence.**  
   Fix: Phase 2 exit requires **≥8 injected fault scenarios executed + recorded**, not just calm-market paper days.

4) **Observability that needs an engineer is observability theater.**  
   Fix: `/status` must be owner-readable (TradingMode + reason in ≤5 seconds) with documented reason codes (Phase 2).

5) **Replay without adversarial scenarios certifies average-case only.**  
   Fix: Phase 3 acceptance must include defined **stress scenarios** (vol spike, illiquidity, late fills, outage/gaps).

6) **Human approval can degrade into rubber-stamping.**  
   Fix: Phase 4 approvals are limited in scope/frequency; bulk/cumulative risk changes require separate review.

7) **Evidence packs can become a dumping ground.**  
   Fix: each phase evidence pack must include a **1-page summary** stating what was proven, what failed, and remaining risks.

---

## Roadmap Audit Findings (2026-01-28)

Status: **Fixed** (all items resolved in this document).

| ID | Finding | Resolution | Evidence (section) |
|---|---|---|---|
| RM-001 | Phase 1 chokepoint wording conflicted (order construction vs dispatch). | Standardized on a **dispatch chokepoint** with explicit exchange-client restriction. | Phase 1 — Delivered artifacts; P1-A |
| RM-002 | Pre-dispatch gates implied emergency close in Phase 1. | Clarified “risk-reducing orders” while keeping automated flattening out of Phase 1. | Phase 1 — Delivered artifacts; Explicitly NOT done yet |
| RM-003 | RiskState gate lacked a Phase 1 definition or test. | Defined minimum RiskState set and required a specific test. | Phase 1 — System guarantees |
| RM-004 | Phase 0 evidence pack omitted health endpoint snapshot. | Added `health/health_endpoint_snapshot.md` to evidence pack. | Phase 0 Evidence Pack |
| RM-005 | AUTO gates allowed `ci_links.md` to be “N/A”. | Require CI links or recorded local output for AUTO gates. | Phase 0 Evidence Pack |
| RM-006 | Restart-loop proof lacked a required artifact. | Added required evidence artifact path for 100+ cycle run. | Phase 1 — Acceptance artifacts |

## Glossary (plain language)

- **WAL / Intent Ledger:** a write-ahead log so a crash/restart can’t cause duplicate orders.
- **Order intent:** the fully-specified “what we want to do” object (symbol, size, price, tags, constraints).
- **PolicyGuard / TradingMode:** the authority that says whether the system is allowed to create new risk.
- **ReduceOnly:** only actions that reduce exposure are permitted.
- **Truth Capsule:** the “receipt” saved before trading: inputs, decision, and intent.
- **Decision Snapshot:** market context captured at decision time (used for replay/audit).
- **Replay Gatekeeper:** blocks deployments unless replay evidence meets thresholds.
- **Canary:** a small, low-risk production rollout before scaling.



---

## Contractual Milestone Checklist (sign-off ready)

> Use this as the acceptance checklist for each phase. A phase is **not** complete unless every checkbox is satisfied and the evidence pack is stored.

### Phase 0 — Launch Policy & Ops Baseline ✅ COMPLETE (2026-01-28)
- [x] Trading Policy exists (risk limits, instruments, max daily loss, max order rate). → `docs/launch_policy.md`
- [x] Policy limits are **machine-readable and enforced** at runtime (not just in docs). → `config/policy.json`, `tools/policy_loader.py`, `tests/phase0/test_machine_policy_loader_and_config.md`
- [x] Trading modes defined and documented (`Active`, `ReduceOnly`, `Kill`) with who/what can switch them. → `docs/launch_policy.md`
- [x] Separate API keys per environment; least privilege; rotation plan documented. → `docs/env_matrix.md`, `docs/keys_and_secrets.md`
- [x] Key scopes are **proven** (probe tests recorded). → `evidence/phase0/keys/key_scope_probe.json`
- [x] Incident runbook exists (kill switch, exchange outage, PnL spike, mixed fills). → `docs/break_glass_runbook.md`
- [x] At least one **break-glass drill** executed and recorded (simulate runaway order → force `KILL` → verify no further OPENs; `REDUCE_ONLY` still works). → `evidence/phase0/break_glass/drill.md`
- [x] Basic health + owner status output exists (CLI) and is readable by a non-coder. → `docs/health_endpoint.md`, `stoic-cli`
- [x] Canonical verify harness entrypoint is enforced (`plans/verify.sh` delegates to `plans/verify_fork.sh`), and workflow paths follow canonical contract locations.

**Sign-off statement:** Ops rules are defined **and binding**; "safe" is enforced, drilled, and observable.

### Phase 1 — Foundation
- [ ] All exchange dispatch routes through the single **dispatch chokepoint** (only one module may call the exchange client).
- [ ] WAL/intent ledger prevents duplicates across crash/restart/reconnect.
- [ ] Determinism tests pass (hashing/quantization/labels).
- [ ] `s4` label schema is enforced exactly (`s4:{sid8}:{gid12}:{li}:{ih16}`), including Deribit `<=64` chars, no truncation, overflow reject semantics (`Rejected(LabelTooLong)` + `RiskState::Degraded`), and AT-216/217/041/921 coverage.
- [ ] Illegal orders are rejected before any exchange API call.
- [ ] Any edge/profitability gate is explicitly labeled **policy** and cannot block risk-reducing orders (close/reduce-only).
- [ ] Deribit Venue Facts Addendum checks are artifact-backed and CI-enforced (evidence check failure blocks build).
- [ ] Verification harness fails the build on contract violations.
- [ ] Logs/metrics include `run_id` and `intent_id` (traceability).

**Sign-off statement:** The system cannot create unintended exposure silently.

### Phase 2 — Guardrails
- [ ] Atomic group executor + bounded rescue attempts implemented and tested.
- [ ] PolicyGuard is authoritative and monotonic (no re-enable leaks).
- [ ] Runtime F1 gate is active in PolicyGuard (`F1_CERT` missing/stale/invalid/mismatched => at most `ReduceOnly`; OPEN blocked).
- [ ] Policy fallback ladder (Dead Man's Switch) is explicit and monotonic (`Active -> ReduceOnly -> Kill`) with deterministic reason codes.
- [ ] Reconciliation loop exists (WS gaps + REST; zombie/orphan sweeps).
- [ ] `/status` exposes *why* trading is blocked/reduced using contract fields (`trading_mode`, `mode_reasons`, `open_permission_reason_codes`) and the Owner dashboard passes the 5-second rule.
- [ ] `/status` profile isolation fields are correct and present (`supported_profiles`, `enforced_profile`) under CSP semantics.
- [ ] A non-technical owner can read `/status` and identify **TradingMode + reason** in **≤5 seconds**.
- [ ] Fault-injection tests pass (rate limits, disconnects, gaps, mixed fills) **with ≥8 injected scenarios executed + recorded**.
- [ ] Paper trading completed for **at least 10 trading days (or 14 calendar days)** with clean reconciliation, no duplicates, and fault handling verified.
- [ ] CSP certification gate passes before micro-live (`build:csp_only`, `test:csp_only`, runtime F1 binding checks, and CSP acceptance coverage for reconciliation/emergency containment/OpenPermissionLatch).

**Sign-off statement:** Exposure cannot persist accidentally; the system chooses safety automatically.

### Phase 3 — Data Loop
- [ ] Truth Capsule is written before dispatch for every order intent.
- [ ] Decision Snapshot is linked to every dispatch; coverage metric computed.
- [ ] Trade attribution matches fills (100% of fills attributed).
- [ ] chrony/NTP discipline is enforced operationally and health-checked.
- [ ] Shadow-mode outputs are schema-compatible with live evidence outputs.
- [ ] Replay runner can reconstruct decisions from evidence within defined tolerances.
- [ ] Replay acceptance includes defined **stress scenarios** (vol spike, illiquidity, late fills, outage/gaps), not just average periods.
- [ ] Evidence/telemetry failure blocks **new** risk creation (reduce-only still allowed).
- [ ] If enabled, full tick/L2 archives honor rolling 72h retention and watermark behavior (Decision Snapshots remain mandatory regardless).

**Sign-off statement:** Every trade is explainable and replayable with measurable coverage.

### Phase 4 — Live Fire Controls
- [ ] Replay Gatekeeper blocks promotion when thresholds fail.
- [ ] Canary ladder exists (shadow → micro-live → full) with automatic rollback.
- [ ] ExecutionStyle is locked to `Sniper` (IOC limit-only) for live-fire rollout unless contract-amended.
- [ ] ReduceOnly cooldown and rollback behaviors tested end-to-end.
- [ ] Certification artifact binds build+config+contract version in CI/promotion and is consistent with the runtime F1 gate introduced in Phase 2.
- [ ] Release-gate scoreboard includes `atomic_naked_events`, `429_count_5m`, `10028_count_5m` and blocks promotion on threshold failures.
- [ ] Human approval recorded for risk-increasing changes.
- [ ] Risk-increasing approvals are limited in **scope and frequency**; bulk/cumulative changes require separate review.
- [ ] Retention/watermark gates enforce 80/85/92 transitions plus default retention safety (`tick_l2_retention_hours=72`, `decision_snapshot_retention_days=30` with replay-window protection).
- [ ] Production SLOs met for **at least 14 calendar days** before scaling up.

**Sign-off statement:** The system can evolve safely without relying on human vigilance.

---

## Evidence Pack Template (recommended folder layout)

Create one folder per phase completion:

- `evidence/phase0/`
- `evidence/phase1/`
- `evidence/phase2/`
- `evidence/phase3/`
- `evidence/phase4/`

Each folder should contain:
- `README.md` (what was tested, how to reproduce)
- `SUMMARY_1PAGE.md` (what was proven, what failed, what remains risky — owner-readable)
- `test_results.txt` or CI links
- `run_logs/` (representative logs with run_id)
- `metrics_exports/` (screenshots/exports)
- `incident_drills/` (what drills were run + outcome)

This is what prevents “soft done” and makes the roadmap enforceable.
