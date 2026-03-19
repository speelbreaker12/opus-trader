### **2.2 PolicyGuard (Single Authoritative TradingMode Resolver)**
**Goal:** Eliminate conflicting “mode sources” and prevent stale/late policy pushes from re‑enabling risk.

**Where:** `crates/soldier_core/src/policy/guard.rs`

**Inputs:**
- **Timebase convention:** all `*_ts_ms` values used for staleness/freshness are **monotonic‑epoch milliseconds** (epoch‑aligned, monotonic); `now_ms` is current monotonic‑epoch milliseconds (and `now` refers to `now_ms` in this contract); seconds are derived as `(now_ms - *_ts_ms)/1000`.
- `python_policy` (latest policy payload)
- `python_policy_generated_ts_ms` (monotonic‑epoch ms; timestamp from Commander when policy was computed)
- `watchdog_last_heartbeat_ts_ms` (monotonic‑epoch ms)
- `loop_tick_last_ts_ms` (monotonic‑epoch ms; last completed hot‑loop tick)
- `now_ms` (local monotonic‑epoch milliseconds used for staleness calculations)
- `cortex_override` (effective max-severity across §2.3 producers; see §2.3)

- `runtime_binding_cert` (from `artifacts/RUNTIME_BINDING_CERT.json`: `{status, generated_ts_ms, build_id, runtime_config_hash, contract_version}`; legacy transition alias `artifacts/F1_CERT.json` is accepted when canonical file is absent)
- `fee_model_cache_age_s` (from §4.2)
- `risk_state` (Healthy | Degraded | Maintenance | Kill)
- `enforced_profile` (enum: CSP | GOP | FULL; from runtime config; GOP-only gates apply when `enforced_profile != CSP`)
- `bunker_mode_active` (bool; from §2.3.2 Network Jitter Monitor)
- `bunker_mode_last_update_ts_ms` (monotonic-epoch ms; timestamp when bunker_mode_active was last updated by §2.3.2)
- `evidence_chain_state` (EvidenceChainState; from §2.2.2 EvidenceGuard; required only when `enforced_profile != CSP`)
- `policy_age_sec` (derived: `(now_ms - python_policy_generated_ts_ms) / 1000`)
- `mm_util` (float; maintenance margin utilization; from §1.4.3 Margin Headroom Gate)
- `mm_util_last_update_ts_ms` (monotonic‑epoch ms; freshness timestamp for `mm_util`; see §2.2.1.2 and §7.0)
- `disk_used_pct` (float; ratio in [0,1], where 0.80 means 80% used; from §7.2 Disk Watermarks)
- `disk_used_last_update_ts_ms` (monotonic‑epoch ms; freshness timestamp for `disk_used_pct`; see §2.2.1.2 and §7.0)
- `disk_used_pct_secondary` (float; independent source for corroboration; see §2.2.3.1.2)
- `disk_used_secondary_last_update_ts_ms` (monotonic‑epoch ms; freshness timestamp for `disk_used_pct_secondary`)
- `emergency_reduceonly_active` (bool; true if `POST /api/v1/emergency/reduce_only` is latched/cooldown active)
  - Cooldown semantics: Once set to true via endpoint call, remains true for `emergency_reduceonly_cooldown_s` (default: 300s; see Appendix A) after the endpoint call timestamp.
  - State transition: automatically clears to false after cooldown duration expires AND reconciliation confirms exposure is safe (if reconciliation is required by trigger source).
  - Invariant: While true, PolicyGuard MUST compute `TradingMode::ReduceOnly` (see §2.2.3 Axis Resolver).
- `open_permission_blocked_latch` (bool; from §2.2.4 CP-001)
- `open_permission_reason_codes` (OpenPermissionReasonCode[]; from §2.2.4 CP-001)
- `session_termination_active` (bool; true if 10028/session termination occurred and reconciliation has not cleared)
- `10028_count_5m` (int; rolling 5m count used for observability, alerting, and release metrics; see §7.0)

**Field rename transition (contract version 5.2):**
`rate_limit_session_kill_active` is renamed to `session_termination_active` in contract version `5.2`.
- Implementations MUST accept both field names while running contract version `5.2`.
- `/status` MUST emit the new name (`session_termination_active`) in contract version `5.2`.
- `/status` MAY additionally emit the old name as a deprecated alias only during contract version `5.2`.
- The old name MUST be removed (MUST NOT appear in requests or responses) in the first contract version strictly greater than `5.2`.

AT-1260
- Given: contract_version=5.2 and policy payload contains `rate_limit_session_kill_active=true` with `session_termination_active` absent.
- When: PolicyGuard computes TradingMode.
- Then: TradingMode == Kill (alias is honoured).
- Pass criteria: Kill computed via alias. Fail criteria: old field ignored.

#### **2.2.0 PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order)**
Profile: CSP

**Why this exists (safety-critical):** PolicyGuard consumes inputs produced by multiple concurrent components. A “torn” read (e.g., a fresh timestamp paired with a stale value) can incorrectly compute `TradingMode::Active` and allow an OPEN that should have been blocked.

**Rules (Non-Negotiable):**
1) **Single-snapshot rule:** Each call to `PolicyGuard.get_effective_mode()` MUST acquire exactly one immutable *input snapshot* and MUST compute:
   - axes (§2.2.3.2),
   - TradingMode (§2.2.3.3),
   - `mode_reasons` (§2.2.3.5),
   using only that snapshot. PolicyGuard MUST NOT read mutable live inputs multiple times within the same call.

2) **Atomicity rule:** The snapshot MUST be coherent. It MUST be impossible for a snapshot to contain a mix of “before” and “after” values from any single producer update.
   - At minimum, for every paired field `(X, X_last_update_ts_ms)` the snapshot MUST NOT contain `X_last_update_ts_ms` from an update that is newer than the `X` value in that same snapshot.

3) **Memory order rule:** Publication and consumption of any safety-critical input that can influence TradingMode MUST establish a happens-before relationship:
   - Writers MUST publish with **Release** semantics.
   - PolicyGuard MUST read with **Acquire** semantics.
   - Using **Relaxed** loads/stores for safety-critical publication/consumption is non-compliant.

AT-1118
- Given: the codebase is searched for all atomic operations (`Ordering::Relaxed`) on fields that can influence TradingMode (safety-critical inputs as defined by §2.2.0).
- When: a code-audit scan (grep/lint) is performed.
- Then: no `Ordering::Relaxed` load or store is found on any safety-critical atomic that feeds into PolicyGuard's `get_effective_mode()` computation; all such atomics use `Acquire` (loads) or `Release` (stores) or stronger.
- Pass criteria: zero instances of `Ordering::Relaxed` on safety-critical publication/consumption atomics.
- Fail criteria: any `Ordering::Relaxed` found on a safety-critical atomic field.

4) **Fail-closed acquisition:** If a coherent snapshot cannot be acquired (contention, corruption, or any other reason), PolicyGuard MUST fail-closed for that tick:
   - return `TradingMode::ReduceOnly`, and
   - include `REDUCEONLY_INPUT_MISSING_OR_STALE` in `mode_reasons`.

**Acceptance Test (REQUIRED):**
AT-1054
- Given: a loom-style scheduler (or equivalent systematic interleaving harness) that can interleave a producer update and a `get_effective_mode()` read.
- And: initial state has `mm_util = 0.10` and `mm_util_last_update_ts_ms = now_ms - (mm_util_max_age_ms + 1_000)` (stale).
- And: a producer publishes an update that sets `mm_util = mm_util_reduceonly + 0.001` AND `mm_util_last_update_ts_ms = now_ms` (fresh).
- And: all other gates are forced pass such that:
  - old pair → ReduceOnly via `REDUCEONLY_INPUT_MISSING_OR_STALE`,
  - new pair → ReduceOnly via `REDUCEONLY_MARGIN_MM_UTIL_HIGH`.
- When: TradingMode is computed concurrently with the producer update across all interleavings.
- Then: PolicyGuard MUST NEVER return `TradingMode::Active`.
- Pass criteria: no interleaving yields Active.
- Fail criteria: any interleaving yields Active (indicating a torn snapshot and/or missing Acquire/Release ordering).

#### **2.2.1 Runtime Binding Gate (HARD, runtime enforcement)**
- PolicyGuard MUST read `artifacts/RUNTIME_BINDING_CERT.json` as the canonical runtime-binding artifact.
- Transition compatibility: if canonical artifact is missing, PolicyGuard MAY read legacy `artifacts/F1_CERT.json` only while `runtime.contract_version == "5.2"`; for any other `contract_version`, legacy `F1_CERT.json` MUST be ignored and missing canonical artifact MUST force ReduceOnly.
- Required schema (minimum keys): `{ status, generated_ts_ms, build_id, runtime_config_hash, contract_version }`.
  - `build_id`: immutable build identifier for the running binary (e.g., git commit SHA).
  - `runtime_config_hash`: `sha256` hex of canonicalized runtime config (see below).
  - `contract_version`: MUST equal the canonical `contract_version` literal in Definitions.
  - `policy_hash_at_cert_time` MAY be included for observability only and MUST NOT be used as a runtime validity gate.
- Freshness window: default 24h (configurable). If missing OR stale OR FAIL => TradingMode MUST be ReduceOnly.
- Binding hardening: if any of these do not match runtime, runtime binding cert MUST be treated as INVALID (ReduceOnly):
  - `cert.build_id != runtime.build_id`
  - `cert.runtime_config_hash != runtime.runtime_config_hash`
  - `cert.contract_version != runtime.contract_version`
- While in ReduceOnly due to runtime-binding invalidity: allow only closes/hedges/cancels; block all opens.
- This rule is strict: no caching last-known-good and no grace periods.

#### **2.2.1.1 Promotion Certification (non-runtime gate)**
- Promotion certification is a release-governance artifact and MUST NOT be used as a runtime safety prerequisite.
- Artifact: `artifacts/F1_PROMOTION_CERT.json` (produced by §8 release gates).
- Required for stage promotion paths (Shadow -> Testnet -> Live).
- Not required for CSP runtime enforcement when runtime binding cert is valid.

**Acceptance Tests (REQUIRED):**

AT-020
- Given: runtime binding cert `status == PASS` but `build_id` OR `runtime_config_hash` OR `contract_version` mismatches runtime.
- When: TradingMode is computed.
- Then: TradingMode MUST be ReduceOnly and OPEN must be blocked.
- Pass criteria: `/status.trading_mode == ReduceOnly` and OPEN does not dispatch.
- Fail criteria: `trading_mode` Active or OPEN dispatch occurs.

AT-021
- Given: runtime binding cert was valid previously, then becomes missing OR stale OR FAIL.
- When: TradingMode is computed.
- Then: TradingMode MUST be ReduceOnly (no "last-known-good" bypass).
- Pass criteria: `/status.trading_mode == ReduceOnly` and OPEN does not dispatch.
- Fail criteria: `trading_mode` Active while runtime binding cert is missing/stale/FAIL.

AT-012
- Given: runtime binding cert has `contract_version="5.2"` and runtime `contract_version` is `"5.2"`.
- When: PolicyGuard validates binding checks.
- Then: `contract_version` comparison passes (no ReduceOnly due to formatting mismatch).
- Pass criteria: TradingMode not forced to ReduceOnly due solely to `contract_version` formatting.
- Fail criteria: ReduceOnly occurs due to "header string vs numeric string" mismatch.

AT-410
- Given: runtime binding cert `status == PASS` with matching build_id/runtime_config_hash/contract_version, but `policy_hash_at_cert_time` differs from current policy hash.
- When: TradingMode is computed.
- Then: TradingMode is not forced to ReduceOnly due solely to `policy_hash_at_cert_time`.
- Pass criteria: TradingMode remains Active if no other gates are active.
- Fail criteria: ReduceOnly occurs with only `policy_hash_at_cert_time` mismatching.

AT-423
- Given: `artifacts/RUNTIME_BINDING_CERT.json` (or transition alias `artifacts/F1_CERT.json`) on disk contains a PASS cert with matching build_id/runtime_config_hash/contract_version.
- When: the file is modified on disk to `status="FAIL"` or deleted, and PolicyGuard computes TradingMode on the next tick.
- Then: TradingMode MUST be ReduceOnly and `/status.runtime_binding_state` reflects FAIL or MISSING.
- Pass criteria: `/status.trading_mode == ReduceOnly` within one tick and OPEN does not dispatch.
- Fail criteria: `trading_mode` Active or `/status.runtime_binding_state` remains PASS after the file change.

AT-1202
- Given: valid `artifacts/RUNTIME_BINDING_CERT.json`, `enforced_profile == CSP`, and no promotion cert.
- When: TradingMode is computed with all other gates passing.
- Then: runtime binding gate allows Active; promotion cert absence does not force ReduceOnly.
- Pass criteria: Active permitted under CSP when runtime binding is valid.
- Fail criteria: ReduceOnly forced solely because promotion cert is missing.

AT-1203
- Given: runtime binding cert is missing/invalid under any profile.
- When: TradingMode is computed.
- Then: TradingMode MUST be ReduceOnly.
- Pass criteria: OPEN blocked until runtime binding cert becomes valid.
- Fail criteria: Active while runtime binding cert is invalid.

AT-1209
- Given: runtime binding cert is valid, but promotion transition is attempted without valid `artifacts/F1_PROMOTION_CERT.json`.
- When: release/promotion gate evaluates.
- Then: stage promotion fails closed.
- Pass criteria: promotion blocked until promotion cert is valid.
- Fail criteria: promotion proceeds without valid promotion cert.

**Acceptance Tests (References):**
- AT-003 in §7.0 validates `/status` runtime binding fields.


**Canonical hashing rule (non-negotiable):**
- `runtime_config_hash` MUST be computed as `sha256(canonical_json_bytes(config))` where `canonical_json_bytes` means:
  - JSON with **stable key ordering** (sorted recursively),
  - no insignificant whitespace,
  - UTF-8 encoding.

AT-113
- Given: two runtime config JSON inputs that are semantically identical but differ only in key order and whitespace.
- When: `runtime_config_hash` is computed for both.
- Then: both hashes MUST be identical.
- Pass criteria: PolicyGuard does not force ReduceOnly due solely to formatting-only differences.
- Fail criteria: formatting-only changes alter the hash and cause F1 binding mismatch.


#### **2.2.1.2 PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens)**

**Rule (non-negotiable):**
PolicyGuard MUST NOT return `TradingMode::Active` if any critical safety input required for Kill/ReduceOnly decisions is missing or stale.

**Critical inputs (minimum):**
**Critical inputs (definition):** any PolicyGuard input referenced by §2.2.3 axis predicates that is required under the current `enforced_profile`. GOP-only inputs (e.g., `evidence_chain_state`) are critical only when `enforced_profile != CSP`. Missing/unparseable required inputs MUST be treated as missing/stale and force ReduceOnly with `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- `mm_util` (from account summary) must have `mm_util_last_update_ts_ms`
- `disk_used_pct` must have `disk_used_last_update_ts_ms`
- session termination / rate-limit kill flag must be explicit (no "unknown treated as false")
- `cortex_override` (from §2.3 producers) — if missing or unparseable MUST be treated as ForceReduceOnly; set REDUCEONLY_INPUT_MISSING_OR_STALE

AT-1262
- Given: `cortex_override` is absent from the input snapshot or its value is unparseable/corrupted; all other axis inputs are nominal.
- When: PolicyGuard computes TradingMode.
- Then: TradingMode == ReduceOnly and mode_reasons includes REDUCEONLY_INPUT_MISSING_OR_STALE.
- Pass criteria: ReduceOnly with correct reason code; no OPEN dispatched.
- Fail criteria: Active returned, ForceKill silently dropped, or reason code absent.

**Freshness defaults (configurable):**
- `mm_util_max_age_ms = 30_000`
- `disk_used_max_age_ms = 30_000`
- `bunker_mode_max_age_ms = 10_000`

**Enforcement:**
- If any critical input is missing OR `now_ms - last_update_ts_ms > max_age_ms`:
  - force `TradingMode = ReduceOnly` (block OPEN; allow CLOSE/HEDGE/CANCEL)
  - set `mode_reasons` to include `REDUCEONLY_INPUT_MISSING_OR_STALE`

**Acceptance test (REQUIRED):**
- Simulate `mm_util_last_update_ts_ms` stale > max age → verify OPEN blocked within one tick; CLOSE/HEDGE/CANCEL still allowed.

AT-001
- Given: `mm_util` is present but `mm_util_last_update_ts_ms` is older than `mm_util_max_age_ms`.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: OPEN intents are blocked within one tick; CLOSE/HEDGE/CANCEL remain allowed.
- Fail criteria: PolicyGuard returns Active or allows any OPEN while critical inputs are stale/missing.

AT-112
- Given: `watchdog_last_heartbeat_ts_ms` is missing or unparseable.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: OPEN does not dispatch.
- Fail criteria: TradingMode Active (or OPEN dispatch) when an axis-resolver input is missing/unparseable.

AT-348
- Given: `session_termination_active` is missing or unparseable.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: OPEN does not dispatch.
- Fail criteria: TradingMode Active (or OPEN dispatch) when the session termination flag is missing/unparseable.

AT-349
- Given: `mm_util` is present but `mm_util_last_update_ts_ms` is missing or unparseable, and all other gates would allow `TradingMode::Active`.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: OPEN does not dispatch.
- Fail criteria: TradingMode Active (or OPEN dispatch) when `mm_util_last_update_ts_ms` is missing/unparseable.

AT-350
- Given: `disk_used_pct` is present but `disk_used_last_update_ts_ms` is missing or unparseable, and all other gates would allow `TradingMode::Active`.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: OPEN does not dispatch.
- Fail criteria: TradingMode Active (or OPEN dispatch) when `disk_used_last_update_ts_ms` is missing/unparseable.

AT-413
- Given: each critical input referenced by §2.2.3 is missing or unparseable one at a time, and all other gates allow `TradingMode::Active`.
- When: PolicyGuard computes `TradingMode`.
- Then: `TradingMode==ReduceOnly` and `mode_reasons` includes `REDUCEONLY_INPUT_MISSING_OR_STALE`.
- Pass criteria: every missing/unparseable input forces ReduceOnly within one tick; CLOSE/HEDGE/CANCEL allowed.
- Fail criteria: any missing/unparseable input yields Active or missing reason code.



#### **2.2.2 EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT**
Profile: GOP

**Profile gating (Normative):**
- EvidenceGuard is a **HARD RUNTIME INVARIANT** only when `enforced_profile != CSP` (i.e., GOP or FULL is enforced).
- When `enforced_profile == CSP`, EvidenceGuard MUST be treated as **NOT_ENFORCED** and MUST NOT:
  - change `TradingMode`,
  - change `OpenPermissionLatch`,
  - or block any CSP-permitted dispatch decision.


**Purpose (TOC constraint relief):** Close the missing enforcement link: if the evidence chain is not green, the system MUST NOT open new risk. “Nice architecture” is meaningless unless it is unbreakable in production.

**Definition (Evidence Chain = required artifacts):**
The following MUST be writable + joinable for every dispatched open-intent:
- WAL intent entry (durable)
- TruthCapsule (with decision_snapshot_id)
- Decision Snapshot payload (L2 top-N at decision time)
- Attribution row for any fill(s) that occur (fees/slippage/net pnl)
  - NOTE: An open-intent that produces zero fills is NOT required to have an attribution row.

**Invariant (Non-Negotiable):**
- If Evidence Chain is not GREEN → **block ALL new OPEN intents**.
- CLOSE / HEDGE / CANCEL intents are allowed only if the cancel/replace is NOT risk-increasing per §2.2.5, and only when not constrained by §2.2.3 Kill semantics (risk-reducing only).
- Risk-increasing CANCEL/REPLACE MUST be rejected while `EvidenceChainState != GREEN` (see §2.2.5 definition).
- When `enforced_profile != CSP`: EvidenceGuard triggers `RiskState::Degraded`; PolicyGuard computes `TradingMode::ReduceOnly` via the canonical axis resolver while `EvidenceChainState != GREEN`, and until GREEN recovers and remains stable for the cooldown window.

**GREEN/RED criteria (minimum):**
EvidenceChainState = GREEN iff ALL are true (rolling window; default `evidenceguard_window_s = 60` seconds, safety-critical; configurable in Appendix A):
- **All required EvidenceGuard counters MUST be defined and parseable** (fail-closed).
  - Missing/unparseable required counter(s) => EvidenceChainState MUST be not GREEN.
  - Required counters (minimum): `truth_capsule_write_errors`, `decision_snapshot_write_errors`, `wal_write_errors`, `parquet_queue_overflow_count`, `attribution_write_errors`.
- Required counters MUST be fresh: if `now_ms - evidenceguard_counters_last_update_ts_ms` > `evidenceguard_counters_max_age_ms` (default 60000; see Appendix A for `evidenceguard_counters_max_age_ms`), EvidenceChainState MUST be not GREEN and OPEN intents MUST be blocked.
- `wal_write_errors` MUST increment on any failure to satisfy RecordedBeforeDispatch for an OPEN intent, including WAL enqueue failure (bounded queue full) and any persistence/write failure.
- `attribution_write_errors` MUST increment on any failure to write an attribution row for a filled OPEN intent, including persistence errors and missing/unparseable fill data.
- `truth_capsule_write_errors` has not increased within the last `evidenceguard_window_s`
- `decision_snapshot_write_errors` has not increased within the last `evidenceguard_window_s`
- `parquet_queue_overflow_count` has not increased within the last `evidenceguard_window_s`
- `wal_write_errors` has not increased within the last `evidenceguard_window_s`
- `attribution_write_errors` has not increased within the last `evidenceguard_window_s`

- `parquet_queue_depth_pct` is defined AND below thresholds (fail-closed if metrics unavailable):
  - Metrics MUST exist: `parquet_queue_depth` (gauge, count), `parquet_queue_capacity` (gauge, count).
  - Derived: `parquet_queue_depth_pct = parquet_queue_depth / max(parquet_queue_capacity, 1)`
  - Trip (breach window): if `parquet_queue_depth_pct > parquet_queue_trip_pct` for >= `parquet_queue_trip_window_s` seconds → EvidenceChainState != GREEN
  - Clear (hysteresis): require `parquet_queue_depth_pct < parquet_queue_clear_pct` for >= `queue_clear_window_s` seconds before GREEN (cleared only after max(queue_clear_window_s, evidenceguard_global_cooldown) with all criteria satisfied)

**Where enforced (must be explicit):**
- When `enforced_profile != CSP`, PolicyGuard `get_effective_mode()` MUST include EvidenceGuard in the axis resolver.
- When `enforced_profile != CSP`, the hot-path execution gate MUST check EvidenceChainState before dispatching OPEN orders.

**Acceptance Tests (REQUIRED):**

AT-005
- Given: Evidence writers are healthy (WAL + TruthCapsule + Decision Snapshot succeed) and an OPEN intent results in zero fills.
- When: EvidenceGuard evaluates EvidenceChainState over the window.
- Then: EvidenceChainState does not flip to not-GREEN solely due to missing attribution rows.
- Pass criteria: EvidenceChainState can remain GREEN (assuming other writers are healthy).
- Fail criteria: EvidenceGuard blocks opens because an attribution row is absent when no fills occurred.

AT-105
- Given: `evidenceguard_window_s=60` and `truth_capsule_write_errors` increases by 1 at T0 and does not increase afterward.
- When: EvidenceGuard evaluates at `now_ms=T0+59_000` and again at `now_ms=T0+61_000`.
- Then: at +59s EvidenceChainState is not GREEN due to the window; at +61s it may become GREEN only if other criteria + cooldown/hysteresis are satisfied.
- Pass criteria: the 60s window boundary affects GREEN eligibility deterministically.
- Fail criteria: GREEN eligibility ignores the window or uses an unspecified duration.

AT-107
- Given: `wal_write_errors` increments (unable to write intent to WAL).
- When: EvidenceGuard evaluates EvidenceChainState.
- Then: EvidenceChainState MUST be not GREEN (fail-closed); OPEN intents blocked.
- Pass criteria: WAL write failure forces ReduceOnly/blocking of Opens.
- Fail criteria: System remains GREEN despite WAL write failures (fail-open).

AT-414
- Given: an OPEN intent fills and the attribution row is missing or fails to write.
- When: EvidenceGuard evaluates EvidenceChainState.
- Then: EvidenceChainState MUST be not GREEN (fail-closed); OPEN intents blocked.
- Pass criteria: EvidenceChainState not GREEN; OPEN does not dispatch.
- Fail criteria: EvidenceChainState remains GREEN or OPEN dispatch occurs.

AT-334
- Given: `decision_snapshot_write_errors` increments within the `evidenceguard_window_s`.
- When: EvidenceGuard evaluates EvidenceChainState.
- Then: EvidenceChainState MUST be not GREEN (fail-closed); OPEN intents blocked; CLOSE/HEDGE/CANCEL allowed subject to §2.2.3 TradingMode dispatch authorization.
- Pass criteria: OPEN does not dispatch while `decision_snapshot_write_errors` increases.
- Fail criteria: EvidenceChainState remains GREEN or OPEN dispatch occurs while `decision_snapshot_write_errors` increases.

AT-335
- Given: `parquet_queue_depth` or `parquet_queue_capacity` is missing or unparseable.
- When: EvidenceGuard evaluates `parquet_queue_depth_pct`.
- Then: EvidenceChainState MUST be not GREEN (fail-closed); OPEN intents blocked; CLOSE/HEDGE/CANCEL allowed subject to §2.2.3 TradingMode dispatch authorization.
- Pass criteria: OPEN does not dispatch while required parquet queue metrics are missing/unparseable.
- Fail criteria: EvidenceChainState remains GREEN or OPEN dispatch occurs while required parquet queue metrics are missing/unparseable.

AT-422
- Given: config overrides are set to `parquet_queue_trip_pct = 0.80`, `parquet_queue_trip_window_s = 5`, `parquet_queue_clear_pct = 0.75`, `queue_clear_window_s = 10`, and `evidenceguard_global_cooldown = 0`, and all other EvidenceGuard criteria are satisfied.
- When: `parquet_queue_depth_pct` is 0.85 for 6s, then 0.72 for 9s, then 0.72 for 10s.
- Then: after 6s, EvidenceChainState != GREEN and TradingMode == ReduceOnly; after 9s, EvidenceChainState != GREEN; after 10s, EvidenceChainState == GREEN and EvidenceGuard no longer forces ReduceOnly.
- Pass criteria: trip/clear behavior follows overridden config values, not defaults.
- Fail criteria: no trip, no clear, or behavior matches hard-coded defaults instead of config.

AT-404
- Given: `EvidenceChainState != GREEN`, a cancel/replace that increases exposure, and no Kill-tier triggers are active.
- When: EvidenceGuard evaluates permissions.
- Then: the cancel/replace is rejected; non-risk-increasing cancels may proceed; OPEN remains blocked.
- Pass criteria: risk-increasing cancel/replace rejected while EvidenceChainState is not GREEN.
- Fail criteria: risk-increasing cancel/replace allowed.

AT-214
- Given: `wal_write_errors` is missing or unparseable while EvidenceGuard evaluates EvidenceChainState.
- When: EvidenceGuard computes EvidenceChainState for this tick/window.
- Then: EvidenceChainState MUST be not GREEN (fail-closed) and OPEN intents MUST be blocked.
- Pass criteria: OPEN does not dispatch because a required counter is missing/unparseable.
- Fail criteria: EvidenceChainState becomes GREEN or any OPEN dispatch occurs while `wal_write_errors` is missing/unparseable.

AT-215
- Given: `decision_snapshot_write_errors` is missing or unparseable while EvidenceGuard evaluates EvidenceChainState.
- When: EvidenceGuard computes EvidenceChainState for this tick/window.
- Then: EvidenceChainState MUST be not GREEN (fail-closed) and OPEN intents MUST be blocked.
- Pass criteria: OPEN does not dispatch because a required counter is missing/unparseable.
- Fail criteria: EvidenceChainState becomes GREEN or any OPEN dispatch occurs while `decision_snapshot_write_errors` is missing/unparseable.

AT-415
- Given: `truth_capsule_write_errors` is missing/unparseable OR `parquet_queue_overflow_count` is missing/unparseable.
- When: EvidenceGuard computes EvidenceChainState for this tick/window.
- Then: EvidenceChainState MUST be not GREEN (fail-closed) and OPEN intents MUST be blocked.
- Pass criteria: OPEN does not dispatch because a required counter is missing/unparseable.
- Fail criteria: EvidenceChainState becomes GREEN or any OPEN dispatch occurs while required counters are missing/unparseable.

AT-923
- Given: `evidenceguard_counters_last_update_ts_ms` is older than `evidenceguard_counters_max_age_ms`.
- When: EvidenceGuard computes EvidenceChainState for this tick/window.
- Then: EvidenceChainState MUST be not GREEN (fail-closed) and OPEN intents MUST be blocked.
- Pass criteria: OPEN does not dispatch because required counters are stale.
- Fail criteria: EvidenceChainState becomes GREEN or any OPEN dispatch occurs while counters are stale.


**Canonical TradingMode computation (axis resolver + staleness + watchdog semantics + reason codes) is defined in §2.2.3 (PolicyGuard-owned).**

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

AT-1261
- Given: `fee_model_cache_age_s > fee_model_hard_stale_s`; all other SystemIntegrityAxis inputs nominal.
- When: TradingMode is computed.
- Then: TradingMode == ReduceOnly and mode_reasons includes REDUCEONLY_FEE_MODEL_HARD_STALE.
- Pass criteria: OPEN blocked; correct reason code emitted. Fail criteria: Active returned or reason missing.

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

---

##### **2.2.3.6 Kill Semantics (Capital Supremacy Safe, CSP)**

**Kill SHALL mean:**
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
- Then: `TradingMode == Kill`.
- Pass criteria: Kill is computed regardless of other non-kill gates.
- Fail criteria: ReduceOnly/Active is computed while `risk_state == Kill`.

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

#### **2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001**
Profile: CSP

**Goal:** Prevent "false-safe opens" after restart, WS gaps, or session termination until reconciliation proves state truth.

**Semantics:**
- If `open_permission_blocked_latch == true`:
  - OPEN intents MUST be blocked.
  - CLOSE / HEDGE / CANCEL intents MUST remain allowed, except risk-increasing cancels/replaces MUST be rejected per §2.2.5.
- When `open_permission_blocked_latch == true`, the latch feeds into PolicyGuard's `SystemIntegrityAxis` as a `DEGRADED` input (§2.2.3.2), producing `TradingMode::ReduceOnly`. OPEN blocking is enforced both directly (latch gate) and indirectly (via PolicyGuard TradingMode dispatch authorization).

**State fields:**
- `open_permission_blocked_latch` (bool; `true` means OPEN blocked)
- `open_permission_reason_codes` (`OpenPermissionReasonCode[]`; MUST be `[]` iff `open_permission_blocked_latch == false`)
- `open_permission_requires_reconcile` (bool; MUST equal `open_permission_blocked_latch` for v5.2 - all reason codes are reconcile-class)

**Acceptance Tests (References):**
- AT-027 in §7.0 validates `/status` latch field invariants.

**Deterministic reconstruction (required; no persistence):**
- On startup, set `open_permission_blocked_latch = true` with reason `RESTART_RECONCILE_REQUIRED`.
- The latch MUST clear only after reconciliation succeeds.

**Reconciliation success criteria (required):**
- Ledger inflight intents (non-terminal) match exchange open orders by label (all matched within label disambiguation rules per §1.1.2).
- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon` (default: instrument's `min_amount` or `1e-6` if undefined).
- No missing trades over the last `reconcile_trade_lookback_sec` (default: 300s) as determined by REST `/get_user_trades` query. If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
- All reconcile-class reason codes cleared (no unresolved WS gaps, inventory mismatches, or session termination flags).

**Reconciliation stall observability (deterministic, no override-clear):**
- If reconciliation remains blocked and `open_permission_blocked_latch` stays true for longer than `reconcile_stall_max_delay_s`, runtime MUST emit structured log `RECONCILE_STALL` and increment counter metric `reconcile_stall_total`.
- `RECONCILE_STALL` payload MUST include the failing criterion that is preventing reconciliation success.
- Emission cadence MUST be deterministic: for a continuous stall episode, emit once when the threshold is first exceeded; re-emit only if the failing criterion changes during that same episode.
- A new emission episode starts only after reconciliation success clears the stall condition/latch, and a later stall exceeds the threshold again.
- This observability rule MUST NOT clear or override the latch; latch clears only after reconciliation success criteria are satisfied.

AT-1243
- Given: `open_permission_blocked_latch == true` and reconciliation remains blocked beyond `reconcile_stall_max_delay_s`.
- When: reconciliation stall observability evaluates.
- Then: runtime emits structured `RECONCILE_STALL` log with the failing criterion, increments `reconcile_stall_total`, and keeps latch set with no override-clear.
- And: for one continuous stall episode, emission occurs once at first threshold exceedance, with re-emission only on failing-criterion change; a new episode can emit again only after clear and re-stall.
- Pass criteria: log + counter emitted with deterministic cadence and failing criterion; latch remains set.
- Fail criteria: missing log/counter, missing failing criterion payload, repeated spam emission without criterion change/new episode, or latch cleared without reconciliation success.

AT-1100
- Given: reconciliation runs and REST `/get_user_trades` over the last `reconcile_trade_lookback_sec` returns trades that are not present in the local ledger (missing trades).
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked until the missing trades are resolved and a subsequent reconciliation pass succeeds.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite missing trades, or latch clears prematurely.

AT-1263
- Given: `open_permission_blocked_latch == true`; REST `/get_user_trades` returns network error, timeout, HTTP error, or unparseable response.
- When: reconciliation success criteria are evaluated.
- Then: reconciliation fails; `open_permission_blocked_latch` remains true; OPEN blocked.
- Pass criteria: latch held; reconciliation reported failed. Fail criteria: latch clears on transport failure.

**Allowed values (reconcile-only):** `OpenPermissionReasonCode[]`
- `RESTART_RECONCILE_REQUIRED`
- `WS_BOOK_GAP_RECONCILE_REQUIRED`
- `WS_TRADES_GAP_RECONCILE_REQUIRED`
- `WS_DATA_STALE_RECONCILE_REQUIRED`
- `INVENTORY_MISMATCH_RECONCILE_REQUIRED`
- `SESSION_TERMINATION_RECONCILE_REQUIRED`

**Hard rule:** Runtime-binding and EvidenceChain failures MUST NOT appear in `open_permission_reason_codes` (they are cleared by cert/evidence recovery, not reconciliation).

**Acceptance Tests (REQUIRED):**
AT-010
- Given: `open_permission_blocked_latch==true` with `open_permission_reason_codes` containing `RESTART_RECONCILE_REQUIRED`.
- When: the system evaluates an OPEN intent for dispatch.
- Then: no OPEN order is dispatched; CLOSE/HEDGE/CANCEL intents remain dispatchable, except risk-increasing cancels/replaces are rejected (per §2.2.5), subject to Kill semantics in §2.2.3.
- Pass criteria: OPEN dispatch count remains 0; CLOSE/HEDGE/CANCEL dispatch is permitted; risk-increasing cancel/replace is rejected.
- Fail criteria: any OPEN is dispatched while the latch is true.

AT-430
- Given: startup occurs with no persisted latch state.
- When: initialization completes before reconciliation runs.
- Then: `open_permission_blocked_latch == true`, `open_permission_reason_codes` contains `RESTART_RECONCILE_REQUIRED`, and `open_permission_requires_reconcile == true`.
- Pass criteria: latch fields match expected startup values and OPEN remains blocked.
- Fail criteria: latch not set, reason missing, or OPEN allowed before reconciliation.

AT-1242
- Given: the system is running with `open_permission_blocked_latch==false` (latch clear, normal operation).
- When: one of the following trigger events occurs: (a) WS book gap detected, (b) WS trades gap detected, (c) WS data becomes stale beyond threshold, (d) inventory mismatch detected between ledger and exchange, (e) exchange session termination received.
- Then: `open_permission_blocked_latch` MUST be set to `true` and `open_permission_reason_codes` MUST contain the corresponding reason code (`WS_BOOK_GAP_RECONCILE_REQUIRED`, `WS_TRADES_GAP_RECONCILE_REQUIRED`, `WS_DATA_STALE_RECONCILE_REQUIRED`, `INVENTORY_MISMATCH_RECONCILE_REQUIRED`, or `SESSION_TERMINATION_RECONCILE_REQUIRED` respectively); OPEN intents MUST be blocked.
- Pass criteria: latch transitions to `true` with the correct reason code; OPEN dispatch count remains 0 while latch is set.
- Fail criteria: latch remains `false` after trigger event, reason code is missing/incorrect, or OPEN dispatches while latch is set.

AT-011
- Given: `open_permission_blocked_latch==true` for a WS gap reason (e.g., `WS_TRADES_GAP_RECONCILE_REQUIRED`).
- When: reconciliation succeeds (all criteria in this section are satisfied).
- Then: the latch clears (`open_permission_blocked_latch==false` and `open_permission_reason_codes==[]`), and opens may proceed only if PolicyGuard computes `TradingMode::Active`.
- Pass criteria: latch fields match the invariants immediately after reconciliation; opens remain blocked unless mode is Active.
- Fail criteria: latch clears without reconciliation success, or opens proceed while latch remains true.

AT-402
- Given: `open_permission_blocked_latch==true` with `open_permission_reason_codes` containing `RESTART_RECONCILE_REQUIRED` and a cancel/replace that increases exposure.
- When: cancel/replace permission is evaluated.
- Then: the cancel/replace is rejected until reconciliation clears the latch.
- Pass criteria: risk-increasing cancel blocked while latch is true; allowed only after latch clears and other gates allow.
- Fail criteria: risk-increasing cancel allowed while latch is true.

AT-110
- Given: `open_permission_blocked_latch==true`.
- When: an order placement intent is evaluated with `reduce_only` missing or null.
- Then: it MUST be treated as OPEN and blocked.
- Pass criteria: no order placement is dispatched.
- Fail criteria: any order placement dispatch occurs while `reduce_only` is missing and latch is true.

AT-411
- Given: runtime binding cert is missing/stale/FAIL OR (`EvidenceChainState != GREEN` and `enforced_profile != CSP`), and no reconcile-class triggers are active.
- When: `open_permission_reason_codes` are computed.
- Then: `open_permission_reason_codes` does not include runtime-binding or EvidenceChain failures, and `open_permission_blocked_latch` is unchanged.
- Pass criteria: no F1/Evidence codes in reason list; latch not set without a reconcile trigger.
- Fail criteria: any F1/Evidence code appears or latch is set without a reconcile trigger.
- Note: This AT tests the Hard rule (runtime-binding and EvidenceChain failures MUST NOT appear in `open_permission_reason_codes`) in isolation. The Hard rule is unconditional — it applies regardless of whether reconcile-class triggers are concurrently active. The "no reconcile-class triggers" precondition isolates the test from latch interactions but does not limit the Hard rule's scope.

AT-1253
- Given: runtime binding cert is missing/stale/FAIL AND a reconcile-class trigger is concurrently active (e.g., `WS_BOOK_GAP_RECONCILE_REQUIRED`).
- When: `open_permission_reason_codes` are computed.
- Then: `open_permission_reason_codes` contains the reconcile-class reason code but MUST NOT contain runtime-binding or EvidenceChain failure codes.
- Pass criteria: only reconcile-class codes in reason list; no F1/Evidence codes despite concurrent cert failure.
- Fail criteria: F1/Evidence codes appear in `open_permission_reason_codes`.


#### **2.2.5 Cancel/Replace Permission Rules (Canonical)**

Cancel/Replace intents are allowed only if ALL are true:
1. TradingMode dispatch authorization permits the cancel/replace (§2.2.3); risk-increasing cancel/replace is forbidden when `TradingMode ∈ {ReduceOnly, Kill}`.
2. NOT risk-increasing while `open_permission_blocked_latch == true` (§2.2.4).
3. NOT risk-increasing while `EvidenceChainState != GREEN` when `enforced_profile != CSP` (§2.2.2).
4. NOT risk-increasing while `RiskState == Degraded` (§3.4).
5. Does NOT cancel protective reduce-only closing/hedging orders (§3.2).

**Definition (Risk-Increasing Cancel/Replace):**
- Any cancel/replace that increases absolute net exposure, increases exposure in the current risk direction, or removes `reduce_only` protection on a closing/hedging order.
- Examples: canceling reduce_only close/hedge orders; replacing with larger size in the risk-increasing direction.
Rejections for risk-increasing cancel/replace MUST use `Rejected(RiskIncreasingCancelReplaceForbidden)`.

**Acceptance Test (REQUIRED):**
Profile: GOP
AT-917
- Given: `EvidenceChainState != GREEN`, `enforced_profile != CSP`, and a risk-increasing cancel/replace.
- When: cancel/replace permission is evaluated.
- Then: the request is rejected with `Rejected(RiskIncreasingCancelReplaceForbidden)`.
- Pass criteria: rejection reason matches; no risk-increasing cancel/replace dispatch occurs.
- Fail criteria: dispatch occurs or reason missing/mismatched.

Profile: CSP

#### **2.2.6 RejectReasonCode Registry (Intent-Level Rejections)**

**Scope (non-negotiable):** Applies to any intent rejected **before dispatch**. This does **not** replace `ModeReasonCode` or `OpenPermissionReasonCode`.

**MUST:**
- Any intent rejected before dispatch MUST include `reject_reason_code: RejectReasonCode`, and the value MUST be in this registry.
- Any use of `Rejected(...)`, `Rejected(reason=...)`, or `Reject(intent=...)` in this contract implies `reject_reason_code = <TOKEN>` and `<TOKEN> ∈ RejectReasonCode`.

**Completeness rule (non-negotiable):**
- The registry MUST be complete w.r.t. this contract: if a new rejection token is added anywhere, the registry MUST be updated in the same patch.

**Allowed values (minimal complete set):**
- `TooSmallAfterQuantization`
- `InstrumentMetadataMissing`
- `ChurnBreakerActive`
- `LiquidityGateNoL2`
- `EmergencyCloseNoPrice`
- `ExpectedSlippageTooHigh`
- `NetEdgeTooLow`
- `NetEdgeInputMissing`
- `PricerInputMissing`
- `PricerInputInvalid`
- `GateCascadeSkip` _(internal diagnostic — never emitted as primary reject code; set on cascaded downstream gates)_
- `InsufficientDepthWithinBudget`
- `AssemblyFailed`
- `FeeCacheStale`
- `RecordedBeforeDispatchFailed`
- `InventorySkew`
- `InventorySkewDeltaLimitMissing`
- `PendingExposureBudgetExceeded`
- `GlobalExposureBudgetExceeded`
- `ContractsAmountMismatch`
- `MarginHeadroomRejectOpens`
- `MarginHeadroomInputMissing`
- `OrderTypeMarketForbidden`
- `OrderTypeStopForbidden`
- `LinkedOrderTypeForbidden`
- `PostOnlyWouldCross`
- `RiskIncreasingCancelReplaceForbidden`
- `RateLimitBrownout`
- `InstrumentExpiredOrDelisted`
- `FeedbackLoopGuardActive`
- `LabelTooLong`
- `TradingModeBlockedOpen`

**Acceptance Test (REQUIRED):**
AT-930
- Given: a test harness that triggers at least one rejection in each category (quantization, liquidity, exposure reservation, preflight, cancel/replace permission).
- When: each rejection occurs.
- Then: the response includes `reject_reason_code`, and its value is a member of `RejectReasonCode`.
- Pass criteria: all sampled rejections include a registry value.
- Fail criteria: any rejection has a missing or non-registry reason.

AT-1101
- Given: the full set of `Rejected(...)` tokens referenced anywhere in this contract.
- When: a completeness check is performed against the `RejectReasonCode` registry enum in code.
- Then: every rejection token referenced in the contract MUST have a corresponding variant in the `RejectReasonCode` enum; no contract-referenced token is missing from the registry.
- Pass criteria: 1:1 correspondence between contract rejection tokens and code enum variants.
- Fail criteria: any contract-referenced rejection token is absent from the `RejectReasonCode` enum.
