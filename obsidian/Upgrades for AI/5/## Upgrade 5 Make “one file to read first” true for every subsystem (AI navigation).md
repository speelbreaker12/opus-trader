

Right now, your workflow docs are excellent (AGENTS.md / WORKFLOW_CONTRACT), but code navigation can still devolve unless each subsystem has an obvious “start here.”

### Concrete implementation

Add a tiny `README.md` (or module docs) at:

- `crates/soldier_core/src/execution/mod.rs` (facade)
    
- `crates/soldier_core/src/risk/mod.rs` (facade)
    
- `crates/soldier_infra/src/store/mod.rs` already acts like a facade via re-exports.
    

And each one includes:

- **Purpose**
    
- **Public API list**
    
- **Tests to run**
    
- **Contract sections mapped**
    

This is _progressive disclosure_ made real.