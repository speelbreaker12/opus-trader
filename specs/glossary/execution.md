# Glossary: Execution Pipeline

> Extracted from code in `crates/soldier_core/src/execution/`. Update when struct definitions change.
> Generated 2026-03-16.

## Public Facade (`api.rs` re-exports)

| Symbol | Kind | Source Module |
|--------|------|---------------|
| `ExecutionEngine` | struct | `engine.rs` |
| `ExecutionInput` | enum | `engine.rs` |
| `ExecutionDecision` | enum | `engine.rs` |
| `ApprovedExecution` | struct | `engine.rs` |
| `ExecutionRejection` | struct | `engine.rs` |
| `ExecutionStep` | enum | `engine.rs` |
| `RuntimeStep` | enum | `engine.rs` |
| `ExecutionRuntime` | struct | `engine.rs` |
| `ExecutionBaseInput` | struct | `engine.rs` |
| `ExecutionPreflightInput` | struct | `engine.rs` |
| `ExecutionOrderType` | enum | `engine.rs` |
| `ExecutionPostOnlyInput` | struct | `engine.rs` |
| `QuantizeExecutionInput` | struct | `engine.rs` |
| `OpenExecutionInput` | struct | `engine.rs` |
| `CloseExecutionInput` | struct | `engine.rs` |
| `HedgeExecutionInput` | struct | `engine.rs` |
| `CancelExecutionInput` | struct | `engine.rs` |
| `LiquidityExecutionInput` | struct | `engine.rs` |
| `ExecutionL2BookSnapshot` | struct | `engine.rs` |
| `ExecutionL2Level` | struct | `engine.rs` |
| `NetEdgeExecutionInput` | struct | `engine.rs` |
| `InventorySkewExecutionInput` | struct | `engine.rs` |
| `PricerExecutionInput` | struct | `engine.rs` |
| `GateStep` | enum | `build_order_intent.rs` |
| `RecordedBeforeDispatchGate` | trait | `wal_gate.rs` |
| `RejectReasonCode` | enum | `reject_reason_generated.rs` |
| `GateRejectCodes` | struct | `reject_reason.rs` |
| `Side` | enum | `quantize.rs` |
| `GateOutcome` | enum | `gate_outcome.rs` |
| `EmergencyClosePriceInput` | struct | `emergency_close.rs` |
| `EmergencyClosePriceSelection` | struct | `emergency_close.rs` |
| `EmergencyClosePriceSource` | enum | `emergency_close.rs` |
| `EmergencyTopOfBookSnapshot` | struct | `emergency_close.rs` |
| `EmergencyVenueBand` | struct | `emergency_close.rs` |
| `LabelInput` | struct | `label.rs` |
| `LabelError` | enum | `label.rs` |
| `AtomicGroup` | struct | `group.rs` |
| `GroupConfig` | struct | `group.rs` |
| `GroupError` | enum | `group.rs` |
| `GroupLock` | struct | `group.rs` |
| `GroupState` | enum | `group.rs` |
| `GroupStateTransition` | struct | `group.rs` |
| `LegResult` | struct | `group.rs` |
| `Tlsm` | struct | `tlsm.rs` |
| `TlsmState` | enum | `tlsm.rs` |
| `TlsmEvent` | enum | `tlsm.rs` |
| `TlsmTransitionSink` | trait | `tlsm.rs` |
| `PersistedTransition` | struct | `tlsm.rs` |
| `TransitionResult` | enum | `tlsm.rs` |


## Gate Input Structs (commonly misremembered fields)

The "NOT this" column lists plausible-but-wrong names someone might guess.

### `NetEdgeInput` (`gates.rs`, `pub(crate)`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `gross_edge_usd` | `Option<f64>` | `edge_usd`, `gross_usd` | All Option -- missing => fail-closed |
| `fee_usd` | `Option<f64>` | `fee_estimate_usd`, `fees` | Different name in PricerInput! |
| `expected_slippage_usd` | `Option<f64>` | `slippage_usd`, `slip_usd` | |
| `min_edge_usd` | `Option<f64>` | `min_net_edge`, `threshold` | |

### `NetEdgeExecutionInput` (`engine.rs`, public facade)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `gross_edge_usd` | `Option<f64>` | | Same as internal |
| `fee_usd` | `Option<f64>` | `fee_estimate_usd` | Same as internal; NOT `fee_estimate_usd` |
| `expected_slippage_usd` | `Option<f64>` | | Same as internal |
| `min_edge_usd` | `Option<f64>` | | Same as internal |

### `LiquidityGateInput` (`gate.rs`, `pub(crate)`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `order_qty` | `f64` | `qty`, `amount`, `size` | |
| `is_buy` | `bool` | `side` | Bool, not Side enum |
| `intent_class` | `GateIntentClass` | `intent_type` | |
| `is_marketable` | `bool` | | Reserved for diagnostics |
| `l2_snapshot` | `Option<L2BookSnapshot>` | `book`, `l2_book`, `orderbook` | |
| `now_ms` | `u64` | `timestamp`, `current_time` | |
| `l2_book_snapshot_max_age_ms` | `u64` | `max_book_age_ms`, `staleness_ms` | Long but exact |
| `max_slippage_bps` | `f64` | `slippage_limit`, `max_slip` | In basis points |

### `LiquidityExecutionInput` (`engine.rs`, public facade)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `order_qty` | `f64` | `qty` | |
| `side` | `Side` | `is_buy` | Side enum (differs from internal!) |
| `is_marketable` | `bool` | | |
| `l2_snapshot` | `Option<ExecutionL2BookSnapshot>` | `l2_book` | Different L2 type than internal |
| `now_ms` | `u64` | | |
| `l2_book_snapshot_max_age_ms` | `u64` | `max_book_age_ms` | |
| `max_slippage_bps` | `f64` | | |

### `PricerInput` (`pricer.rs`, `pub(crate)`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `fair_price` | `f64` | `mid_price`, `index_price` | |
| `gross_edge_usd` | `f64` | | NOT Option (differs from NetEdgeInput) |
| `min_edge_usd` | `f64` | | NOT Option |
| `fee_estimate_usd` | `f64` | `fee_usd`, `fees` | Different from NetEdgeInput.fee_usd! |
| `expected_slippage_usd` | `f64` | `slippage_usd` | |
| `qty` | `f64` | `order_qty`, `amount` | |
| `side` | `Side` | | |

### `PricerExecutionInput` (`engine.rs`, public facade)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `fair_price` | `f64` | | |
| `gross_edge_usd` | `f64` | | |
| `min_edge_usd` | `f64` | | |
| `fee_estimate_usd` | `f64` | `fee_usd` | Matches PricerInput, NOT NetEdgeInput |
| `expected_slippage_usd` | `f64` | | |
| `qty` | `f64` | `order_qty` | |
| `side` | `Side` | | |

### `InventorySkewInput` (`inventory_skew.rs`, `pub`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `current_delta` | `f64` | `delta`, `position` | |
| `pending_delta` | `f64` | `reserved_delta`, `inflight` | |
| `delta_limit` | `Option<f64>` | `max_delta`, `position_limit` | Missing => fail-closed |
| `side` | `Side` | | |
| `min_edge_usd` | `f64` | | Baseline before skew adjustment |
| `net_edge_usd` | `f64` | | From upstream net-edge |
| `limit_price` | `f64` | `price` | Pre-skew candidate |
| `tick_size` | `f64` | | |
| `inventory_skew_k` | `f64` | `k`, `skew_factor` | Multiplier (contract default 0.5) |
| `inventory_skew_tick_penalty_max` | `u8` | `max_ticks`, `penalty_max` | Contract default 3 |

### `InventorySkewExecutionInput` (`engine.rs`, public facade)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `current_delta` | `f64` | | |
| `pending_delta` | `f64` | | |
| `delta_limit` | `Option<f64>` | | |
| `side` | `Side` | | |
| `min_edge_usd` | `f64` | | |
| `net_edge_usd` | `f64` | | |
| `limit_price` | `f64` | | |
| `tick_size` | `f64` | | |
| `inventory_skew_k` | `f64` | | |
| `inventory_skew_tick_penalty_max` | `u8` | | |

### `QuantizeConstraints` (`quantize.rs`, `pub`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `tick_size` | `f64` | `price_step`, `price_increment` | |
| `amount_step` | `f64` | `qty_step`, `lot_size` | |
| `min_amount` | `f64` | `min_qty`, `min_order_size` | |

### `QuantizeExecutionInput` (`engine.rs`, public facade)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `raw_qty` | `f64` | `qty`, `amount` | |
| `raw_limit_price` | `f64` | `price`, `limit_price` | Pre-quantization |
| `side` | `Side` | | |
| `tick_size` | `f64` | | |
| `amount_step` | `f64` | | |
| `min_amount` | `f64` | | |

### `PreflightInput` (`preflight.rs`, `pub`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `instrument_kind` | `InstrumentKind` | `instrument_type` | From `crate::venue` |
| `order_type` | `OrderType` | `order_kind` | Local enum, not ExecutionOrderType |
| `has_trigger` | `bool` | `is_triggered` | |
| `linked_order_type` | `Option<&str>` | `oco_type` | |
| `linked_orders_allowed` | `bool` | `oco_allowed` | From capability matrix |
| `post_only_input` | `Option<PostOnlyInput>` | `post_only` | Contains the full crossing check context |

### `PostOnlyInput` (`post_only_guard.rs`, `pub`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `post_only` | `bool` | `is_post_only` | |
| `side` | `Side` | | |
| `limit_price` | `f64` | `price` | Must be pre-quantized |
| `best_ask` | `Option<f64>` | `ask`, `ask_price` | |
| `best_bid` | `Option<f64>` | `bid`, `bid_price` | |

### `EmergencyClosePriceInput` (`emergency_close.rs`, `pub`)

| Field | Type | NOT this | Notes |
|-------|------|----------|-------|
| `side` | `Side` | | |
| `now_ms` | `u64` | | |
| `book_snapshot_max_age_ms` | `u64` | `l2_book_snapshot_max_age_ms` | Different name from LiquidityGateInput! |
| `instrument_cache_age_s` | `f64` | `cache_age_ms` | Seconds, NOT milliseconds |
| `instrument_cache_ttl_s` | `f64` | `cache_ttl_ms` | Seconds, NOT milliseconds |
| `l2` | `Option<EmergencyTopOfBookSnapshot>` | `l2_snapshot` | |
| `l1` | `Option<EmergencyTopOfBookSnapshot>` | `l1_snapshot` | |
| `venue_band` | `Option<EmergencyVenueBand>` | `price_band` | |


## CRITICAL: Fee Field Name Divergence

The fee field is named differently across gate inputs. This is the single highest-frequency source of field-name errors in this codebase:

| Struct | Fee Field Name | Type |
|--------|---------------|------|
| `NetEdgeInput` | `fee_usd` | `Option<f64>` |
| `NetEdgeExecutionInput` | `fee_usd` | `Option<f64>` |
| `PricerInput` | `fee_estimate_usd` | `f64` |
| `PricerExecutionInput` | `fee_estimate_usd` | `f64` |

Rule: Net Edge uses `fee_usd`. Pricer uses `fee_estimate_usd`. Never swap them.


## Enums

### `Side` (`quantize.rs`)

| Variant | Notes |
|---------|-------|
| `Buy` | Quantize: price rounds DOWN (floor) |
| `Sell` | Quantize: price rounds UP (ceil) |

### `GateStep` (`build_order_intent.rs`)

Gate ordering is deterministic (CONTRACT.md CSP.5.2):

| Variant | Gate # | OPEN | CLOSE/HEDGE | CANCEL |
|---------|--------|------|-------------|--------|
| `DispatchAuth` | 1 | yes | yes | yes (exits early) |
| `Preflight` | 2 | yes | yes | skip |
| `Quantize` | 3 | yes | yes | skip |
| `DispatchConsistency` | 4 | yes | skip | skip |
| `FeeCacheCheck` | 5 | yes | yes | skip |
| `ExpiryGuard` | 6 | yes | yes (allow if None) | skip |
| `LiquidityGate` | 7 | yes | skip | skip |
| `NetEdgeGate` | 8 | yes | skip | skip |
| `Pricer` | 9 | yes | skip | skip |
| `RecordedBeforeDispatch` | 10 | yes (blocks) | yes (non-blocking) | skip |

### `ExecutionInput` (`engine.rs`)

| Variant | Maps To |
|---------|---------|
| `Open(OpenExecutionInput)` | Full 10-gate pipeline |
| `Close(CloseExecutionInput)` | Base gates + WAL (non-blocking) |
| `Hedge(HedgeExecutionInput)` | Base gates + WAL (non-blocking) |
| `Cancel(CancelExecutionInput)` | DispatchAuth only |

### `ExecutionDecision` (`engine.rs`)

| Variant | Contains |
|---------|----------|
| `Approved(ApprovedExecution)` | `effective_risk_state`, `pending_reservation_id`, `adjusted_min_edge_usd` |
| `Rejected(ExecutionRejection)` | `code: RejectReasonCode`, `step: ExecutionStep`, `detail: String` |

### `ExecutionStep` (`engine.rs`)

| Variant | Contains |
|---------|----------|
| `Runtime(RuntimeStep)` | For runtime-level rejections (BaseGates, PendingExposure, etc.) |
| `Gate(GateStep)` | For chokepoint gate rejections |

### `RuntimeStep` (`engine.rs`)

| Variant | Notes |
|---------|-------|
| `BaseGates` | Shared gates 1-6 evaluation |
| `PendingExposure` | Pending exposure budget check |
| `GlobalExposureBudget` | Global exposure budget check |
| `InventorySkew` | Inventory skew gate |
| `MarginGate` | Margin headroom gate |
| `Assembly` | Intent assembly failure |

### `RejectReasonCode` (`reject_reason_generated.rs`, generated)

| Variant | Wire Format | Gate/Source |
|---------|-------------|-------------|
| `TooSmallAfterQuantization` | `TOO_SMALL_AFTER_QUANTIZATION` | Quantize |
| `InstrumentMetadataMissing` | `INSTRUMENT_METADATA_MISSING` | Quantize |
| `ChurnBreakerActive` | `CHURN_BREAKER_ACTIVE` | Runtime |
| `LiquidityGateNoL2` | `LIQUIDITY_GATE_NO_L2` | LiquidityGate |
| `EmergencyCloseNoPrice` | `EMERGENCY_CLOSE_NO_PRICE` | EmergencyClose |
| `ExpectedSlippageTooHigh` | `EXPECTED_SLIPPAGE_TOO_HIGH` | LiquidityGate |
| `NetEdgeTooLow` | `NET_EDGE_TOO_LOW` | NetEdgeGate / Pricer |
| `NetEdgeInputMissing` | `NET_EDGE_INPUT_MISSING` | NetEdgeGate |
| `PricerInputMissing` | `PRICER_INPUT_MISSING` | Pricer |
| `PricerInputInvalid` | `PRICER_INPUT_INVALID` | Pricer |
| `GateCascadeSkip` | `GATE_CASCADE_SKIP` | Pipeline |
| `InsufficientDepthWithinBudget` | `INSUFFICIENT_DEPTH_WITHIN_BUDGET` | LiquidityGate |
| `FeeCacheStale` | `FEE_CACHE_STALE` | FeeCacheCheck |
| `RecordedBeforeDispatchFailed` | `RECORDED_BEFORE_DISPATCH_FAILED` | WAL |
| `AssemblyFailed` | `ASSEMBLY_FAILED` | Chokepoint |
| `InventorySkew` | `INVENTORY_SKEW` | InventorySkew |
| `InventorySkewDeltaLimitMissing` | `INVENTORY_SKEW_DELTA_LIMIT_MISSING` | InventorySkew |
| `PendingExposureBudgetExceeded` | `PENDING_EXPOSURE_BUDGET_EXCEEDED` | Runtime |
| `GlobalExposureBudgetExceeded` | `GLOBAL_EXPOSURE_BUDGET_EXCEEDED` | Runtime |
| `ContractsAmountMismatch` | `CONTRACTS_AMOUNT_MISMATCH` | DispatchConsistency |
| `MarginHeadroomRejectOpens` | `MARGIN_HEADROOM_REJECT_OPENS` | MarginGate / DispatchAuth |
| `OrderTypeMarketForbidden` | `ORDER_TYPE_MARKET_FORBIDDEN` | Preflight |
| `OrderTypeStopForbidden` | `ORDER_TYPE_STOP_FORBIDDEN` | Preflight |
| `LinkedOrderTypeForbidden` | `LINKED_ORDER_TYPE_FORBIDDEN` | Preflight |
| `PostOnlyWouldCross` | `POST_ONLY_WOULD_CROSS` | Preflight |
| `RiskIncreasingCancelReplaceForbidden` | `RISK_INCREASING_CANCEL_REPLACE_FORBIDDEN` | Runtime |
| `RateLimitBrownout` | `RATE_LIMIT_BROWNOUT` | Runtime |
| `InstrumentExpiredOrDelisted` | `INSTRUMENT_EXPIRED_OR_DELISTED` | ExpiryGuard |
| `FeedbackLoopGuardActive` | `FEEDBACK_LOOP_GUARD_ACTIVE` | Runtime |
| `LabelTooLong` | `LABEL_TOO_LONG` | Label |

Note: `as_str()` returns PascalCase (`"NetEdgeTooLow"`). Serde wire format is SCREAMING_SNAKE_CASE (`"NET_EDGE_TOO_LOW"`). Do not confuse them.

### `TlsmState` (`tlsm.rs`)

| Variant | Terminal? | Notes |
|---------|-----------|-------|
| `Created` | no | Initial state |
| `Sent` | no | Order dispatched to exchange |
| `Acked` | no | Exchange acknowledged |
| `PartiallyFilled` | no | |
| `Filled` | yes | |
| `Cancelled` | yes | |
| `Failed` | yes | |

### `TlsmEvent` (`tlsm.rs`)

| Variant | Notes |
|---------|-------|
| `Sent` | |
| `Acked` | |
| `PartialFill` | |
| `Filled` | |
| `Cancelled` | |
| `VenueRejected` | Canonical venue-reject |
| `Rejected` | Legacy alias for VenueRejected |
| `Failed` | Internal failure |

### `GroupState` (`group.rs`)

| Variant | Terminal? | Notes |
|---------|-----------|-------|
| `New` | no | Created, not dispatched |
| `Dispatched` | no | All legs dispatched |
| `Complete` | yes | All legs terminal, fills balanced |
| `MixedFailed` | no | Atomicity broken, containment required |
| `Flattening` | no | Emergency close in progress |
| `Flattened` | yes | Exposure neutral |

### `GateOutcome` (`gate_outcome.rs`)

| Variant | Contains | Notes |
|---------|----------|-------|
| `Allow { gate }` | `GateStep` | Cannot carry a reason code |
| `Reject { gate, reason_code }` | `GateStep`, `RejectReasonCode` | Always carries a reason code |

### `GateIntentClass` (`gate.rs`, internal)

| Variant | L2 required? | Slippage check? |
|---------|-------------|-----------------|
| `Open` | yes | yes (full qty must be fillable) |
| `Close` | yes | yes (clamped to fillable) |
| `Hedge` | yes | yes (clamped to fillable) |
| `CancelOnly` | no | no (always allowed) |

### `ChokeIntentClass` (`build_order_intent.rs`)

| Variant | Notes |
|---------|-------|
| `Open` | All 10 gates required |
| `Close` | Skip gates 4, 7-9; WAL non-blocking |
| `Hedge` | Skip gates 4, 7-9; WAL non-blocking |
| `CancelOnly` | Skip gates 2-10 |

### `EmergencyClosePriceSource` (`emergency_close.rs`)

| Variant | Priority | Notes |
|---------|----------|-------|
| `L2` | 1 (highest) | Fresh L2 top-of-book |
| `L1` | 2 | Fresh L1 fallback |
| `VenueBand` | 3 (lowest) | Requires fresh instrument metadata |

### `QuantizeError` (`quantize.rs`)

| Variant | Contains | RejectReasonCode |
|---------|----------|------------------|
| `TooSmallAfterQuantization { qty_q, min_amount }` | Quantized qty + threshold | `TooSmallAfterQuantization` |
| `InstrumentMetadataMissing { field }` | Static field name | `InstrumentMetadataMissing` |
| `InvalidInput { field }` | Static field name | `InstrumentMetadataMissing` (legacy compat) |


## Domain Model Types (`domain_model.rs`)

| Type | Kind | Notes |
|------|------|-------|
| `InstrumentFamily` | enum | `Option`, `Future`, `Perpetual` |
| `AmountSemantics` | enum | `Coin`, `Usd` -- authoritative sizing discriminator |
| `InstrumentMeta` | struct | `instrument_id`, `instrument_family`, `amount_semantics`, `tick_size`, `amount_step`, `min_amount`, `contract_size_usd` |
| `OrderSizeInput` | enum | `CoinQty(f64)`, `UsdQty(f64)`, `Contracts(i64)` |
| `NormalizedOrderSize` | struct | `canonical_size_kind`, `contracts`, `qty_coin`, `qty_usd`, `notional_usd` |
| `IntentId` | newtype | `IntentId(u64)` -- deterministic 64-bit identity |
| `QuantizedQtySteps` | newtype | `QuantizedQtySteps(i64)` |
| `QuantizedPriceTicks` | newtype | `QuantizedPriceTicks(i64)` |


## Contract <-> Code Mapping

| Contract Term (CONTRACT.md) | Code Term | Notes |
|------------------------------|-----------|-------|
| TradingMode (Active/ReduceOnly/Kill) | `TradingMode` (in `crate::risk`) | Not in execution; resolved by PolicyGuard |
| RiskState (Healthy/Degraded/Maintenance/Kill) | `RiskState` (in `crate::risk`) | Gate 1 (DispatchAuth) uses this |
| §1.1.1 Canonical Quantization | `quantize()` in `quantize.rs` | Floor qty, directional price rounding |
| §1.3 Pre-Trade Liquidity Gate | `evaluate_liquidity_gate()` in `gate.rs` | Gate 7 |
| §1.4 No Market Orders / IOC Limit | `compute_limit_price()` in `pricer.rs` | Gate 9 |
| §1.4.1 Net Edge Gate | `evaluate_net_edge()` in `gates.rs` | Gate 8 |
| §1.4.2 Inventory Skew | `evaluate_inventory_skew()` in `inventory_skew.rs` | Runtime step |
| §1.4.4 Order-Type Preflight | `preflight_intent()` in `preflight.rs` | Gate 2 |
| §1.4.4 C Post-Only Guard | `check_post_only()` in `post_only_guard.rs` | Sub-gate of Preflight |
| §1.2.1 Group State Machine | `GroupState` enum in `group.rs` | New->Dispatched->Complete/MixedFailed->Flattening->Flattened |
| §2.1 Trade Lifecycle State Machine | `Tlsm` / `TlsmState` in `tlsm.rs` | Created->Sent->Acked->PartiallyFilled->Filled/Cancelled/Failed |
| §3.1 Emergency Close Fallback | `select_emergency_close_best_price()` in `emergency_close.rs` | L2 > L1 > VenueBand priority |
| CSP.3.2 WAL Non-Blocking | `RecordedBeforeDispatchGate` trait | WAL failure non-blocking for Close/Hedge |
| CSP.5.2 Single Chokepoint | `build_order_intent()` in `build_order_intent.rs` | All dispatch routes through here |
| AT-920 Dispatch Consistency | `DispatchConsistencyProof` in `dispatch_map.rs` | Contracts vs amount mismatch check |
| §1.1 Label Schema | `encode_label()` / `decode_label()` in `label.rs` | Format: `s4:{sid8}:{gid12}:{li}:{ih16}` |


## Key Architectural Invariants

1. **Two layers of input types**: Internal gate inputs (`LiquidityGateInput`, `NetEdgeInput`, `PricerInput`) are `pub(crate)`. Public facade inputs (`LiquidityExecutionInput`, `NetEdgeExecutionInput`, `PricerExecutionInput`) are exported via `api.rs`. The engine translates between them.

2. **Side representation diverges**: `LiquidityGateInput` uses `is_buy: bool`. All public-facing types and other internal types use `Side` enum. Be careful at the translation boundary.

3. **Fee field name diverges across gates**: `NetEdgeInput.fee_usd` vs `PricerInput.fee_estimate_usd`. See the CRITICAL section above.

4. **`book_snapshot_max_age_ms`**: The liquidity gate uses `l2_book_snapshot_max_age_ms`. The emergency close input uses `book_snapshot_max_age_ms`. Different names for the same concept.

5. **Timestamp units diverge**: Emergency close uses seconds (`instrument_cache_age_s`, `instrument_cache_ttl_s`) for instrument cache freshness, but milliseconds (`now_ms`, `book_snapshot_max_age_ms`) for book freshness. All other gates use milliseconds throughout.
