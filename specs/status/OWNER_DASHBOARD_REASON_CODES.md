# Owner Dashboard Reason Codes (Contract-Aligned)

> **Related docs:**
> - [LOCKED_DECISIONS.md](./LOCKED_DECISIONS.md) — Why these rules exist
> - [README.md](./README.md) — Enforcement layer overview
> - [status_reason_registries_manifest.json](./status_reason_registries_manifest.json) — Single source of truth

This document defines how the **Owner Dashboard** renders authoritative reasons for restricted trading.

---

## Visual Contract (What the Owner Sees)

```
┌─────────────────────────────────────────────────────────────────────┐
│  DEPLOYMENT: LIVE                              BUILD: abc123def     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  TRADING MODE     ████████████████████████████████████████████████  │
│                   ██  ReduceOnly  ██                                │
│                   ████████████████████████████████████████████████  │
│                                                                     │
│  PRIMARY REASON   Open-permission latch is set (reconcile required) │
│                                                                     │
│  LATCH REASON     Market-data silence — must reconcile              │
│                                                                     │
│  UNBLOCK          AUTO: ws_event_lag_ms <= 500 for >= 60s           │
│                   Current: ws_event_lag_ms = 3200                   │
│                   Target: ws_event_lag_ms <= 500                    │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  [Force ReduceOnly]  [View /status JSON]  [Incident Runbook]        │
└─────────────────────────────────────────────────────────────────────┘
```

**5-second rule:** Owner must identify `TradingMode` + primary reason in ≤5 seconds.

---

## Key Alignment Rules

### 1. TradingMode is immutable and contract-defined
```
TradingMode ∈ { Active, ReduceOnly, Kill }
```
- **Active**: Normal trading permitted
- **ReduceOnly**: Can only reduce exposure (close positions, hedge)
- **Kill**: No trading at all (except capital supremacy override)

**Paper is NOT a TradingMode.** Paper is a `DeploymentEnvironment`:
```
DeploymentEnvironment ∈ { DEV, STAGING, PAPER, LIVE }
```

### 2. Owner-visible reasons derive from contract fields

| Dashboard Element | Source Field |
|-------------------|--------------|
| TradingMode | `/status.trading_mode` |
| Primary reason | First of `/status.mode_reasons` |
| Latch reason | First of `/status.open_permission_reason_codes` |
| Unblock steps | `/status.owner_view.unblock[]` |

The dashboard **renders** what PolicyGuard reports. It does not compute or infer.

### 3. Single source of truth
All enumerations and display strings come from:
```
specs/status/status_reason_registries_manifest.json
```
No code or UI may invent reason tokens outside the manifest.

---

## Non-Negotiable Rules

### Rule 1: No Free-Text Reasons
- The dashboard MUST only display enumerated values from the manifest.
- Unknown values trigger `STATE_UNHEALTHY_STATUS_SCHEMA` prominently.
- Free-text explanations exist only in `owner_view.owner_message` (derived, not authoritative).

### Rule 2: Dashboard Does Not Compute TradingMode
- The dashboard does **not** set or compute TradingMode.
- The dashboard only **renders** what PolicyGuard reports.
- If you're tempted to add logic like `if (x && y) show "Active"` — stop.

### Rule 3: Fail-Closed on Schema Violations
If `/status` contains an unknown `trading_mode`, `mode_reasons`, or `open_permission_reason_codes`:
1. Dashboard MUST show `STATE_UNHEALTHY_STATUS_SCHEMA`
2. Dashboard MUST show "Force ReduceOnly" button prominently
3. Operator response: `POST /api/v1/emergency/reduce_only`

### Rule 4: 5-Second Rule
Owner must identify `TradingMode` + primary reason in ≤5 seconds.

If they can't, the UI has failed.

---

## Deterministic Precedence (Primary Reason Selection)

```python
def get_primary_reason(status):
    if status.trading_mode == "Kill":
        return status.mode_reasons[0]  # Kill-tier reason

    if status.trading_mode == "ReduceOnly":
        return status.mode_reasons[0]  # ReduceOnly-tier reason

    if status.open_permission_blocked_latch:
        return status.open_permission_reason_codes[0]  # Latch reason

    # Active with no issues
    return derive_owner_state(status)  # e.g., STATE_IDLE_HEALTHY
```

Contract guarantees:
- `mode_reasons` is ordered deterministically
- First element is highest priority
- Dashboard must respect this ordering

---

## Registry Reference

### ModeReasonCode (from `/status.mode_reasons`)

| Tier | Prefix | Meaning |
|------|--------|---------|
| Kill | `KILL_*` | System cannot trade at all |
| ReduceOnly | `REDUCEONLY_*` | Can only reduce exposure |

See `status_reason_registries_manifest.json` for full list with unblock conditions.

### OpenPermissionReasonCode (from `/status.open_permission_reason_codes`)

These mean: **reconciliation required** before opening new risk.

| Code | Meaning |
|------|---------|
| `RESTART_RECONCILE_REQUIRED` | System restarted |
| `WS_BOOK_GAP_RECONCILE_REQUIRED` | Order book feed gap |
| `WS_TRADES_GAP_RECONCILE_REQUIRED` | Trades feed gap |
| `WS_DATA_STALE_RECONCILE_REQUIRED` | Market data stale |
| `INVENTORY_MISMATCH_RECONCILE_REQUIRED` | Position mismatch |
| `SESSION_TERMINATION_RECONCILE_REQUIRED` | Exchange session killed |

### OwnerStateCode (dashboard-only)

These **do not affect TradingMode**. They provide context when Active:

| Code | Meaning |
|------|---------|
| `STATE_STARTUP_RECONCILING` | Starting up |
| `STATE_IDLE_HEALTHY` | Healthy, no signals |
| `STATE_PAPER_MODE` | Paper trading |
| `STATE_MICRO_LIVE` | Live with micro-caps |
| `STATE_UNHEALTHY_STATUS_SCHEMA` | Schema violation (fail-closed) |

---

## Owner Acceptance Tests

### Test A — 5-Second Rule
1. Show dashboard to a non-technical owner
2. Ask: "Why is trading restricted?"
3. **Pass if:** Answer in ≤5 seconds
4. **Fail if:** Owner needs to click, scroll, or ask engineer

### Test B — Deterministic Unblock
For any displayed reason:
1. Dashboard must show either:
   - **AUTO**: metric threshold + duration (e.g., "mm_util < 0.80 for >= 60s")
   - **MANUAL**: required action (e.g., "Incident record + explicit approval")
2. **Pass if:** Unblock condition is machine-readable
3. **Fail if:** Unblock is vague ("wait for things to improve")

### Test C — Chaos Drill Visibility
Trigger each scenario and verify correct primary reason appears immediately:

| Trigger | Expected Primary Reason |
|---------|------------------------|
| F1 cert invalid | `REDUCEONLY_F1_CERT_INVALID` |
| WS gap | `REDUCEONLY_OPEN_PERMISSION_LATCHED` + latch reason visible |
| 10028 session kill | `KILL_RATE_LIMIT_SESSION_TERMINATION` |
| Market data stale | `REDUCEONLY_OPEN_PERMISSION_LATCHED` + `WS_DATA_STALE_RECONCILE_REQUIRED` |

### Test D — Schema Violation Fail-Closed
1. Feed fake `/status` with unknown reason code
2. **Pass if:** Dashboard shows `STATE_UNHEALTHY_STATUS_SCHEMA` + "Force ReduceOnly" button
3. **Fail if:** Dashboard shows unknown code or crashes

---

## Implementation Checklist

- [ ] Generate UI enums from `status_reason_registries_manifest.json`
- [ ] Display `trading_mode` prominently (largest text element)
- [ ] Display first `mode_reasons` element as primary reason
- [ ] Display first `open_permission_reason_codes` if latch is true
- [ ] Display `owner_view.unblock` steps with current/target values
- [ ] Add "Force ReduceOnly" button that calls `POST /api/v1/emergency/reduce_only`
- [ ] Add "View /status JSON" button for debugging
- [ ] Fail-closed on unknown enum values
- [ ] CI check: fail if UI uses reason codes not in manifest
