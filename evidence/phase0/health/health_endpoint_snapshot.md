# Health Endpoint (Phase 0)

> **Purpose:** Single command to verify system is running and configured correctly.
> **NOTE:** This is Phase 0-safe. Do NOT include TradingMode or /status-style reason codes here.

## Metadata
- doc_id: HEALTH-001
- version: 1.0
- contract_version_target: 5.2
- last_updated_utc: 2026-01-27T14:00:00Z

---

## Health Check Command

```bash
./stoic-cli health
```

---

## Required Fields (minimal)

| Field | Type | Description |
|-------|------|-------------|
| `ok` | boolean | `true` if all checks pass |
| `build_id` | string | Git commit SHA or build identifier |
| `contract_version` | string | Version of CONTRACT.md (e.g., "5.2") |
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

## Forbidden in Phase 0 Health (explicitly excluded)

These belong in `/status` (Phase 2), not health:

- [x] TradingMode
- [x] Reason codes
- [x] Position information
- [x] P&L data
- [x] Any permissioning decisions

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
```

---

## Owner Sign-Off

- [ ] Health command implemented
- [ ] Returns required fields (ok, build_id, contract_version)
- [ ] Exit codes correct
- [ ] Does NOT include forbidden fields

**owner_signature:** ______________________
**date_utc:** ______________________
