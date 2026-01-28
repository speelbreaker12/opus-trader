# Roadmap (Merged + Hardened) — Automated Crypto Options Trading System
_Last updated: January 26, 2026_

This document merges:
- Your phase-based roadmap with strong mechanical safety guarantees (Phases 1–4). 
- The strategic structure: constraint-first scheduling (TOC), environment ladder, and deployment/testing gates.

> **Contract + Implementation Plan remain the source of truth for requirements.** This roadmap is the human-readable control layer.  
> (Note: the files you shared for Contract/Implementation Plan are redirect stubs pointing to `specs/…`.)

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

---

## 3) One-page Executive Table (Outcome + Permission)

| Phase | Name | What’s true at the end (plain language) | Permission unlocked | Where it must run |
|---:|---|---|---|---|
| 0 | Launch Policy & Ops Baseline | We agree on risk limits, modes, keys, and how incidents are handled. | We can run safely in DEV/STAGING without ambiguity. | DEV/STAGING |
| 1 | Foundation (“Never Panic, Never Duplicate”) | The system is mechanically prevented from sending illegal/duplicate orders or sizing wrong silently. | Safe dry-run + restart/replay testing. | DEV/STAGING |
| 2 | Guardrails (“Contain Damage Automatically”) | If we get exposed, the system can always contain/reduce exposure automatically under exchange/infrastructure failures. | **Paper trading** is allowed. **Micro-live** is allowed only after paper gates pass. | STAGING/PAPER |
| 3 | Data Loop (“Make Every Outcome Explainable”) | Every trade is explainable, attributable, and replayable with measurable coverage. | We can iterate strategy with evidence and regression tests. | PAPER/MICRO-LIVE |
| 4 | Live Fire Controls (“Change Nothing Unsafely”) | No risky change reaches production without replay proof + controlled rollout + rollback. | Scaled production with safe evolution. | MICRO-LIVE/PROD |

---

# Phase 0 — Launch Policy & Ops Baseline (Prerequisite)

### Outcome (non-coder version)
Before we argue about features, we lock the **rules of the game**: what the bot is allowed to do, what “unsafe” means, and how we respond when things go wrong.

### Delivered artifacts
- **Trading Policy** (allowed venues/instruments, max leverage, max delta/gamma/vega, max daily loss, max order rate, **micro-live caps**).
- **TradingMode** defined (contract): `ACTIVE`, `REDUCE_ONLY`, `KILL`.
- **DeploymentEnvironment** defined: `DEV`, `STAGING`, `PAPER`, `LIVE`.
- **Key & Secrets policy**: separate keys per environment, least privilege, rotation plan.
- **Ops baseline**: basic logs/metrics, alerts, and an incident runbook (kill-switch steps).

### Exit criteria (evidence pack)
- `docs/trading_policy.md` (human-readable policy)
- `config/trading_policy.(yaml|json)` (machine-readable limits **actually enforced** by the runtime)
- `docs/runbook.md` (what to do on disconnects, mixed fills, PnL spikes, etc.)
- `docs/secrets_and_access.md`
- **Proof of binding + drills**
  - A recorded **break-glass drill** (at least 1) showing: simulated runaway order attempt → forced `KILL` → verified **no further OPENs**; `REDUCE_ONLY` still permitted.
  - A recorded **key-scope probe** showing keys are least-privilege (e.g., read-only key cannot trade; trading key cannot withdraw, etc.).
- A **single command** to start the system in DEV/STAGING and print a `/health` style status (e.g., ok, build_id, contract_version; deployment_environment if available).

---

# Phase 1 — Foundation
### “Never Panic, Never Duplicate”

## Definition of Done (Phase 1)

### 1) Delivered artifacts (merged)
- A **single, enforced order-construction chokepoint** (e.g., `build_order_intent()`).
- A **durable intent ledger (WAL)** + replay logic.
- Deterministic:
  - instrument classification
  - sizing units + quantization
  - intent hashing
  - label generation
- Preflight guards that **hard-reject** illegal orders (market/stop/linked/post-only crossing, etc.).
- “Pre-dispatch gates” wired before any exchange call:
  - liquidity gate (data must be good enough)
  - fee staleness gate
  - If you have any “edge/profitability” gate: it MUST be explicitly labeled as **policy** (not execution safety), MUST NOT block emergency close / `REDUCE_ONLY`, and MUST be versioned + tested.
- A runnable verification harness (e.g., `plans/verify.sh`) that fails the build on contract violations.
- **Baseline observability**: structured logs + metrics with a `run_id` and `intent_id`.

### 2) System guarantees
- **Idempotency is absolute:** crash/restart/reconnect cannot duplicate orders.
- **No OPEN risk can be created** when:
  - WAL enqueue fails
  - sizing metadata is stale/missing
  - RiskState ≠ Healthy
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
- No emergency flattening.
- No `/status` endpoint (ok if Phase 0 has minimal health output).
- No evidence/attribution/replay governance.

### Acceptance artifacts (what “proof” looks like)
- **Tests**
  - determinism tests for hashing/quantization/labels
  - WAL crash-replay tests (no duplicate dispatch)
  - illegal order rejection tests
- **Operational proof**
  - a restart loop test that runs 100+ cycles with zero duplicates
  - metrics: `duplicate_dispatch_count == 0`, `illegal_order_attempts == 0`

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

### 2) System guarantees
- **Capital supremacy invariant:** if exposure exists, at least one risk-reducing action is always permitted.
- **Mixed fills never persist:** partial/asymmetric execution triggers containment.
- **TradingMode is monotonic and authoritative:** once risk is blocked, it stays blocked until explicit operator action.
- **External failures are survivable:** rate limits, disconnects, websocket gaps, maintenance windows.

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
  - run 7–14 days paper with:
    - zero unreconciled positions
    - zero duplicate dispatches
    - bounded “containment events” with clear reasons
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
- Deterministic **fill simulator** (for replay + regression).
- Slippage calibration with safe default penalty.
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
- Disk retention + watermark enforcement (evidence cannot silently disappear).
- **F1 Certification** (name optional): CI-generated, runtime-enforced, binds build + config + contract version.
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
- Certification artifact produced in CI and verified at runtime.
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

## Glossary (plain language)

- **WAL / Intent Ledger:** a write-ahead log so a crash/restart can’t cause duplicate orders.
- **Order intent:** the fully-specified “what we want to do” object (symbol, size, price, tags, constraints).
- **PolicyGuard / TradingMode:** the authority that says whether the system is allowed to create new risk.
- **DeploymentEnvironment:** where the system is running (`DEV`, `STAGING`, `PAPER`, `LIVE`); not a TradingMode.
- **ReduceOnly:** only actions that reduce exposure are permitted.
- **Truth Capsule:** the “receipt” saved before trading: inputs, decision, and intent.
- **Decision Snapshot:** market context captured at decision time (used for replay/audit).
- **Replay Gatekeeper:** blocks deployments unless replay evidence meets thresholds.
- **Canary:** a small, low-risk production rollout before scaling.



---

## Contractual Milestone Checklist (sign-off ready)

> Use this as the acceptance checklist for each phase. A phase is **not** complete unless every checkbox is satisfied and the evidence pack is stored.

### Phase 0 — Launch Policy & Ops Baseline
- [ ] Trading Policy exists (risk limits, instruments, max daily loss, max order rate).
- [ ] Policy limits are **machine-readable and enforced** at runtime (not just in docs).
- [ ] TradingMode defined and documented (`ACTIVE`, `REDUCE_ONLY`, `KILL`) with who/what can switch it.
- [ ] DeploymentEnvironment defined and documented (`DEV`, `STAGING`, `PAPER`, `LIVE`) with how it is set.
- [ ] Separate API keys per environment; least privilege; rotation plan documented.
- [ ] Key scopes are **proven** (probe tests recorded).
- [ ] Incident runbook exists (kill switch, exchange outage, PnL spike, mixed fills).
- [ ] At least one **break-glass drill** executed and recorded (simulate runaway order → force `KILL` → verify no further OPENs; `REDUCE_ONLY` still works).
- [ ] Basic health output exists (API endpoint or CLI) and is readable by a non-coder.

**Sign-off statement:** Ops rules are defined **and binding**; “safe” is enforced, drilled, and observable.

### Phase 1 — Foundation
- [ ] All order creation routes through the single chokepoint (order intent builder).
- [ ] WAL/intent ledger prevents duplicates across crash/restart/reconnect.
- [ ] Determinism tests pass (hashing/quantization/labels).
- [ ] Illegal orders are rejected before any exchange API call.
- [ ] Any edge/profitability gate is explicitly labeled **policy** and cannot block emergency close / `REDUCE_ONLY`.
- [ ] Verification harness fails the build on contract violations.
- [ ] Logs/metrics include `run_id` and `intent_id` (traceability).

**Sign-off statement:** The system cannot create unintended exposure silently.

### Phase 2 — Guardrails
- [ ] Atomic group executor + bounded rescue attempts implemented and tested.
- [ ] PolicyGuard is authoritative and monotonic (no re-enable leaks).
- [ ] Reconciliation loop exists (WS gaps + REST; zombie/orphan sweeps).
- [ ] `/status` and `/health` (or equivalent) expose *why* trading is blocked/reduced with documented **reason codes**.
- [ ] A non-technical owner can read `/status` and identify **TradingMode + reason** in **≤5 seconds**.
- [ ] Fault-injection tests pass (rate limits, disconnects, gaps, mixed fills) **with ≥8 injected scenarios executed + recorded**.
- [ ] Paper trading completed for **at least 10 trading days (or 14 calendar days)** with clean reconciliation, no duplicates, and fault handling verified.

**Sign-off statement:** Exposure cannot persist accidentally; the system chooses safety automatically.

### Phase 3 — Data Loop
- [ ] Truth Capsule is written before dispatch for every order intent.
- [ ] Decision Snapshot is linked to every dispatch; coverage metric computed.
- [ ] Trade attribution matches fills (100% of fills attributed).
- [ ] Replay runner can reconstruct decisions from evidence within defined tolerances.
- [ ] Replay acceptance includes defined **stress scenarios** (vol spike, illiquidity, late fills, outage/gaps), not just average periods.
- [ ] Evidence/telemetry failure blocks **new** risk creation (reduce-only still allowed).

**Sign-off statement:** Every trade is explainable and replayable with measurable coverage.

### Phase 4 — Live Fire Controls
- [ ] Replay Gatekeeper blocks promotion when thresholds fail.
- [ ] Canary ladder exists (shadow → micro-live → full) with automatic rollback.
- [ ] ReduceOnly cooldown and rollback behaviors tested end-to-end.
- [ ] Certification artifact binds build+config+contract version and is enforced at runtime.
- [ ] Human approval recorded for risk-increasing changes.
- [ ] Risk-increasing approvals are limited in **scope and frequency**; bulk/cumulative changes require separate review.
- [ ] Production SLOs met for **at least 14 calendar days** before scaling up.

**Sign-off statement:** The system can evolve safely without relying on human vigilance.

---

## Evidence Pack Template (recommended folder layout)

Create one folder per phase completion:

- `evidence/phase0_policy/`
- `evidence/phase1_foundation/`
- `evidence/phase2_guardrails/`
- `evidence/phase3_dataloop/`
- `evidence/phase4_livefire/`

Each folder should contain:
- `README.md` (what was tested, how to reproduce)
- `SUMMARY_1PAGE.md` (what was proven, what failed, what remains risky — owner-readable)
- `test_results.txt` or CI links
- `run_logs/` (representative logs with run_id)
- `metrics_exports/` (screenshots/exports)
- `incident_drills/` (what drills were run + outcome)

This is what prevents “soft done” and makes the roadmap enforceable.
