# Keys & Secrets Policy (Phase 0)

> **Purpose:** Prevent the #1 real-world failure: bad key hygiene (scope leaks, withdrawals enabled, keys used in wrong env).
> This is an operational contract, not advice.

## Metadata
- doc_id: KEYS-001
- version: 1.0
- contract_version_target: 5.2
- last_updated_utc: 2026-01-27T14:00:00Z

---

## Principles (non-negotiable)

- Least privilege for every key
- Withdrawals disabled for all keys
- Separate keys per environment (DEV/STAGING/PAPER/LIVE)
- Rotation is planned and practiced
- Secrets never stored in repo

---

## Key Types & Required Scopes

| Key Purpose | Required Scopes | Forbidden Scopes |
|-------------|-----------------|------------------|
| DATA_ONLY | read_market_data, read_account | trade, withdraw, transfer |
| TRADE (any env) | read_account, trade | withdraw, transfer |
| ADMIN (emergency) | read_account, trade, cancel_all | withdraw, transfer |

**Forbidden scopes (always):**
- [x] withdraw
- [x] transfer
- [x] admin (except emergency key)

---

## Key Naming Convention

```
key_{environment}_{purpose}_{sequence}
```

Examples:
- `key_staging_trade_001`
- `key_paper_trade_001`
- `key_live_trade_001`
- `key_live_readonly_001`

---

## Storage & Access

| Question | Answer |
|----------|--------|
| Secret storage system | HashiCorp Vault (LIVE), .env files (non-LIVE) |
| Who can read LIVE secrets | Ops team only, via IAM role |
| How devs get DEV secrets | N/A (mocked) |
| How secrets injected at runtime | Environment variables from Vault/dotenv |
| What must never appear in logs | Key secrets, passphrases, Vault tokens |

---

## Rotation Plan (mechanical)

| Key Type | Rotation Cadence | Owner |
|----------|------------------|-------|
| STAGING | Quarterly | DevOps |
| PAPER | Quarterly | DevOps |
| LIVE | Monthly | Security + DevOps |

### Rotation Steps (LIVE)

1. Create new key on exchange (withdraw disabled)
2. Add new key to Vault with new version
3. Deploy using new key reference
4. Run key scope probe to verify permissions
5. Verify trading works with new key
6. Revoke old key on exchange
7. Remove old key from Vault

### Emergency Rotation Triggers

- Key compromise suspected
- Unauthorized access detected
- Employee departure with key access
- Exchange security advisory

---

## Leak Response (fail-safe)

If you suspect compromise:

1. **Immediately** revoke key on exchange
2. Rotate all potentially affected secrets
3. Run break-glass drill steps if active positions
4. Record incident in `evidence/incidents/`
5. Conduct postmortem within 24 hours

---

## Key Inventory

| Key ID | Environment | Scopes | Withdraw | Created | Last Rotated | Next Rotation |
|--------|-------------|--------|----------|---------|--------------|---------------|
| key_staging_trade_001 | STAGING | read, trade | **false** | [DATE] | [DATE] | [DATE] |
| key_paper_trade_001 | PAPER | read, trade | **false** | [DATE] | [DATE] | [DATE] |
| key_live_trade_001 | LIVE | read, trade | **false** | [DATE] | [DATE] | [DATE] |
| key_live_readonly_001 | LIVE | read | **false** | [DATE] | [DATE] | [DATE] |

---

## Key Scope Probe (required Phase 0 evidence)

You MUST generate `evidence/phase0/keys/key_scope_probe.json` for each environment.

**Minimum JSON fields:**
- `env`
- `exchange`
- `key_id` (redacted ok)
- `scopes` (list)
- `withdraw_enabled` (bool)
- `timestamp_utc`
- `operator`

---

## Forbidden (always)

- [x] Withdrawals enabled on any automated trading key
- [x] Storing secrets in git (even encrypted)
- [x] Sharing keys across environments
- [x] Logging key secrets
- [x] Hardcoding secrets in source code

---

## Owner Sign-Off

- [ ] All keys follow least-privilege principle
- [ ] Withdrawals disabled on ALL automated trading keys
- [ ] Rotation plan documented and scheduled
- [ ] LIVE keys protected from local access
- [ ] No secrets in repository

**owner_signature:** ______________________
**date_utc:** ______________________
