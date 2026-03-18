# Integrations Map

**Analysis date:** 2026-03-04  
**Scope:** External services, broker/API surfaces, auth boundaries, webhooks, and env-driven integration points.

## 1) External API/services inventory

| Integration | Role | Direction | Auth model | Primary refs |
|---|---|---|---|---|
| Deribit | Trading venue / broker + market data source | Outbound | API keys + scope controls (docs/policy) | `docs/env_matrix.md`, `docs/keys_and_secrets.md`, `docs/launch_policy.md`, `specs/vendor_docs/deribit.md`, `crates/soldier_infra/src/deribit/public/mod.rs` |
| Convex HTTP endpoint | Status ingestion endpoint (`/status`) | Inbound to Convex, outbound from publisher | Bearer token `CONVEX_PUBLISH_SECRET` | `dashboard/convex/http.ts`, `dashboard/publisher/publisher.py` |
| Convex DB/functions | Status snapshot storage + query API | App-internal (Convex runtime) | Convex internal auth/context | `dashboard/convex/schema.ts`, `dashboard/convex/status.ts`, `dashboard/convex/status_contract.ts` |
| Claude Code MCP | Dev-time contract lookup/validation server | Local tool integration | Local process + MCP protocol | `python/mcp_server/server.py`, `python/mcp_server/README.md` |
| GitHub Actions | CI verification and gates | Inbound triggers + outbound checks/artifacts | GitHub token (`github.token`) | `.github/workflows/ci.yml`, `plans/pr_gate.sh` |

## 2) Databases and durable stores
- Convex tables as primary dashboard status store:
  - `statusSnapshots`
  - `latestStatusPointers`
  - Defined in `dashboard/convex/schema.ts`.
- Local SQLite spool/outbox for publisher retry durability in `dashboard/publisher/spool.py` (`PRAGMA journal_mode=WAL`, outbox indexes).
- Local JSON state files:
  - runtime state defaults in `stoic-cli` (`artifacts/phase0/runtime_state.json`, `var/runtime/runtime_state.json`)
  - sidecar state in `dashboard/publisher/state.py` (`status_publisher_state.v1`).

## 3) Broker/exchange integration details
- Exchange modeled is Deribit with environment-separated accounts and URLs in `docs/env_matrix.md`.
- Public/private endpoint expectations and session/rate-limit rules are documented in `specs/vendor_docs/deribit.md`.
- Rust infra currently exposes Deribit data-model adapters (instrument + fee/account summary structures) in:
  - `crates/soldier_infra/src/deribit/public/mod.rs`
  - `crates/soldier_infra/src/deribit/account_summary.rs`
- Runtime key-scope validation path is implemented in `stoic-cli` (`keys-check` command against `evidence/phase0/keys/key_scope_probe.json`).

## 4) Auth and secrets providers
- Deribit credentials and environment isolation policy are defined in `docs/env_matrix.md` and `docs/keys_and_secrets.md`.
- LIVE secret source is documented as Vault; STAGING testnet uses `.env.staging` (gitignored) in `docs/env_matrix.md`.
- Convex ingest auth is explicit Bearer secret comparison in `dashboard/convex/http.ts` against `process.env.CONVEX_PUBLISH_SECRET`.
- Publisher attaches Authorization header from `CONVEX_PUBLISH_SECRET` in `dashboard/publisher/publisher.py`.

## 5) Webhooks/callback style integrations
- Webhook-like ingestion endpoint: Convex HTTP route `POST /status` in `dashboard/convex/http.ts`.
- Publisher delivery path posts snapshot envelopes to `CONVEX_PUBLISH_ENDPOINT` with retries/backoff in `dashboard/publisher/publisher.py`.
- Retry/error classes (429/5xx/auth/schema) are codified in `dashboard/publisher/publisher.py` and validated in `tests/test_publisher_contract.py`.

## 6) Environment/config integration points (high-signal)
- Trading/runtime env controls in `stoic-cli`:
  - `STOIC_POLICY_PATH`, `STOIC_RUNTIME_STATE_PATH`, `STOIC_RUNTIME_STATE_V1_PATH`
  - `STOIC_ALLOW_EXTERNAL_RUNTIME_STATE`, `STOIC_UNSAFE_EXTERNAL_STATE_ACK`, `STOIC_DRILL_MODE`
  - `STOIC_BUILD_ID`, `STOIC_MAX_PENDING_ORDERS`
- Publisher env controls in `dashboard/publisher/publisher.py`:
  - `CONVEX_PUBLISH_ENDPOINT`, `CONVEX_PUBLISH_SECRET`
  - `STATUS_SOURCE_PATH`, `STATUS_PUBLISHER_*`, `ENVIRONMENT`, `HEAD_COMMIT`
- Policy/environment matrix control docs:
  - `docs/env_matrix.md`
  - `config/policy.json`
  - `docs/health_endpoint.md`

## 7) Integration boundaries to plan around
- Deribit network transport is policy/spec-heavy today; much of Rust integration is type/contracts rather than a full live client implementation (`crates/soldier_infra/src/deribit/*` + `specs/vendor_docs/deribit.md`).
- Status distribution path is intentionally decoupled: runtime state JSON -> publisher normalizer -> Convex ingest (`stoic-cli` + `dashboard/publisher/*` + `dashboard/convex/*`).
- Secrets management controls are documented and partially enforced in CLI/policy flows; operational enforcement still depends on deployment/Vault setup described in docs.
