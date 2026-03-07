## Plan: 4 PRs, in order

### PR 1 — Add the shell, no behavior change

Goal: introduce the new public API **without** ripping out old paths yet.

Add:

- `ExecutionEngine`
    
- `ExecutionInput`
    
- `ExecutionRuntime`
    
- `ExecutionDecision`
    

Implementation:

- `ExecutionEngine::decide(...)` delegates internally:
    
    - `Open(...)` → current `build_open_order_intent_runtime(...)`
        
    - `Reduce/Cancel(...)` → current pipeline/chokepoint path as appropriate
        

Rules:

- Keep old public orchestration APIs temporarily.
    
- Mark them `#[deprecated]` + `#[doc(hidden)]`.
    
- Add **equivalence tests**: old API result == new engine result for:
    
    - open healthy
        
    - open rejected
        
    - close bypass path
        
    - cancel-only
        
    - WAL failure
        

This gives you the single entrypoint **first**, without a big-bang refactor.

---

### PR 2 — Normalize the **public output**

Goal: make the engine return the right contract so you can start shrinking the facade.

Right now:

- `PipelineResult` already carries `decision + reject_reason_code`
    
- `OpenRuntimeOutput` carries `choke_result + gate_results + metadata`
    

Use that as the transition:

- make `ExecutionDecision::Rejected` carry:
    
    - `RejectReasonCode`
        
    - `GateStep`
        
    - detail text
        
- make `ExecutionDecision::Approved` carry only the metadata production callers need
    

**Do not** expose `GateResults` publicly in the new output.  
That is internal orchestration state, not contract.

Once this is in place, you can start cutting these from `api.rs`:

- `ChokeMetrics`
    
- `GateResults`
    
- `build_gate_results`
    
- maybe `reject_reason_from_chokepoint` later, if the engine always returns code directly
    

---

### PR 3 — Normalize the **public input**

Goal: stop leaking internal execution wiring through public structs.

Today, `IntentPipelineInput` and `OpenRuntimeInput` still expose gate wiring directly, including liquidity/net-edge/pricer inputs.

Replace that with:

- `OpenExecutionInput`
    
- `ReduceExecutionInput`
    
- `CancelExecutionInput`
    

Each one should contain only **domain-level inputs**, for example:

- order request
    
- venue capabilities / feature flags
    
- fee snapshot / config
    
- expiry input
    
- market snapshot
    
- risk snapshot
    
- dispatch consistency proof if it is truly domain contract, otherwise derive it internally
    

Then create **private builders** inside execution that derive:

- `BaseGatesInput`
    
- `LiquidityGateInput`
    
- `NetEdgeInput`
    
- `PricerInput`
    
- `QuantizeConstraints`
    
- `AssembledPipelineParams`
    

At the end of this PR:

- `IntentPipelineInput`
    
- `OpenRuntimeInput`
    
- `QuantizePipelineInput`
    
- `PipelineResult`
    
- `OpenRuntimeOutput`
    

should all be `pub(crate)` or private.

This is the real unlock that lets you finally make gate wire types `pub(crate)` too.

---

### PR 4 — Collapse the internal orchestration paths

Goal: stop living with two public orchestration functions forever.

Right now both `pipeline.rs` and `open_runtime.rs` are orchestration layers over shared gates + chokepoint.

After PR 3, add one private internal runner, something like:

fn run_execution_internal(  
    input: InternalExecutionInput<'_>,  
    runtime: &mut ExecutionRuntime<'_>,  
) -> ExecutionDecision

Then:

- `ExecutionEngine::decide` becomes the only public entrypoint
    
- `evaluate_intent_pipeline` becomes `pub(crate)` or deleted
    
- `build_open_order_intent_runtime` becomes `pub(crate)` or deleted
    
- all tests in `tests/` switch to `ExecutionEngine`
    
- layer-1 derivation tests stay as unit tests in the execution submodules
    

This is where Upgrade 1B is actually finished.

## What should remain public after 1B

Keep only what real external consumers need.

Definitely keep public:

- `ExecutionEngine`
    
- `ExecutionInput`
    
- `ExecutionDecision`
    
- `RejectReasonCode`
    
- `RecordedBeforeDispatchGate` (infra needs this)
    
- TLSM public types that infra uses (`TlsmTransitionSink`, `PersistedTransition`, `TlsmState`, etc.)
    

Probably cut from the facade:

- `ChokeMetrics`
    
- `GateResults`
    
- `build_gate_results`
    
- `IntentPipelineInput`
    
- `OpenRuntimeInput`
    
- `PipelineResult`
    
- `OpenRuntimeOutput`
    

## Mechanical proof that 1B is done

At the end, I’d want these proofs:

1. **No public legacy orchestration**
    

rg -n 'evaluate_intent_pipeline|build_open_order_intent_runtime' crates/ \  
  -g'!crates/soldier_core/src/execution/**'

Should be zero.

2. **No public legacy input/output leak**
    

rg -n 'IntentPipelineInput|OpenRuntimeInput|PipelineResult|OpenRuntimeOutput|GateResults|ChokeMetrics' \  
  crates/soldier_core/src/execution/api.rs

Should be zero.

3. **Contract tests only use the engine**
    

rg -n 'build_gate_results|build_order_intent_with_|reject_reason_from_chokepoint' \  
  crates/soldier_core/tests

Should be zero or limited to intentionally kept legacy-compat tests during migration.

4. **Wire types can finally become `pub(crate)`**
    

- `LiquidityGateInput`
    
- `NetEdgeInput`
    
- `PricerInput`
    
- etc.
    

If those are still `pub` at the end of 1B, you didn’t actually finish the upgrade.

## The trap to avoid

Do **not** ship a fake `ExecutionEngine` that simply takes `IntentPipelineInput` or `OpenRuntimeInput` publicly. That is wrapper theater, not architecture.

The point of 1B is not “one more public type.”  
The point is: **one public decision API, private wiring, smaller mental model**.