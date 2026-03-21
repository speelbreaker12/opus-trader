#### **2.2.3 TradingMode Computation (Axis Resolver v2 + Reason Codes)**
Profile: CSP

**Hard Rule:** The Soldier never "stores" TradingMode as authoritative state. It recomputes it every loop tick via `PolicyGuard.get_effective_mode()` (the **Axis Resolver**) immediately before any dispatch (§2.2.3.4).

---

##### **2.2.3.0 Axis Model (Normative)**

PolicyGuard MUST compute TradingMode from three independent health axes:

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

**Secondary influence mechanism:** Dual-impact signals influence their secondary axis indirectly through `risk_state` transitions. WAL write failure and ledger corruption trigger `RiskState::Degraded` (SystemIntegrityAxis), which may escalate to `RiskState::Kill` → `CapitalRiskAxis == CRITICAL` if the underlying condition persists or worsens. Session termination is authoritative Kill (SystemIntegrityAxis == FAILING). The secondary CapitalRiskAxis influence does NOT add new predicates to §2.2.3.2 CapitalRiskAxis computation; it is captured by the existing `risk_state` input.

---

##### **2.2.3.1.1 Capital-Critical Kill Triggers (No Corroboration Required)**

Capital-critical Kill triggers (`mm_util >= mm_util_kill`, `risk_state == Kill`, `cortex_override == ForceKill`) are authoritative and do NOT require corroboration. These triggers directly set `CapitalRiskAxis == CRITICAL` → `TradingMode = Kill` without a secondary confirmation signal. Rationale: capital protection is the highest-priority safety invariant and MUST NOT be delayed by corroboration checks.

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
- If `disk_used_pct >= disk_kill_pct` but `disk_used_pct_secondary` is missing, unparseable, below threshold, or stale,
  or if either disk sample timestamp is missing, unparseable, or older than `disk_used_max_age_ms`, PolicyGuard MUST
  treat Disk Kill as unconfirmed and emit `REDUCEONLY_DISK_KILL_UNCONFIRMED`.
- That disk-corroboration freshness failure MUST NOT be surfaced as `REDUCEONLY_INPUT_MISSING_OR_STALE` unless some
  other independent critical input is missing, unparseable, or stale in the same tick.
- **Session Termination Kill (authoritative):**
  `session_termination_active == true`.
  This signal is authoritative and does NOT require corroboration by rolling counts.

**Unconfirmed behavior (Non‑Negotiable):**
- If the primary predicate is true but confirmation fails, PolicyGuard MUST compute `TradingMode = ReduceOnly`
  and include the appropriate `REDUCEONLY_*_UNCONFIRMED` reason code.
- Failed corroboration on a watchdog or disk Kill predicate downgrades only that predicate's contribution to
  `SystemIntegrityAxis`; it does not override other active Kill-tier predicates in the same coherent snapshot.
- Final `TradingMode` MUST still be resolved per §2.2.3.3.
- Therefore, if any simultaneous confirmed or authoritative Kill-tier trigger is active, PolicyGuard MUST compute
  `TradingMode == Kill` and MUST emit only the winning-tier `KILL_*` reasons.

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

AT-1261
- Given: `fee_model_cache_age_s > fee_model_hard_stale_s`; all other SystemIntegrityAxis inputs nominal.
- When: TradingMode is computed.
- Then: TradingMode == ReduceOnly and mode_reasons includes REDUCEONLY_FEE_MODEL_HARD_STALE.
- Pass criteria: OPEN blocked; correct reason code emitted. Fail criteria: Active returned or reason missing.

AT-1277
- Given: `cortex_override == ForceKill`; all other Kill triggers inactive (mm_util nominal, risk_state Healthy, no watchdog/disk/session kill).
- When: TradingMode is computed.
- Then: `TradingMode == Kill` and `mode_reasons` includes `KILL_CORTEX_FORCE_KILL`.
- Pass criteria: Kill computed; `KILL_CORTEX_FORCE_KILL` present; no other Kill reason codes present.
- Fail criteria: Active or ReduceOnly returned, or `KILL_CORTEX_FORCE_KILL` absent from `mode_reasons`.

AT-1278
- Given: `cortex_override == ForceReduceOnly`; all Kill triggers inactive; all other ReduceOnly predicates pass (nominal).
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_CORTEX_FORCE_REDUCE_ONLY`.
- Pass criteria: ReduceOnly computed; correct reason code present; no other ReduceOnly reasons.
- Fail criteria: Active returned, or `REDUCEONLY_CORTEX_FORCE_REDUCE_ONLY` absent from `mode_reasons`.

AT-1279
- Given: `mm_util >= mm_util_kill`; all other Kill triggers inactive (risk_state Healthy, cortex_override absent, no watchdog/disk/session kill).
- When: TradingMode is computed.
- Then: `TradingMode == Kill` and `mode_reasons` includes `KILL_MARGIN_MM_UTIL_CRITICAL`.
- Pass criteria: Kill computed; `KILL_MARGIN_MM_UTIL_CRITICAL` present.
- Fail criteria: Active or ReduceOnly returned, or `KILL_MARGIN_MM_UTIL_CRITICAL` absent.

AT-1280
- Given: `risk_state == Maintenance`; all Kill triggers inactive; all other ReduceOnly predicates pass (nominal).
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_RISKSTATE_MAINTENANCE` and does NOT include `REDUCEONLY_RISKSTATE_DEGRADED`.
- Pass criteria: correct reason code present; wrong reason code absent.
- Fail criteria: wrong code emitted, or both codes emitted, or Active returned.

AT-1281
- Given: `risk_state == Degraded`; all Kill triggers inactive; all other ReduceOnly predicates pass (nominal).
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_RISKSTATE_DEGRADED` and does NOT include `REDUCEONLY_RISKSTATE_MAINTENANCE`.
- Pass criteria: correct reason code present; wrong reason code absent.
- Fail criteria: wrong code emitted, or both codes emitted, or Active returned.

---

##### **2.2.3.3 TradingMode Resolution (Deterministic, Pure Function of Axes)**

TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } MUST be computed from axes by the following rules (no other rules are permitted):

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
- ReduceOnly: 11 states (rows 2, 4-5, 7-8, 10-11, 13-14, 16-17)
- Kill: 15 states (rows 3, 6, 9, 12, 15, 18-27)

**Implementation Note:** The resolver function MUST be a pure function with no hidden state. Given the same axis triple, it MUST always produce the same TradingMode.

**Monotonicity Rule (CSP):**
- If any axis worsens between ticks, TradingMode MUST NOT become less restrictive on that tick.

**Recovery Rule (CSP):**
- Axis recovery MUST be slower than axis degradation. Recovery MUST respect the hysteresis/cooldown rules of each producer:
  - EvidenceGuard (§2.2.2) windowing + cooldown (only when `enforced_profile != CSP`)
  - Bunker Mode (§2.3.2) stable-exit window
  - Emergency ReduceOnly (§2.2 inputs) cooldown + reconcile-clear
  - Open Permission Latch (§2.2.4) reconcile-clear

AT-1264
- Given: `bunker_mode_active` becomes true (Bunker Mode entry via §2.3.2); all other axis inputs nominal.
- And then: `bunker_mode_active` clears to false before `bunker_exit_stable_s` has elapsed.
- When: TradingMode is computed on subsequent ticks.
- Then: TradingMode == ReduceOnly until full `bunker_exit_stable_s` window elapses since bunker entry condition cleared.
- Pass criteria: ReduceOnly held for full stable-exit window; Active not returned prematurely.
- Fail criteria: Active returned before `bunker_exit_stable_s` elapses.

---

##### **2.2.3.4 Dispatch Authorization (Non-Negotiable)**

- Every network dispatch attempt MUST consult PolicyGuard immediately before dispatch (hot path check; §2.2.3.4).
- OPEN intents MUST dispatch only if `TradingMode == Active` AND all other gates allow.
- If `TradingMode == ReduceOnly`: OPEN intents MUST NOT dispatch; CLOSE/HEDGE/CANCEL intents MAY dispatch only if not risk-increasing per §2.2.5.
- If `TradingMode == Kill`: OPEN intents MUST NOT dispatch; ONLY risk-reducing intents MAY dispatch per §2.2.3.6.

---

##### **2.2.3.4.1 Non‑Active OPEN Cancellation (CSP, Non‑Negotiable)**

Whenever `TradingMode != Active`, the engine MUST attempt to cancel all outstanding OPEN orders with `reduce_only != true`, subject to the deterministic precedence block below.
- This cancel loop MUST be **bounded and non‑blocking** per tick (see `cancel_open_batch_max`, `cancel_open_budget_ms` in Appendix A).
- If any risk‑increasing OPENs remain, the system MUST retry on subsequent ticks until cleared.
- Legacy WAL records that omit `reduce_only` MUST be treated as OPEN-equivalent (`reduce_only=false`) for non-Active cancel-sweep eligibility.
- Reconciliation MAY exempt an in-flight order from cancel sweep only with positive proof that keeping the order in-flight is risk-reducing against current net exposure.
- If risk direction cannot be positively proven risk-reducing, the order MUST remain cancel-eligible, explicit diagnostics MUST be emitted, and reconciliation MUST be prioritized on subsequent ticks.
- Cancel sweep MUST NOT cancel an in-flight order when that cancellation would leave zero risk-reducing in-flight orders while net exposure is non-zero or unknown.

**Deterministic precedence (normative):** for each in-flight order evaluated by non-Active cancel sweep, decisions MUST be applied in this order:
1. **Capital guard first:** if canceling the order would leave zero risk-reducing in-flight orders while net exposure is non-zero or unknown, the order MUST NOT be canceled.
2. **Proof-gated exemption second:** otherwise, reconciliation MAY exempt the order only with positive proof that keeping it in-flight is risk-reducing.
3. **Default cancel-all third:** otherwise, the order is cancel-eligible and MUST be canceled within the bounded sweep budget; legacy missing `reduce_only` is treated as `false`.
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
7. `REDUCEONLY_EVIDENCE_CHAIN_NOT_GREEN` (only when `enforced_profile != CSP`; see §2.2.3.2 SystemIntegrityAxis)
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

**Acceptance Tests:**

AT-1244
- Given: PolicyGuard computes `TradingMode == ReduceOnly` with multiple active reduce-only predicates (e.g., `risk_state == Degraded` AND `bunker_mode_active == true` AND `open_permission_blocked_latch == true`).
- When: `mode_reasons` is computed for that tick.
- Then: `mode_reasons` MUST contain all applicable `REDUCEONLY_*` reason codes, in the canonical order defined above, and MUST NOT contain any `KILL_*` codes.
- Pass criteria: reasons are tier-pure (only `REDUCEONLY_*`), complete (all active predicates represented), and deterministically ordered per the registry above.
- Fail criteria: missing active reason, `KILL_*` code present, or order deviates from canonical registry.

AT-1282
- Given: `risk_state == Kill`, `session_termination_active == true`, and `bunker_mode_active == true`; all other Kill-tier predicates inactive.
- When: `TradingMode` and `mode_reasons` are computed for that tick.
- Then: `TradingMode == Kill` and `mode_reasons == [KILL_RISKSTATE_KILL, KILL_RATE_LIMIT_SESSION_TERMINATION]`.
- Pass criteria: all active Kill-tier reasons are emitted, canonical registry order is preserved, and no `REDUCEONLY_*` reason appears.
- Fail criteria: any active Kill-tier reason missing, order non-canonical, or any `REDUCEONLY_*` reason mixed into `mode_reasons`.

---

##### **2.2.3.6 Kill Semantics (Capital Supremacy Safe, CSP)**

**Kill MUST mean:**
- No creation of new exposure.
- Only risk-reducing actions are permitted until exposure is neutral.

**Kill MUST NOT mean:**
- “No dispatch of any kind” while exposure exists.

**Capital Supremacy Invariant (Non-Negotiable):**
If net exposure ≠ 0, the system MUST define at least one legal risk-reducing action, regardless of TradingMode.
No state is permitted where:
- exposure ≠ 0, AND
- no CLOSE / HEDGE / emergency flatten action is permitted.

**Kill containment requirement:**
When `TradingMode == Kill` AND net exposure ≠ 0, the system MUST permit and attempt a bounded, deterministic containment sequence:

1) Cancel any risk-increasing OPEN orders (including any non-reduce-only orders).
2) Execute §3.1 Deterministic Emergency Close (reduce-only; bounded attempts).
3) If residual exposure remains above limits after bounded close attempts, place a reduce-only hedge fallback.

Containment actions MUST be:
- **Bounded** (no infinite retries),
- **Deterministic** (same inputs → same actions),
- **Monotonic with respect to exposure** (never increase net exposure; use `reduce_only` / close-only primitives where supported).

Containment MUST be attempted even if:
- `EvidenceChainState != GREEN`,
- WAL is degraded,
- `session_termination_active == true`,
- `disk_used_pct >= disk_kill_pct`,
- `bunker_mode_active == true`,
- or watchdog staleness is the trigger cause.

(If dispatch fails due to transport or venue rejection, that is a runtime outcome; the authorization MUST still allow the attempt.)

**Post-containment hard stop (allowed):**
If `TradingMode == Kill` AND net exposure == 0, the system MAY cease further dispatch and remain halted until the underlying kill trigger clears (or manual intervention), but it MUST continue to publish `/status`.

---

##### **2.2.3.7 Acceptance Tests (REQUIRED)**

**Policy Staleness Rule**
AT-336
- Given: `policy_age_sec > max_policy_age_sec`.
- When: TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_POLICY_STALE`.
- Pass criteria: mode is ReduceOnly exactly when `policy_age_sec > max_policy_age_sec`.
- Fail criteria: mode remains Active when policy is stale, or ReduceOnly occurs below threshold.

**Watchdog Kill Rule**
AT-337
- Given: `now_ms - watchdog_last_heartbeat_ts_ms > watchdog_kill_s * 1000` **AND** `now_ms - loop_tick_last_ts_ms > watchdog_kill_s * 1000`.
- When: TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == Kill` and `mode_reasons` includes `KILL_WATCHDOG_HEARTBEAT_STALE`.
- Pass criteria: Kill occurs exactly above the thresholds when both corroboration signals are stale.
- Fail criteria: Kill fails to trigger when both are stale or triggers with only one stale.

**RiskState Kill Is Authoritative**
AT-918
- Given: `risk_state == Kill`.
- When: TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == Kill` and `mode_reasons` includes `KILL_RISKSTATE_KILL`.
- Pass criteria: Kill is computed regardless of other non-kill gates; `KILL_RISKSTATE_KILL` present in `mode_reasons`.
- Fail criteria: ReduceOnly/Active is computed while `risk_state == Kill`, or `KILL_RISKSTATE_KILL` absent from `mode_reasons`.

**EvidenceGuard Forces ReduceOnly**
AT-416
- Given: `EvidenceChainState != GREEN` for >60s (window + cooldown per §2.2.2), `enforced_profile != CSP`, and no Kill-tier triggers are active.
- When: TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly`.
- Pass criteria: ReduceOnly holds while evidence is not GREEN and clears only after EvidenceGuard recovery rules are satisfied.
- Fail criteria: Active is computed while evidence is not GREEN.

**Mode Reasons Are Tier-Pure and Deterministically Ordered**
AT-417
- Given: a sequence of ticks where multiple Axis Resolver predicates toggle (including both kill-tier and reduceonly-tier predicates).
- When: `mode_reasons` are emitted on each tick.
- Then:
  - `mode_reasons` are tier-pure (no mixing kill + reduceonly),
  - deterministically ordered,
  - and update immediately as the computed TradingMode changes.
- Pass criteria: ordering and tier purity invariants hold across the tick sequence.
- Fail criteria: mixed tiers, nondeterministic ordering, or stale reasons after mode change.

**Hot Path Must Consult PolicyGuard Immediately Before Dispatch**
AT-931
- Given: the strategy loop computes an intent while `TradingMode == Active`, but before dispatch the Axis Resolver input flips to ReduceOnly/Kill (e.g., evidence trip).
- When: the dispatch path runs.
- Then: the order MUST NOT dispatch if the current TradingMode forbids it.
- Pass criteria: dispatch count remains 0 and reject_reason_code == TradingModeBlockedOpen.
- Fail criteria: dispatch occurs based on stale TradingMode.

**Non‑Active OPEN Cancellation**
AT-1065
- Given: `TradingMode == ReduceOnly` and there exist outstanding OPEN orders with `reduce_only != true`.
- When: the loop ticks.
- Then: cancel requests for those OPEN orders are issued within the bounded cancel budget, and OPEN dispatch remains blocked.
- Pass criteria: cancels are attempted (bounded by `cancel_open_batch_max` / `cancel_open_budget_ms`), outstanding risk‑increasing OPENs trend to zero over subsequent ticks.
- Fail criteria: no cancel attempts, or risk‑increasing OPENs remain indefinitely while ReduceOnly.

**Proof-Gated Reconciliation Exemption for Non-Active Cancel Sweep**
AT-1241
- Given: `TradingMode != Active`, cancel sweep evaluates an in-flight order, and risk direction/classification is ambiguous (including legacy WAL records with missing `reduce_only`).
- When: reconciliation evaluates whether that order may be exempted from cancellation.
- Then: exemption is allowed only with positive proof that keeping the order in-flight is risk-reducing; otherwise the order remains cancel-eligible, explicit diagnostics are emitted, and reconciliation is prioritized.
- Pass criteria: only positively proven risk-reducing in-flight orders are exempted; ambiguous orders remain cancel-eligible with diagnostics and reconciliation priority asserted.
- Fail criteria: exemption occurs without positive proof, or diagnostics/reconciliation-priority signaling is missing when proof is absent.

**Capital-Supremacy Guard for Last Risk-Reducing In-Flight Order**
AT-1242
- Given: `TradingMode != Active`, net exposure is non-zero or unknown, and canceling a candidate in-flight order would leave zero risk-reducing in-flight orders.
- When: cancel sweep applies cancellation decisions.
- Then: that order MUST NOT be canceled, while other cancel-eligible risk-increasing OPEN orders remain cancelable.
- Pass criteria: cancel sweep never creates a state where exposure is non-zero/unknown and no risk-reducing in-flight orders remain.
- Fail criteria: the last risk-reducing in-flight order is canceled while exposure is non-zero or unknown.

**Emergency ReduceOnly Cooldown Is Enforced**
AT-132
- Given: `emergency_reduceonly_active == true` and the cooldown timer has not expired.
- When: TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_EMERGENCY_REDUCEONLY_ACTIVE`.
- Pass criteria: ReduceOnly holds for the full cooldown window and clears only after cooldown expiry AND reconciliation confirms exposure is safe (if required).
- Fail criteria: Active occurs before cooldown expiry.

**Axis Resolver Enumerability (27-State Mapping)**
AT-1048
- Given: a unit-test harness that can inject axis values into the pure resolver function.
- When: all 27 combinations of `(CapitalRiskAxis, MarketIntegrityAxis, SystemIntegrityAxis)` are evaluated.
- Then: every combination maps deterministically to exactly one TradingMode per §2.2.3.3.
- Pass criteria: no undefined combination; outputs match the resolver rules.
- Fail criteria: any undefined/fallthrough behavior or mismatched mapping.


**Axis Resolver Monotonicity (No Less-Restrictive on Worse Axes)**
AT-1053
- Given: a pure resolver function `resolve_trading_mode(capital, market, system)` and a restrictiveness ordering `Active < ReduceOnly < Kill`.
- When: all ordered pairs of axis tuples `(A, B)` are evaluated where:
  - for each axis, `B` is equal or worse than `A`, and
  - at least one axis in `B` is strictly worse than `A`.
- Then: `resolve_trading_mode(B)` MUST NOT be less restrictive than `resolve_trading_mode(A)`.
- Pass criteria: the monotonicity property holds for all such pairs.
- Fail criteria: any pair produces a less restrictive TradingMode under worse axes.

**Axis Isolation — MarketIntegrityAxis (Bunker Mode Only)**
AT-1050
- Given: all Kill-tier triggers are forced inactive, and all ReduceOnly predicates are forced pass EXCEPT `bunker_mode_active`.
- When: `bunker_mode_active == true` and TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly` and `mode_reasons == [REDUCEONLY_BUNKER_MODE_ACTIVE]`.
- Pass criteria: exact reason set and ReduceOnly computed.
- Fail criteria: any additional reason appears, or mode is Active/Kill.

**Axis Isolation — CapitalRiskAxis (Margin Util Only)**
AT-1051
- Given: all Kill-tier triggers are forced inactive, and all ReduceOnly predicates are forced pass EXCEPT `mm_util >= mm_util_reduceonly`.
- When: `mm_util >= mm_util_reduceonly` AND `mm_util < mm_util_kill` and TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly` and `mode_reasons == [REDUCEONLY_MARGIN_MM_UTIL_HIGH]`.
- Pass criteria: exact reason set and ReduceOnly computed.
- Fail criteria: any additional reason appears, or mode is Active/Kill.

**Axis Isolation — SystemIntegrityAxis (Open Permission Latch Only)**
AT-1052
- Given: all Kill-tier triggers are forced inactive, and all ReduceOnly predicates are forced pass EXCEPT `open_permission_blocked_latch == true`.
- When: `open_permission_blocked_latch == true` and TradingMode is computed by the Axis Resolver.
- Then: `TradingMode == ReduceOnly` and `mode_reasons == [REDUCEONLY_OPEN_PERMISSION_LATCHED]`.
- Pass criteria: exact reason set and ReduceOnly computed.
- Fail criteria: any additional reason appears, or mode is Active/Kill.


**No-Deadlock-Under-Exposure (Capital Supremacy)**
AT-1049
- Given: `TradingMode in {ReduceOnly, Kill}` and net exposure ≠ 0.
- When: the system proposes a risk-reducing intent (`CLOSE`, reduce-only hedge, or emergency flatten).
- Then: at least one such intent is permitted to dispatch (subject to venue reachability), and OPEN remains blocked.
- Pass criteria: a risk-reducing dispatch attempt is authorized and OPEN dispatch count remains 0.
- Fail criteria: exposure ≠ 0 but all risk-reducing dispatch is forbidden.

**Kill Containment Is Mandatory When Exposed**
AT-338
- Given: `TradingMode == Kill` (e.g., `mm_util >= mm_util_kill`) and open exposure exists.
- When: the execution loop ticks under Kill.
- Then: containment actions (cancel risk-increasing orders; §3.1 emergency close; hedge fallback) are attempted and no OPENs are dispatched.
- Pass criteria: at least one risk-reducing dispatch attempt occurs while exposed; OPEN dispatch count remains 0.
- Fail criteria: no containment dispatch attempt while exposed or any OPEN dispatch.

**Disk Kill Still Permits Containment (No Stranded Exposure)**
AT-339
- Given: `disk_used_pct >= disk_kill_pct` **and** `disk_used_pct_secondary >= disk_kill_pct`, and open exposure exists.
- When: TradingMode is computed and Kill containment runs.
- Then: containment actions are permitted/attempted; OPEN remains blocked.
- Pass criteria: at least one risk-reducing dispatch attempt occurs while exposed; OPEN dispatch count remains 0.
- Fail criteria: the system “hard-stops” with exposure by forbidding all dispatch.

**Evidence/WAL Degradation Does Not Forbid Containment**
AT-340
- Given: `TradingMode == Kill` due to a kill-tier trigger AND (`EvidenceChainState != GREEN` OR WAL is degraded), with open exposure.
- When: Kill containment runs.
- Then: containment actions are still permitted/attempted; OPEN remains blocked.
- Pass criteria: risk-reducing dispatch attempts occur while exposed; OPEN dispatch count remains 0.
- Fail criteria: containment is blocked solely due to evidence/WAL degradation.

**Session Termination Does Not Forbid Containment**
AT-346
- Given: `session_termination_active == true` and open exposure exists.
- When: TradingMode is computed and Kill containment runs.
- Then: containment actions are permitted/attempted; OPEN remains blocked.
- Pass criteria: risk-reducing dispatch attempts occur while exposed; OPEN dispatch count remains 0.
- Fail criteria: containment is forbidden solely due to session termination.

**Watchdog Kill Does Not Forbid Containment**
AT-347
- Given: watchdog heartbeat **and** loop tick are stale beyond `watchdog_kill_s` AND open exposure exists.
- When: TradingMode is computed and Kill containment runs.
- Then: containment actions are permitted/attempted; OPEN remains blocked.
- Pass criteria: risk-reducing dispatch attempts occur while exposed; OPEN dispatch count remains 0.
- Fail criteria: containment is forbidden solely due to watchdog kill.

**Bunker Mode Does Not Forbid Containment Under Kill**
AT-013
- Given: `bunker_mode_active == true`, a Kill-tier trigger is active (e.g., `mm_util >= mm_util_kill`), and open exposure exists.
- When: TradingMode is computed and Kill containment runs.
- Then: containment actions are permitted/attempted; OPEN remains blocked.
- Pass criteria: risk-reducing dispatch attempts occur while exposed; OPEN dispatch count remains 0.
- Fail criteria: containment is forbidden solely due to `bunker_mode_active == true`.

**Unconfirmed Kill Signals Force ReduceOnly**
AT-1066
- Given: watchdog heartbeat is stale beyond `watchdog_kill_s`, but `loop_tick_last_ts_ms` is fresh.
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_WATCHDOG_UNCONFIRMED`.
- Pass criteria: ReduceOnly enforced; no Kill.
- Fail criteria: Kill computed with only one corroboration signal.

AT-1067
- Given: `disk_used_pct >= disk_kill_pct` but `disk_used_pct_secondary < disk_kill_pct` (or missing/stale).
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_DISK_KILL_UNCONFIRMED`.
- Pass criteria: ReduceOnly enforced; no Kill.
- Fail criteria: Kill computed without corroboration.

AT-1068
- Given: `session_termination_active` is missing or unparseable.
- When: TradingMode is computed.
- Then: `TradingMode == ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: ReduceOnly enforced; no Kill.
- Fail criteria: TradingMode Active (or OPEN dispatch) when the session-termination signal is missing/unparseable.

AT-1069
- Given: confirmed kill predicates per §2.2.3.1.2 (watchdog, disk, or session termination).
- When: TradingMode is computed.
- Then: `TradingMode == Kill` with the appropriate `KILL_*` reason codes.
- Pass criteria: Kill computed only when corroboration holds.
- Fail criteria: Kill not computed despite confirmed predicates.
