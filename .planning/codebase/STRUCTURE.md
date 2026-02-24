# Codebase Structure

**Analysis Date:** 2026-02-23

## Directory Layout
```
opus-trader/
├── crates/                           # Rust workspace (Cargo.toml)
│   ├── soldier_core/                 # Core domain: gates, execution, risk, venue, recovery
│   │   ├── src/
│   │   │   ├── execution/            # 10-gate pipeline, intent assembly, order sizing
│   │   │   ├── risk/                 # Risk state, exposure budget, margin, fees, pending exposure
│   │   │   ├── venue/                # Instrument kinds, cache, capabilities, expiry guard, lifecycle
│   │   │   ├── idempotency/          # Intent hashing, label encoding
│   │   │   ├── recovery/             # Label matching, reconciliation
│   │   │   └── lib.rs                # Module exports
│   │   ├── tests/                    # Integration tests for all modules
│   │   └── Cargo.toml
│   │
│   └── soldier_infra/                # Infrastructure: storage, bootstrap, Deribit adapters
│       ├── src/
│       │   ├── store/                # WAL ledger, trade-ID registry
│       │   ├── deribit/              # Public API types, account summary parsing
│       │   ├── wal.rs                # Durability barrier (gate 10 adapter)
│       │   ├── bootstrap.rs          # Full bootstrap orchestration
│       │   ├── config.rs             # Gate config builders, threshold validation
│       │   └── lib.rs                # Module exports
│       ├── tests/                    # Integration tests for storage, config, bootstrap
│       └── Cargo.toml
│
├── specs/                            # Contracts, implementation plans, formal specs
│   ├── CONTRACT.md                   # 7-section safety contract (gates, risk, durability, policy, evidence, governance, status)
│   ├── WORKFLOW_CONTRACT.md          # Verification harness contract
│   ├── IMPLEMENTATION_PLAN.md        # PRD story index
│   ├── ENTRY_POINTS.md               # Top-level dispatch and bootstrap entry points
│   ├── DESIGN_PATTERNS.md            # Fail-closed, idempotency, label encoding patterns
│   ├── flows/                        # State machine diagrams (TLSM, RiskState)
│   ├── state_machines/               # Detailed state machine specs
│   ├── schemas/                      # JSON schemas for config, status payloads
│   ├── status/                       # /status endpoint specification
│   └── invariants/                   # Invariant proof checklist
│
├── python/                           # Python tooling
│   ├── proof_graph/                  # Per-story proof graph validation
│   │   ├── __init__.py
│   │   ├── schema.py                 # Proof schema definitions
│   │   ├── rules.py                  # Proof validation rules
│   │   ├── validate.py               # Batch validation
│   │   ├── scaffold.py               # Story scaffolding
│   │   ├── contract_ats.py           # CONTRACT.md anchor tracking
│   │   └── tests/
│   ├── schemas/                      # Config/status schema validators
│   └── mcp_server/                   # MCP server for integration testing
│
├── plans/                            # Workflow harness and PRD tooling
│   ├── prd.json                      # PRD story index with pass gates
│   ├── verify.sh                     # Main verification entrypoint
│   ├── verify_fork.sh                # Core verification implementation
│   ├── prd_set_pass.sh               # Guarded pass mutation
│   ├── postmortem_template.md        # Postmortem structure template
│   ├── progress.txt                  # Status file for CI feedback
│   └── [story-specific-plans]/       # Per-story execution plans
│
├── docs/                             # Documentation and discovery
│   ├── architecture/                 # System map, validation rules
│   ├── codebase/                     # Code structure and patterns (docs/codebase/)
│   ├── reconcile/                    # Reconciliation workflows
│   ├── skills/                       # Skill documentation (interview, review, audit)
│   ├── contract_kernel.json          # Extracted contract anchors
│   ├── phase0_index.md               # Phase 0 acceptance checklist
│   ├── phase1_index.md               # Phase 1 acceptance checklist
│   └── [other discovery]/
│
├── .planning/                        # Planning and discovery outputs (NEW)
│   └── codebase/
│       ├── ARCHITECTURE.md           # Layers, data flow, abstractions (this document set)
│       ├── STRUCTURE.md              # Directory layout, naming conventions (this document set)
│       └── STACK.md                  # Technology stack (existing)
│
├── artifacts/                        # Generated evidence and test outputs
│   ├── phase0/                       # Phase 0 state snapshots, replay outcomes
│   ├── phase1/                       # Phase 1 evidence, gate outputs
│   ├── story/                        # Per-story postmortems and reviews
│   └── [test-outputs]/               # Verification runs, mutation results
│
├── .github/workflows/                # CI configuration
│   └── ci.yml
│
├── CLAUDE.md                         # Claude Code instructions (read automatically)
├── ENTRYPOINTS.md                    # Entry points index (cross-ref to ENTRY_POINTS.md)
├── Cargo.toml                        # Workspace manifest
└── Cargo.lock                        # Dependency lock file
```

## Directory Purposes

**crates/soldier_core/src/execution/:**
- Purpose: Order intent evaluation pipeline (gates 1-10), assembly, dispatch validation
- Contains: Gate evaluation functions, intent assembly orchestration, order sizing, quantization, labeling, preflight validation, pricing, dispatch map validation
- Key files:
  - `mod.rs`: Module exports, metric name constants
  - `open_runtime.rs`: OPEN path orchestration (gates 1-10 + margin + exposure + pending exposure)
  - `intent_assembly.rs`: Intent assembly orchestration (sizing + dispatch consistency proof)
  - `pipeline.rs`: Shared pipeline orchestration (gates 1-10 for CLOSE/HEDGE/CANCEL)
  - `base_gates.rs`: Shared gates 1-6 evaluator (preflight, quantize, dispatch, fees, expiry)
  - `gate.rs`: Liquidity gate (gate 7) with L2 snapshot and slippage
  - `gates.rs`: Net edge gate (gate 8) with edge/slippage tradeoff
  - `inventory_skew.rs`: Inventory skew gate (gate 9) with position adjustment
  - `pricer.rs`: Limit price computation with mark + slippage clamping
  - `dispatch_map.rs`: Dispatch consistency proof validation (AT-920)
  - `build_order_intent.rs`: Order intent builder with WAL gate (gate 10)
  - `preflight.rs`: Preflight validation (post-only, order type, capabilities)
  - `quantize.rs`: Contract multiplier quantization
  - `order_size.rs`: Canonical order size builder
  - `label.rs`: Intent label encoding (group + sequence + flags)
  - `group.rs`: Atomic group execution with locking
  - `tlsm.rs`: Trade lifecycle state machine (TLSM)
  - `reject_reason.rs`: Rejection reason code mapping

**crates/soldier_core/src/risk/:**
- Purpose: Risk assessment, policy enforcement, exposure budgeting, margin management
- Contains: Risk state machines, exposure bucket tracking, pending exposure, fee staleness, margin mode hints
- Key files:
  - `mod.rs`: Module exports
  - `state.rs`: RiskState enum (Healthy/Degraded/Maintenance/Kill)
  - `exposure_budget.rs`: Delta exposure bucketing and budget enforcement
  - `pending_exposure.rs`: Per-instrument pending exposure reservation system
  - `margin_gate.rs`: Margin utilization checks with mode hints
  - `fees.rs`: Fee cache staleness evaluation
  - `instrument_state.rs`: Per-instrument metadata types

**crates/soldier_core/src/venue/:**
- Purpose: Exchange-specific type mapping, instrument derivation, cache, capabilities
- Contains: Instrument kind enums, venue cache with TTL, capability flags, lifecycle state machines
- Key files:
  - `mod.rs`: Module exports
  - `types.rs`: InstrumentKind enum (Spot/Perp/Call/Put) and derivation logic
  - `cache.rs`: InstrumentCache with TTL-based RiskState transitions
  - `capabilities.rs`: VenueCapabilities and BotFeatureFlags
  - `lifecycle.rs`: Lifecycle state machines (cancel outcomes, settlement, expiry guard)

**crates/soldier_core/src/idempotency/:**
- Purpose: Intent deduplication via hashing
- Contains: xxhash64-based intent hashing, hash formatting
- Key files:
  - `hash.rs`: `compute_intent_hash()`, `format_intent_hash()`, `intent_hash_ih16()`

**crates/soldier_core/src/recovery/:**
- Purpose: Recovery metadata and reconciliation support
- Contains: Label matching for startup reconciliation, label parsing
- Key files:
  - `label_match.rs`: `match_label()` for finding recovered intents in WAL

**crates/soldier_infra/src/store/:**
- Purpose: Durable storage: WAL ledger and trade-ID registry
- Contains: Append-only ledger with fsync barriers, trade-ID deduplication, TLSM replay
- Key files:
  - `ledger.rs`: WalLedger with async writer thread (bounded queue, fsync barrier), TlsState, ReplayOutcome
  - `trade_id_registry.rs`: TradeIdRegistry with insert-if-absent semantics
  - `mod.rs`: Module exports (LedgerMetrics, RegistryMetrics, ReplayOutcome)

**crates/soldier_infra/src/deribit/:**
- Purpose: Deribit exchange adapter types and API parsers
- Contains: Instrument metadata types, public API response parsers, account summary parsers
- Key files:
  - `mod.rs`: Module exports
  - `public/mod.rs`: Public API types (DeribitInstrument)
  - `account_summary.rs`: Account-level metadata parsing

**crates/soldier_infra/src/:**
- Purpose: Infrastructure bootstrap, WAL durability barrier, configuration assembly
- Key files:
  - `wal.rs`: DurableWalGate adapter for gate 10 (implements RecordedBeforeDispatch marker)
  - `bootstrap.rs`: Full bootstrap orchestration, BootstrapResult with startup latch enforcement
  - `config.rs`: Gate config builders, Appendix A threshold validation

**specs/:**
- Purpose: Formal specifications, contracts, implementation plans
- Key files:
  - `CONTRACT.md`: 7-section safety contract (§0–§7; ~343KB)
  - `ENTRY_POINTS.md`: Top-level dispatch and bootstrap entry points with call hierarchy
  - `IMPLEMENTATION_PLAN.md`: PRD story index with gate mappings
  - `DESIGN_PATTERNS.md`: Fail-closed, idempotency, label encoding patterns
  - `WORKFLOW_CONTRACT.md`: Verification harness contract
  - `TRACE.yaml`: Traceability matrix (CONTRACT → Plan → PRD → code)

**plans/:**
- Purpose: Workflow harness for verification, PRD execution, pass gating
- Key files:
  - `prd.json`: PRD story index with `passes=true/false` gates
  - `verify.sh`: Main verification entrypoint (delegates to verify_fork.sh)
  - `verify_fork.sh`: Core implementation (cargo test, artifact checks, contract validation)
  - `prd_set_pass.sh`: Guarded story pass mutation (prevents manual override)
  - `progress.txt`: Status file for CI feedback

**python/proof_graph/:**
- Purpose: Per-story proof graph validation and scaffolding
- Contains: Proof schema definitions, validation rules, batch validators
- Key files:
  - `schema.py`: Proof graph JSON schema
  - `rules.py`: Validation rules (AT references, loss modes, enforcement points)
  - `validate.py`: Batch validation across stories
  - `scaffold.py`: Story proof scaffolding from templates

**python/schemas/:**
- Purpose: Config and status schema validators
- Contains: JSON schema files for config validation, status payload validation

**docs/architecture/:**
- Purpose: Architecture documentation and decision rationale
- Key files:
  - `system_map.md`: 7-category system decomposition (Commander, Soldier, Execution, Durability, Evidence, Shadow, Governance)
  - `validation_rules.md`: Validation rule checklist for specs
  - `precedence_ladder.csv`: Policy decision precedence rules

**docs/codebase/:**
- Purpose: Code structure maps (complements .planning/codebase/)
- Key files:
  - `architecture.md`: High-level component overview
  - `structure.md`: Repository layout (for backward compatibility)
  - `stack.md`: Technology stack
  - `conventions.md`: Naming and style conventions
  - `testing.md`: Testing patterns

**.planning/codebase/ (NEW):**
- Purpose: Detailed architecture and structure discovery (generated by orchestrator)
- Key files:
  - `ARCHITECTURE.md`: Layers, data flow, abstractions, entry points (this document)
  - `STRUCTURE.md`: Directory layout, naming conventions, where to add new code (this document)
  - `STACK.md`: Technology stack (existing)

**artifacts/:**
- Purpose: Generated test outputs and evidence
- Key files:
  - `phase0/`: State snapshots, runtime tests, replay outcomes
  - `phase1/`: Integration test evidence, gate outputs
  - `story/`: Per-story postmortems (artifacts/story/<ID>/postmortem.md)

## Key File Locations

**Entry Points:**
- `crates/soldier_core/src/execution/open_runtime.rs:393`: `build_open_intent_with_assembly()` (OPEN dispatch)
- `crates/soldier_core/src/execution/intent_assembly.rs:159`: `evaluate_assembled_pipeline()` (CLOSE/HEDGE/CANCEL dispatch)
- `crates/soldier_infra/src/bootstrap.rs:284`: `bootstrap_full()` (application startup)
- `specs/ENTRY_POINTS.md`: Complete entry point catalog with call hierarchy

**Configuration:**
- `crates/soldier_infra/src/config.rs`: Gate config builders, threshold validation (Appendix A)
- `specs/schemas/config.json`: Config schema (threshold ranges)
- `plans/prd.json`: PRD story index with pass gates

**Core Logic:**
- `crates/soldier_core/src/execution/base_gates.rs`: Shared gates 1-6 (preflight, quantize, dispatch, fees, expiry)
- `crates/soldier_core/src/execution/pipeline.rs`: Shared pipeline orchestrator (gates 1-10)
- `crates/soldier_core/src/execution/open_runtime.rs`: OPEN path gates 7-10 (margin, exposure, pending, liquidity, net edge, inventory skew)
- `crates/soldier_core/src/risk/`: Risk assessment (exposure budget, margin, pending exposure)
- `crates/soldier_core/src/venue/`: Venue metadata (instrument kinds, cache, capabilities)

**Testing:**
- `crates/soldier_core/tests/`: Execution, risk, venue, recovery tests
- `crates/soldier_infra/tests/`: Storage, bootstrap, config, Deribit tests
- `plans/verify.sh`: Main verification entrypoint (delegates to verify_fork.sh)
- `specs/WORKFLOW_CONTRACT.md`: Verification harness contract

**Documentation:**
- `specs/CONTRACT.md`: 7-section safety contract
- `specs/DESIGN_PATTERNS.md`: Fail-closed, idempotency, label encoding patterns
- `specs/IMPLEMENTATION_PLAN.md`: PRD story index
- `docs/architecture/system_map.md`: 7-category system decomposition

## Naming Conventions

**Files:**
- `mod.rs`: Module root (defines `pub mod` declarations and public exports)
- `*_gates.rs`: Gate evaluators (e.g., `base_gates.rs`, `margin_gate.rs`)
- `open_runtime.rs`: OPEN-path orchestration (distinct from shared `pipeline.rs`)
- `test_*.rs`: Test modules (in `tests/` directories)
- `*_test.rs`: In-file test modules (via `#[cfg(test)]`)

**Directories:**
- `crates/`: Rust workspace (published or internal crates)
- `src/`: Source code root (Rust convention)
- `tests/`: Integration test directory (Rust convention)
- `specs/`: Formal specifications (non-code contracts)
- `plans/`: Workflow harness (scripts, PRD tooling)
- `artifacts/`: Generated evidence and test outputs

**Types/Enums:**
- `*Gate*`: Gate-related types (e.g., `LiquidityGate`, `MarginGateDecision`)
- `*Result`: Result types (e.g., `LiquidityGateResult`, `PipelineResult`)
- `*Metrics`: Metric aggregators (e.g., `LiquidityGateMetrics`)
- `*Input`: Function input types (e.g., `IntentPipelineInput`)
- `*Rejection`: Rejection reason types (e.g., `LiquidityGateRejection`)

**Functions:**
- `evaluate_*()`: Gate evaluators (e.g., `evaluate_liquidity_gate()`)
- `build_*()`: Constructor or builder functions (e.g., `build_order_intent()`)
- `compute_*()`: Computation functions (e.g., `compute_limit_price()`)
- `*_to_*()`: Conversion functions
- `validate_*()`: Validation functions (e.g., `validate_and_dispatch()`)

## Where to Add New Code

**New Gate / Risk Check:**
- Implementation: `crates/soldier_core/src/risk/` (for risk-specific) or `crates/soldier_core/src/execution/` (for execution)
- Input struct: In the same module (e.g., `pub struct MyGateInput { ... }`)
- Evaluator function: `pub fn evaluate_my_gate(input: &MyGateInput, metrics: &mut MyMetrics) -> Result<MyGateProof, MyRejection> { ... }`
- Metric exporter: Add constant to `crates/soldier_core/src/execution/mod.rs` (e.g., `METRIC_MY_GATE_REJECT`)
- Integration: Thread input/metrics through `IntentPipelineInput`, `OpenRuntimeInput`, and orchestrator (pipeline.rs or open_runtime.rs)
- Tests: `crates/soldier_core/tests/test_my_gate.rs` (table-driven, include fail-closed tests with pattern keywords: nan, missing, stale, invalid, expired, forbidden, degraded)

**New Infra Component (Storage, Config, Bootstrap):**
- Implementation: `crates/soldier_infra/src/` (create new module if significant)
- Module exports: Add to `crates/soldier_infra/src/lib.rs` public use
- Bootstrap integration: Wire into `FullBootstrapConfig` or `bootstrap_full()`
- Tests: `crates/soldier_infra/tests/test_my_component.rs`

**New Venue Adapter (Exchange-specific):**
- Implementation: `crates/soldier_infra/src/deribit/` (add submodule for new exchange)
- Types: Exchange-specific types in `deribit/mod.rs` or dedicated file
- Instrument kind derivation: Add variant to `InstrumentKind` enum, update `derive_instrument_kind()`
- Tests: `crates/soldier_infra/tests/test_new_venue.rs`

**New Recovery / Reconciliation Logic:**
- Implementation: `crates/soldier_core/src/recovery/`
- Recovery entry: Add function to `crates/soldier_core/src/recovery/mod.rs`
- Integration: Call from application bootstrap after `WalLedger::replay()`
- Tests: `crates/soldier_core/tests/test_recovery_*.rs`

**Utilities / Shared Helpers:**
- Small utilities: Add to nearest module (execution, risk, venue, recovery)
- General purpose: Create `crates/soldier_core/src/util.rs` (with submodules if large)
- Strings/formatting: Add to respective module (e.g., label formatting in `execution/label.rs`)

**Tests:**
- Unit tests: Same module as code (via `#[cfg(test)]` or separate test file)
- Integration tests: `crates/soldier_core/tests/` or `crates/soldier_infra/tests/`
- Pattern: Table-driven tests with parametrized inputs; always include at least one error path
- Fail-closed tests: Include pattern keywords (nan, missing, stale, invalid, expired, forbidden, degraded) for automated coverage checks

**Documentation:**
- Code-level: Rust doc comments (//! for modules, /// for items)
- Specs: Add to `specs/` (CONTRACT.md for safety invariants, DESIGN_PATTERNS.md for patterns)
- Postmortems: `artifacts/story/<ID>/postmortem.md` (after story completion)
- Discovery: Keep docs/codebase/ and .planning/codebase/ synchronized

## Special Directories

**artifacts/:**
- Purpose: Generated evidence and test outputs (committed for reproducibility)
- Generated: Yes (by cargo test, verify.sh, PRD harnesses)
- Committed: Yes (for reproducibility; artifacts/story/ contains postmortems)
- Content: State snapshots, replay outcomes, gate outputs, test evidence

**target/:**
- Purpose: Build artifacts (Rust cargo output)
- Generated: Yes (by cargo build/test)
- Committed: No (in .gitignore)
- Content: Compiled binaries, test outputs, dependencies

**mutants.out/, mutants.out.old/:**
- Purpose: Mutation testing results (tracking test coverage against wrong implementations)
- Generated: Yes (by cargo-mutants)
- Committed: Yes (for visibility)
- Content: Mutant scores, killed/survived mutation tracking

**.cache/, .context/, .gates/, .code/:**
- Purpose: Claude Code session cache and context
- Generated: Yes (by Claude Code)
- Committed: No (in .gitignore)
- Content: Session state, previous analyses, git context

**.planning/codebase/:**
- Purpose: Architecture and structure discovery outputs (NEW)
- Generated: Yes (by GSD mapper orchestrator)
- Committed: Yes (for onboarding and navigation)
- Content: ARCHITECTURE.md, STRUCTURE.md, STACK.md

---
*Structure analysis: 2026-02-23*
