# Snapshot — docs/env_matrix.md (Phase 0)

Snapshot taken at sign-off.
- date_utc: 2026-01-27T14:00:00Z
- source_path: docs/env_matrix.md
- version: 1.0

---

# Environment Isolation Matrix (Phase 0)

> **Purpose:** Make it mechanically obvious which accounts/keys belong to which environment.
> No key reuse. No ambiguity. If it's not in this table, it's forbidden.

## Metadata
- doc_id: ENV-001
- version: 1.0
- contract_version_target: 5.2
- last_updated_utc: 2026-01-27T14:00:00Z

---

## Invariants (non-negotiable)

- DEV/STAGING/PAPER MUST NOT be able to reach LIVE accounts or LIVE keys.
- Each environment uses distinct exchange accounts and distinct API keys.
- Withdrawals MUST be disabled for all keys.
- Secrets MUST NOT be stored in git or plaintext files in repo.

---

## Matrix

| Env | Venue | Account/Subaccount | API Key ID | Permissions/Scopes | Withdraw Enabled | Base URL | Secrets Source | Notes |
|-----|-------|-------------------|------------|-------------------|------------------|----------|----------------|-------|
| DEV | N/A | N/A | N/A | N/A | N/A | mocked | N/A | All calls mocked |
| STAGING | Deribit | testnet_acct_001 | key_staging_*** | read, trade | **false** | test.deribit.com | .env.staging | Git-ignored |
| PAPER | Deribit | paper_acct_001 | key_paper_*** | read, trade | **false** | www.deribit.com | .env.paper | Paper mode |
| LIVE | Deribit | prod_acct_001 | key_live_*** | read, trade | **false** | www.deribit.com | Vault | Role-based access |

---

## Network / Access Controls

How isolation is enforced:

| Control | DEV | STAGING | PAPER | LIVE |
|---------|-----|---------|-------|------|
| Outbound allowlist | localhost only | test.deribit.com | www.deribit.com | www.deribit.com |
| Secret access | None needed | Local .env file | Local .env file | Vault + IAM role |
| Who can access secrets | Any dev | Any dev | Any dev | Ops only |
| IP whitelist on exchange | N/A | None | None | Production IPs only |

---

## Environment Detection

The system determines its environment via:

```
TRADING_ENV=DEV      → Mock mode, no real calls
TRADING_ENV=STAGING  → Testnet credentials loaded
TRADING_ENV=PAPER    → Paper account credentials loaded
TRADING_ENV=LIVE     → Production credentials from Vault
```

**Default:** If `TRADING_ENV` is not set, defaults to `DEV` (safest).

---

## Cross-Environment Isolation Guarantees

| Guarantee | How Enforced |
|-----------|--------------|
| LIVE keys cannot be used in DEV/STAGING | Vault policy restricts to prod IAM role |
| DEV cannot connect to production | No credentials available locally |
| Config drift detected | Config hash checked at startup |
| Wrong env key rejected | Key ID prefix checked against TRADING_ENV |

---

## Forbidden (always)

- [x] Reusing keys across environments
- [x] Storing LIVE keys in local files
- [x] Accessing LIVE Vault path from non-prod network
- [x] Running with TRADING_ENV=LIVE on developer machine

---

## Owner Sign-Off

- [ ] Each environment has separate exchange account
- [ ] Each environment has separate API key
- [ ] Withdrawals disabled on ALL keys
- [ ] LIVE keys are not accessible locally
- [ ] Isolation guarantees reviewed

**owner_signature:** ______________________
**date_utc:** ______________________
