

### Problem

Right now both crates expose entire module trees (`pub mod execution; pub mod risk; ...`). That’s fine in a tiny repo. It becomes a coupling disaster as soon as you add “just one more crate” or the AI starts importing internal helpers across modules because it’s convenient.

Evidence: `soldier_core/src/lib.rs` exports everything as public modules.

### Goal

Make it so:

- There is exactly **one obvious entry file** per subsystem (“progressive disclosure”).
    
- Everything else is `mod` / `pub(crate)` so AI _can’t_ create spaghetti imports.
    

### Concrete implementation

Create an **API facade** inside each deep module. Example for execution:

**Before (conceptually):**

- `soldier_core::execution::pipeline::run_pipeline(...)`
    
- `soldier_core::execution::gate::evaluate_liquidity_gate(...)`
    
- Everything is reachable.
    

**After:**

- `soldier_core::execution::ExecutionEngine` is the entrypoint.
    
- Internals are private.
    

Example structure:

// crates/soldier_core/src/execution/mod.rs  
  
//! Execution module facade.  
//! Read this file first.  
  
pub mod api;           // the only public surface  
mod base_gates;  
mod build_order_intent;  
mod pipeline;  
mod gate;  
mod pricer;  
mod quantize;  
// ...  
  
pub use api::{ExecutionEngine, ExecutionInput, ExecutionDecision, RejectReason};

And your public API becomes something like:

// crates/soldier_core/src/execution/api.rs  
  
use super::{pipeline, RejectReasonCode};  
use crate::risk::RiskState;  
  
pub struct ExecutionEngine {  
    // config, maybe caches, maybe telemetry sink handle  
}  
  
pub struct ExecutionInput {  
    pub risk_state: RiskState,  
    // + everything pipeline needs, grouped  
}  
  
pub enum ExecutionDecision {  
    Dispatch { /* intent */ },  
    Reject { code: RejectReasonCode, detail: String },  
}  
  
impl ExecutionEngine {  
    pub fn decide(&mut self, input: ExecutionInput) -> ExecutionDecision {  
        pipeline::run_execution_pipeline(input /* , telemetry */)  
    }  
}

### Proof step (must be mechanical)

Add a rule: **no other crate may import internal execution modules**.

- Rust makes this easy: once internals are not `pub`, imports fail at compile time.
    
- This is how you prevent the AI from “finding a shortcut.”