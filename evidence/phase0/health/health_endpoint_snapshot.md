# Health + Owner Status (Phase 0)

> **Purpose:** Minimal operator commands to verify both liveness and authority state.
> Phase 0 requires health plus a tiny owner status surface.

## Metadata
- doc_id: HEALTH-001
- version: 1.0
- contract_version_target: 5.2
- last_updated_utc: 2026-01-27T14:00:00Z

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
  "pending_orders": 0
}
```

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

### Forced Unhealthy Path (for gate tests)
```bash
STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli health --format json
echo $?  # 1 = unhealthy (policy load failure)
STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli status --format json
# status shows trading_mode=KILL and is_trading_allowed=false
```

---

## Owner Sign-Off

- [ ] Health command implemented
- [ ] Status command implemented
- [ ] Health returns required fields (ok, build_id, contract_version)
- [ ] Status returns required fields (ok, build_id, contract_version, trading_mode, is_trading_allowed, timestamp_utc)
- [ ] Fail-closed behavior verified on missing policy

**owner_signature:** ______________________
**date_utc:** ______________________
