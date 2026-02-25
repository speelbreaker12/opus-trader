# Architecture

**Analysis Date:** 2026-02-25

## Pattern Overview

**Overall:** Layered trading runtime with durable execution pipeline and separate dashboard sidecar

**Key Characteristics:**
- Workspace-level separation between domain execution and infrastructure adapters
- Intent-to-command pipeline with explicit preflight and gate stages
- Durable WAL + ledger replay and idempotency handling
- Mixed-language operations: Rust core + Python publisher + Convex/TypeScript status API + verification harness

## Layers

**Execution Core (`soldier_core`):**
- Purpose: Owns trading intent assembly, policy checks, dispatch decisions, and execution orchestration
- Contains: `crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_core/src/execution/intent_assembly.rs`, `crates/soldier_core/src/execution/dispatch_map.rs`, `crates/soldier_core/src/execution/base_gates.rs`, `crates/soldier_core/src/execution/open_runtime.rs`, and module exports in `crates/soldier_core/src/lib.rs`
- Depends on: Risk, venue, recovery, and idempotency modules in `crates/soldier_core/src`
- Used by: `crates/soldier_infra/src` integration layer and external runtime hosts

**Risk & Validation Layer (`soldier_core::risk`):**
- Purpose: Applies preflight and risk constraints before dispatch
- Contains: `crates/soldier_core/src/risk/mod.rs` and risk types referenced by execution flow
- Depends on: Execution context and intent metadata
- Used by: Core gate pipeline (`crates/soldier_core/src/execution/*`)

**Venue Abstraction Layer:**
- Purpose: Keeps execution policy separated from exchange-specific protocol mapping
- Contains: Venue traits/types in `crates/soldier_core/src/venue/mod.rs`, protocol adapters in `crates/soldier_infra/src/deribit/public/mod.rs` and `crates/soldier_infra/src/deribit/mod.rs`
- Depends on: Canonical execution payloads from core
- Used by: Dispatcher and bootstrap wiring

**Persistence and Recovery Layer (`soldier_infra`):**
- Purpose: Provides startup coordination, durable write-ahead storage, and deterministic recovery
- Contains: `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_infra/src/store/trade_id_registry.rs`, and recovery integration in `crates/soldier_core/src/recovery/mod.rs`
- Depends on: Runtime state updates from execution and id generation
- Used by: bootstrap flow, replay/restore flows, and idempotency enforcement

**Bootstrap and Configuration Layer:**
- Purpose: Owns environment parsing and runtime assembly
- Contains: `crates/soldier_infra/src/config.rs` and bootstrap entrypoints in `crates/soldier_infra/src/bootstrap.rs`
- Depends on: Config sources, filesystem, and runtime dependencies
- Used by: external startup process and tests

**Observability Layer (Dashboard + Publisher):**
- Purpose: Accept status updates, persist, and expose operational state
- Contains: HTTP endpoint and data model in `dashboard/convex/http.ts`, `dashboard/convex/schema.ts`, `dashboard/convex/status.ts`; publisher/transform/state/spool pipeline in `dashboard/publisher/publisher.py`, `dashboard/publisher/transform.py`, `dashboard/publisher/state.py`, `dashboard/publisher/spool.py`; validation in `dashboard/convex/validators.ts`
- Depends on: runtime status snapshots and external API credentials
- Used by: operators, monitoring, and post-incident review

## Data Flow

**Trading Intent Processing:**

1. External orchestrator passes an intent into the core execution path (`crates/soldier_core/src/execution/*`).
2. The request is normalized and assembled in `crates/soldier_core/src/execution/intent_assembly.rs`.
3. Core runtime context is prepared via `crates/soldier_core/src/execution/open_runtime.rs`.
4. `crates/soldier_core/src/execution/pipeline.rs` executes ordered stages, including preflight and checks from `crates/soldier_core/src/execution/base_gates.rs`.
5. Risk and recovery-aware decisioning is applied (`crates/soldier_core/src/risk/mod.rs`, `crates/soldier_core/src/recovery/mod.rs`).
6. `crates/soldier_core/src/execution/dispatch_map.rs` resolves dispatch target/format, with labeling via `crates/soldier_core/src/execution/label.rs`.
7. Venue-specific handling uses infrastructure integration in `crates/soldier_infra/src/deribit/*`.
8. Idempotency and durability hooks record intent/results through `crates/soldier_infra/src/store/trade_id_registry.rs` and `crates/soldier_infra/src/wal.rs` with replay storage in `crates/soldier_infra/src/store/ledger.rs`.

**Status Publication Flow (Operational):**

1. Runtime status is transformed in `dashboard/publisher/transform.py`.
2. Validation and dedupe occur in `dashboard/publisher/state.py` and `dashboard/publisher/spool.py`.
3. Publication is done by `dashboard/publisher/publisher.py` to Convex endpoint `dashboard/convex/http.ts`.
4. Convex writes status records via `dashboard/convex/status.ts` using schema from `dashboard/convex/schema.ts`.

**State Management:**
- Stateful persistence is durable and append-oriented (`crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_infra/src/wal.rs`) with explicit bootstrap/restart recovery.
- Runtime operational state for dashboard publishing is persisted in `dashboard/publisher/state.py` / `dashboard/publisher/spool.py`.
- In-memory-only state and orchestration behavior are not fully exposed in this repo (`Not detected`).

## Key Abstractions

**Pipeline:**
- Purpose: Encapsulates ordered processing of an order/intent.
- Examples: `crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_core/src/execution/intent_assembly.rs`
- Pattern: layered stage pipeline

**Gate:**
- Purpose: Small, composable validation stage with fail-fast behavior.
- Examples: `crates/soldier_core/src/execution/base_gates.rs`
- Pattern: guard/chain-of-responsibility

**Label + Dispatch Mapping:**
- Purpose: Tagging and routing logic for different execution targets.
- Examples: `crates/soldier_core/src/execution/label.rs`, `crates/soldier_core/src/execution/dispatch_map.rs`
- Pattern: mapping table + strategy-based dispatch

**Durability Log:**
- Purpose: Reliable recovery and restartability.
- Examples: `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_core/src/recovery/mod.rs`
- Pattern: write-ahead append + replay

## Entry Points

**Rust Runtime Setup:**
- Location: `crates/soldier_infra/src/bootstrap.rs`
- Triggers: external startup code calling bootstrap functions
- Responsibilities: initialize persistence, load config, and assemble core/infrastructure wiring

**Status Ingestion API:**
- Location: `dashboard/convex/http.ts`
- Triggers: HTTP POST to `/status`
- Responsibilities: validate request auth, parse payload, route to status mutation

**Publisher Daemon:**
- Location: `dashboard/publisher/publisher.py`
- Triggers: runtime/manual execution of the publisher process
- Responsibilities: read spooled state, retry delivery, post updates to Convex

**Verification Orchestrator:**
- Location: `plans/verify.sh`
- Triggers: developer/runner invocation
- Responsibilities: orchestrate contract, lint, and workflow gates

## Error Handling

**Strategy:** Typed `Result`/error propagation at Rust boundaries and explicit fail-closed checks at durability checkpoints; publisher uses explicit retry and logging on transient failures.

**Patterns:**
- `Result`-oriented control flow in core and infra modules (`crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_infra/src/bootstrap.rs`)
- Validation-first handling (`crates/soldier_core/src/risk/mod.rs`, `dashboard/convex/http.ts`, `dashboard/publisher/transform.py`, `dashboard/publisher/validators` equivalent in `dashboard/convex/validators.ts`)
- Durable-operation guardrails through WAL/ledger write paths in `crates/soldier_infra/src/wal.rs` and `crates/soldier_infra/src/store/ledger.rs`
- Authentication/authorization rejection in HTTP entry `dashboard/convex/http.ts`

## Cross-Cutting Concerns

**Logging:**
- Not detected as a centralized package; logging/logging-style behavior appears inline and module-local (e.g., publisher output and verify tooling scripts).

**Validation:**
- Boundary validation is present at multiple layers: `dashboard/convex/validators.ts`, payload transform in `dashboard/publisher/transform.py`, and runtime preflight/gates in `crates/soldier_core/src/execution/base_gates.rs`.

**Authentication:**
- `dashboard/convex/http.ts` uses bearer/secret validation for inbound status posts.

**Durability:**
- Managed through explicit WAL + ledger + trade-id registry in `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/src/store/ledger.rs`, `crates/soldier_infra/src/store/trade_id_registry.rs`.

---

*Architecture analysis: 2026-02-25*
*Update when major patterns change*
