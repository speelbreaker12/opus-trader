# Codebase Map: Structure

## Repository layout

- `crates/` — Rust workspace crates.
  - `crates/soldier_core/` — execution/risk/venue domain logic.
  - `crates/soldier_infra/` — infra and adapter logic.
- `plans/` — workflow harness (`verify`, PRD tooling, pass gating).
- `docs/` — schemas and codebase maps.
- `specs/` — contracts, plans, formal specs.
- `scripts/` — contract/spec validation scripts.
- `reviews/` — review checklists and postmortems.
- `.github/workflows/ci.yml` — CI.

## Key entry points

- `plans/verify.sh` — canonical verify entrypoint.
- `plans/verify_fork.sh` — canonical verify implementation.
- `plans/prd_set_pass.sh` — guarded pass mutation.
- `crates/soldier_core/src/lib.rs` — core crate root.

## Important files

- `specs/CONTRACT.md`
- `specs/WORKFLOW_CONTRACT.md`
- `specs/IMPLEMENTATION_PLAN.md`
- `plans/prd.json`
- `plans/progress.txt`

## Generated artifacts

- `artifacts/verify/*`
- `target/*`
