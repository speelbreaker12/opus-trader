# Codebase Structure

**Analysis Date:** 2026-02-25

## Directory Layout

```
[project-root]/
├── .planning/                  # Planning artifacts and generated maps
│   └── codebase/               # `ARCHITECTURE.md`, `STRUCTURE.md`
├── crates/                     # Rust workspace crates
│   ├── soldier_core/           # Core execution/risk/venue domain
│   │   ├── src/                # `execution`, `risk`, `venue`, `recovery`
│   │   └── src/store/          # storage abstractions for core-facing data
│   └── soldier_infra/          # Infrastructure, persistence, bootstrap
│       ├── src/                # config/bootstrap/wal/store/venue adapters
│       └── src/store/          # ledger and registry implementations
├── dashboard/                  # Runtime telemetry and publication
│   ├── convex/                 # Convex endpoint + schema + status mutations
│   └── publisher/              # Python publisher/spool/state utilities
├── docs/                       # Documentation and process guidance
├── plans/                      # Verification workflow and gate scripts
├── specs/                      # Contract and workflow specs
├── tests/                      # Test suites (feature-level mapping not exhaustive)
├── scripts/                    # Utility scripts
├── tools/                      # Operational tooling
├── python/                     # Python helpers
├── artifacts/                  # Verification artifacts and logs
└── target/                     # Rust build artifacts
```

## Directory Purposes

**`.planning/`:**
- Purpose: Stores planning outputs and generated artifacts.
- Contains: mapping documents and agent-generated deliverables.
- Key files: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`.
- Subdirectories: `codebase/`.

**`crates/`:**
- Purpose: Primary runtime source code.
- Contains: Rust crates with clear domain/infrastructure split.
- Key files: `Cargo.toml`, `crates/soldier_core/Cargo.toml`, `crates/soldier_infra/Cargo.toml`.
- Subdirectories: `soldier_core/`, `soldier_infra/`.

**`crates/soldier_core/`:**
- Purpose: Core execution engine and policy logic.
- Contains: `execution`, `risk`, `venue`, `recovery`, `idempotency` modules.
- Key files: `crates/soldier_core/src/lib.rs`, `crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_core/src/recovery/mod.rs`.
- Subdirectories: `crates/soldier_core/src/execution/`, `crates/soldier_core/src/risk/`, `crates/soldier_core/src/venue/`, `crates/soldier_core/src/recovery/`.

**`crates/soldier_infra/`:**
- Purpose: Infrastructure implementation and persistence support.
- Contains: bootstrap, config, WAL, ledger, trade-id registry, and Deribit integrations.
- Key files: `crates/soldier_infra/src/bootstrap.rs`, `crates/soldier_infra/src/config.rs`, `crates/soldier_infra/src/wal.rs`, `crates/soldier_infra/src/store/ledger.rs`.
- Subdirectories: `crates/soldier_infra/src/deribit/`, `crates/soldier_infra/src/store/`.

**`dashboard/`:**
- Purpose: Operational observability and status publishing.
- Contains: Convex backend and Python publisher modules.
- Key files: `dashboard/convex/http.ts`, `dashboard/convex/status.ts`, `dashboard/publisher/publisher.py`.
- Subdirectories: `dashboard/convex/`, `dashboard/publisher/`.

**`plans/`:**
- Purpose: Verification and workflow gate execution.
- Contains: shell scripts and plan/state config files.
- Key files: `plans/verify.sh`, `plans/verify_fork.sh`, `plans/preflight.sh`.
- Subdirectories: not deeply nested for this mapping.

**`specs/`:**
- Purpose: Contracts and workflow requirements consumed by checks.
- Contains: behavioral definitions and workflow contracts.
- Key files: `specs/CONTRACT.md`, `specs/WORKFLOW_CONTRACT.md`, `plans/prd.json`.
- Subdirectories: multiple spec/contract files.

**`docs/`:**
- Purpose: Knowledge base and process documentation.
- Contains: architecture/structure maps and standards.
- Key files: `docs/codebase/architecture.md`, `docs/codebase/structure.md`, `docs/codebase/stack.md`.
- Subdirectories: `docs/codebase/`, `docs/skills/`.

## Key File Locations

**Entry Points:**
- `crates/soldier_infra/src/bootstrap.rs`: runtime bootstrap and initialization.
- `dashboard/convex/http.ts`: HTTP entry for status ingestion.
- `dashboard/publisher/publisher.py`: publisher process entrypoint.
- `plans/verify.sh`: verification orchestration entrypoint.
- `crates/soldier_core/src/lib.rs`: core module root exports (`Not detected`: application `main` binary in this repo).

**Configuration:**
- `Cargo.toml`: workspace configuration.
- `crates/soldier_infra/src/config.rs`: infra/runtime configuration parsing.
- `dashboard/convex/http.ts`: request authentication/validation boundary for inbound status posts.
- `plans/progress.txt`: workflow state tracking.

**Core Logic:**
- `crates/soldier_core/src/execution/intent_assembly.rs`: canonical input assembly.
- `crates/soldier_core/src/execution/pipeline.rs`: staged execution pipeline.
- `crates/soldier_core/src/execution/dispatch_map.rs`: routing decisions.
- `crates/soldier_infra/src/wal.rs`: durability boundary.
- `crates/soldier_infra/src/store/ledger.rs`: replayable ledger.
- `dashboard/publisher/transform.py`: status normalization before publish.

**Testing:**
- `tests/`: Not detected (directory exists, but test topology not fully mapped in this pass).
- `crates/*/src` module tests: Not detected (local/unit tests not deeply enumerated in this pass).

**Documentation:**
- `README.md`: onboarding + behavior overview.
- `REPO_MAP.md`: repository layout reference.
- `ENTRYPOINTS.md`: documented entry behavior.
- `AGENTS.md`: agent-specific instruction envelope.

## Naming Conventions

**Files:**
- Snake_case for most Rust/TS/Python source files: `intent_assembly.rs`, `status.ts`, `publisher.py`.
- Uppercase project metadata and policy files: `README.md`, `AGENTS.md`, `CHANGELOG.md` (if present).
- Shell scripts at top of workflow folder: `verify.sh`, `preflight.sh`.

**Directories:**
- Snake_case and kebab_case names for package/grouping directories: `soldier_core`, `soldier_infra`, `dashboard`, `plans`.
- Plural naming for grouped collections: `docs/`, `tests/`, `prompts/` (where present).

**Special Patterns:**
- `mod.rs` for Rust module entry files.
- `*.md` for policy/spec artifacts.
- `*.sh` for executable gate scripts.

## Where to Add New Code

**New Feature:**
- Primary code: `crates/soldier_core/src/execution/`.
- Recovery/infrastructure interactions: `crates/soldier_infra/src/`.
- Tests: `tests/` (or local module tests).

**New Component/Module:**
- Implementation: `crates/soldier_core/src/<domain>/`.
- Types/interfaces: same directory as module.
- Tests: `tests/` or local module test sections.

**New Route/Command:**
- Definition/handler: `dashboard/convex/http.ts` and `dashboard/convex/status.ts`.
- Verification of request path: `dashboard/convex/validators.ts`.
- Tests: Not detected (no dedicated route test folder observed).

**Utilities:**
- Shared helpers: `crates/soldier_core/src/` and `dashboard/publisher/`.
- Type definitions: `dashboard/convex/schema.ts`, `crates/soldier_infra/src/`.

## Special Directories

**`artifacts/`:**
- Purpose: Verification and CI run outputs.
- Source: `plans/verify.sh` execution.
- Committed: Not detected (typically generated).

**`target/`:**
- Purpose: Rust compiler build output.
- Source: Cargo build/test operations.
- Committed: No

**`.planning/codebase/`:**
- Purpose: This mapping output location.
- Source: generated by this pass using repository templates.
- Committed: Yes

---

*Structure analysis: 2026-02-25*
*Update when directory structure changes*
