# Tech Stack Map

**Analysis date:** 2026-03-04  
**Scope:** Current stack used by runtime code, dashboard sidecar, and verification harness.

## 1) Languages and primary code locations
- `Rust` (edition `2024`) for core/infra crates in `crates/soldier_core/Cargo.toml` and `crates/soldier_infra/Cargo.toml`.
- `TypeScript` for Convex data/API layer in `dashboard/convex/http.ts`, `dashboard/convex/status.ts`, `dashboard/convex/schema.ts`.
- `Python` for operator/runtime tools in `stoic-cli`, `dashboard/publisher/publisher.py`, `tools/validate_status.py`, `python/mcp_server/server.py`.
- `Bash` for workflow/verification orchestration in `plans/verify.sh`, `plans/verify_fork.sh`, `plans/preflight.sh`.

## 2) Runtime and toolchain baseline
- Rust workspace root is defined in `Cargo.toml` and lockfile is `Cargo.lock`.
- CI installs stable Rust toolchain via `.github/workflows/ci.yml` (`dtolnay/rust-toolchain@stable`).
- Dashboard Node runtime is ESM (`"type": "module"`) in `dashboard/package.json` with TS config in `dashboard/tsconfig.json` (`target: es2022`, `moduleResolution: Bundler`).
- CI uses Node `20` in `.github/workflows/ci.yml`; dashboard package manager is npm via `dashboard/package-lock.json`.
- Python runtime is shebang-driven (`#!/usr/bin/env python3`) across `stoic-cli`, `tools/*.py`, and `dashboard/publisher/*.py`.

## 3) Frameworks and key libraries
- Convex framework/client in `dashboard/package.json` (`convex`) with schema/mutations in `dashboard/convex/schema.ts` and `dashboard/convex/status.ts`.
- Rust serialization/observability stack:
  - `serde` and `serde_json` in `crates/soldier_core/Cargo.toml`, `crates/soldier_infra/Cargo.toml`.
  - `tracing` in both crate manifests and `tracing-test`/`proptest` in `crates/soldier_core/Cargo.toml`.
- Rust hashing dependency `xxhash-rust` in `crates/soldier_core/Cargo.toml`.
- Python MCP SDK dependency in `python/mcp_server/requirements.txt` (`mcp>=1.0.0`).
- Python status-sidecar persistence uses stdlib `sqlite3` in `dashboard/publisher/spool.py`.

## 4) Dependency manifests and lock points
- Rust manifests: `Cargo.toml`, `crates/soldier_core/Cargo.toml`, `crates/soldier_infra/Cargo.toml`.
- Rust lockfile: `Cargo.lock`.
- Dashboard manifests: `dashboard/package.json`, `dashboard/package-lock.json`, `dashboard/tsconfig.json`.
- Python package pins for MCP server: `python/mcp_server/requirements.txt`.
- CI Python tooling deps: `plans/ci/requirements-verify.txt`, `plans/ci/requirements-crossref.txt`.

## 5) Build, lint, and test entrypoints
- Canonical verify entrypoint is `plans/verify.sh` (thin wrapper) delegating to `plans/verify_fork.sh`.
- Preflight checks are in `plans/preflight.sh` (schema/self-dep/shell checks and fixture guards).
- Rust gates in `plans/lib/rust_gates.sh`:
  - `cargo fmt --all -- --check`
  - `cargo clippy --workspace --all-targets --all-features -- -D warnings` (full mode)
  - `cargo test --workspace ... --locked`
- Python gates in `plans/lib/python_gates.sh` use `ruff`, `pytest`, and optional `mypy`.
- Node gates in `plans/lib/node_gates.sh` run lint/typecheck/test if root lockfile + scripts are present.
- CI orchestration is centralized in `.github/workflows/ci.yml` (crossref, verify, and workflow-specific jobs).

## 6) Configuration surfaces
- Runtime trading policy lives in `config/policy.json`, validated/loaded by `tools/policy_loader.py` and consumed by `stoic-cli`.
- Contract/workflow control docs: `specs/CONTRACT.md`, `specs/WORKFLOW_CONTRACT.md`, `plans/prd.json`.
- Runtime/state schemas:
  - `python/schemas/runtime_state_v1.schema.json`
  - `python/schemas/status_csp_min.schema.json`
- Convex-side validation and schema lock:
  - `dashboard/convex/status_contract.ts`
  - `dashboard/convex/validators.ts`

## 7) Practical planning notes
- Stack is polyglot but centered on Rust domain logic + Python operational tooling; TS/Convex is a focused status publishing surface.
- Node/Convex code is isolated under `dashboard/`; root verify path is primarily Rust/Python/workflow gates.
- No container or IaC baseline is present in repo manifests (no `Dockerfile`, no compose, no Terraform files in root map).
