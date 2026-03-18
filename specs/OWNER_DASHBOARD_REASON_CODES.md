# Owner Dashboard Reason Codes (Canonical v1)

This appendix defines **enumerated reason codes** for the Owner Dashboard and `/api/v1/status`.

The goal is **owner-readable, hostile-proof enforcement**:
- Non-technical owner can understand status in seconds.
- Builders cannot hand-wave (“it’s fine”) because **every code has a deterministic unblock condition**.
- **No free-text reasons** are allowed.
- Safety, ops, and governance are separated.

> **Contract rule:** If /status.trading_mode is ReduceOnly or Kill and /status.mode_reasons is empty, or if open-permission is blocked without /status.open_permission_reason_codes, trading must halt immediately (fail closed).

---

## 0) Non‑negotiable principles

1) **No free text reasons**
- `/status.mode_reasons[]` and `/status.open_permission_reason_codes[]` MUST be drawn from this list.
- Any unknown/unmapped code MUST be treated as a schema violation:
  - PolicyGuard MUST fail closed by emitting `EXEC_UNMAPPED_REASON_CODE` and setting TradingMode to Kill.
  - The dashboard MUST surface the violation and instruct fail-closed behavior (it does not set TradingMode).

2) **Every code answers three questions**
- Why is trading restricted?
- Is this expected/benign or dangerous?
- What exact condition unblocks it?

3) **TradingMode is derived**
- PolicyGuard computes TradingMode from contract inputs (not the dashboard).
- Reason codes are derived from contract fields in /status; the dashboard MUST NOT invent or clear codes.

4) **PolicyGuard is the only authority**
- Only the PolicyGuard may publish `/status.trading_mode`, `/status.mode_reasons`, and `/status.open_permission_reason_codes`.
- Subsystems may only *raise* conditions; they may not clear them unless the contract says they can.

5) **Evidence is a hard dependency for creating new risk**
- If evidence is missing, stale, or cannot be written, **OPEN risk is forbidden**.

---

## 1) `/status` schema (minimum contract)

`GET /api/v1/status` MUST return (contract-required fields; dashboard may add extensions):

```json
{
  "schema_version": 1,
  "contract_version": "5.2",
  "trading_mode": "ACTIVE|REDUCE_ONLY|KILL",
  "mode_reasons": ["ModeReasonCode", "..."],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["OpenPermissionReasonCode", "..."],
  "open_permission_requires_reconcile": true,
  "supported_profiles": ["CSP", "GOP", "FULL"],
  "enforced_profile": "CSP|GOP|FULL",
  "deployment_environment": "DEV|STAGING|PAPER|LIVE",
  "primary_reason_code": "ENUM_CODE",
  "since_ts": "RFC3339 timestamp",
  "owner_message": "SHORT_ENUM_DERIVED_MESSAGE",
  "unblock": [
    {
      "code": "ENUM_CODE",
      "type": "AUTO|MANUAL",
      "condition": "MACHINE_CHECKABLE_CONDITION",
      "current": "value",
      "target": "value"
    }
  ],
  "build_id": "git_sha_or_build_hash",
  "config_hash": "sha256_of_runtime_config"
}
```

**Rules**
- `owner_message` is **not free text**; it MUST be derived from the reason code manifest (same message every time).
- `primary_reason_code` is derived from the union of `/status.mode_reasons` and `/status.open_permission_reason_codes` using the manifest precedence rules.
- `mode_reasons` / `open_permission_reason_codes` ordering MUST be deterministic (see precedence rules).
- `since_ts` MUST reflect the timestamp of the highest-severity reason code currently active.
- `deployment_environment` is a dashboard extension (environment state), not a TradingMode.

---

## 2) Precedence, latching, and flapping control

### Source of truth (no parallel reason system)
The owner dashboard reason system is derived from contract fields only:
- `/status.trading_mode`
- `/status.mode_reasons`
- `/status.open_permission_reason_codes`
- intent-level `reject_reason_code`
The dashboard MUST NOT create additional reason sources; it only renders these fields using the manifest mapping.

### Precedence (highest severity wins)
1. **KILL reasons**
2. **REDUCE_ONLY reasons**
3. **ACTIVE**

Within the same severity, order MUST be deterministic:
- The canonical ordering is encoded in the reason code manifest.

### Latching rules (anti-theater)
Some reasons MUST be **latched** (cannot auto-clear):
- Any `EXEC_*` reason that implies correctness breach
- Any `GOV_*` reason that blocks certification / config mismatch
- `RISK_MAX_LOSS_REACHED`

Latched reasons require explicit manual acknowledgement via a **recorded approval/reset** (artifact), not merely “condition looks okay now.”

### Debounce / hysteresis (anti-flapping)
Any auto-clear reason MUST remain clear for a minimum window before clearing (e.g., 30–60s) to prevent mode flapping.

---

## 3) Canonical reason codes

### 3.1 Execution & Correctness (highest priority)
These mean something fundamental broke. Owner mental model: **“The system protected me from a bug.”**

| Code | Meaning (plain English) | Default TradingMode | Unblock Condition (deterministic) | Latched |
|---|---|---:|---|---:|
| EXEC_DUPLICATE_INTENT_DETECTED | Duplicate order attempt detected | KILL | Incident record + clean restart + WAL replay proves no duplicate dispatch | ✅ |
| EXEC_ORDER_INVARIANT_VIOLATION | Mechanical invariant failed (size/units/determinism) | KILL | Fix merged + new build certified + invariant test passes | ✅ |
| EXEC_WAL_WRITE_FAILED | Intent ledger could not persist safely | REDUCE_ONLY | WAL health=OK AND last N writes succeeded | ✅ |
| EXEC_UNCLASSIFIED_ORDER | Order could not be classified safely | KILL | Classification fix + tests pass | ✅ |
| EXEC_ILLEGAL_ORDER_BLOCKED | Forbidden order type attempted | REDUCE_ONLY | Config/strategy corrected + preflight tests pass | ❌ |
| EXEC_UNMAPPED_REASON_CODE | A reason code was emitted but not in manifest | KILL | Manifest + code aligned + redeploy | ✅ |

> **Important:** `REDUCE_ONLY` is only allowed here if it is mechanically impossible to flip exposure (exchange-level reduce-only, or hard invariant `reduce_qty <= current_position`).

---

### 3.2 Risk containment & exposure
These mean the system is actively preserving capital. Owner mental model: **“Self-preservation mode.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| RISK_PARTIAL_FILL_CONTAINMENT | One leg filled, others didn’t | REDUCE_ONLY | Exposure flattened/hedged and verified by reconciliation | ❌ |
| RISK_MAX_LOSS_REACHED | Daily loss limit hit | KILL | Manual reset after recorded review (artifact) | ✅ |
| RISK_POSITION_LIMIT_REACHED | Hard position limit exceeded | REDUCE_ONLY | Exposure reduced below limit and reconciled | ❌ |
| RISK_MARGIN_PRESSURE | Margin utilization too high | REDUCE_ONLY | Margin returns to safe band for T minutes | ❌ |
| RISK_EMERGENCY_CLOSE_ACTIVE | Emergency close algorithm running | REDUCE_ONLY | Close completes successfully + reconciled | ❌ |

---

### 3.3 Data, evidence & observability
If evidence is missing, new risk is forbidden. Owner mental model: **“We are blind; therefore we don’t trade.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| DATA_MARKET_FEED_STALE | Required market data is stale | REDUCE_ONLY | Data age <= threshold for T seconds | ❌ |
| DATA_PRICE_SNAPSHOT_MISSING | Decision snapshot could not be recorded | REDUCE_ONLY | Snapshot pipeline healthy + write succeeds | ❌ |
| DATA_TRUTH_CAPSULE_FAILED | Evidence write failed | REDUCE_ONLY | Evidence writer healthy + write succeeds | ❌ |
| DATA_SNAPSHOT_COVERAGE_LOW | Replay snapshot coverage below threshold | REDUCE_ONLY | Coverage >= threshold on defined scenarios | ✅ |
| DATA_TIME_DRIFT_EXCEEDED | Clock drift outside tolerance | REDUCE_ONLY | Time sync restored + drift within tolerance for T minutes | ❌ |

---

### 3.4 External environment (exchange / network)
Not your fault, still dangerous. Owner mental model: **“Outside world is unreliable.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| EXT_RATE_LIMITED | Exchange rate-limited requests | REDUCE_ONLY | Backoff window elapsed + success rate recovers | ❌ |
| EXT_SESSION_TERMINATED | Exchange killed session | KILL | Re-auth + full reconciliation succeeds | ✅ |
| EXT_WEBSOCKET_GAP | Missed exchange events | REDUCE_ONLY | Full reconcile succeeds + gap cleared | ❌ |
| EXT_EXCHANGE_MAINTENANCE | Exchange in maintenance | REDUCE_ONLY | Maintenance ends + connectivity healthy | ❌ |
| EXT_CONNECTIVITY_LOSS | Network connectivity lost | KILL | Connectivity restored + reconciliation succeeds | ✅ |

---

### 3.5 Ops / platform integrity (internal infra)
These prevent silent degradation. Owner mental model: **“Infra is becoming unsafe.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| OPS_DISK_WATERMARK_HIGH | Disk watermark exceeded (risk of evidence loss) | REDUCE_ONLY | Disk usage below safe watermark and retention verified | ❌ |
| OPS_EVIDENCE_QUEUE_SATURATED | Evidence queue/backpressure (risk of blind trading) | REDUCE_ONLY | Queue depth below threshold for T minutes | ❌ |

---

### 3.6 Security & identity
These prevent credential-driven catastrophic errors. Owner mental model: **“Keys/permissions are unsafe.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| SEC_API_KEY_SCOPE_INVALID | API key permissions exceed policy | KILL | Keys rotated/scoped + probe proves least privilege | ✅ |
| SEC_API_KEY_REVOKED | Key revoked/invalid | KILL | Keys rotated + auth succeeds + reconciliation passes | ✅ |

---

### 3.7 Governance & approvals (Phase 4+)
These prevent unsafe evolution, not bad trades. Owner mental model: **“Waiting for proof or permission.”**

| Code | Meaning | Default TradingMode | Unblock Condition | Latched |
|---|---|---:|---|---:|
| GOV_REPLAY_NOT_CERTIFIED | Replay gate failed | REDUCE_ONLY | Replay passes (defined scenarios) | ✅ |
| GOV_CANARY_FAILED | Canary deployment failed | REDUCE_ONLY | Rollback + review artifact produced | ✅ |
| GOV_APPROVAL_REQUIRED | Human approval missing | REDUCE_ONLY | Approval recorded (artifact) | ✅ |
| GOV_CONFIG_MISMATCH | Runtime config differs from certified config | KILL | Config aligned + certified build deployed | ✅ |
| GOV_CERT_EXPIRED | Certification expired | REDUCE_ONLY | Re-certify + deploy certified build | ✅ |

---

### 3.8 Expected / benign states (panic prevention)
These exist to prevent false alarms.

| Code | Meaning | TradingMode |
|---|---|---:|
| STATE_STARTUP_RECONCILING | Startup reconciliation in progress | REDUCE_ONLY |
| STATE_PAPER_MODE | Paper trading only (deployment_environment=PAPER) | ACTIVE |
| STATE_MICRO_LIVE | Micro-live caps enforced (deployment_environment=LIVE) | ACTIVE |
| STATE_IDLE | No signals, but healthy | ACTIVE |

---

## 4) Owner acceptance tests (non‑negotiable)

1) **5‑Second Rule**
- Owner can explain why trading is restricted in ≤5 seconds without an engineer.

2) **Deterministic Unblock**
- For any code: “What exact condition clears this?”
- If the answer is vague: fail.

3) **No free text**
- If any dashboard element or API uses free text as the reason: fail.

4) **Chaos drill visibility**
- Trigger: partial fill, stale data, replay failure.
- Verify: correct reason code + correct TradingMode + immediate visibility.

5) **Unknown code fail‑closed**
- Emit an unknown code intentionally.
- Verify: PolicyGuard enters KILL with `EXEC_UNMAPPED_REASON_CODE`.

---

## 5) Builder-proof implementation requirement (single source of truth)

The code list MUST live in a single manifest file (JSON/YAML) in-repo and be used by:
- backend (PolicyGuard)
- dashboard
- tests

If the dashboard shows a code not in the manifest, acceptance fails.
The manifest is the single source of truth for the code list, ordering (precedence), and owner_message.
