# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```rust
/// GOOD: Tests observable behavior through public API
#[test]
fn test_open_intent_blocked_when_policy_stale() {
    let mut ctx = TestContext::new();
    ctx.set_policy_stale(true);
    ctx.force_other_gates_pass();

    let result = ctx.dispatch_open_intent();

    assert_eq!(result.dispatch_count, 0);
    assert_eq!(result.reject_reason, RejectReasonCode::PolicyStale);
}
```

Characteristics:
- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test (dispatch_count + reason is one logical assertion)

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```rust
/// BAD: Tests internal function call, not behavior
#[test]
fn test_policy_guard_calls_check_staleness() {
    let guard = PolicyGuard::new(config);
    let result = guard.check_staleness(); // testing internals
    assert!(result.is_stale);
}
```

Red flags:
- Testing private/internal methods
- Asserting on call counts or ordering of internal operations
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through internal state instead of public interface

```rust
// BAD: Bypasses public interface to check internal state
#[test]
fn test_latch_set_internally() {
    let mut engine = ExecutionEngine::new(config);
    engine.handle_ws_gap();
    assert!(engine.open_permission_latch); // reaching into internals
}

// GOOD: Verifies through public interface
#[test]
fn test_ws_gap_blocks_open_dispatch() {
    let mut ctx = TestContext::new();
    ctx.trigger_ws_gap();

    let result = ctx.dispatch_open_intent();

    assert_eq!(result.dispatch_count, 0);
    assert_eq!(result.latch_reason, LatchReason::WsBookGap);
}
```

## Causality Proof (This Codebase)

From CONTRACT.md: Tests must prove the guard is the *sole* reason for the outcome via:
- `dispatch_count` (0 vs 1)
- Specific `reject_reason` code
- Specific `latch_reason` code

This means TRIP/NON-TRIP test pairs: same setup, flip one variable, different outcome. The flip proves causality.
