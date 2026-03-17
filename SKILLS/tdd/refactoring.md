# Refactor Candidates

After all tests pass (GREEN), look for:

- **Duplication** → Extract function (keep tests on public interface)
- **Long methods** → Break into private helpers (tests still use public API)
- **Shallow modules** → Combine or deepen (merge two thin layers into one deep one)
- **Feature envy** → Move logic to where data lives
- **Primitive obsession** → Introduce newtypes (`InstrumentId`, `OrderQty`)
- **Existing code** the new code reveals as problematic

## Rules

- **Never refactor while RED** — get to GREEN first
- **Run tests after each refactor step** — small steps, always passing
- **Tests should NOT change during refactor** — if they do, you're changing behavior
- **Don't refactor beyond the current task** — CLAUDE.md says avoid over-engineering

## This Codebase Patterns

### Gate consolidation
If two gates share logic, consider a shared trait with `evaluate(&Input) -> GateResult`. But only if there's real duplication — don't abstract prematurely.

### Wire type simplification
If a gate's input struct has many fields that are always derived the same way, consider a builder or `From` impl to reduce test setup boilerplate.

### Visibility tightening
After refactoring, check if any `pub` items can become `pub(crate)` or private. The facade pattern in `execution/mod.rs` should expose only `api::*`.
