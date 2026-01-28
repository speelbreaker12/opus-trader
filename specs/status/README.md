# Enforcement Layer: `/status` as a Contract-Controlled Safety Surface

## TL;DR (Read This First)

This repository contains a **non-negotiable enforcement layer** that makes the
system's safety state **machine-checkable, owner-readable, and contract-bound**.

If you are here to:
- "simplify" `/status`
- add "just one more field"
- change a reason code name
- make the dashboard "more flexible"

**Stop.**
This layer exists to prevent exactly that.

---

## What This Layer Is

This enforcement layer turns `/status` from a convenience endpoint into a
**contractually enforced control surface**.

It guarantees that:
- The system cannot hide unsafe states by omission.
- Trading modes cannot be reinterpreted informally.
- Owners can understand system safety in seconds.
- CI will fail **before** unsafe changes reach production.

This is **not optional infrastructure**.
It is equivalent to a type system for operational safety.

---

## What Problem This Solves (Concrete)

Without this layer, a system can:
- Pass demos while omitting critical safety fields
- Be "Active" while silently blocking trades
- Change the meaning of states without version bumps
- Tell owners one thing while doing another

This layer closes those failure modes mechanically.

---

## Core Design Principles

### 1. `/status` Is Authoritative Truth
- Logs are not authoritative.
- Dashboards are not authoritative.
- `/status` is the single source of truth for safety state.

### 2. Omission Is a Failure
If a required field is missing:
- CI fails
- Phase acceptance fails
- The system is considered non-compliant

### 3. No Free Text Authority
Human-readable explanations are allowed **only** as derived views.
They may never determine behavior.

### 4. Contract Beats Code
If code "works" but violates this layer:
- The code is wrong.
- Fix the code.

---

## Directory Structure (Canonical)

```
specs/status/                          # Specs and manifest (this directory)
├── README.md                          # This file
├── LOCKED_DECISIONS.md                # Contract-locked semantic decisions
├── status_reason_registries_manifest.json
├── OWNER_DASHBOARD_REASON_CODES.md
├── PHASE2_CHAOS_DRILLS.md
└── STATUS_JSON_EXAMPLES.md

python/schemas/                        # JSONSchema definitions
├── status_csp_min.schema.json
└── status_csp_exact.schema.json

tests/fixtures/status/                 # Golden fixtures
├── partial_fill_containment.json
├── market_data_stale.json
├── wal_backpressure.json
├── session_termination.json
└── unknown_token_force_kill.json

tools/
└── validate_status.py                 # CLI validator
```

If you add or remove files here, **update this README**.

---

## Key Files (What They Do)

### `status_reason_registries_manifest.json`
Single source of truth for:
- `TradingMode` enum: `Active`, `ReduceOnly`, `Kill`
- `DeploymentEnvironment` enum: `DEV`, `STAGING`, `PAPER`, `LIVE`
- `ModeReasonCode` by tier (Kill, ReduceOnly)
- `OpenPermissionReasonCode` for latch states
- `RejectReasonCode` for intent-level rejections
- `OwnerStateCode` for dashboard display
- Display strings for owner-readable messages
- Ordering/precedence rules

If you change a reason code:
1. Update this manifest
2. Regenerate schemas (if using codegen)
3. Update fixtures
4. Update tests

Skipping any step is a contract violation.

---

### `python/schemas/status_csp_min.schema.json`
JSONSchema for **runtime `/status` validation**.

- Enforces:
  - required keys (35 CSP-minimum fields)
  - enums for `trading_mode`, `risk_state`, `f1_cert_state`
  - latch semantics (`latch=true` ⇒ `requires_reconcile=true`)
  - tier-pure `mode_reasons`
  - certificate nullability rules
- **Allows extra fields** so runtime can evolve

Used in:
- CI
- Runtime assertions (optional)

---

### `python/schemas/status_csp_exact.schema.json`
JSONSchema for **golden fixtures only**.

- Same rules as `status_csp_min`
- **No extra fields allowed** (`additionalProperties: false`)

Purpose:
- Keeps fixtures boring and diffable
- Prevents fixture drift

Never use this for runtime validation.

---

### `tests/fixtures/status/*.json`
**Golden `/status` outputs** for known scenarios.

Used to:
- Diff actual vs expected output during chaos drills
- Prove semantics did not drift
- Validate schema correctness

Fixtures must:
- Validate against `status_csp_exact.schema.json`
- Include **all** CSP minimum keys
- Use only manifest enums

Current fixtures:
| File | Scenario |
|------|----------|
| `partial_fill_containment.json` | Leg A fills, leg B rejects → ReduceOnly |
| `market_data_stale.json` | WS feed stale → latch + ReduceOnly |
| `wal_backpressure.json` | Intent ledger saturated → ReduceOnly |
| `restart_reconcile.json` | System restart → latch + reconcile required |
| `session_termination.json` | 10028 session kill → latch + ReduceOnly |
| `unknown_token_force_kill.json` | Registry drift → Kill (fail-closed) |

---

### `tools/validate_status.py`
CLI validator that enforces:
- JSONSchema validation (Draft 2020-12)
- Contract version binding
- Tier purity and ordering
- Latch invariants
- Manifest membership

Usage:
```bash
# Validate a fixture
python tools/validate_status.py \
  --file tests/fixtures/status/market_data_stale.json \
  --schema python/schemas/status_csp_exact.schema.json \
  --manifest specs/status/status_reason_registries_manifest.json

# Validate live /status
python tools/validate_status.py \
  --url http://127.0.0.1:8080/api/v1/status \
  --schema python/schemas/status_csp_min.schema.json \
  --manifest specs/status/status_reason_registries_manifest.json
```

Exit codes:
- `0` = OK
- `1` = Validation failed
- `2` = Setup error (missing files, bad args)

---

## CI Enforcement

CI runs status validation via `plans/verify.sh` section `0d)`:

1. **Drift guard**: Fails if canonical files are missing
2. **Fixture validation**: Each fixture must pass exact schema + manifest checks

To run locally:
```bash
pip install jsonschema
./plans/verify.sh quick
```

---

## Owner View (`owner_view`)

`owner_view` exists to make the system understandable, **not controllable**.

Rules:
- Display-only
- Derived from contract fields
- Schema-locked (no extra keys)
- Must never contradict `trading_mode`, `mode_reasons`, or latch state

Structure:
```json
{
  "owner_view": {
    "primary_owner_reason_code": "DATA_MARKET_FEED_STALE",
    "owner_message": "Market data is stale; new OPEN risk is blocked.",
    "unblock": [
      {
        "type": "AUTO",
        "condition": "ws_event_lag_ms <= 500 for >= 60s",
        "current": "ws_event_lag_ms=3200",
        "target": "ws_event_lag_ms<=500"
      }
    ]
  }
}
```

If `owner_view` and contract fields disagree:
- The UI must fail closed.

---

## What You Must NOT Do

- ❌ Do not add free-text explanations outside `owner_view`
- ❌ Do not infer permissions in the UI
- ❌ Do not rename reason codes casually
- ❌ Do not remove fields "to simplify"
- ❌ Do not treat `/status` as a debugging aid
- ❌ Do not bypass the manifest by hardcoding enums

---

## How to Change This Layer Safely

If you genuinely need to change something:

1. Update `specs/status/status_reason_registries_manifest.json`
2. Update schemas in `python/schemas/` (or regenerate if using codegen)
3. Update fixtures in `tests/fixtures/status/`
4. Run `tools/validate_status.py` on all fixtures
5. Bump `schema_version` or `contract_version` if required
6. Run chaos drills per `PHASE2_CHAOS_DRILLS.md`
7. Get explicit approval

If you skip steps, CI will (and should) fail.

---

## Why This Is Strict (Read Before Complaining)

This system trades real money under uncertainty.

Most failures in such systems are not algorithmic —
they are **interpretation failures**.

This enforcement layer exists so:
- The system cannot lie accidentally
- Engineers cannot reinterpret safety casually
- Owners are never blind

If this feels "heavy," that's because safety is heavy.

---

## Final Rule

If the system state cannot be explained **in under 5 seconds** by reading `/status`,
the system is considered unsafe — regardless of performance.

This README is part of the contract.

Do not weaken it.
