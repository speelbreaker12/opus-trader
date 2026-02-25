# External Integrations

**Analysis Date:** 2026-02-25

## APIs & External Services

**Payment Processing:**
- Not detected

**Email/SMS:**
- Not detected

**External APIs:**
- Deribit - trading venue for market/private API access
  - Integration method: HTTP-based integration (public/private API calls implied by exchange host config)
  - Auth: Exchange API credentials loaded by environment (`TRADING_ENV`-scoped keying in `docs/env_matrix.md` and startup identity checks in `docs/keys_and_secrets.md`)
  - Endpoints used: `test.deribit.com` (STAGING) and `www.deribit.com` (PAPER/LIVE) by environment matrix

- Convex - status API and data service
  - Integration method: Convex JS client functions + HTTP function endpoint (`dashboard/convex/http.ts`) and HTTP publish calls in `dashboard/publisher/publisher.py`
  - Auth: Bearer secret token check against `CONVEX_PUBLISH_SECRET` in inbound function
  - Endpoints used: Convex publish endpoint configured via `CONVEX_PUBLISH_ENDPOINT`

## Data Storage

**Databases:**
- Convex - operational status data store (`statusSnapshots`, `latestStatusPointers`)
  - Connection: environment-configured Convex endpoint
  - Client: `convex` package from `dashboard/package.json` and Convex functions in `dashboard/convex`
  - Migrations: none detected

- SQLite (local file)
  - Connection: local spool DB path via `STATUS_PUBLISHER_SPOOL_DB_PATH` in publisher
  - Client: Python stdlib `sqlite3` in `dashboard/publisher/spool.py`
  - Migrations: none detected

**File Storage:**
- Not detected

**Caching:**
- Not detected

## Authentication & Identity

**Auth Provider:**
- Exchange key scopes and Vault/local env storage (custom runtime auth)
  - Implementation: environment-driven API credentials with fail-closed environment checks
  - Token storage: Vault for LIVE; `.env.staging` for STAGING; no LIVE keys in local `.env` by contract
  - Session management: runtime identity verification against exchange account/subaccount on startup

**OAuth Integrations:**
- Not detected

## Monitoring & Observability

**Error Tracking:**
- Not detected

**Analytics:**
- Not detected

**Logs:**
- Rust tracing (`tracing` crate) and publisher logs to stdout/stderr
  - Integration: local process logs (no external collector detected)

## CI/CD & Deployment

**Hosting:**
- Convex
  - Deployment: not explicitly documented in repo files
  - Environment vars: `CONVEX_*` and exchange/runtime vars injected by deployment/runtime environment

**CI Pipeline:**
- Not detected

## Environment Configuration

**Development:**
- Required env vars: `TRADING_ENV`, `CONVEX_PUBLISH_ENDPOINT`, `CONVEX_PUBLISH_SECRET`, `STATUS_PUBLISHER_*`
- Secrets location: Vault policy for LIVE; local env for STAGING testnet keys
- Mock/stub services: DEV mode is mocked (no private exchange creds)

**Staging:**
- Uses testnet exchange account and `.env.staging` key source in contract table

**Production:**
- Uses LIVE exchange account and Vault/IAM-backed secrets for trade keys
- Live exchange calls allowed only for private endpoints under constrained key scopes

## Webhooks & Callbacks

**Incoming:**
- Convex
  - `/status` HTTP endpoint in `dashboard/convex/http.ts` for inbound status posts
  - Verification: `Authorization: Bearer <CONVEX_PUBLISH_SECRET>` check
  - Events: status snapshot ingestion and duplicate suppression/validation logic

**Outgoing:**
- Convex publish callbacks from runtime publisher
  - Endpoint: `CONVEX_PUBLISH_ENDPOINT` (configured URL)
  - Retry logic: exponential backoff with local spool/failover in `dashboard/publisher/publisher.py`

---

*Integration audit: 2026-02-25*
*Update when adding/removing external services*
