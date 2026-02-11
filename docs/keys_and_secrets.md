# Keys & Secrets Policy (Phase 0)

> **Purpose:** Prevent the #1 real-world failure: bad key hygiene (scope leaks, withdrawals enabled, keys used in wrong env).
> This is an operational contract, not advice.

## Metadata
- doc_id: KEYS-001
- version: 1.1
- contract_version_target: 5.2
- last_updated_utc: 2026-02-09T23:30:00Z

---

## Principles (non-negotiable)

- Least privilege for every key
- Withdrawals disabled for all keys
- Separate keys per environment (DEV/STAGING/PAPER/LIVE) where keys exist
- PAPER MUST NOT have any trade-capable keys
- BREAK_GLASS_MANUAL keys are human-only and MUST NOT be accessible to bot runtime
- Key naming conventions are not enforcement; runtime MUST verify account/subaccount identity
- Rotation is planned and practiced
- Secrets never stored in repo

---

## Key Types & Required Scopes

| Key Purpose | Required Scopes | Forbidden Scopes |
|-------------|-----------------|------------------|
| DATA_ONLY (PAPER optional) | read_market_data (read_account optional) | trade, withdraw, transfer |
| TRADE_TESTNET (STAGING only) | read_account, trade | withdraw, transfer |
| TRADE_LIVE (LIVE only) | read_account, trade | withdraw, transfer |
| BREAK_GLASS_MANUAL (human only, optional) | cancel_all (and read_account only if exchange requires) | withdraw, transfer; MUST NOT be mounted into bot runtime |

**Forbidden scopes (always):**
- [x] withdraw
- [x] transfer

---

## Key Naming Convention

```
key_{environment}_{purpose}_{sequence}
```

Examples:
- `key_staging_trade_001`
- `key_paper_data_001`
- `key_live_trade_001`
- `key_live_readonly_001`
- `key_breakglass_manual_001`

Naming is for hygiene only; runtime identity checks are authoritative.

---

## Storage & Access

| Question | Answer |
|----------|--------|
| Secret storage system | HashiCorp Vault (LIVE), `.env` files (STAGING testnet only), PAPER public endpoints preferred |
| Who can read LIVE secrets | Ops team only, via IAM role |
| How devs get DEV secrets | N/A (mocked) |
| How secrets injected at runtime | Environment variables from Vault/dotenv (STAGING only) |
| Live fallback to local files | Forbidden |
| Local `.env` constraints | MUST be non-withdraw, non-transfer, and MUST NOT contain LIVE trade keys |
| What must never appear in logs | Key secrets, passphrases, Vault tokens |

---

## Runtime Identity Enforcement (required)

For any environment that has a private key loaded:
- On startup, call a private identity endpoint (for example, account summary).
- Assert returned account/subaccount matches `docs/env_matrix.md` for `TRADING_ENV`.
- Any mismatch MUST fail closed (no dispatch).

Additional fail-closed rules:
- `TRADING_ENV=LIVE` without Vault credentials -> fail closed.
- `TRADING_ENV=PAPER` with any trade-capable key present -> fail closed.

---

## Rotation Plan (mechanical)

| Key Type | Rotation Cadence | Owner |
|----------|------------------|-------|
| TRADE_TESTNET (STAGING) | Quarterly | DevOps |
| DATA_ONLY (PAPER, if used) | Quarterly | DevOps |
| TRADE_LIVE (LIVE) | Monthly | Security + DevOps |

### Rotation Steps (LIVE/STAGING trade keys)

1. Create new key on exchange (withdraw disabled)
2. Add new key to secret store
3. Deploy/runtime reload using new key reference
4. Run key scope probe to verify permissions
5. Run startup identity check and confirm account/subaccount match
6. Revoke old key on exchange
7. Remove old key from secret store

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
3. Run break-glass runbook steps if active positions
4. Record incident in `evidence/incidents/`
5. Conduct postmortem within 24 hours

---

## Key Inventory

| Key ID | Environment | Key Type | Scopes | Withdraw | Created | Last Rotated | Next Rotation |
|--------|-------------|----------|--------|----------|---------|--------------|---------------|
| key_staging_trade_001 | STAGING | TRADE_TESTNET | read, trade | **false** | 2026-02-09 | 2026-02-09 | 2026-03-09 |
| N/A (public endpoints only) | PAPER | NONE | public_market_data_only | N/A | N/A | N/A | N/A |
| key_live_trade_001 | LIVE | TRADE_LIVE | read, trade | **false** | 2026-02-09 | 2026-02-09 | 2026-03-09 |
| key_live_readonly_001 | LIVE | DATA_ONLY | read_market_data, read_account | **false** | 2026-02-09 | 2026-02-09 | 2026-03-09 |
| key_breakglass_manual_001 | MANUAL | BREAK_GLASS_MANUAL | cancel_all | **false** | 2026-02-09 | 2026-02-09 | 2026-03-09 |

---

## Key Scope Probe (required Phase 0 evidence)

Generate `evidence/phase0/keys/key_scope_probe.json` for each environment that uses a real key.

Expected by environment:
- DEV: none (mocked)
- PAPER: none (preferred) or DATA_ONLY only
- STAGING: TRADE_TESTNET
- LIVE: TRADE_LIVE (and optional LIVE DATA_ONLY)

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
- [x] PAPER with trade-capable keys
- [x] BREAK_GLASS_MANUAL key mounted into runtime
- [x] Treating key names/prefixes as the sole environment control

---

## Owner Sign-Off

- [x] PAPER has no trade-capable credentials
- [x] LIVE keys are unavailable to local/dev environments
- [x] Startup identity check is implemented and fail-closed
- [x] BREAK_GLASS_MANUAL key is runtime-inaccessible
- [x] Rotation plan documented and scheduled
- [x] No secrets in repository

**owner_signature:** admin
**date_utc:** 2026-02-11
