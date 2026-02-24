# External Integrations

**Analysis Date:** 2026-02-23

## APIs & External Services

**Cryptocurrency Exchange (Deribit):**
- Deribit futures trading venue adapter
  - SDK/Client: Custom implementation in `crates/soldier_infra/src/deribit/`
  - Sub-modules:
    - `account_summary.rs` - Fee tier caching and account data
    - `public/mod.rs` - Instrument metadata (settlement periods, tick sizes)
  - Auth: Assumed via environment variables or vault (not directly visible in code)
  - Purpose: Market data fetching, order submission, position tracking

**Market Data:**
- WebSocket subscription handling (referenced in `CLAUDE.md` fail-closed patterns for WS gaps)
- REST API for instrument metadata (DeribitInstrument types in `deribit/public/mod.rs`)

## Data Storage

**Databases:**
- None (no SQL/NoSQL database client found)

**File Storage:**
- Local filesystem only
  - Write-Ahead Log (WAL) persistence: `crates/soldier_infra/src/store/ledger.rs`
    - Intent records stored durably
    - Replay capability for crash recovery
    - Configurable writer via `WalWriterConfig`
  - Trade ID registry: `crates/soldier_infra/src/store/trade_id_registry.rs`
    - Idempotency registry stored locally

**Caching:**
- Fee cache: `crates/soldier_infra/src/deribit/account_summary.rs`
  - In-memory cache for Deribit fee tiers
  - TTL configured via `FeeCache` type
  - Hard staleness limit (config: `fee_cache_hard_s`)

## Authentication & Identity

**Auth Provider:**
- Custom (vault-managed credentials assumed from policy.json)

**Implementation:**
- `config/policy.json` defines:
  - Environment-level trading capability (trade_capable: true/false)
  - LIVE environment expected to use vault-managed credentials
  - Other environments (DEV, STAGING, PAPER) have explicit trust models
- No OAuth, SAML, or JWT implementation visible
- Credential handling:
  - Assumed to flow through `FullBootstrapConfig` (`crates/soldier_infra/src/bootstrap.rs`)
  - Environment-specific (LIVE vs STAGING vs DEV vs PAPER)

## Monitoring & Observability

**Error Tracking:**
- None (No Sentry, Datadog, or equivalent)

**Logs:**
- Structured logging via `tracing` crate
  - Macros: `tracing::info!`, `tracing::warn!`, `tracing::error!`
  - All safety-critical events logged with context (`instrument_id`, `side`, `intent_id`, `trading_mode`, etc.)
- Log output: stdout/stderr (no centralized log aggregation)

**Metrics:**
- In-memory counters available:
  - `LedgerMetrics` - WAL append operations (`crates/soldier_infra/src/store/ledger.rs`)
  - `RegistryMetrics` - Trade ID registry operations
  - `FeeCacheMetrics` - Fee cache hit/miss/stale events
  - Reject counters (e.g., `net_edge_reject_total`) referenced in tests

## CI/CD & Deployment

**Hosting:**
- GitHub (repository host)
- GitHub Actions (CI runner: ubuntu-latest)

**CI Pipeline:**
- `.github/workflows/ci.yml` - Multi-stage verification:
  - **phase1-snapshot-isolation-smoke** - Snapshot isolation checks
  - **prd-story-gate** - PRD story review enforcement (currently disabled: `if: false`)
  - **crossref-gate** - Contract cross-reference validation
  - **verify** - Full verification (Rust build, Python tools, Node setup)
- `.github/workflows/codeql.yml` - Security scanning (Python analysis only)
- Triggers: PR, push to main, scheduled daily at 1 UTC
- Artifact storage: GitHub Actions artifacts (`artifacts/` directory)

**Deployment:**
- No deployment-specific configuration found
- Branches: `main` (primary), story/* pattern (feature branches), deploy/* pattern (deployment branches)
- **No container orchestration, serverless platform, or cloud deployment config**

## Environment Configuration

**Required env vars:**
- `BASE_REF` - Git base reference for verification (set in CI: `origin/main`)
- `VERIFY_CONSOLE` - Logging verbosity (set in CI: `verbose`)
- `CROSSREF_ARTIFACTS_DIR` - Output directory for crossref validation
- `PROPTEST_CASES` - Property test case count (referenced in test code)
- `GH_TOKEN` - GitHub token for PR gate (provided by actions/github-script)
- Exchange credentials (Deribit API key, secret) - assumed via environment or vault

**Secrets location:**
- `config/policy.json` - Policy configuration (NOT secrets, but environment-sensitive)
- `.env` files - Not checked in (referenced in `.gitignore` implicitly)
- Vault assumed for LIVE environment (mentioned in policy.json: "vault-managed credentials")

## Webhooks & Callbacks

**Incoming:**
- GitHub webhook events (PR opened, push, review, issue comments) → CI trigger
- No explicit API webhook endpoints defined

**Outgoing:**
- None identified

---

*Integration audit: 2026-02-23*
