## 

### Problem

You already have the right source of truth: `specs/status/status_reason_registries_manifest.json`.  
And your validator enforces contract-version binding and code membership.

But unless Rust and Python **consume that manifest mechanically**, you will regress into:

- Hand-written strings
    
- Slightly different enums
    
- “Active but actually blocked” style lies
    

### Goal

**One registry → generated types in both languages → compile-time + CI enforcement**

### Concrete implementation

Add a generator script:

- Input: `specs/status/status_reason_registries_manifest.json`
    
- Output (Rust): `crates/soldier_core/src/status/reason_codes.rs`
    
- Output (Python): `python/status_reason_codes.py`
    

Rust output example:

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]  
pub enum ModeReasonCode {  
    REDUCEONLY_OPEN_PERMISSION_LATCHED,  
    REDUCEONLY_POLICY_STALE,  
    KILL_WATCHDOG_HEARTBEAT_STALE,  
    // ...  
}  
  
impl ModeReasonCode {  
    pub fn as_str(self) -> &'static str {  
        match self {  
            ModeReasonCode::REDUCEONLY_OPEN_PERMISSION_LATCHED => "REDUCEONLY_OPEN_PERMISSION_LATCHED",  
            // ...  
        }  
    }  
}

Python output example:

from enum import Enum  
  
class ModeReasonCode(str, Enum):  
    REDUCEONLY_OPEN_PERMISSION_LATCHED = "REDUCEONLY_OPEN_PERMISSION_LATCHED"  
    # ...

### CI/verify gate (non-negotiable)

Add a verify step:

1. run generator
    
2. fail if `git diff` shows changes
    

That makes drift impossible without an explicit, reviewed change.