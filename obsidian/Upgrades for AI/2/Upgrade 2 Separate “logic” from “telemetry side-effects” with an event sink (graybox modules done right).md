## 

### Problem

A lot of your gate functions increment counters / emit metric lines inside the logic. That’s not “wrong,” but it increases the blast radius of changes: AI touches math → breaks observability contracts → breaks dashboards or contract acceptance.

You _already_ care deeply about metric/contract parity (explicitly in your plan).

### Goal

Make core logic testable as a graybox:

- Inputs → Decision + Events
    
- Tests assert both **behavior** and **emitted events**
    
- Internal implementation can change freely without breaking callers
    

### Concrete implementation pattern

Define a tiny telemetry interface in core:

pub trait ExecutionEvents {  
    fn inc_counter(&mut self, name: &'static str);  
    fn reject(&mut self, code: &'static str, detail: &str);  
}

Then your pure-ish logic becomes:

pub fn evaluate_fee_staleness(  
    input: &FeeCacheSnapshot,  
    events: &mut dyn ExecutionEvents,  
) -> Result<(), FeeStalenessReject> {  
    if input.is_hard_stale() {  
        events.inc_counter("fee_staleness_hard_total");  
        events.reject("FEE_MODEL_HARD_STALE", "fee cache hard-stale");  
        return Err(FeeStalenessReject::HardStale);  
    }  
    Ok(())  
}

Production impl can still write to your current thread-local metric buffer if you want — but now that’s an **adapter**, not baked into every gate.

### Proof step

Write a unit test that asserts emitted events:

#[test]  
fn fee_hard_stale_emits_contract_event() {  
    let mut events = VecEvents::default();  
    let input = FeeCacheSnapshot::hard_stale_fixture();  
  
    let err = evaluate_fee_staleness(&input, &mut events).unwrap_err();  
  
    assert_eq!(err, FeeStalenessReject::HardStale);  
    assert!(events.counters.contains("fee_staleness_hard_total"));  
    assert!(events.rejects.iter().any(|r| r.code == "FEE_MODEL_HARD_STALE"));  
}

This makes the module graybox: you don’t need to inspect internal helpers to be confident.