## 

You already did this well in `bootstrap_storage()` with `BootstrapResult` forcing acknowledgement.

Do the same anywhere you have “you MUST handle this or you die later” semantics.

### Example: force callers to handle reject reasons explicitly

Instead of returning `Option<OrderIntent>` or a loose `Result`, return a type that must be consumed:

#[must_use = "You must either dispatch the intent or record/propagate the reject outcome"]  
pub struct IntentDecision {  
    pub outcome: GateOutcome,  
    intent: Option<OrderIntent>,  
}  
  
impl IntentDecision {  
    pub fn into_dispatch(self) -> Result<OrderIntent, GateOutcome> {  
        self.intent.ok_or(self.outcome)  
    }  
}

This prevents the AI (or a rushed human) from doing the classic bug:

- “if intent exists dispatch” and silently dropping the “why it failed” path.
    

It’s the same discipline you used for replay/latch.