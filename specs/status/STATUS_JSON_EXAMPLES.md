# /status JSON Examples (Contract-Compliant) — v1

These fixtures are **contract-shaped**: they include every CSP-minimum `/status` key and only use contract enums for:
- `trading_mode ∈ {Active, ReduceOnly, Kill}`
- `mode_reasons ∈ ModeReasonCode[]` (tier-pure + ordered)
- `open_permission_reason_codes ∈ OpenPermissionReasonCode[]`

Owner-friendly reason codes/messages live under `owner_view` (an extension object). Extra keys are allowed; they must never contradict contract fields.

## Conventions used in examples

- `contract_version` is the numeric string `"5.2"`.
- `mode_reasons` ordering follows the contract’s deterministic order list.
- If `open_permission_blocked_latch == true`, `open_permission_reason_codes` is non-empty and `open_permission_requires_reconcile == true`.
- `connectivity_degraded` is set per the contract rule (true when latch reasons indicate gaps/staleness/termination).

---

## Example 1 — Partial/Mixed Fill → Containment

Scenario: one leg fills, the paired leg rejects; system enters containment.

Expected: `TradingMode=ReduceOnly`, `risk_state=Degraded`, and **no new OPENs**.

```json
{
  "status_schema_version": 1,
  "supported_profiles": ["CSP"],
  "enforced_profile": "CSP",

  "trading_mode": "ReduceOnly",
  "risk_state": "Degraded",
  "bunker_mode_active": false,
  "connectivity_degraded": false,

  "policy_age_sec": 12,
  "last_policy_update_ts": 1769440312000,

  "f1_cert_state": "PASS",
  "f1_cert_expires_at": 1769526712000,

  "disk_used_pct": 0.42,
  "disk_used_last_update_ts_ms": 1769440310000,
  "disk_used_pct_secondary": 0.41,
  "disk_used_secondary_last_update_ts_ms": 1769440310000,

  "mm_util": 0.18,
  "mm_util_last_update_ts_ms": 1769440310000,

  "loop_tick_last_ts_ms": 1769440312500,

  "atomic_naked_events_24h": 0,
  "429_count_5m": 0,
  "10028_count_5m": 0,

  "wal_queue_depth": 4,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 0,

  "deribit_http_p95_ms": 140,
  "ws_event_lag_ms": 35,

  "mode_reasons": [
    "REDUCEONLY_EMERGENCY_REDUCEONLY_ACTIVE",
    "REDUCEONLY_RISKSTATE_DEGRADED"
  ],

  "open_permission_blocked_latch": false,
  "open_permission_reason_codes": [],
  "open_permission_requires_reconcile": false,

  "owner_view": {
    "primary_owner_reason_code": "RISK_PARTIAL_FILL_CONTAINMENT",
    "owner_message": "Partial/mixed fill detected; system is flattening/hedging and blocking new OPEN risk.",
    "unblock": [
      {
        "type": "AUTO",
        "condition": "net_exposure == 0 AND containment_state == CLEAN for >= 60s",
        "current": "net_exposure=+0.42 (delta)",
        "target": "net_exposure=0"
      }
    ]
  }
}
```

---

## Example 2 — Market Data Goes Stale → OPEN Permission Latched

Scenario: market feed freezes / event lag breaches threshold.

Expected: OPEN permission latch sets with `WS_DATA_STALE_RECONCILE_REQUIRED`, and `TradingMode=ReduceOnly` with reason `REDUCEONLY_OPEN_PERMISSION_LATCHED`.

```json
{
  "status_schema_version": 1,
  "supported_profiles": ["CSP"],
  "enforced_profile": "CSP",

  "trading_mode": "ReduceOnly",
  "risk_state": "Healthy",
  "bunker_mode_active": false,
  "connectivity_degraded": true,

  "policy_age_sec": 9,
  "last_policy_update_ts": 1769440410000,

  "f1_cert_state": "PASS",
  "f1_cert_expires_at": 1769526810000,

  "disk_used_pct": 0.43,
  "disk_used_last_update_ts_ms": 1769440410000,
  "disk_used_pct_secondary": 0.42,
  "disk_used_secondary_last_update_ts_ms": 1769440410000,

  "mm_util": 0.17,
  "mm_util_last_update_ts_ms": 1769440410000,

  "loop_tick_last_ts_ms": 1769440410900,

  "atomic_naked_events_24h": 0,
  "429_count_5m": 0,
  "10028_count_5m": 0,

  "wal_queue_depth": 2,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 0,

  "deribit_http_p95_ms": 160,
  "ws_event_lag_ms": 3200,

  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],

  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["WS_DATA_STALE_RECONCILE_REQUIRED"],
  "open_permission_requires_reconcile": true,

  "owner_view": {
    "primary_owner_reason_code": "DATA_MARKET_FEED_STALE",
    "owner_message": "Market data is stale; new OPEN risk is blocked until reconciliation clears the latch.",
    "unblock": [
      {
        "type": "AUTO",
        "condition": "ws_event_lag_ms <= 500 for >= 60s AND reconciliation_success == true",
        "current": "ws_event_lag_ms=3200",
        "target": "ws_event_lag_ms<=500"
      }
    ]
  }
}
```

---

## Example 3 — WAL / Intent Ledger Backpressure

Scenario: WAL queue is full or enqueue failures are occurring; opens must fail-closed.

Expected: `TradingMode=ReduceOnly`, `risk_state=Degraded`, WAL metrics reflect backpressure.

```json
{
  "status_schema_version": 1,
  "supported_profiles": ["CSP"],
  "enforced_profile": "CSP",

  "trading_mode": "ReduceOnly",
  "risk_state": "Degraded",
  "bunker_mode_active": false,
  "connectivity_degraded": false,

  "policy_age_sec": 6,
  "last_policy_update_ts": 1769440510000,

  "f1_cert_state": "PASS",
  "f1_cert_expires_at": 1769526910000,

  "disk_used_pct": 0.44,
  "disk_used_last_update_ts_ms": 1769440510000,
  "disk_used_pct_secondary": 0.44,
  "disk_used_secondary_last_update_ts_ms": 1769440510000,

  "mm_util": 0.19,
  "mm_util_last_update_ts_ms": 1769440510000,

  "loop_tick_last_ts_ms": 1769440510600,

  "atomic_naked_events_24h": 0,
  "429_count_5m": 0,
  "10028_count_5m": 0,

  "wal_queue_depth": 1024,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 17,

  "deribit_http_p95_ms": 145,
  "ws_event_lag_ms": 45,

  "mode_reasons": ["REDUCEONLY_RISKSTATE_DEGRADED"],

  "open_permission_blocked_latch": false,
  "open_permission_reason_codes": [],
  "open_permission_requires_reconcile": false,

  "owner_view": {
    "primary_owner_reason_code": "EXEC_WAL_WRITE_FAILED",
    "owner_message": "Intent ledger is backpressured; OPEN dispatch is fail-closed until WAL is healthy again.",
    "unblock": [
      {
        "type": "AUTO",
        "condition": "wal_queue_depth < wal_queue_capacity AND wal_queue_enqueue_failures stops increasing for >= 60s",
        "current": "wal_queue_depth=1024, wal_queue_enqueue_failures=17",
        "target": "wal_queue_depth<1024 and failures stable"
      }
    ]
  }
}
```

---

## Example 4 — Exchange Session Termination (10028-style) → Latch + (Possibly) Kill

This example is the **unconfirmed** case (ReduceOnly + latch).

```json
{
  "status_schema_version": 1,
  "supported_profiles": ["CSP"],
  "enforced_profile": "CSP",

  "trading_mode": "ReduceOnly",
  "risk_state": "Degraded",
  "bunker_mode_active": false,
  "connectivity_degraded": true,

  "policy_age_sec": 4,
  "last_policy_update_ts": 1769440610000,

  "f1_cert_state": "PASS",
  "f1_cert_expires_at": 1769527010000,

  "disk_used_pct": 0.40,
  "disk_used_last_update_ts_ms": 1769440610000,
  "disk_used_pct_secondary": 0.40,
  "disk_used_secondary_last_update_ts_ms": 1769440610000,

  "mm_util": 0.20,
  "mm_util_last_update_ts_ms": 1769440610000,

  "loop_tick_last_ts_ms": 1769440610400,

  "atomic_naked_events_24h": 0,
  "429_count_5m": 0,
  "10028_count_5m": 3,

  "wal_queue_depth": 1,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 0,

  "deribit_http_p95_ms": 180,
  "ws_event_lag_ms": 70,

  "mode_reasons": [
    "REDUCEONLY_OPEN_PERMISSION_LATCHED",
    "REDUCEONLY_RISKSTATE_DEGRADED",
    "REDUCEONLY_SESSION_KILL_UNCONFIRMED"
  ],

  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["SESSION_TERMINATION_RECONCILE_REQUIRED"],
  "open_permission_requires_reconcile": true,

  "owner_view": {
    "primary_owner_reason_code": "EXT_SESSION_TERMINATED",
    "owner_message": "Exchange session terminated; system is blocked from new OPENs until re-auth + reconciliation succeeds.",
    "unblock": [
      {
        "type": "MANUAL",
        "condition": "re-authenticate + reconciliation_success == true (artifact recorded)",
        "current": "session=terminated",
        "target": "session=active + reconcile=clean"
      }
    ]
  }
}
```

---

## Example 5 — Unknown/Unmapped Token Detected → ForceKill via Cortex Override (Fail-Closed)

Contract-valid fail-closed pattern: detect the violation, emit `ForceKill` via a producer, PolicyGuard reports `KILL_CORTEX_FORCE_KILL`.

```json
{
  "status_schema_version": 1,
  "supported_profiles": ["CSP"],
  "enforced_profile": "CSP",

  "trading_mode": "Kill",
  "risk_state": "Healthy",
  "bunker_mode_active": false,
  "connectivity_degraded": false,

  "policy_age_sec": 3,
  "last_policy_update_ts": 1769440710000,

  "f1_cert_state": "PASS",
  "f1_cert_expires_at": 1769527110000,

  "disk_used_pct": 0.39,
  "disk_used_last_update_ts_ms": 1769440710000,
  "disk_used_pct_secondary": 0.39,
  "disk_used_secondary_last_update_ts_ms": 1769440710000,

  "mm_util": 0.16,
  "mm_util_last_update_ts_ms": 1769440710000,

  "loop_tick_last_ts_ms": 1769440710300,

  "atomic_naked_events_24h": 0,
  "429_count_5m": 0,
  "10028_count_5m": 0,

  "wal_queue_depth": 0,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 0,

  "deribit_http_p95_ms": 120,
  "ws_event_lag_ms": 20,

  "mode_reasons": ["KILL_CORTEX_FORCE_KILL"],

  "open_permission_blocked_latch": false,
  "open_permission_reason_codes": [],
  "open_permission_requires_reconcile": false,

  "owner_view": {
    "primary_owner_reason_code": "EXEC_UNMAPPED_REASON_CODE",
    "owner_message": "Contract/registry violation detected; system forced Kill (fail-closed).",
    "unblock": [
      {
        "type": "MANUAL",
        "condition": "fix registry drift + rebuild + redeploy (build_id/config_hash must change)",
        "current": "unknown_token_detected=true",
        "target": "no_unknown_tokens + new_build_deployed"
      }
    ]
  }
}
```
