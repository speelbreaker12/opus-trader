# Codebase Map: Stack

## Languages

- Rust (workspace crates)
- Bash (workflow harness)
- Python (spec/contract validators)
- JSON/YAML/Markdown (specs, docs, schemas)

## Runtime

- Rust std + local modules (no async runtime committed yet).

## Build and Tooling

- Cargo workspace (`Cargo.toml`).
- `./plans/verify.sh` is the canonical verification gate.
- CI runs `./plans/verify.sh full`.

## Key Dependencies

- `soldier_infra` depends on `soldier_core`.
- Python validator tooling from repository scripts.

## Observability

- verify artifacts in `artifacts/verify/<run_id>/`.
- metrics/log counters in core modules.
