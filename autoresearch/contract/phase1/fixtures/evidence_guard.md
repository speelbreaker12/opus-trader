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
