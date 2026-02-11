# Health + Owner Status (Phase 0)

> **Purpose:** Minimal operator commands to verify both liveness and authority state.
> Phase 0 requires health plus a tiny owner status surface.

## Metadata
- doc_id: HEALTH-001
- version: 1.1
- contract_version_target: 5.2
- last_updated_utc: 2026-02-10T16:30:00Z

---

## Commands

```bash
./stoic-cli health
./stoic-cli status
```

Implementation note:
- `./stoic-cli` loads machine policy via `tools/policy_loader.py` from `config/policy.json`.

---

## Required Fields (minimal)

### Health fields
| Field | Type | Description |
|-------|------|-------------|
| `ok` | boolean | `true` if all checks pass |
| `build_id` | string | Git commit SHA or build identifier |
| `contract_version` | string | Version of CONTRACT.md (e.g., "5.2") |
| `timestamp_utc` | string | ISO 8601 timestamp |

### Status fields
| Field | Type | Description |
|-------|------|-------------|
| `ok` | boolean | `true` if status checks pass |
| `build_id` | string | Git commit SHA or build identifier |
| `contract_version` | string | Version of CONTRACT.md (e.g., "5.2") |
| `trading_mode` | string | Current mode (`ACTIVE`, `REDUCE_ONLY`, `KILL`) |
| `is_trading_allowed` | boolean | `true` only when mode allows new OPEN risk |
| `orders_in_flight` | integer | Simulated in-flight order count |
| `pending_orders` | integer | Simulated pending order count |
| `runtime_state_path` | string/null | Resolved runtime state file path used by command |
| `external_runtime_state` | boolean | `true` only when outside-repo runtime state override is active |
| `timestamp_utc` | string | ISO 8601 timestamp |

### Example Output (Healthy)
```json
{
  "ok": true,
  "build_id": "abc123def",
  "contract_version": "5.2",
  "timestamp_utc": "2026-01-27T14:00:00Z"
}
```

### Example Output (Unhealthy)
```json
{
  "ok": false,
  "build_id": "abc123def",
  "contract_version": "5.2",
  "timestamp_utc": "2026-01-27T14:00:00Z",
  "errors": [
    "config: missing required key",
    "exchange: connection timeout"
  ]
}
```

### Example Status Output
```json
{
  "ok": true,
  "build_id": "abc123def",
  "contract_version": "5.2",
  "timestamp_utc": "2026-01-27T14:00:00Z",
  "trading_mode": "KILL",
  "is_trading_allowed": false,
  "orders_in_flight": 0,
  "pending_orders": 0,
  "runtime_state_path": "/repo/artifacts/phase0/runtime_state.json",
  "external_runtime_state": false
}
```

### Runtime state override safety

- Default mode is fail-closed: `STOIC_RUNTIME_STATE_PATH` must stay under repo root.
- Outside-repo runtime state is allowed only with explicit override:
  - `STOIC_ALLOW_EXTERNAL_RUNTIME_STATE=1`
- Mutating commands (`emergency`, `simulate-open`, `simulate-close`) require a second explicit ack when external override is active:
  - `STOIC_UNSAFE_EXTERNAL_STATE_ACK=I_UNDERSTAND`
- Status/command JSON surfaces this state via `runtime_state_path`, `external_runtime_state`, and warnings.

---

## Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Healthy - all checks pass |
| 1 | Unhealthy - one or more checks failed |
| 2 | Error - could not determine health |

---

## Health Checks Performed

| Check | Pass Condition | Failure Severity |
|-------|----------------|------------------|
| Config loaded | All required keys present | Critical |
| Build ID present | Non-empty string | Critical |
| Contract version present | Non-empty string | Critical |
| Process running | PID exists | Critical |

---

## Phase 0 Boundary (explicitly excluded)

Phase 0 includes minimal status fields only; these remain out of scope:

- [x] Full `/api/v1/status` schema and reason-code registry
- [x] Position/P&L dashboards
- [x] Phase 2+ policy explanation fields

---

## Usage Examples

### Basic Health Check
```bash
./stoic-cli health
echo $?  # 0 = healthy, 1 = unhealthy
```

### In Scripts
```bash
if ./stoic-cli health > /dev/null 2>&1; then
  echo "System healthy"
else
  echo "System unhealthy"
  exit 1
fi
```

### JSON Parsing
```bash
./stoic-cli health --format json | jq '.ok'
./stoic-cli status --format json | jq '.trading_mode,.is_trading_allowed'
```

### External Runtime State Override (explicit break-glass only)
```bash
STOIC_RUNTIME_STATE_PATH=/tmp/phase0_runtime_state.json \
STOIC_ALLOW_EXTERNAL_RUNTIME_STATE=1 \
./stoic-cli status --format json

STOIC_RUNTIME_STATE_PATH=/tmp/phase0_runtime_state.json \
STOIC_ALLOW_EXTERNAL_RUNTIME_STATE=1 \
STOIC_UNSAFE_EXTERNAL_STATE_ACK=I_UNDERSTAND \
./stoic-cli emergency kill --reason "phase0 drill"
```

### Forced Unhealthy Path (for gate tests)
```bash
STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli health --format json
echo $?  # 1 = unhealthy (policy load failure)
STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli status --format json
# status shows trading_mode=KILL and is_trading_allowed=false
```

---

## Owner Sign-Off

- [x] Health command implemented
- [x] Status command implemented
- [x] Health returns required fields (ok, build_id, contract_version)
- [x] Status returns required fields (ok, build_id, contract_version, trading_mode, is_trading_allowed, timestamp_utc)
- [x] Fail-closed behavior verified on missing policy

**owner_signature:** admin
**date_utc:** 2026-02-11
