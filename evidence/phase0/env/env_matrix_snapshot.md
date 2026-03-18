# Environment Isolation Matrix (Phase 0)

> **Purpose:** Make it mechanically obvious which accounts/keys belong to which environment.
> No key reuse. No ambiguity. If it's not in this table, it's forbidden.

## Metadata
- doc_id: ENV-001
- version: 1.1
- contract_version_target: 5.2
- last_updated_utc: 2026-02-09T23:30:00Z

---

## Invariants (non-negotiable)

- DEV/STAGING/PAPER MUST NOT be able to reach LIVE accounts or LIVE keys.
- PAPER MUST NOT hold trade-capable credentials.
- Each environment uses distinct exchange accounts and distinct API keys where keys exist.
- Withdrawals and transfers MUST be disabled for all automated keys.
- Secrets MUST NOT be stored in git or plaintext files in repo.

---

## Matrix

| Env | Venue | Account/Subaccount | API Key ID | Key Type | Permissions/Scopes | Withdraw Enabled | Base URL | Secrets Source | Probe Evidence Path | Notes |
|-----|-------|-------------------|------------|----------|-------------------|------------------|----------|----------------|---------------------|-------|
| DEV | N/A | N/A | N/A | NONE | N/A | N/A | mocked | N/A | N/A | All calls mocked |
| STAGING | Deribit | testnet_acct_001 | key_staging_trade_*** | TRADE_TESTNET | read_account, trade | **false** | test.deribit.com | .env.staging (testnet only, git-ignored) | evidence/phase0/keys/key_scope_probe.json | Testnet only; no real funds |
| PAPER | Deribit | N/A | N/A | NONE | public_market_data_only | N/A | www.deribit.com | N/A | evidence/phase0/keys/key_scope_probe.json | Public endpoints only; execution simulated; no private trade auth |
| LIVE | Deribit | prod_acct_001 | key_live_trade_*** | TRADE_LIVE | read_account, trade | **false** | www.deribit.com | Vault (prod IAM only) | evidence/phase0/keys/key_scope_probe.json | Real execution; restricted operator access |

---

## Network / Access Controls

How isolation is enforced:

| Control | DEV | STAGING | PAPER | LIVE |
|---------|-----|---------|-------|------|
| Outbound allowlist | localhost only | test.deribit.com | www.deribit.com (public endpoints only) | www.deribit.com (private endpoints + IP allowlist) |
| Secret access | None needed | Local .env file (testnet only) | None required | Vault + IAM role |
| Who can access secrets | None | Approved devs (testnet only) | N/A | Ops only |
| IP whitelist on exchange | N/A | Optional (testnet) | N/A | Required (production IPs only) |

Note: PAPER and LIVE may share hostnames for market data, so isolation is credential-enforced. PAPER remains non-trading by design because it has no private trade credentials.

---

## Environment Detection

The system determines its environment via:

```
TRADING_ENV=DEV      -> Mock mode, no real calls
TRADING_ENV=STAGING  -> Testnet credentials loaded
TRADING_ENV=PAPER    -> Market-data-only mode; no private trade credentials
TRADING_ENV=LIVE     -> Production credentials from Vault
```

**Default:** If `TRADING_ENV` is not set, defaults to `DEV` (safest).

**Hard fail rules:**
- If `TRADING_ENV=LIVE` and Vault credentials are missing, startup MUST fail closed.
- LIVE MUST NOT fall back to local `.env` files.
- If `TRADING_ENV=PAPER` and any trade-capable credential is present, startup MUST fail closed.

---

## Cross-Environment Isolation Guarantees

| Guarantee | How Enforced |
|-----------|--------------|
| LIVE keys cannot be used in DEV/STAGING/PAPER | Vault policy restricts to prod IAM role |
| Wrong env account detected | Startup private identity probe (account/subaccount) must match this matrix; mismatch fails closed |
| PAPER cannot place private orders | PAPER loads no private trade credentials |
| DEV cannot connect to production private APIs | No production credentials available locally |
| Config drift detected | Config hash + startup identity probe |

---

## Forbidden (always)

- [x] Reusing keys across environments
- [x] Storing LIVE keys in local files
- [x] Accessing LIVE Vault path from non-prod network
- [x] Running with `TRADING_ENV=LIVE` on developer machine
- [x] PAPER with trade-capable keys
- [x] Using key-name prefix checks as the sole environment control

---

## Owner Sign-Off

- [x] Each environment has separate exchange account where private credentials exist
- [x] PAPER has no trade-capable credentials
- [x] Withdrawals disabled on ALL automated keys
- [x] LIVE keys are not accessible locally
- [x] Startup identity-probe fail-closed check is implemented

**owner_signature:** admin
**date_utc:** 2026-02-11
