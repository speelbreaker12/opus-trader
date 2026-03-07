**Upgrade 1B PR1: add a single execution entrypoint shell**.

Why that, and not more cleanup? Because PR #149 finishes the **test migration + fast-loop support** job, but the public execution surface is still a **flat bag of primitives** rather than one public orchestrator. `execution/api.rs` still exports chokepoint/reject-reason/group/TLSM symbols, while orchestration is still split across `evaluate_intent_pipeline(...)` and `build_open_order_intent_runtime(...)`. Those legacy paths still expose public input/output structs like `IntentPipelineInput`, `PipelineResult`, `OpenRuntimeInput`, and `OpenRuntimeOutput`, and those structs still carry gate-level wiring such as `LiquidityGateInput`, `NetEdgeInput`, `PricerInput`, and `wal_recorded`. PR #149 improves coverage and smoke tests, but it does not change that contract shape.

So the bottleneck is now **API shape**, not more testing. Also, even though `soldier_core` and `soldier_infra` still expose public top-level module trees, I would **not** fan out into `risk` or `infra` next. Finish execution first, because that is where the orchestration leak still lives.

Here’s the sequence I’d run.

### 1) Open a small PR that adds the shell only

Add:

- `ExecutionEngine`
    
- `ExecutionInput::{Open, Close, Hedge, CancelOnly}`
    
- `ExecutionRuntime`
    
- `ExecutionDecision::{Approved, Rejected}`
    

Do **not** collapse `Close` and `Hedge` yet. The current chokepoint still models them separately, so merging them now is premature abstraction. Keep them distinct until the code proves they are the same forever. The engine should delegate internally to the current paths:

- `Open` → current open-runtime path
    
- `Close/Hedge/CancelOnly` → current pipeline/chokepoint path as appropriate.
    

**Acceptance checks for PR1**

- old API vs engine parity on:
    
    - approve/reject
        
    - reject code
        
    - gate step
        
    - open-path metadata: `pending_reservation_id`, `effective_risk_state`, `adjusted_min_edge_usd`
        
- run a quick consumer audit for `mode_hint` before dropping it:
    
    - `rg -n 'mode_hint|adjusted_min_edge_usd|pending_reservation_id|effective_risk_state' crates/ --type rust`
        

### 2) Normalize the public output

Once the shell exists and parity is proven, make the public result small and stable:

- `ExecutionDecision::Approved { ... }`
    
- `ExecutionDecision::Rejected { code, step, detail }`
    

Do **not** expose `GateResults` or raw pipeline/open-runtime wrappers to callers anymore. Right now `PipelineResult` and `OpenRuntimeOutput` are transitional wrappers around internal orchestration state; the engine should absorb that and return the final contract directly.

A good rule here:

- `RejectReasonCode` stays public
    
- `reject_reason_from_chokepoint` can stay public during migration
    
- `ChokeMetrics`, `GateResults`, `PipelineResult`, and `OpenRuntimeOutput` should be on the chopping block after parity is established.
    

### 3) Normalize the public input

This is the real unlock.

Replace public wiring structs with domain-level inputs:

- `OpenExecutionInput`
    
- `CloseExecutionInput`
    
- `HedgeExecutionInput`
    
- `CancelOnlyExecutionInput`
    

Then build the internal gate inputs **inside** execution:

- `LiquidityGateInput`
    
- `NetEdgeInput`
    
- `PricerInput`
    
- `QuantizeConstraints`
    
- `BaseGatesInput`
    
- etc.
    

Today, `IntentPipelineInput` and `OpenRuntimeInput` still publish those wires directly. That’s why your gate input types can’t become `pub(crate)` yet.

Two explicit rules belong in the spec before coding:

- **WAL semantics table by variant**
    
    - Open
        
    - Close
        
    - Hedge
        
    - CancelOnly  
        Spell out whether an adapter is required, optional, or bypassed.
        
- **Metrics strategy**  
    Decide now whether the engine:
    
    - owns metrics internally,
        
    - accepts an internal sink trait,
        
    - or carries public metrics one more phase.  
        Right now metrics are still threaded through the old paths, so this cannot stay vague.
        

### 4) Cut the legacy public APIs

After the engine is live and contract tests use it:

- make `IntentPipelineInput`, `OpenRuntimeInput`, `PipelineResult`, and `OpenRuntimeOutput` `pub(crate)` or private
    
- make gate wire types `pub(crate)`
    
- shrink `execution/api.rs`
    
- update the facade allowlist
    
- tighten smoke tests so they exercise `ExecutionEngine`, not legacy helpers.
    

### 5) Only then move to `risk` / `venue` / `infra`

After 1B is complete, repeat the same deep-module discipline in the other subsystems. But right now that would be a distraction. `execution` is the current constraint.

## The exact next deliverable

The next artifact should be a **Phase‑2 spec for PR1 only**, not implementation.

That spec should contain:

- public types for `ExecutionEngine`, `ExecutionInput`, `ExecutionRuntime`, `ExecutionDecision`
    
- variant matrix for `Open / Close / Hedge / CancelOnly`
    
- WAL rule table
    
- output parity checklist
    
- consumer audit for `mode_hint` and other open-runtime metadata
    
- deprecation plan for legacy orchestration functions
    

That’s the highest-leverage next move.