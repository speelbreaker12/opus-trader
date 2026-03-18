# Interface Design for Testability

Good interfaces make testing natural:

## 1. Accept dependencies, don't create them

```rust
// Testable: client is injected
pub fn dispatch_order(intent: &OrderIntent, client: &dyn ExchangeClient) -> Result<()> {
    client.submit(intent.to_order())
}

// Hard to test: creates its own client
pub fn dispatch_order(intent: &OrderIntent) -> Result<()> {
    let client = BinanceClient::from_env()?;  // untestable
    client.submit(intent.to_order())
}
```

## 2. Return results, don't produce side effects

```rust
// Testable: returns a decision, caller acts on it
pub fn evaluate_gate(input: &GateInput) -> GateResult {
    if input.is_stale() {
        GateResult::Block(RejectReason::Stale)
    } else {
        GateResult::Pass
    }
}

// Hard to test: produces side effects internally
pub fn evaluate_and_dispatch(input: &GateInput) -> Result<()> {
    if !input.is_stale() {
        self.client.submit(order)?;  // side effect buried inside
    }
    Ok(())
}
```

## 3. Small surface area

- Fewer public methods = fewer tests needed
- Fewer params = simpler test setup
- The 8-gate pipeline has ONE entry point (`tick()`) — that's the interface

## 4. Fail-closed by default (this codebase)

Interfaces should make the safe path the easy path:

```rust
// GOOD: Default is restrictive, caller must prove safety
pub fn resolve_trading_mode(&self) -> TradingMode {
    if self.all_checks_pass() {
        TradingMode::Active
    } else {
        TradingMode::ReduceOnly  // fail-closed default
    }
}

// BAD: Default is permissive, caller must remember to check
pub fn resolve_trading_mode(&self) -> TradingMode {
    if self.any_check_fails() {
        TradingMode::ReduceOnly
    } else {
        TradingMode::Active  // optimistic default
    }
}
```

The difference is subtle but critical: the first version only returns `Active` when ALL checks pass. The second returns `Active` when no check has explicitly failed — missing a check means permissive behavior.

## 5. Newtypes for domain concepts

```rust
// Testable: compiler catches wrong argument order
struct InstrumentId(String);
struct OrderQty(Decimal);

pub fn build_intent(id: InstrumentId, qty: OrderQty) -> Intent { ... }

// Hard to test correctly: easy to swap arguments
pub fn build_intent(id: String, qty: Decimal) -> Intent { ... }
```
