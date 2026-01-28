# Locked Decisions: /status Contract Semantics

These decisions are **locked** — they define how the contract interprets `/status` fields.
Changing them requires contract version bump, schema updates, and full chaos drill re-certification.

---

## Decision A: Latch ⇒ ¬Active + REDUCEONLY_OPEN_PERMISSION_LATCHED

### Rule
```
open_permission_blocked_latch == true
  ⇒ trading_mode ∈ {ReduceOnly, Kill}  (never Active)
  ⇒ if trading_mode == ReduceOnly:
       mode_reasons MUST contain "REDUCEONLY_OPEN_PERMISSION_LATCHED"
```

### Why This Exists
Without this rule, a system could claim `trading_mode=Active` while secretly blocking all OPEN intents via the latch. This creates a **truth fork**: the dashboard says "Active" but the system refuses to trade.

This decision closes that gap:
- If the latch is set, trading mode **must** reflect it
- Owners see `ReduceOnly` and know OPEN is blocked
- No hidden state

### What Breaks Without It
- Dashboard shows "Active" while all orders are rejected
- Owner assumes system is trading when it's not
- Incident response is delayed because the lie persists

### Enforcement
- `tools/validate_status.py` checks this (tag: `[DECISION-A]`)
- CI fails if latch=true with trading_mode=Active
- CI fails if latch=true with ReduceOnly but missing REDUCEONLY_OPEN_PERMISSION_LATCHED

---

## Decision B: CSP Minimum Keys Are Mandatory

### Rule
```
Every /status response MUST contain all 35 CSP minimum keys.
Golden fixtures MUST be a superset of CSP_MINIMUM_KEYS.
```

### Why This Exists
Omission is a lie. If a field is missing, the system can hide unsafe conditions by simply not reporting them.

Examples of what omission enables:
- Hide disk pressure by not reporting `disk_used_pct`
- Hide WAL failures by not reporting `wal_queue_enqueue_failures`
- Hide rate limiting by not reporting `429_count_5m`

### What Breaks Without It
- "Simplified" status responses that omit inconvenient fields
- Fixtures that pass validation but don't represent real /status shape
- Production systems that diverge from fixtures

### Enforcement
- `tools/validate_status.py` checks CSP minimum keys (tag: `[CSP-MIN]`)
- Keys are hardcoded in validator (not loaded from external file)
- Schema also enforces via `required` array

---

## Decision C: ModeReasonCode vs OpenPermissionReasonCode Separation

### Rule
```
mode_reasons      → Why trading_mode is ReduceOnly/Kill
open_permission_reason_codes → Why OPEN specifically is blocked (latch reasons)
```

For latch scenarios (restart, WS gap, data stale):
```json
{
  "trading_mode": "ReduceOnly",
  "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
  "open_permission_blocked_latch": true,
  "open_permission_reason_codes": ["RESTART_RECONCILE_REQUIRED"]
}
```

### Why This Exists
These are **different questions**:
1. "Why can't I create new risk?" → `mode_reasons`
2. "Why is OPEN specifically blocked?" → `open_permission_reason_codes`

Conflating them creates ambiguity:
- Is OPEN blocked because of a Kill condition? Or a latch?
- Can I still do reduce-only actions? Depends on which one.

The latch blocks OPEN but allows reduce-only. Kill blocks everything. These need different signals.

### What Breaks Without It
- UI can't distinguish "need to reconcile" from "system is dead"
- Operators don't know if they can still flatten positions
- Incident playbooks become ambiguous

### Enforcement
- Schema enforces that latch=true requires non-empty `open_permission_reason_codes`
- Validator checks enum membership in manifest registries
- Tier purity ensures mode_reasons match trading_mode tier

---

## Decision D: owner_view Is Strictly Derived

### Rule
```
owner_view:
  - MUST NOT introduce new authority
  - MUST NOT contradict trading_mode, mode_reasons, or latch state
  - MUST be schema-locked (only allowed keys: primary_owner_reason_code, owner_message, unblock)
  - Is display-only; UI MUST hard-fail on inconsistency
```

### Why This Exists
Free-text explanations are a trust hazard. If `owner_view.owner_message` can say anything, it becomes a vector for:
- Misleading owners about system state
- Contradicting contract fields
- Introducing informal authority ("the message said it was safe")

By making `owner_view` strictly derived and schema-locked:
- It can only explain what contract fields already show
- It cannot introduce new information
- UI can trust contract fields and treat owner_view as cosmetic

### What Breaks Without It
- `owner_message` says "system healthy" while `trading_mode=Kill`
- Engineers add `owner_view.custom_field` that determines behavior
- Dashboard trusts owner_view over contract fields

### Enforcement
- Schema locks `owner_view` to exactly 3 keys
- Validator checks owner_view is object (if present)
- UI contract (OWNER_DASHBOARD_REASON_CODES.md) mandates fail-closed on inconsistency

---

## Cross-References

| Decision | Enforced By | Schema Rule | Validator Tag |
|----------|-------------|-------------|---------------|
| A | `validate_status.py` | `allOf` conditional | `[DECISION-A]` |
| B | `validate_status.py` | `required` array | `[CSP-MIN]` |
| C | Schema + validator | Separate arrays | `[LATCH]`, `[TIER]` |
| D | Schema | `additionalProperties: false` on owner_view | `[SCHEMA]` |

---

## How to Change a Locked Decision

1. Write a proposal explaining why the current decision is wrong
2. Get explicit approval from contract owner
3. Bump `contract_version` in manifest and schemas
4. Update all fixtures
5. Update validator
6. Re-run all chaos drills
7. Update this document

Do not skip steps. CI will catch you.
