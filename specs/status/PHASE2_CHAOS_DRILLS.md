# Phase 2 Chaos-Drill Checklist (Contract-Keyed)

> **Related docs:**
> - [README.md](./README.md) — Enforcement layer overview
> - [LOCKED_DECISIONS.md](./LOCKED_DECISIONS.md) — Contract invariants
> - [../ROADMAP.md](../../docs/ROADMAP.md) — Phase 2 acceptance criteria

Phase 2 includes PolicyGuard + TradingMode + OpenPermissionLatch + WS gap detection + reconciliation.

**This checklist is the Phase 2 acceptance gate.** You do not pass Phase 2 unless every drill is executed and the observed `/status` satisfies contract invariants.

---

## Quick Reference: Validation Commands

```bash
# Validate observed /status against schema + manifest
python tools/validate_status.py \
  --file evidence/drill_X/observed_status.json \
  --schema python/schemas/status_csp_min.schema.json \
  --manifest specs/status/status_reason_registries_manifest.json

# Validate against exact schema (for fixtures)
python tools/validate_status.py \
  --file tests/fixtures/status/market_data_stale.json \
  --schema python/schemas/status_csp_exact.schema.json \
  --manifest specs/status/status_reason_registries_manifest.json \
  --strict

# Validate live endpoint
python tools/validate_status.py \
  --url http://127.0.0.1:8080/api/v1/status
```

---

## Evidence Required for Every Drill

Create one directory per drill: `evidence/phase2/drill_N_<name>/`

```
evidence/phase2/drill_1_partial_fill/
├── trigger.md              # What you did to trigger the scenario
├── observed_status.json    # Raw /api/v1/status payload
├── expected_status.json    # Golden fixture or derived expectation
├── diff.txt                # machine diff (jq or json-diff)
├── validation.log          # Output of validate_status.py
├── time_to_safe_ms         # Time from trigger to "OPEN blocked"
└── notes.md                # What was proven, what failed, risks
```

### Evidence Capture Script
```bash
#!/bin/bash
DRILL_NAME="$1"
EVIDENCE_DIR="evidence/phase2/${DRILL_NAME}"
mkdir -p "$EVIDENCE_DIR"

# Capture /status
curl -s http://127.0.0.1:8080/api/v1/status | jq . > "$EVIDENCE_DIR/observed_status.json"

# Validate
python tools/validate_status.py \
  --file "$EVIDENCE_DIR/observed_status.json" \
  2>&1 | tee "$EVIDENCE_DIR/validation.log"

# Diff against expected (if exists)
if [[ -f "$EVIDENCE_DIR/expected_status.json" ]]; then
  diff <(jq -S . "$EVIDENCE_DIR/expected_status.json") \
       <(jq -S . "$EVIDENCE_DIR/observed_status.json") \
       > "$EVIDENCE_DIR/diff.txt" || true
fi

echo "Evidence captured to $EVIDENCE_DIR"
```

---

## Global Pass/Fail Invariants

Every drill must satisfy these invariants. Run `validate_status.py` to check automatically.

| Invariant | Validator Tag | Description |
|-----------|---------------|-------------|
| CSP minimum keys | `[CSP-MIN]` | All 35 required keys present |
| Active ⇒ empty mode_reasons | `[INVARIANT]` | `trading_mode=Active` requires `mode_reasons=[]` |
| Tier purity | `[TIER]` | Kill reasons only with Kill mode; ReduceOnly reasons only with ReduceOnly |
| Tier ordering | `[ORDER]` | mode_reasons order matches manifest order |
| Latch invariants | `[LATCH]` | `latch=true` ⇒ non-empty reason codes + requires_reconcile=true |
| Decision A | `[DECISION-A]` | `latch=true` ⇒ `trading_mode ∈ {ReduceOnly, Kill}` + appropriate mode_reason |
| Capital supremacy | (manual) | Kill must still allow risk-reducing actions if exposure ≠ 0 |

---

## Drill Matrix

### Drill 1 — Mixed/Partial Fill (Legging Risk)

**Trigger:** Force leg A fill, leg B reject (simulate via test harness or exchange sandbox).

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "risk_state": "Degraded",
  "mode_reasons": ["REDUCEONLY_EMERGENCY_REDUCEONLY_ACTIVE", "REDUCEONLY_RISKSTATE_DEGRADED"],
  "open_permission_blocked_latch": false
}
```

**Golden fixture:** `tests/fixtures/status/partial_fill_containment.json`

**Pass criteria:**
- [ ] `trading_mode` = `ReduceOnly`
- [ ] No new OPEN dispatch occurs
- [ ] Containment attempts proceed (hedge/flatten)
- [ ] Exposure monotonically reduces to neutral

---

### Drill 2 — Market Data Stale

**Trigger:** Stop WS market data feed or inject lag > threshold (e.g., 3000ms).

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["WS_DATA_STALE_RECONCILE_REQUIRED"],
  "open_permission_requires_reconcile": true,
  "connectivity_degraded": true,
  "ws_event_lag_ms": 3200
}
```

**Golden fixture:** `tests/fixtures/status/market_data_stale.json`

**Pass criteria:**
- [ ] Latch sets immediately when lag exceeds threshold
- [ ] OPEN blocked
- [ ] Latch clears **only** after reconciliation success
- [ ] `ws_event_lag_ms` reflects actual lag

---

### Drill 3 — WAL Backpressure / Enqueue Failure

**Trigger:** Saturate WAL queue, force enqueue failures.

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "risk_state": "Degraded",
  "mode_reasons": ["REDUCEONLY_RISKSTATE_DEGRADED"],
  "wal_queue_depth": 1024,
  "wal_queue_capacity": 1024,
  "wal_queue_enqueue_failures": 17
}
```

**Golden fixture:** `tests/fixtures/status/wal_backpressure.json`

**Pass criteria:**
- [ ] OPEN fails closed (no "oops trades")
- [ ] `wal_queue_enqueue_failures` increases
- [ ] System continues ticking (no hot-loop stall)
- [ ] ReduceOnly actions still permitted

---

### Drill 4 — Crash + Restart Mid-Flight

**Trigger:** `kill -9` process with inflight intents; restart.

**Expected /status (on startup):**
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["RESTART_RECONCILE_REQUIRED"],
  "open_permission_requires_reconcile": true
}
```

**Golden fixture:** `tests/fixtures/status/restart_reconcile.json`

**Pass criteria:**
- [ ] On startup: latch is set with `RESTART_RECONCILE_REQUIRED`
- [ ] No duplicate dispatch (WAL replay is idempotent)
- [ ] No OPEN before reconciliation completes
- [ ] Latch clears only after reconciliation succeeds

---

### Drill 5 — WS Book Gap

**Trigger:** Inject a changeId gap (prevChangeId mismatch) in order book feed.

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["WS_BOOK_GAP_RECONCILE_REQUIRED"]
}
```

**Pass criteria:**
- [ ] Gap detected within 1 tick
- [ ] Latch sets immediately
- [ ] OPEN blocked until reconciliation clears

---

### Drill 6 — WS Trades Gap

**Trigger:** Inject trade sequence gap (non-monotonic sequence number / timestamp jump).

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["WS_TRADES_GAP_RECONCILE_REQUIRED"]
}
```

**Pass criteria:**
- [ ] Gap detected
- [ ] No duplicate trade processing
- [ ] OPEN blocked until reconcile clears

---

### Drill 7 — Session Termination (10028)

**Trigger:** Force private WS termination / auth invalidation (simulate 10028 or revoke API key).

**Expected /status:**
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED", "REDUCEONLY_RISKSTATE_DEGRADED", "REDUCEONLY_SESSION_KILL_UNCONFIRMED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["SESSION_TERMINATION_RECONCILE_REQUIRED"],
  "10028_count_5m": 1
}
```

**Golden fixture:** `tests/fixtures/status/session_termination.json`

**Pass criteria:**
- [ ] OPEN blocked immediately
- [ ] `10028_count_5m` increments
- [ ] Reconciliation required before resuming

---

### Drill 8 — Unknown Token / Registry Drift (Fail-Closed Proof)

**Trigger A (CI):** Introduce a fake reason token in codegen inputs → CI must fail.

**Trigger B (runtime, optional):** Inject an invalid token from a subsystem.

**Expected fail-closed /status:**
```json
{
  "trading_mode": "Kill",
  "mode_reasons": ["KILL_CORTEX_FORCE_KILL"]
}
```

**Golden fixture:** `tests/fixtures/status/unknown_token_force_kill.json`

**Pass criteria:**
- [ ] System fails closed (Kill mode)
- [ ] Does not resume until rebuilt/redeployed
- [ ] CI blocks the invalid token before it reaches production

---

## Phase 2 Sign-Off Checklist

Phase 2 is complete **only if** all boxes are checked:

- [ ] All 8 drills executed
- [ ] Each drill has evidence folder with all required files
- [ ] `validate_status.py` passes for all observed_status.json files
- [ ] No free-text reason codes (all tokens in manifest)
- [ ] Latch invariants hold in all applicable drills
- [ ] Capital supremacy verified (Kill mode still allows risk-reducing)
- [ ] Owner dashboard passes 5-second rule for each scenario
- [ ] 1-page summary written for each drill (`notes.md`)

**Sign-off statement:**
> All Phase 2 chaos drills have been executed with contract-valid `/status` outputs.
> Evidence packs are stored in `evidence/phase2/`.
> The system correctly transitions to safe states under all tested fault conditions.

Signed: _________________ Date: _____________
