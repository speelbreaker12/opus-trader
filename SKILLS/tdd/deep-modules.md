# Deep Modules

From John Ousterhout's *A Philosophy of Software Design*:

**Deep module** = small interface + lots of implementation

```
┌─────────────────────┐
│   Small Interface   │  ← Few methods, simple params
├─────────────────────┤
│                     │
│                     │
│  Deep Implementation│  ← Complex logic hidden
│                     │
│                     │
└─────────────────────┘
```

**Shallow module** = large interface + little implementation (avoid)

```
┌─────────────────────────────────┐
│       Large Interface           │  ← Many methods, complex params
├─────────────────────────────────┤
│  Thin Implementation            │  ← Just passes through
└─────────────────────────────────┘
```

## Applied to This Codebase

### Deep: ExecutionEngine

`ExecutionEngine::tick()` is a deep interface — one method hides the entire 8-gate pipeline (RiskState → Preflight → Quantize → NetEdge → Pricer → LiquidityGate → RecordedBeforeDispatch → Dispatch). Callers don't know about gates.

### Shallow (avoid): Individual gate accessors

Exposing `pub fn risk_gate()`, `pub fn preflight_gate()`, etc. as separate public methods would be shallow — the interface mirrors the implementation 1:1.

### When designing new modules, ask:

- Can I reduce the number of public methods?
- Can I simplify the parameters?
- Can I hide more complexity inside?
- Does the interface reveal implementation structure? (bad)
- Can a caller use this without understanding the internals? (good)

## Testing Implication

Deep modules are tested at the **boundary** (the small interface), not by reaching inside. This means:
- Tests call `ExecutionEngine::tick()`, not individual gates
- Gate-level tests live as unit tests inside `src/`, not as integration tests
- Wire types (`LiquidityGateInput`, etc.) can be `pub(crate)` — they're internal
