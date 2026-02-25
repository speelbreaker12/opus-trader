# Technology Stack

**Analysis Date:** 2026-02-25

## Languages

**Primary:**
- TypeScript 5.5 - `dashboard/convex` functions and scripts
- Rust (edition 2024) - core/infrastructure workspace crates in `crates/soldier_core` and `crates/soldier_infra`
- Python - local MCP server and status publisher tooling

**Secondary:**
- Not detected

## Runtime

**Environment:**
- Node.js (>=18, inferred from package-lock engine constraints in `dashboard/package-lock.json`)
- Rust compiler runtime target (as required by workspace crates)
- Python 3 (in `python/mcp_server/server.py`)

**Package Manager:**
- npm (Node workspace in `dashboard/`)
- Cargo (Rust workspace)
- pip (`python/mcp_server/requirements.txt`)
- Lockfile: `dashboard/package-lock.json` present

## Frameworks

**Core:**
- Convex 1.x - backend/data platform and HTTP endpoint layer (`dashboard/convex`)

**Testing:**
- Rust built-in test harness (`cargo test`) for crates under `crates/` — inferred from dependency usage (`proptest`, test modules)
- Not detected (for dashboard-side tooling)

**Build/Dev:**
- TypeScript 5.5 (`dashboard/package.json` / `dashboard/tsconfig.json`)
- tsx 4.19 (`dashboard/package.json`)
- Convex CLI via `npx convex`
- cargo for Rust workspace builds (`Cargo.toml`)

## Key Dependencies

[Only include dependencies critical to understanding the stack - limit to 5-10 most important]

**Critical:**
- convex ^1.16.0 - status API/runtime + schema/mutations
- mcp >=1.0.0 - MCP server tooling
- serde 1.x - serialization for Rust core/infra domain/state
- tracing 0.1 - runtime observability/logging instrumentation
- xxhash-rust 0.8 - hashing support used in execution pipeline

**Infrastructure:**
- proptest 1.x - property testing for Rust behavior checks
- serde_json 1.x - JSON handling in Rust
- sqlite3 (Python stdlib `sqlite3`) - local spool persistence in `dashboard/publisher/spool.py`

## Configuration

**Environment:**
- `.env` pattern is environment-driven (`TRADING_ENV`, `CONVEX_PUBLISH_ENDPOINT`, `CONVEX_PUBLISH_SECRET`, and `STATUS_PUBLISHER_*` vars in publisher docs/code)
- Secrets policy and source differ by environment (`.env.staging` for STAGING, Vault for LIVE)

**Build:**
- `dashboard/package.json`
- `dashboard/package-lock.json`
- `dashboard/tsconfig.json`
- `Cargo.toml` (workspace)
- `crates/soldier_core/Cargo.toml`
- `crates/soldier_infra/Cargo.toml`
- `python/mcp_server/requirements.txt`

## Platform Requirements

**Development:**
- macOS/Linux/Windows not explicitly constrained in code/config
- Node, Rust, and Python toolchains available

**Production:**
- Convex-hosted status backend for runtime publishing and querying (`dashboard/convex`)
- Live trading venue connectivity managed by runtime deployment (Deribit host from `docs/env_matrix.md`)

---

*Stack analysis: 2026-02-25*
*Update after major dependency changes*
