# Architecture

**Analysis Date:** 2026-02-23

## Pattern Overview
**Overall:** Fail-Closed Safety-Critical Trading System with Layered Risk Gates

**Key Characteristics:**
- Multi-layered execution chokepoints enforcing pessimistic (fail-closed) safety decisions
- Durable write-ahead logging (WAL) before dispatch to ensure crash-safety and idempotency
- Separation of domain logic (Rust `soldier_core`) from exchange adapters (Rust `soldier_infra`)
- Contract-driven development with specs, entry points, and formal acceptance tests
- Bounded queue isolation between hot execution loop and durable storage writers

## Layers

**Execution Layer (Core Domain Logic):**
- Purpose: Order intent evaluation through 10-gate pipeline with quantization, preflight checks, and pricing
- Location: `crates/soldier_core/src/execution/`
- Contains: Intent assembly, pipeline orchestration, dispatch validation, gate evaluation logic, order sizing, pricing, quantization, labeling, and state machine management
- Depends on: Venue types (instrument kinds), Risk assessment outputs, Idempotency primitives
- Used by: Infra bootstrap, WAL gate adapter, acceptance tests, proof-of-concept harnesses

**Risk Assessment Layer:**
- Purpose: Policy enforcement, exposure budgets, margin headroom, pending exposure tracking, fee staleness validation
- Location: `crates/soldier_core/src/risk/`
- Contains: Risk state machines (Healthy/Degraded/Maintenance/Kill), exposure bucket tracking, margin mode hints, pending exposure reservation system, fee cache snapshots and staleness checks
- Depends on: Venue instrument metadata, execution intent metadata
- Used by: Base gates evaluator, OPEN runtime, execution pipeline, policy guard

**Venue & Instrument Cache Layer:**
- Purpose: Exchange-specific type mapping, instrument kind derivation, venue capabilities, expiry guards, lifecycle error classification
- Location: `crates/soldier_core/src/venue/`
- Contains: Instrument kind enums (Spot/Perp/Call/Put), cache with TTL-based RiskState transitions, capability flags, lifecycle state machines for cancel/settlement handling
- Depends on: Deribit public types (from infra), instrument metadata from exchange
- Used by: Execution pipeline, open runtime, recovery/reconciliation logic

**Idempotency & Recovery Layer:**
- Purpose: Intent deduplication via hash, label encoding/decoding for recovery, label matching during reconciliation
- Location: `crates/soldier_core/src/idempotency/` and `crates/soldier_core/src/recovery/`
- Contains: Intent hash computation (xxhash64), label parsing (12-bit group + 8-bit sequence + flags), label matching queries for startup replay
- Depends on: Execution types (OrderIntent, Side, etc.)
- Used by: Reconciliation harness, WAL replay, trade-ID registry lookups

**Infrastructure Layer (Exchange Adapters):**
- Purpose: Durable storage bootstrap, WAL durability barriers, Deribit API types, trade-ID registry, configuration assembly
- Location: `crates/soldier_infra/src/`
- Contains: WalLedger (append-only intent record store), TradeIdRegistry (per-trade metadata), Deribit instrument parsers, config builders, bootstrap orchestration
- Depends on: soldier_core types and gate functions
- Used by: Application bootstrap, WAL gate 10, recovery harness, durability tests

**Durable Storage Subsystem:**
- Purpose: Crash-safe intent recording with fsync barriers, trade-ID deduplication, state transition logging
- Location: `crates/soldier_infra/src/store/`
- Contains: WalLedger with async writer (bounded queue, fsync barrier), TlsState machines, LedgerMetrics, ReplayOutcome tracking, TradeIdRegistry with insert-if-absent atomicity
- Depends on: Execution intent records (via serde), standard library I/O
- Used by: Bootstrap result, DurableWalGate adapter, reconciliation replay

## Data Flow

**OPEN Intent Dispatch Flow:**
1. External caller provides OrderIntent metadata (intent_class=Open, instrument, size, etc.)
2. `build_open_intent_with_assembly()` invoked (entry point per ENTRY_POINTS.md)
3. Intent assembly: `assemble_sizing()` derives InstrumentKind + OrderSize + dispatch consistency proof
4. `build_open_order_intent_runtime()` evaluates gates 1-6 (shared base gates) via `evaluate_base_gates()`
5. OPEN-specific gates 7-10: liquidity, net edge, inventory skew, margin headroom, pending exposure, global exposure budget
6. Pricer clamps limit price based on liquidity snapshot
7. `build_order_intent_with_wal_gate()` records intent to WAL (gate 10) before returning ChokeResult
8. On accept: OrderIntent returned with RecordedBeforeDispatch marker
9. On reject: ChokeResult with reject reason code, intent not persisted

**CLOSE/HEDGE/CANCEL Intent Dispatch Flow:**
1. External caller provides assembled intent params (pre-sized quantities, intent_class=Close/Hedge/Cancel)
2. `evaluate_assembled_pipeline()` invoked (entry point per ENTRY_POINTS.md)
3. Intent assembly: same as OPEN
4. `evaluate_intent_pipeline()` evaluates gates 1-10 (shared pipeline orchestrator)
5. Same chokepoint gate evaluation + WAL record
6. Intent returned with terminal reason code if cancelled, or dispatch mapping if accepted

**Base Gates (Shared 1-6):**
1. Gate 1: Intent preflight (order type, side, post-only flags)
2. Gate 2: Preflight intent validation per venue capabilities
3. Gate 3: Quantization (round qty to contract multiples)
4. Gate 4: Dispatch mapping validation (contract qty vs canonical qty)
5. Gate 5: Fee cache staleness check
6. Gate 6: Expiry guard (instrument lifecycle, cancellation logic)

**OPEN-Path Gates (7-10):**
7. Liquidity gate: L2 book snapshot validation, slippage estimation
8. Net edge gate: expected profit after slippage vs min edge threshold
9. Inventory skew gate: position skew adjustment to net edge
10. Margin headroom gate: utilization % check with mode hints (Conservative/Normal/Aggressive)
11. Pending exposure gate: per-instrument uncrossed limit check (from PendingExposureBook)
12. Global exposure budget gate: delta-bucketed exposure check across instruments
13. Pricer: IOC limit clamp based on mark price + slippage
14. WAL record (gate 10): Append intent to durable ledger with fsync barrier before returning

**State Management:**
- Risk state transitions: Healthy → Degraded (cache miss, fee stale, write error) → Maintenance (upcoming exchange maintenance) → Kill (watchdog timeout)
- Pending exposure tracking: ReservationId-keyed entries per instrument, settled on TLSM terminal events
- Trade lifecycle state machine (TLSM): Created → Sent → Acked → PartialFill → {Filled, Cancelled, Failed}
- Label-encoded recovery metadata: group_id (12 bits) + sequence (8 bits) + flags

## Key Abstractions

**Gate Abstraction:**
- Purpose: Modular decision-making with consistent input/output types, metrics, and reject reasons
- Examples: `evaluate_base_gates()`, `evaluate_liquidity_gate()`, `evaluate_net_edge()`, `evaluate_margin_headroom_gate()`
- Pattern: Input struct → metrics out parameter → Result<GateProof, RejectReason>; never panics, always returns decision reason

**Intent Class Hierarchy:**
- Purpose: Route intents to correct gate sequence based on trading intent (Open/Close/Hedge/Cancel)
- Examples: `ChokeIntentClass` (OPEN, CLOSE, HEDGE, CANCEL), disambiguates preflight rules and margin requirements
- Pattern: Derived from `reduce_only` flag and requested direction in dispatch consistency proof

**Dispatch Consistency Proof (AT-920):**
- Purpose: Immutable audit trail linking canonical qty to contract qty with tolerance validation
- Examples: `DispatchConsistencyProof { canonical_qty, dispatch_qty, multiplier, contract_matched }`
- Pattern: Computed once during assembly, threaded through pipeline, never re-computed

**Pending Exposure Reservation:**
- Purpose: Isolate per-instrument uncrossed exposure limits; decouple gate evaluation from settlement
- Examples: `ReservationId`, `PendingExposureBook::reserve()`, settlement on TLSM terminal
- Pattern: Reservation created on gate pass (before network), reversed on rejection or settled on fill

**WAL Durability Barrier:**
- Purpose: Guarantee fsync-before-dispatch for OPEN intents; crash-safe idempotency
- Examples: `WalLedger::append()` (fsync barrier), `DurableWalGate` (gate 10 adapter), `RecordedBeforeDispatch` marker
- Pattern: Intent enqueued to bounded channel; writer thread dequeues, appends to ledger, awaits fsync, returns result

**Trade Lifecycle State Machine (TLSM):**
- Purpose: Track order state across websocket events; tolerate out-of-order fills; prevent double-apply
- Examples: `TlsmEvent::Acked`, `TlsmEvent::PartialFill`, `TlsmEvent::Fill` → `TlsState` transitions
- Pattern: `apply(event)` returns new state + side effects (settlement, cancellation, rollover); idempotent per trade_id

## Entry Points

**Dispatch Pipeline Entry (External API):**
- Location: `crates/soldier_core/src/execution/open_runtime.rs:393` (`build_open_intent_with_assembly()`)
- Triggers: OPEN intent request from application layer
- Responsibilities: Orchestrate assembly + OPEN gates 1-10 + WAL record; return ChokeResult with metrics
- Returns: `OpenRuntimeOutput { choke_result, gate_results, pending_reservation_id, mode_hint, effective_risk_state }`

- Location: `crates/soldier_core/src/execution/intent_assembly.rs:159` (`evaluate_assembled_pipeline()`)
- Triggers: CLOSE/HEDGE/CANCEL intent request from application layer
- Responsibilities: Orchestrate assembly + shared pipeline + WAL record; return ChokeResult
- Returns: `PipelineResult { decision: ChokeResult, reject_reason_code }`

**Bootstrap Entry (Application Startup):**
- Location: `crates/soldier_infra/src/bootstrap.rs:284` (`bootstrap_full()`)
- Triggers: Application startup, must occur before any intent evaluation
- Responsibilities: Validate gate config, initialize WAL ledger, initialize trade-ID registry, replay ledger for in-flight intents
- Returns: `BootstrapResult` with `ReplayOutcome` (must be acknowledged via `.acknowledge()` to force startup latch decision)

**Individual Gate Entries (Composition):**
- Preflight: `crates/soldier_core/src/execution/preflight.rs:200` (`preflight_intent()`)
- Quantization: `crates/soldier_core/src/execution/quantize.rs:186` (`quantize()`)
- Dispatch validation: `crates/soldier_core/src/execution/dispatch_map.rs:230` (`validate_and_dispatch()`)
- Fee staleness: `crates/soldier_core/src/risk/fees.rs` (`evaluate_fee_staleness()`)
- Expiry guard: `crates/soldier_core/src/venue/lifecycle.rs:95` (`evaluate_expiry_guard()`)
- Liquidity: `crates/soldier_core/src/execution/gate.rs:461` (`evaluate_liquidity_gate()`)
- Net edge: `crates/soldier_core/src/execution/gates.rs:166` (`evaluate_net_edge()`)
- Pricer: `crates/soldier_core/src/execution/pricer.rs:131` (`compute_limit_price()`)
- Inventory skew: `crates/soldier_core/src/execution/inventory_skew.rs:124` (`evaluate_inventory_skew()`)
- WAL gate 10: `crates/soldier_infra/src/wal.rs:145` (`DurableWalGate::record_before_dispatch()`)

**Recovery Entry (Crash/Reconnect):**
- Location: `crates/soldier_infra/src/store/ledger.rs` (`WalLedger::replay()`)
- Triggers: Application startup after bootstrap, used to load in-flight intent state
- Responsibilities: Parse WAL records, reduce to latest per-intent view, return ReplayOutcome with in-flight count
- Returns: `ReplayOutcome { in_flight_count, recovered_intents, ... }`

## Error Handling

**Strategy:** Fail-Closed (pessimistic) with explicit rejection reason codes

**Patterns:**
- Gate rejections: Always return `GateRejectReason` enum with specific code (e.g., `LiquidityTooThin`, `FeeCacheStale`, `MarginHeadroomInsufficient`)
- Risk state degradation: Cache miss or write failure → `RiskState::Degraded` → ReduceOnly latch
- WAL append failures: Return `LedgerAppendError`, increment wal_write_errors metric, fail OPEN intents closed
- Dispatch mismatch: `DispatchConsistencyProof { contract_matched: false }` → reject with `DispatchMismatch` reason
- Unrecognized instrument: `AssemblySizingError::UnknownInstrumentKind` → reject intent
- TLSM invalid transition: Log error, ignore out-of-order fill (no panic); only apply valid successor states
- Missing OPEN-path input: Gate marked failed before chokepoint; chokepoint rejects on any gate failure

**Never:**
- Unwrap/expect without strong reason (all use `?` operator or explicit `ok_or`)
- Silently ignore errors (log with tracing, return explicit reason)
- Assume successful write without checking append result
- Proceed with stale risk state (always re-evaluate before dispatch)

## Cross-Cutting Concerns

**Logging:** Structured tracing with fields for intent_id, side, instrument, gate_stage, rejection_code. Metrics exported via metric constants (e.g., `METRIC_LIQUIDITY_GATE_REJECT`). No print statements; all to tracing.

**Validation:** Contract-aware schemas (serde with #[serde(deny_unknown_fields)]) for config. Appendix A threshold validation in `build_gate_config_from_raw()`. Intent format validation in preflight (order type, side, post-only).

**Idempotency:** Intent hash (xxhash64 over canonical fields) for deduplication. Trade-ID registry for fill-level idempotency (insert-if-absent semantics). Label encoding for recovery metadata (group_id + sequence).

**State Machines:** TLSM for order lifecycle (never panic on out-of-order events). RiskState for policy mode (transitions are monotonic toward safety). TlsState for WAL records (explicit terminal state whitelisting).

---
*Architecture analysis: 2026-02-23*
