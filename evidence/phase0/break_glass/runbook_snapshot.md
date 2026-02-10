# Snapshot — docs/break_glass_runbook.md (Phase 0)

Snapshot taken at sign-off.
- date_utc: 2026-02-10T02:20:00Z
- source_path: docs/break_glass_runbook.md
- version: 1.1

---

# Break-Glass Runbook (Phase 0)

> **Purpose:** One-page steps to stop new risk immediately and safely.
> Phase 0 is NOT DONE until a drill is executed and recorded.

## Metadata
- doc_id: BG-001
- version: 1.1
- contract_version_target: 5.2
- last_updated_utc: 2026-02-10T02:00:00Z

---

## When to Trigger Break-Glass

- Suspected runaway order loop
- Unexpected live orders appearing
- Exchange session termination / auth problems
- Cannot verify what is live at the venue
- Key compromise suspected
- Unexplained P&L movement
- System behaving unexpectedly

---

## Immediate Actions (STOP NEW RISK)

### Method A — Kill Switch (preferred)

**Step 1: Execute kill command**
```bash
./stoic-cli emergency kill --reason "description of issue"
```

**Step 2: Confirm KILL mode active**
```bash
./stoic-cli status
# Must show: trading_mode: KILL
```

**Step 3: Confirm no further orders**
```bash
./stoic-cli orders --pending
# Must show: 0 pending orders
```

### Method B — Disable Credentials (backup)

Use if CLI is unavailable or unresponsive:

**Step 1: Revoke key on exchange**
- Log into Deribit dashboard
- Navigate to API Keys
- Disable/delete the trading key

**Step 2: Confirm API auth fails**
```bash
./stoic-cli health
# Should show policy/config/auth error and exit non-zero
```

**Step 3: Manually cancel orders on exchange UI**
- Use exchange "Cancel All" if available

---

## Verification (prove "no new OPEN risk")

After triggering break-glass, verify:

| Check | Command | Expected Result |
|-------|---------|-----------------|
| No pending orders | `./stoic-cli orders --pending` | Empty list |
| No orders in flight | `./stoic-cli status --detailed` | orders_in_flight: 0 |
| Mode is KILL | `./stoic-cli status` | trading_mode: KILL |

---

## If Exposure Exists (risk reduction allowed)

Even in emergency, we must be able to reduce risk:

**Step 1: Switch to REDUCE_ONLY mode**
```bash
./stoic-cli emergency reduce-only --reason "reducing exposure after incident"
```

**Step 2: Verify close orders work**
```bash
STOIC_DRILL_MODE=1 ./stoic-cli simulate-close --instrument <INSTRUMENT> --dry-run
# Should show: ACCEPTED
```

**Step 3: Execute risk reduction (Phase 0 scope)**
- Use the venue/exchange close workflow or your strategy's explicit risk-reducing path.
- `stoic-cli` in Phase 0 provides dry-run verification (`simulate-close`) only.
- Guardrail: `simulate-*` commands are drill-only and require `STOIC_DRILL_MODE=1`.

**Step 4: Restore KILL mode after reduction**
```bash
./stoic-cli emergency kill --reason "exposure reduced, restoring kill"
```

---

## Escalation / Contacts

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| Primary On-Call | [FILL] | [FILL] | @[FILL] |
| Secondary On-Call | [FILL] | [FILL] | @[FILL] |
| Engineering Lead | [FILL] | [FILL] | @[FILL] |
| Operations Lead | [FILL] | [FILL] | @[FILL] |

### Severity Levels

| Level | Criteria | Notification |
|-------|----------|--------------|
| P1 - Critical | Uncontrolled losses, system compromised | Phone call immediately |
| P2 - High | KILL triggered, unknown cause | Slack + email within 5 min |
| P3 - Medium | Unusual behavior, contained | Slack within 30 min |

### What to Capture

- Timestamps (UTC) of all actions
- Screenshots of exchange state
- Log excerpts from system/venue logs for the incident window
- Current positions and orders

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────┐
│           EMERGENCY QUICK REFERENCE             │
├─────────────────────────────────────────────────┤
│ STOP ALL TRADING (Method A):                    │
│   ./stoic-cli emergency kill --reason "..."     │
│                                                 │
│ VERIFY STOPPED:                                 │
│   ./stoic-cli status                            │
│   ./stoic-cli orders --pending                  │
│                                                 │
│ IF CLI BROKEN (Method B):                       │
│   1. Revoke key on exchange dashboard           │
│   2. Cancel all orders on exchange UI           │
│                                                 │
│ REDUCE EXPOSURE:                                │
│   ./stoic-cli emergency reduce-only             │
│   STOIC_DRILL_MODE=1 ./stoic-cli simulate-close --instrument X --dry-run │
│                                                 │
│ ESCALATE:                                       │
│   P1: Call [PRIMARY PHONE]                      │
│   P2+: Slack #trading-incidents                 │
└─────────────────────────────────────────────────┘
```

---

## Phase 0 Drill (required)

Required evidence files:
- `evidence/phase0/break_glass/drill.md`
- `evidence/phase0/break_glass/log_excerpt.txt`
- `evidence/phase0/break_glass/runbook_snapshot.md`

Drill must include:
- Trigger scenario
- Time to halt
- Proof that OPEN dispatch stopped
- Verification that REDUCE_ONLY still works
- Gaps found + follow-ups

---

## Forbidden (always)

- [x] Continuing to trade while investigating incident
- [x] Bypassing kill switch "just to close one position"
- [x] Delaying escalation to "figure it out first"
- [x] Modifying code during active incident

---

## Owner Sign-Off

- [ ] All operators trained on this runbook
- [ ] Kill switch tested in STAGING
- [ ] Contact list verified current
- [ ] Escalation path tested
- [ ] Method A and Method B both documented

**owner_signature:** ______________________
**date_utc:** ______________________
