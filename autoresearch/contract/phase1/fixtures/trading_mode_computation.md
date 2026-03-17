#### **2.2.3 TradingMode Computation (Axis Resolver v2 + Reason Codes)**
Profile: CSP

**Hard Rule:** The Soldier never "stores" TradingMode as authoritative state. It recomputes it every loop tick via `PolicyGuard.get_effective_mode()` (the **Axis Resolver**) immediately before any dispatch (§2.2.3.4).

---

##### **2.2.3.0 Axis Model (Normative)**

PolicyGuard SHALL compute TradingMode from three independent health axes:

- `CapitalRiskAxis     ∈ { SAFE, WARNING, CRITICAL }`
- `MarketIntegrityAxis ∈ { STABLE, STRESSED, BROKEN }`
- `SystemIntegrityAxis ∈ { HEALTHY, DEGRADED, FAILING }`

**Axis Computation Rules (Non-Negotiable):**
- **Independence rule:** Each axis MUST depend only on signals assigned to that axis. Axis computation MUST NOT depend on TradingMode, other axes, or derived outcomes.
- **Primary assignment rule:** Every PolicyGuard input signal MUST have exactly one primary axis.
- **Dual-impact rule:** A signal MAY influence a secondary axis only if listed in §2.2.3.1.
- **Authoritative attribution rule:** The axis input lists in §2.2.3.2 are authoritative. A signal MUST NOT influence an axis unless it appears in that axis’s input list, except for secondary-axis influence explicitly allowlisted in §2.2.3.1.

##### **2.2.3.1 Dual-Impact Allowlist (Explicit)**

| Signal | Primary Axis | Secondary Axis | Justification |
|---|---|---|---|
| WAL write failure | SystemIntegrityAxis | CapitalRiskAxis | Restart/idempotency correctness compromised |
| Ledger corruption | SystemIntegrityAxis | CapitalRiskAxis | Reconciliation correctness compromised |
| Exchange session termination (`session_termination_active`) | SystemIntegrityAxis | CapitalRiskAxis | Containment reliability uncertain |

---

##### **2.2.3.1.2 Kill Trigger Corroboration (Non‑Capital)**

To reduce single‑signal corruption risk, the following **non‑capital** Kill triggers require corroboration.
If the primary predicate is true but corroboration is missing/false, the trigger MUST NOT contribute to `SystemIntegrityAxis == FAILING`; instead PolicyGuard MUST force **ReduceOnly** with the specified reason code(s).

**Confirmed predicates (Normative):**
- **Watchdog Kill (confirmed):**  
  `(now_ms - watchdog_last_heartbeat_ts_ms > watchdog_kill_s * 1000)` **AND**  
  `(now_ms - loop_tick_last_ts_ms > watchdog_kill_s * 1000)`
- **Disk Kill (confirmed):**  
  `disk_used_pct >= disk_kill_pct` **AND** `disk_used_pct_secondary >= disk_kill_pct`,  
  with both timestamps fresh per `disk_used_max_age_ms`.
- **Session Termination Kill (authoritative):**
  `session_termination_active == true`.
  This signal is authoritative and does NOT require corroboration by rolling counts.

**Unconfirmed behavior (Non‑Negotiable):**
- If the primary predicate is true but confirmation fails, PolicyGuard MUST compute `TradingMode = ReduceOnly`
  and include the appropriate `REDUCEONLY_*_UNCONFIRMED` reason code.

**Session-termination clarification (Normative):**
- `10028_count_5m` remains an observability/release metric.
- `10028_count_5m` MUST NOT gate session-termination Kill decisions.

**Scope guard:** These corroboration rules do **NOT** apply to capital‑critical Kill triggers (`mm_util >= mm_util_kill`, `risk_state == Kill`).

---

##### **2.2.3.2 Axis Computation (Deterministic)**

PolicyGuard MUST compute the axes as follows, using only the coherent input snapshot acquired per §2.2.0.

**CapitalRiskAxis** (capital exposure / margin headroom)
- Inputs: `mm_util`, `risk_state`, `cortex_override`
- `CRITICAL` if ANY are true:
  - `mm_util >= mm_util_kill` (margin headroom exhausted; §1.4.3)
  - `risk_state == Kill`
  - `cortex_override == ForceKill`
- `WARNING` if:
  - `mm_util >= mm_util_reduceonly` AND `mm_util < mm_util_kill`
- `SAFE` otherwise.

**MarketIntegrityAxis** (market data integrity / comms reliability)
- Input: `bunker_mode_active` (from §2.3.2 Network Jitter Monitor)
- `STRESSED` if `bunker_mode_active == true`
- `STABLE` otherwise.
- `BROKEN` is reserved for future explicit monitors. In v5.2 it MUST NOT be produced by any required subsystem.

**SystemIntegrityAxis** (correctness / containment reliability)
- Inputs: `watchdog_last_heartbeat_ts_ms`, `loop_tick_last_ts_ms`, `disk_used_pct`, `disk_used_pct_secondary`, `session_termination_active`, plus all reduce-only gates below.
- `FAILING` if ANY are true:
  - Watchdog Kill confirmed (per §2.2.3.1.2)
  - Disk Kill confirmed (per §2.2.3.1.2)
  - Session Termination Kill confirmed (per §2.2.3.1.2)
- `DEGRADED` if ANY are true AND `SystemIntegrityAxis != FAILING`:
  - `risk_state in {Degraded, Maintenance}`
  - `emergency_reduceonly_active == true`
  - `open_permission_blocked_latch == true`
  - `EvidenceChainState != GREEN` (§2.2.2) when `enforced_profile != CSP`
  - Runtime binding cert invalid/missing/stale/FAIL (§2.2.1)
  - `cortex_override == ForceReduceOnly`
  - `fee_model_cache_age_s > fee_model_hard_stale_s` (§4.2)
  - `policy_age_sec > max_policy_age_sec` (Appendix A: `max_policy_age_sec`)
  - Any critical PolicyGuard input missing/unparseable/stale per §2.2.1.2
  - Watchdog Kill unconfirmed (per §2.2.3.1.2)
  - Disk Kill unconfirmed (per §2.2.3.1.2)
- `HEALTHY` otherwise.

---

##### **2.2.3.3 TradingMode Resolution (Deterministic, Pure Function of Axes)**

TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } SHALL be computed from axes by the following rules (no other rules are permitted):

1) If `SystemIntegrityAxis == FAILING` OR `CapitalRiskAxis == CRITICAL` → `TradingMode = Kill`
2) Else if `SystemIntegrityAxis == DEGRADED` OR `MarketIntegrityAxis != STABLE` OR `CapitalRiskAxis == WARNING` → `TradingMode = ReduceOnly`
3) Else → `TradingMode = Active`

All 27 axis combinations MUST map deterministically to exactly one TradingMode via these rules.

**Canonical 27-State Mapping Table (Normative):**

This table is the authoritative reference for AT-1048 (enumerability test). Implementations MUST produce identical outputs.

| # | CapitalRiskAxis | MarketIntegrityAxis | SystemIntegrityAxis | TradingMode | Rule |
|---|-----------------|---------------------|---------------------|-------------|------|
| 1 | SAFE | STABLE | HEALTHY | Active | R3 |
| 2 | SAFE | STABLE | DEGRADED | ReduceOnly | R2 |
| 3 | SAFE | STABLE | FAILING | Kill | R1 |
| 4 | SAFE | STRESSED | HEALTHY | ReduceOnly | R2 |
| 5 | SAFE | STRESSED | DEGRADED | ReduceOnly | R2 |
| 6 | SAFE | STRESSED | FAILING | Kill | R1 |
| 7 | SAFE | BROKEN | HEALTHY | ReduceOnly | R2 |
| 8 | SAFE | BROKEN | DEGRADED | ReduceOnly | R2 |
| 9 | SAFE | BROKEN | FAILING | Kill | R1 |
| 10 | WARNING | STABLE | HEALTHY | ReduceOnly | R2 |
| 11 | WARNING | STABLE | DEGRADED | ReduceOnly | R2 |
| 12 | WARNING | STABLE | FAILING | Kill | R1 |
| 13 | WARNING | STRESSED | HEALTHY | ReduceOnly | R2 |
| 14 | WARNING | STRESSED | DEGRADED | ReduceOnly | R2 |
| 15 | WARNING | STRESSED | FAILING | Kill | R1 |
| 16 | WARNING | BROKEN | HEALTHY | ReduceOnly | R2 |
| 17 | WARNING | BROKEN | DEGRADED | ReduceOnly | R2 |
| 18 | WARNING | BROKEN | FAILING | Kill | R1 |
| 19 | CRITICAL | STABLE | HEALTHY | Kill | R1 |
| 20 | CRITICAL | STABLE | DEGRADED | Kill | R1 |
| 21 | CRITICAL | STABLE | FAILING | Kill | R1 |
| 22 | CRITICAL | STRESSED | HEALTHY | Kill | R1 |
| 23 | CRITICAL | STRESSED | DEGRADED | Kill | R1 |
| 24 | CRITICAL | STRESSED | FAILING | Kill | R1 |
| 25 | CRITICAL | BROKEN | HEALTHY | Kill | R1 |
| 26 | CRITICAL | BROKEN | DEGRADED | Kill | R1 |
| 27 | CRITICAL | BROKEN | FAILING | Kill | R1 |

**State Count Summary:**
- Active: 1 state (row 1 only)
- ReduceOnly: 17 states (rows 2, 4-5, 7-8, 10-11, 13-14, 16-17)
- Kill: 9 states (rows 3, 6, 9, 12, 15, 18-27)

**Implementation Note:** The resolver function MUST be a pure function with no hidden state. Given the same axis triple, it MUST always produce the same TradingMode.

**Monotonicity Rule (CSP):**
- If any axis worsens between ticks, TradingMode MUST NOT become less restrictive on that tick.

**Recovery Rule (CSP):**
- Axis recovery MUST be slower than axis degradation. Recovery MUST respect the hysteresis/cooldown rules of each producer:
  - EvidenceGuard (§2.2.2) windowing + cooldown (only when `enforced_profile != CSP`)
  - Bunker Mode (§2.3.2) stable-exit window
  - Emergency ReduceOnly (§2.2 inputs) cooldown + reconcile-clear
  - Open Permission Latch (§2.2.4) reconcile-clear

---

##### **2.2.3.4 Dispatch Authorization (Non-Negotiable)**

- Every network dispatch attempt MUST consult PolicyGuard immediately before dispatch (hot path check; §2.2.3.4).
- OPEN intents MUST dispatch only if `TradingMode == Active` AND all other gates allow.
- If `TradingMode == ReduceOnly`: OPEN intents MUST NOT dispatch; CLOSE/HEDGE/CANCEL intents MAY dispatch only if not risk-increasing per §2.2.5.
- If `TradingMode == Kill`: OPEN intents MUST NOT dispatch; ONLY risk-reducing intents MAY dispatch per §2.2.3.6.

---

##### **2.2.3.4.1 Non‑Active OPEN Cancellation (CSP, Non‑Negotiable)**

Whenever `TradingMode != Active`, the engine MUST attempt to cancel all outstanding OPEN orders with `reduce_only != true`.
- This cancel loop MUST be **bounded and non‑blocking** per tick (see `cancel_open_batch_max`, `cancel_open_budget_ms` in Appendix A).
- If any risk‑increasing OPENs remain, the system MUST retry on subsequent ticks until cleared.
- CLOSE/HEDGE/CANCEL intents remain permitted subject to §2.2.5.

---

##### **2.2.3.5 ModeReasonCode Registry (`/status.mode_reasons`)**

PolicyGuard MUST expose the reasons that produced the current TradingMode via `/api/v1/status.mode_reasons`.

**Hard rules:**
- PolicyGuard MUST compute `mode_reasons` every tick.
- If `TradingMode == Active`: `mode_reasons MUST == []`.
- If `TradingMode == ReduceOnly`: `mode_reasons` MUST be non-empty and MUST contain only `REDUCEONLY_*` reasons.
- If `TradingMode == Kill`: `mode_reasons` MUST be non-empty and MUST contain only `KILL_*` reasons.
- Reasons MUST be deterministically ordered.
- Reasons MUST be tier-pure: `KILL_*` and `REDUCEONLY_*` MUST NOT mix.

**Allowed values (deterministic order):**
Kill-tier:
1. `KILL_WATCHDOG_HEARTBEAT_STALE`
2. `KILL_RISKSTATE_KILL`
3. `KILL_MARGIN_MM_UTIL_CRITICAL`
4. `KILL_RATE_LIMIT_SESSION_TERMINATION`
5. `KILL_DISK_WATERMARK_KILL`
6. `KILL_CORTEX_FORCE_KILL`

ReduceOnly-tier:
1. `REDUCEONLY_RISKSTATE_MAINTENANCE`
2. `REDUCEONLY_EMERGENCY_REDUCEONLY_ACTIVE`
3. `REDUCEONLY_OPEN_PERMISSION_LATCHED`
4. `REDUCEONLY_BUNKER_MODE_ACTIVE`
5. `REDUCEONLY_RUNTIME_BINDING_INVALID`
6. `REDUCEONLY_F1_CERT_INVALID` (deprecated alias for runtime-binding invalidity; if emitted, semantics MUST match item 5)
7. `REDUCEONLY_EVIDENCE_CHAIN_NOT_GREEN`
8. `REDUCEONLY_CORTEX_FORCE_REDUCE_ONLY`
9. `REDUCEONLY_FEE_MODEL_HARD_STALE`
10. `REDUCEONLY_RISKSTATE_DEGRADED`
11. `REDUCEONLY_POLICY_STALE`
12. `REDUCEONLY_MARGIN_MM_UTIL_HIGH`
13. `REDUCEONLY_INPUT_MISSING_OR_STALE`
14. `REDUCEONLY_WATCHDOG_UNCONFIRMED`
15. `REDUCEONLY_DISK_KILL_UNCONFIRMED`

**Reason Derivation Rules (Non-Negotiable):**
- PolicyGuard MUST evaluate all relevant predicates every tick.
- `mode_reasons` MUST include **all** active reasons from the **computed TradingMode tier** for that tick.
- Reasons from non-winning tiers MUST NOT be included (tier purity).

---

