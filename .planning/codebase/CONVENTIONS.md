# Coding Conventions

**Analysis Date:** 2026-02-23

## Naming Patterns

**Files:**
- Rust source files: `snake_case.rs` (e.g., `liquidity_gate.rs`, `exposure_budget.rs`)
- Test files: `test_<module>.rs` for unit/integration tests (e.g., `test_liquidity_gate.rs`)
- Property-based tests: `prop_<module>.rs` (e.g., `prop_liquidity_gate.rs`)
- Module organization: Public re-exports in `mod.rs` files

**Functions:**
- Private helper functions: `snake_case` (e.g., `compute_wap()`, `reject_with_metrics()`)
- Public API functions: `snake_case` with full underscore separation (e.g., `evaluate_liquidity_gate()`, `compute_intent_hash()`)
- Test functions: `test_<descriptive_name>_<outcome>` or `test_at<number>_<gate>_<scenario>()` (e.g., `test_at222_slippage_exceeds_max_rejected()`, `test_base_gates_all_pass_returns_proof()`)
- Builder/factory functions: `<thing>()` (e.g., `gate_input()`, `passing_base_input()`)

**Variables:**
- Local variables: `snake_case` (e.g., `order_qty`, `reject_reason`, `fillable_qty`)
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `LIQUIDITY_GATE_REJECT_NO_L2_TOTAL`, `CSP_MINIMUM_KEYS`)
- Static atomics: descriptive `SCREAMING_SNAKE_CASE` (e.g., `LIQUIDITY_GATE_REJECT_NO_L2_TOTAL`)
- Tuple/shorthand: abbreviated (e.g., `ts` for timestamp, `wap` for weighted average price)

**Types:**
- Public structs/enums: `PascalCase` (e.g., `LiquidityGateInput`, `RejectReasonCode`, `RiskState`)
- Newtypes for domain values: `PascalCase` (e.g., `InstrumentId`, `ReservationId`)
- Enum variants: `PascalCase` (e.g., `LiquidityGateRejectReason::InsufficientDepthWithinBudget`)
- Generic parameters: `T`, `'a`, `'b` (conventional)
- Lifetime parameters: `'a`, `'static` where applicable

## Code Style

**Formatting:**
- Default Rust style (rustfmt 2024 edition, no custom config checked in)
- Line length: 100 columns (inferred from code samples, not strict rule)
- Indentation: 4 spaces
- Struct/enum field formatting: Each field on own line with type annotation

**Linting:**
- `#![forbid(unsafe_code)]` at crate root (both `soldier_core` and `soldier_infra`)
- No clippy overrides (default lints enforced)
- Exhaustive pattern matching required (no wildcards on critical enums)
- Numeric validation: explicit `is_finite()` checks for all f64 operations

## Import Organization

**Order:**
1. Standard library imports (`use std::...`)
2. External crate imports (`use proptest::...`, `use tracing::...`)
3. Internal crate imports (`use crate::...`)
4. Module-level items (`use super::...`)
5. Grouped by logical domain (e.g., all risk module imports together)

**Path Aliases:**
- No aliasing of crate paths (explicit full paths preferred)
- Re-exports centralized in `mod.rs` files (see `/crates/soldier_core/src/risk/mod.rs`)
- Module re-exports use `pub use` with explicit item list (not `*`)

Example from `risk/mod.rs`:
```rust
pub use exposure_budget::{
    ExposureBucket, ExposureBudgetInput, ExposureBudgetMetrics,
    ExposureBudgetRejectReason, ExposureBudgetResult,
    evaluate_global_exposure_budget, exposure_budget_reject_total,
};
```

## Error Handling

**Patterns:**
- Prefer `?` operator over `unwrap()` or `expect()`
- Only use `expect()` with explanatory context message (e.g., `"config missing: DB_URL"`)
- Error types use enums for domain-specific rejection reasons (e.g., `FillableDepthError`, `LiquidityGateRejectReason`)
- Fail-closed: invalid/missing data returns restrictive/safe value (e.g., missing L2 → reject OPEN orders)
- Explicit error handling for floating-point operations:
  ```rust
  if !value.is_finite() || value <= 0.0 {
      return Err(InvalidBook);
  }
  ```

**Fail-Closed Examples:**
- Missing L2 book: reject order placement (not silent allowance)
- NaN/Inf quantities: reject with specific code (not clamp to default)
- Stale staleness checks: treat missing data as stale (not fresh)

## Logging

**Framework:** `tracing` crate with structured fields

**Patterns:**
- Debug-level logging for operational details: `tracing::debug!("message", field=value)`
- Info-level for significant events: `tracing::info!(instrument_id = %id, side = ?side, "submitting order")`
- Warn-level for recoverable issues: `tracing::warn!(?e, "operation failed")`
- Error-level for unrecoverable issues (rare, fail-closed handles most)
- Format specifiers: `?` for Debug output, `%` for Display, no specifier for structured fields

**Metric Logging:**
- Separate function for counter increments (e.g., `bump_liquidity_gate_reject()`)
- Emit metric lines via `emit_execution_metric_line(METRIC_KEY, "field=value")`
- Process-lifetime counters in static atomics (e.g., `LIQUIDITY_GATE_REJECT_NO_L2_TOTAL`)

Example:
```rust
tracing::debug!(
    "LiquidityGateReject reason={:?} wap={:?} slippage_bps={:?}",
    reason, wap, slippage_bps
);
```

## Comments

**When to Comment:**
- Module-level doc comments (line 1 of each file): high-level purpose + CONTRACT.md references
- Struct/field doc comments: explain domain meaning (e.g., "Quantized price as integer ticks")
- Algorithm explanations: before complex sections (e.g., fillable depth computation)
- Invariants: explain non-obvious constraints (e.g., "Latch stays set until reconcile() is called")
- Safety justifications: explain why fail-closed behavior is correct
- Avoid: restating obvious code (e.g., `x = x + 1; // increment x`)

**Doc Comment Style:**
```rust
//! High-level module description.
//!
//! **Purpose:** What problem does this solve?
//!
//! **Algorithm:** Steps if non-trivial.
//!
//! **Contracts:** Reference CONTRACT.md sections (e.g., AT-222, §1.3).

/// Input to the Liquidity Gate evaluator.
#[derive(Debug, Clone)]
pub struct LiquidityGateInput {
    /// Order quantity to evaluate.
    pub order_qty: f64,
    /// Order side: true = buy, false = sell.
    pub is_buy: bool,
    /// Intent classification.
    pub intent_class: GateIntentClass,
}
```

## Function Design

**Size:** Functions should be focused and short (50-100 lines typical)
- Complex logic broken into private helpers (`compute_wap()`, `compute_fillable_depth()`)
- Top-level public functions orchestrate (e.g., `evaluate_liquidity_gate()` calls helpers)

**Parameters:**
- Use structs for inputs with 3+ fields (all gate evaluators use `XxxInput` structs)
- Pass references for large/complex types: `&input`, `&snapshot`, `&mut metrics`
- Immutable parameters preferred unless mutation is core responsibility (e.g., metrics collection)

**Return Values:**
- Use enums for multi-outcome decisions: `Result<Value, Error>`, `enum Decision { Allowed, Rejected }`
- Return tuples only for closely related pairs (e.g., `(wap, filled_qty)`)
- Struct wrappers for complex results (e.g., `LiquidityGateResult { decision, metadata }`)
- Never return `Option<Value>` without explaining None case in doc comment

## Module Design

**Exports:**
- Centralize re-exports in `mod.rs` files (not scattered across submodules)
- Export types needed by callers, hide internal helpers (`pub fn`, private `fn`)
- Use `pub use` with explicit item lists (no `*` imports)

**Barrel Files:**
Example from `/crates/soldier_core/src/risk/mod.rs`:
```rust
pub mod exposure_budget;
pub mod fees;
pub mod margin_gate;

pub use exposure_budget::{
    ExposureBucketMetrics, evaluate_global_exposure_budget,
};
pub use fees::evaluate_fee_staleness;
pub use margin_gate::evaluate_margin_headroom_gate;
```

**Crate Structure:**
- `soldier_core`: Pure logic, no I/O (execution gates, risk assessment, recovery)
- `soldier_infra`: Infrastructure layer (config, WAL, Deribit integration, bootstrap)
- Dependencies: `soldier_infra` depends on `soldier_core` (strict layering)

---
*Convention analysis: 2026-02-23*
