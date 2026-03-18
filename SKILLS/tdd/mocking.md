# When to Mock

Mock at **system boundaries** only:

- External APIs (exchange WebSocket, REST endpoints)
- Time/clock (for staleness checks)
- Randomness (if any)
- File system (WAL recovery scenarios)

Don't mock:
- Your own modules (gates, guards, quantizer)
- Internal collaborators (pricer calling quantizer)
- Anything you control

## Rust-Specific Patterns

### Use trait objects for boundaries

```rust
// Testable: exchange client is injected
pub struct ExecutionEngine<C: ExchangeClient> {
    client: C,
    // ...
}

// Production: real client
let engine = ExecutionEngine::new(BinanceClient::new(config));

// Test: mock client
let engine = ExecutionEngine::new(MockExchangeClient::new());
```

### Use `cfg(test)` for test helpers, not mocks

```rust
// GOOD: Test helper that builds realistic scenarios
#[cfg(test)]
mod test_helpers {
    pub fn make_healthy_context() -> TestContext {
        TestContext::new()
            .with_fresh_feeds()
            .with_risk_state(RiskState::Healthy)
            .with_all_gates_pass()
    }
}
```

### Prefer real implementations over mocks

For gates and guards: use the real implementation with controlled inputs, not a mock that skips the logic. The bug is in the logic, not in the wiring.

```rust
// BAD: Mocking the gate skips the logic we want to test
let mock_gate = MockLiquidityGate::returns(GateResult::Pass);

// GOOD: Real gate with controlled inputs
let gate = LiquidityGate::new(config);
let input = LiquidityGateInput {
    l2_snapshot: make_deep_book(),  // controlled but realistic
    order_qty: dec!(0.1),
    // ...
};
let result = gate.evaluate(&input);
```

## Integration Tests (`tests/` directory)

Important: `#[cfg(test)]` items are NOT visible to integration tests in `tests/`. Use `#[cfg(feature = "test-helpers")]` via dev-dependency for shared test utilities.

```toml
# Cargo.toml
[features]
test-helpers = []

[dev-dependencies]
soldier_core = { path = ".", features = ["test-helpers"] }
```
