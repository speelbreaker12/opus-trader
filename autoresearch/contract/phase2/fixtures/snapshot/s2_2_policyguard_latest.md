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
