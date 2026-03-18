# Production Entry Points

> R7c wiring audit reference. An enforcement function with zero callers traced back
> to an entry point in this file is classified `PROVEN-UNIT` (island guard).

## Dispatch Call Hierarchy

```
[External caller]
    │
    ├─► build_open_intent_with_assembly()          ← open_runtime.rs:393  (OPEN path)
    │       └─► assemble_sizing()                  ← intent_assembly.rs:104
    │       └─► build_open_order_intent_runtime()  ← open_runtime.rs:88
    │               └─► evaluate_base_gates()      ← base_gates.rs:226  (gates 1-6)
    │               └─► evaluate_margin_headroom_gate()
    │               └─► evaluate_global_exposure_budget()
    │               └─► PendingExposureBook::reserve()
    │               └─► evaluate_liquidity_gate()  ← gate.rs:461
    │               └─► evaluate_inventory_skew()  ← inventory_skew.rs:124
    │               └─► evaluate_net_edge()        ← gates.rs:166
    │               └─► compute_limit_price()      ← pricer.rs:131
    │               └─► build_order_intent()       ← build_order_intent.rs:263
    │
    ├─► evaluate_assembled_pipeline()              ← intent_assembly.rs:159  (CLOSE/HEDGE/CANCEL)
    │       └─► assemble_sizing()
    │       └─► evaluate_intent_pipeline()         ← pipeline.rs:87
    │               └─► evaluate_base_gates()
    │               └─► evaluate_liquidity_gate()
    │               └─► evaluate_net_edge()
    │               └─► compute_limit_price()
    │               └─► build_order_intent_with_reject_reason_code()
    │
    └─► bootstrap_full()                           ← bootstrap.rs:284  (startup only)
            └─► build_gate_config_from_raw()
            └─► bootstrap_storage()
                    └─► WalLedger::with_storage_path()
                    └─► TradeIdRegistry::with_storage_path()
```

## Top-Level Entry Points

### Pipeline Orchestrators (production dispatch paths)

| Function | File | Role |
|----------|------|------|
| `evaluate_assembled_pipeline()` | `intent_assembly.rs:159` | CLOSE/HEDGE/CANCEL: assembly + gates 1-10 |
| `build_open_intent_with_assembly()` | `open_runtime.rs:393` | OPEN: assembly + gates 1-10 + margin/exposure/liquidity |
| `evaluate_intent_pipeline()` | `pipeline.rs:87` | Inner pipeline (gates 1-10), called by assembled pipeline |
| `build_open_order_intent_runtime()` | `open_runtime.rs:88` | Inner OPEN pipeline, called by open assembly |
| `evaluate_base_gates()` | `base_gates.rs:226` | Shared gates 1-6 evaluator |

### Single Chokepoint (CSP.5.2)

| Function | File | Status |
|----------|------|--------|
| `build_order_intent_with_wal_gate()` | `build_order_intent.rs:82` | Preferred (derives gate 10 from WAL append) |
| `build_order_intent_with_optional_wal_gate()` | `build_order_intent.rs:101` | Preferred variant (optional WAL) |
| `build_order_intent()` | `build_order_intent.rs:263` | Deprecated (accepts precomputed `wal_recorded` bool) |

### Individual Gates

| Gate # | Function | File |
|--------|----------|------|
| 2 | `preflight_intent()` | `preflight.rs:200` |
| 3 | `quantize()` | `quantize.rs:186` |
| 4 | `validate_and_dispatch()` | `dispatch_map.rs:230` |
| 5 | `evaluate_fee_staleness()` | `risk/fees.rs` |
| 6 | `evaluate_expiry_guard()` | `venue/lifecycle.rs:95` |
| 7 | `evaluate_liquidity_gate()` | `gate.rs:461` |
| 8 | `evaluate_net_edge()` | `gates.rs:166` |
| 9 | `compute_limit_price()` | `pricer.rs:131` |
| 10 | `DurableWalGate::record_before_dispatch()` | `wal.rs:145` |

### Risk / PolicyGuard

| Function | File | Purpose |
|----------|------|---------|
| `evaluate_margin_headroom_gate()` | `risk/margin_gate.rs` | Margin utilization gate |
| `evaluate_global_exposure_budget()` | `risk/exposure_budget.rs` | Delta-exposure budget |
| `opens_blocked()` | `venue/cache.rs:282` | RiskState → OPEN permission |
| `evaluate_inventory_skew()` | `execution/inventory_skew.rs:124` | Skew-adjusted net edge |

### Infrastructure Bootstrap

| Function | File | Purpose |
|----------|------|---------|
| `bootstrap_full()` | `bootstrap.rs:284` | Validates gate config + WAL + trade-ID registry |
| `bootstrap_storage()` | `bootstrap.rs:145` | WAL + trade-ID registry init only |
| `build_gate_config_from_raw()` | `config.rs:545` | Appendix A threshold validation |
| `resolve_config_value()` | `config.rs:471` | Per-parameter default resolver |

### WAL / Persistence

| Function | File | Purpose |
|----------|------|---------|
| `WalLedger::append()` | `store/ledger.rs` | Durable intent record with fsync |
| `WalLedger::replay()` | `store/ledger.rs` | Startup replay → ReplayOutcome |
| `DurableWalGate::new()` | `wal.rs:112` | Gate-10 adapter construction |
| `TradeIdRegistry::insert_if_absent()` | `store/trade_id_registry.rs` | Idempotency registration |
| `persist_before_dispatch()` | `execution/group.rs:412` | Group intent durable record (AT-936) |

## Wiring Audit Rule

An enforcement function is **PROVEN-INTEGRATED** if `findReferences` shows at least one
caller chain reaching a function in this file. Zero callers = **PROVEN-UNIT** (blocks pass).

All file paths are relative to `crates/soldier_core/src/` or `crates/soldier_infra/src/`.
