# Testing Patterns

**Analysis Date:** 2026-02-23

## Test Framework

**Runner:**
- Rust: `cargo test` (built-in test framework)
- Configuration: Workspace root `Cargo.toml` with members `soldier_core` and `soldier_infra`
- Edition: 2024 (Rust edition specified in crate manifests)

**Assertion Library:**
- Rust standard library `assert!()`, `assert_eq!()`, `assert_ne!()`
- No external assertion library (proptest used for property tests, not general assertions)
- Panics on assertion failure (standard Rust behavior)

**Run Commands:**
```bash
cargo test                           # Run all tests
cargo test --lib                     # Run library tests only
cargo test --test '*'                # Run integration tests
cargo test test_liquidity_gate       # Run specific test module
cargo test -- --nocapture           # Show println! output
cargo test -- --test-threads=1      # Run serially (for debugging)
PROPTEST_CASES=1000 cargo test      # Override proptest case count
```

## Test File Organization

**Location:**
- Unit/integration tests co-located in `crates/<crate>/tests/` directory
- Shared test utilities in `tests/common/mod.rs` (imported via `mod common;`)
- Source code unit tests: rare, examples in `src/` for inline derivations

**Naming:**
- Test files: `test_<module>.rs` (e.g., `test_liquidity_gate.rs`)
- Property tests: `prop_<module>.rs` (e.g., `prop_liquidity_gate.rs`)
- Adversarial tests: `adversarial_<scenario>.rs` (e.g., `adversarial_gi_enforcement.rs`)
- Test functions: `test_<descriptive_name>` or contract-anchored `test_at<num>_<gate>_<scenario>()`

## Test Structure

**Suite Organization:**

Standard pattern from `crates/soldier_core/tests/test_liquidity_gate.rs`:

```rust
//! Tests for Pre-Trade Liquidity Gate per CONTRACT.md §1.3.
//!
//! AT-222: OPEN depth shortfall within slippage budget → reject.
//! AT-344: Missing/stale L2 → reject OPEN.
//! AT-909: Missing/stale L2 → Rejected(LiquidityGateNoL2).
//! AT-421: Cancel-only allowed even without L2.

use soldier_core::execution::{/* imports */};

// ─── AT-222: Slippage > max → reject ────────────────────────────────────

#[test]
fn test_at222_slippage_exceeds_max_rejected() {
    let mut m = LiquidityGateMetrics::new();
    let snap = book(vec![(100.0, 1.0), (110.0, 1.0)], vec![], 900);
    let input = gate_input(2.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);

    // Assertions
    assert_eq!(reason, LiquidityGateRejectReason::InsufficientDepthWithinBudget);
    assert_eq!(m.reject_depth_shortfall(), 1);
}
```

**Key Patterns:**
1. Module docstring lists all AT (Acceptance Test) IDs with brief descriptions
2. Tests grouped by AT or scenario with comment separators (`// ─── AT-222: ... ────`)
3. Each test: setup → execute → assert (arrange-act-assert pattern)
4. Metrics collected into mutable binding for assertion (e.g., `let mut m = ...`)
5. Test helpers extracted to reduce duplication (e.g., `book()`, `gate_input()`)

## Mocking

**Framework:** Manual fixture builders (no mocking library)

**Patterns:**

Fixtures are constructed as test data, not mocked:

```rust
/// Helper: build a simple L2 book with given ask/bid levels.
fn book(asks: Vec<(f64, f64)>, bids: Vec<(f64, f64)>, ts: u64) -> L2BookSnapshot {
    L2BookSnapshot {
        asks: asks
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        bids: bids
            .into_iter()
            .map(|(price, qty)| L2Level { price, qty })
            .collect(),
        timestamp_ms: ts,
    }
}

/// Helper: build a gate input with defaults.
fn gate_input(
    order_qty: f64,
    is_buy: bool,
    intent_class: GateIntentClass,
    l2: Option<L2BookSnapshot>,
) -> LiquidityGateInput {
    LiquidityGateInput {
        order_qty,
        is_buy,
        intent_class,
        is_marketable: true,
        l2_snapshot: l2,
        now_ms: 1000,
        l2_book_snapshot_max_age_ms: 500,
        max_slippage_bps: 10.0,
    }
}
```

**Pattern:** Builders accept specific test parameters + fill defaults for others (single source of truth for defaults).

## Fixtures and Factories

**Test Data:**

Central fixture builder in `tests/common/mod.rs`:

```rust
/// Known-passing baseline: all gates pass, risk_state Healthy, all feeds fresh.
///
/// Single source of truth — used by test_intent_pipeline.rs,
/// adversarial_gi_enforcement.rs, and prop_pipeline_gi001.rs.
pub fn base_open_input<'a>() -> IntentPipelineInput<'a> {
    IntentPipelineInput {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Healthy,
        preflight: PreflightInput {
            instrument_kind: InstrumentKind::Option,
            order_type: OrderType::Limit,
            // ... all fields explicitly set with known-good values
        },
        // ... 60+ lines of nested field initialization
    }
}

/// Assert that a `build_order_intent` call produced a rejection with zero dispatches.
///
/// Use for ALL rejection tests, including WAL-gate failures.
pub fn assert_no_dispatch(result: &ChokeResult, metrics: &ChokeMetrics, context: &str) {
    assert!(
        matches!(result, ChokeResult::Rejected { .. }),
        "{context}: expected ChokeResult::Rejected"
    );
    assert_eq!(
        metrics.approved_total(),
        0,
        "{context}: approved_total must be 0 after rejection"
    );
}
```

**Usage Pattern:** Override specific fields from baseline:
```rust
let mut input = base_open_input();
input.risk_state = RiskState::Degraded;
input.intent_class = ChokeIntentClass::Open;
```

## Coverage

**Requirements:** No explicit coverage target enforced (inferred from code)
- All public functions have corresponding tests
- Critical paths (fail-closed behavior, numeric edge cases) are heavily tested
- Acceptance tests (ATs) map to code via doc comments (AT-222, AT-344, etc.)

**Fail-Closed Test Naming:** Tests validating safety gates must include keywords in function name for automated coverage via `plans/fail_closed_coverage.sh`:
- Keywords: `nan`, `missing`, `stale`, `fail_closed`, `invalid`, `expired`, `forbidden`, `degraded`
- Example: `test_future_dated_l2_rejected_fail_closed()`, `test_at344_missing_l2_rejects_open()`

## Test Types

**Unit Tests:**
- Scope: Single function or tight set (e.g., `compute_wap()`, `compute_fillable_depth()`)
- Approach: Direct function call with controlled inputs, assertions on output + side effects (metrics)
- Location: `test_<module>.rs` alongside integration tests
- No test isolation needed (pure functions, no shared state)

Example:
```rust
#[test]
fn test_slippage_within_limit_allowed() {
    let mut m = LiquidityGateMetrics::new();
    let snap = book(vec![(100.0, 10.0)], vec![], 900);
    let input = gate_input(5.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);

    assert!(matches!(result.decision, LiquidityGateDecision::Allowed));
    assert_eq!(m.allowed_total(), 1);
}
```

**Integration Tests:**
- Scope: Multi-gate pipeline or cross-module interaction
- Approach: Full input struct → output checks + metrics validation
- Example: `test_intent_assembly.rs` (sizing + dispatch mapping), `test_intent_pipeline.rs` (all gates)
- Prove causality: rejects with dispatch_count=0, specific reason codes

Example from `test_intent_assembly.rs`:
```rust
#[test]
fn test_assembly_unknown_kind_fails_closed() {
    let meta = InstrumentKindInput { is_option: false, is_future: false, /* ... */ };
    let params = SizingParams { canonical_qty: 1.0, /* ... */ };

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);
    assert_eq!(result, Err(AssemblySizingError::UnknownInstrumentKind));
}
```

**Property Tests (Proptest):**
- Framework: `proptest` crate with custom strategies
- Location: `prop_<module>.rs` files (e.g., `prop_liquidity_gate.rs`)
- Scope: Invariants that hold for any valid input (fuzzing-style)
- Strategies: Constrain input ranges (e.g., `(0.001_f64..1e4)` for quantities)

Example from `prop_liquidity_gate.rs`:
```rust
proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    #[test]
    fn cancel_only_always_allowed(
        has_book in proptest::bool::ANY,
        order_qty in (0.001_f64..1e4),
    ) {
        let l2_snapshot = if has_book { /* ... */ } else { None };
        let input = LiquidityGateInput { /* ... */ };
        let mut metrics = LiquidityGateMetrics::new();
        let result = evaluate_liquidity_gate(&input, &mut metrics);

        prop_assert!(
            matches!(result.decision, LiquidityGateDecision::Allowed),
            "CancelOnly should always be Allowed"
        );
    }
}
```

**E2E Tests:**
- Framework: Not used in this codebase
- Alternative: Integration tests + acceptance tests (ATs in CONTRACT.md)

## Common Patterns

**Async Testing:**
- Not applicable: codebase is synchronous (no async/await)

**Error Testing:**

Fail-closed validation pattern:

```rust
#[test]
fn test_nan_qty_fails_closed() {
    let meta = InstrumentKindInput { is_option: true, /* ... */ };
    let params = SizingParams {
        canonical_qty: f64::NAN,  // Explicitly test invalid input
        /* ... */
    };
    let mut mismatch = MismatchMetrics::new();

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);

    assert!(
        matches!(result, Err(AssemblySizingError::InvalidOrderSize(_))),
        "NaN qty must be rejected as InvalidOrderSize"
    );
}
```

**Numeric Edge Cases:**

Explicit invalid input testing:

```rust
#[test]
fn test_future_dated_l2_rejected_fail_closed() {
    let snap = book(vec![(100.0, 10.0)], vec![], 1_500);  // ts > now_ms
    let input = gate_input(1.0, true, GateIntentClass::Open, Some(snap));

    let result = evaluate_liquidity_gate(&input, &mut m);
    assert!(matches!(
        result.decision,
        LiquidityGateDecision::Rejected {
            reason: LiquidityGateRejectReason::LiquidityGateNoL2
        }
    ));
}
```

**Metrics Validation:**

Verify counters and side effects:

```rust
let mut m = LiquidityGateMetrics::new();
let result = evaluate_liquidity_gate(&input, &mut m);

assert_eq!(m.reject_depth_shortfall(), 1);
assert_eq!(m.allowed_total(), 0);
assert_eq!(m.reject_no_l2(), 0);
```

---
*Testing analysis: 2026-02-23*
