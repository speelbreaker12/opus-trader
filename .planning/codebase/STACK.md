# Technology Stack

**Analysis Date:** 2026-02-23

## Languages

**Primary:**
- Rust 2024 edition - Core execution logic (`crates/soldier_core/` and `crates/soldier_infra/`)
- Python 3.11+ - Proof graph generation, MCP server, validation tools (`python/`)

**Secondary:**
- Bash - CI/CD orchestration, verification scripts (`plans/`, `scripts/`)
- YAML - GitHub Actions workflows (`.github/workflows/`)
- JSON - Configuration, contract definitions (`config/`, `specs/`)
- Markdown - Documentation and specifications (`specs/`, `docs/`)

## Runtime

**Environment:**
- Rust stable (managed via `dtolnay/rust-toolchain@stable`)
- Python 3.11 (specified in CI: `.github/workflows/ci.yml` and `plans/ci/requirements-*.txt`)

**Package Manager:**
- Cargo (Rust) - version 2 resolver (`Cargo.toml`)
  - Lockfile: `Cargo.lock` (present, 20KB)
- pip (Python) - with PyPI packages
  - Lockfile: None (requirements.txt used instead)

## Frameworks

**Core:**
- `tracing` 0.1 - Structured logging across all Rust crates
- `serde` 1.x with derive macros - Serialization/deserialization (all crates)
- `serde_json` 1.x - JSON support for Rust

**Testing:**
- `proptest` 1.x - Property-based testing in `soldier_core` (dev-dependency)
- `tracing-test` 0.2 - Tracing assertion helpers (dev-dependency)
- pytest - Python test framework (reference in CI at `.github/workflows/codeql.yml`)

**Build/Dev:**
- Cargo workspace (monorepo pattern with 2 crates)
- GitHub Actions - CI/CD orchestration
- CodeQL (v3) - Security analysis for Python code

## Key Dependencies

**Critical:**
- `xxhash-rust` 0.8 with xxh64 feature - Fast hashing for idempotency and registries
- `serde` 1.x - Essential for all data serialization
- `anyhow` 1.0 - Error handling (in Cargo.lock but not explicitly listed in tomls)

**Infrastructure:**
- `mcp` >= 1.0.0 (Python) - Claude Code MCP protocol server (`python/mcp_server/requirements.txt`)
- Standard library heavy: `std::env`, `std::fs`, `std::path`, `std::process`, `std::time`

## Configuration

**Environment:**
- Policy configuration: `config/policy.json`
  - Defines trading environments (DEV, STAGING, PAPER, LIVE)
  - Risk limits (max daily loss, gross notional, order rate)
  - Allowed/forbidden order types
  - Fail-closed default enforcement

- Runtime config: Built via `soldier_infra::config::{RawThresholdConfig, build_gate_config_from_raw}`
  - Appendix A defaults for missing parameters
  - Safety-critical threshold validation (NaN rejection, negative value checks)

**Build:**
- Workspace root: `Cargo.toml` (workspace definition)
- Crate manifests:
  - `crates/soldier_core/Cargo.toml` - Core trading logic
  - `crates/soldier_infra/Cargo.toml` - Infrastructure (deribit adapter, WAL, config)
- Python requirements:
  - `python/mcp_server/requirements.txt` - MCP server dependencies

**CI Configuration:**
- `.github/workflows/ci.yml` - Main verification pipeline
- `.github/workflows/codeql.yml` - Security scanning
- `plans/ci/requirements-crossref.txt` - Cross-reference validation tools
- `plans/ci/requirements-verify.txt` - Verification script dependencies

## Platform Requirements

**Development:**
- Rust toolchain with fmt and clippy components
- Python 3.11+
- Bash shell (POSIX)
- Git (for CI workflows)
- Swap artifacts caching (Swatinem/rust-cache@v2 in CI)

**Production:**
- Target platform: Linux (Ubuntu LTS - ubuntu-latest in workflows)
- No explicit database engine or external service dependencies (file-based WAL storage)
- No containerization (Docker) specified in configuration

---

*Stack analysis: 2026-02-23*
