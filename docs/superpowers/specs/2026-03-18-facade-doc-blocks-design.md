# Facade Doc Block Design

## Rule

- **Has `api.rs`**: `mod.rs`/`lib.rs` gets 3-4 line overview; `api.rs` gets the full facade contract.
- **No `api.rs`** (mod.rs IS the facade): full doc block in `mod.rs`.

## Template: `mod.rs` / `lib.rs` (when `api.rs` exists)

```rust
//! {Subsystem name}.
//!
//! Owns: {comma-separated responsibilities}.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation detail.
```

## Template: `api.rs`

```rust
//! Public {subsystem} facade.
//!
//! This file defines the intended public surface for `{crate_path}`.
//!
//! **Public:** {conceptual groups, not symbol dumps}
//!
//! **Private:** `{mod1}`, `{mod2}`, ...
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public subsystem surface.
```

## Template: `mod.rs` (when mod.rs IS the facade)

```rust
//! {Subsystem name}.
//!
//! Owns: {comma-separated responsibilities}.
//!
//! **Public:** {conceptual groups}
//!
//! **Private:** `{mod1}`, `{mod2}`, ...
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public subsystem surface.
```

Where facade completeness is crate-root rather than local, say so explicitly.

## Wording Rules

1. **Conceptual groups in Public**, not symbol dumps. `api.rs` already has the symbol list.
2. **Module names only in Private**. No one-line descriptions.
3. **Non-brittle Tests line**. Describe locations by pattern, not a file manifest. No counts.
4. **No contract section references** in facade docs. Keep those in the implementation files.

## Per-Subsystem Content

### 1. `execution/mod.rs`

```rust
//! Execution subsystem.
//!
//! Owns: order-intent compilation, execution gating, reject semantics,
//! labeling, group atomicity, TLSM, emergency-close selection, and
//! execution decisions at the dispatch chokepoint.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation detail.
```

### 1b. `execution/api.rs`

```rust
//! Public execution facade.
//!
//! This file defines the intended public surface for `soldier_core::execution`.
//!
//! **Public:** `ExecutionEngine` + inputs, `Side`, `GateStep`,
//! `RejectReasonCode`, group atomicity, TLSM + transitions, label encoding,
//! emergency-close selection, `RecordedBeforeDispatchGate`.
//!
//! **Private:** `build_order_intent`, `pipeline`, `routing`, `gate`, `gates`,
//! `base_gates`, `gate_outcome`, `engine`, `quantize`, `pricer`, `preflight`,
//! `post_only_guard`, `inventory_skew`, `open_runtime`, `order_size`,
//! `intent_assembly`, `dispatch_map`, `domain_model`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public execution surface.
```

### 2. `risk/mod.rs`

```rust
//! Risk subsystem.
//!
//! Owns: fee staleness evaluation, margin headroom gating,
//! pending-exposure evaluation, global exposure budget evaluation,
//! instrument state, and `RiskState`.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation detail.
```

### 2b. `risk/api.rs`

```rust
//! Public risk facade.
//!
//! This file defines the intended public surface for `soldier_core::risk`.
//!
//! **Public:** `RiskState`, fee evaluation, margin gate, pending exposure,
//! exposure budget, `InstrumentState`.
//!
//! **Private:** `fees`, `margin_gate`, `pending_exposure`, `exposure_budget`,
//! `state`, `instrument_state`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public risk surface.
```

### 3. `venue/mod.rs`

```rust
//! Venue subsystem.
//!
//! Owns: instrument cache, venue capabilities, lifecycle classification
//! and expiry guarding, and instrument-kind derivation.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation detail.
```

### 3b. `venue/api.rs`

```rust
//! Public venue facade.
//!
//! This file defines the intended public surface for `soldier_core::venue`.
//!
//! **Public:** `InstrumentCache` + cache types, `VenueCapabilities` +
//! `BotFeatureFlags`, lifecycle types + classification, `InstrumentKind`
//! derivation, expiry guard.
//!
//! **Private:** `cache`, `capabilities`, `lifecycle`, `types`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public venue surface.
```

### 4. `soldier_infra/lib.rs`

```rust
//! Soldier infrastructure crate.
//!
//! Owns: storage bootstrap, gate/config resolution, durable storage
//! (WAL ledger and trade-ID registry), Deribit adapter types, and
//! legacy WAL durability helpers.
//!
//! Public API lives in `api.rs`.
//! All other child modules are intentionally private implementation detail.
```

### 4b. `soldier_infra/api.rs`

```rust
//! Public infra facade.
//!
//! This file defines the intended public surface for `soldier_infra`.
//!
//! **Public:** bootstrap + storage init, gate/config resolution, WAL ledger
//! + trade-ID registry, Deribit adapter types, legacy WAL durability helpers.
//!
//! **Private:** `bootstrap`, `config`, `store`, `deribit`, `wal`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public infra surface.
```

### 5. `idempotency/mod.rs`

```rust
//! Idempotency subsystem.
//!
//! Owns: intent hash computation and deduplication.
//!
//! **Public:** `IntentHashInput`, `compute_intent_hash`, `format_intent_hash`,
//! `intent_hash_ih16`.
//!
//! **Private:** `hash`.
//!
//! **Tests:** facade completeness in `facade_completeness_contract_tests.rs`;
//! integration tests under `tests/` covering the public idempotency surface.
```

### 6. `recovery/mod.rs`

```rust
//! Recovery subsystem.
//!
//! Owns: label-match disambiguation.
//!
//! **Public:** `IntentRecord`, `LabelMatchMetrics`, `MatchQuery`,
//! `MatchResult`, `match_label`.
//!
//! **Private:** `label_match`.
//!
//! **Tests:** facade completeness in `facade_completeness_contract_tests.rs`;
//! integration tests under `tests/` covering the public recovery surface.
```

### 7. `status_codes.rs`

```rust
//! Generated status and reason-code surface.
//!
//! Owns: generated enums for `TradingMode`, `RiskState`, `ModeReasonCode`,
//! `OpenPermissionReasonCode`, `OwnerStateCode`, `DeploymentEnvironment`,
//! `F1CertState`, plus their metadata structs.
//!
//! **Public:** all symbols from `status_codes_generated.rs` via `pub use generated::*`.
//!
//! **Private:** `generated` (inline module wrapping the codegen include).
//!
//! **Tests:** facade completeness in inline `facade_completeness_contract_tests`.
//! Source regenerated by `tools/generate_reason_codes.py`.
```

### 8. `store/mod.rs`

```rust
//! Durable storage subsystem.
//!
//! Owns: WAL ledger append/replay and TLS state persistence,
//! and trade-ID registry.
//!
//! **Public:** `WalLedger`, `IntentRecord`, `TlsState`, `TradeIdRegistry`,
//! `TradeRecord`, and associated config/metrics/error types.
//!
//! **Private:** `ledger`, `trade_id_registry`.
//!
//! **Tests:** unit tests alongside implementation files; integration tests
//! under `tests/` covering the public store surface.
//! Facade completeness covered by the crate-root
//! `facade_completeness_contract_tests.rs`.
```

### 9. `deribit/mod.rs`

```rust
//! Deribit venue adapter types.
//!
//! Owns: Deribit instrument metadata types/mapping and fee-tier cache types.
//!
//! **Public:** `DeribitInstrument`, `DeribitInstrumentKind`, `FeeCache`,
//! `FeeTierData`, `SettlementPeriod`, `TickSizeStep`,
//! `map_deribit_kind_to_input`.
//!
//! **Private:** `account_summary`, `public`.
//!
//! **Tests:** integration tests under `tests/` covering Deribit adapter types.
//! Facade completeness covered by the crate-root
//! `facade_completeness_contract_tests.rs`.
```
