# Contract Addendum: Signal Generation Layer (§4.6)

> **Status:** DRAFT — not yet merged into CONTRACT.md
> **Profile:** GOP (signal generation is not CSP-critical; CSP gates remain independently enforced)
> **Phase applicability:** Phase 3 or later. Signal generation MUST NOT be a Phase 2 completion requirement.
> **Parent contract:** specs/CONTRACT.md v5.2+

---

## Rationale

The current contract specifies execution (§1), state management (§2), safety/recovery (§3), quantitative logic (§4), and self-improvement (§5). It does **not** specify how the system decides *what* to trade — the signal generation layer. This addendum closes that gap.

The signal generation layer sits **above** execution and **below** self-improvement:

```
§5 Self-Improvement (Optimization Cycle, Replay Gatekeeper, Canary)
    ↓ policy patches (min_edge_usd, limit_distance_bps, ...)
§4.6 Signal Generation (this addendum)
    ↓ TradeSignal (instrument, side, size, edge_estimate, ...)
§1 Execution Architecture (gates, pricer, dispatch)
```

**Design constraint (Non-Negotiable):** The signal layer produces *advisory* intents. Every intent still passes through the full CSP gate stack (Liquidity Gate §1.3, Net Edge Gate §1.4.1, Inventory Skew §1.4.2, Margin Headroom §1.4.3, PolicyGuard §2.2, Cortex §2.3). The signal layer MUST NOT bypass, weaken, or conditionally skip any CSP gate. Signal-layer failures MUST NOT degrade CSP protections.

---

## §4.6 Signal Generation Layer

Profile: GOP

### §4.6.0 Scope & Boundaries

**What the signal layer does:**
1. Consumes calibrated SVI surface (§4.1), fee model (§4.2), market data (L2/L1), and greek snapshots.
2. Identifies candidate trades where estimated edge exceeds policy thresholds.
3. Emits `TradeSignal` structs that flow into the execution pipeline (§1).

**What the signal layer does NOT do:**
- Override or bypass any CSP gate.
- Directly submit orders to venues.
- Modify PolicyGuard state, RiskState, or TradingMode.
- Persist state that CSP depends on.

**Where:** `crates/soldier_core/src/strategy/signal.rs`

### §4.6.1 Signal Source: Vol Surface Mispricing Scanner

**Council Weakness Covered:** No systematic opportunity identification; ad-hoc signal logic is untestable and undocumented.

**Requirement:** Given a valid SVI surface (§4.1 gates passed) and current market quotes, identify options where the market-implied vol deviates from the model-implied vol by more than a configurable threshold.

**Algorithm (Deterministic):**

1. **Surface validity pre-check:** If the current SVI surface is `None` (held due to §4.1 guard trips), emit zero signals. Do NOT use stale/rejected surfaces.
2. For each in-scope instrument (per Launch Policy allowed instruments):
   a. Compute model IV from the valid SVI surface at the instrument's `(moneyness, maturity)`.
   b. Extract market IV from the best bid/ask mid (or mark price if bid/ask unavailable).
   c. Compute `iv_edge = market_iv - model_iv` (positive = market overpriced relative to model).
   d. Compute `edge_usd_est` from `iv_edge` using the instrument's vega: `edge_usd_est = abs(iv_edge) * vega_per_1pct * 100 * notional_multiplier`.
3. **Threshold filter:** Emit a `TradeSignal` only if `abs(iv_edge) >= signal_min_iv_edge` (Appendix A) AND `edge_usd_est >= signal_min_edge_usd` (Appendix A).
4. **Signal direction:**
   - If `iv_edge > 0` (market IV > model IV): signal to SELL the option (overpriced).
   - If `iv_edge < 0` (market IV < model IV): signal to BUY the option (underpriced).
5. **Size determination:** `signal_size_usd = min(edge_usd_est * signal_size_scale, max_order_usd)` where `max_order_usd` is from policy (§5.1). Signal size is advisory; execution gates (Inventory Skew §1.4.2, Margin Headroom §1.4.3) may further reduce or reject.

**Fail-Closed Rules:**
- If SVI surface is `None` → zero signals (not stale surface).
- If market IV is non-finite (`NaN`/`Inf`) for an instrument → skip that instrument, do not emit signal.
- If vega is non-finite, zero, or negative → skip that instrument.
- If `edge_usd_est` computation produces non-finite → skip that instrument.
- If `signal_min_iv_edge` or `signal_min_edge_usd` is missing or unparseable → emit zero signals and log `SIGNAL_CONFIG_MISSING`.

**Where:** `crates/soldier_core/src/strategy/signal.rs :: scan_vol_surface(...)`

**Acceptance Tests (REQUIRED):**

AT-1300
- Given: a valid SVI surface and a set of in-scope instruments where exactly one instrument has `abs(iv_edge) >= signal_min_iv_edge` and `edge_usd_est >= signal_min_edge_usd`.
- When: the vol surface scanner runs.
- Then: exactly one `TradeSignal` is emitted with correct direction, instrument, and estimated edge.
- Pass criteria: signal count == 1; signal direction matches iv_edge sign; `edge_usd_est` matches manual calculation within tolerance.
- Fail criteria: signal count != 1, wrong direction, or edge estimate diverges from manual calculation.

AT-1301
- Given: the current SVI surface is `None` (rejected by §4.1 guards).
- When: the vol surface scanner runs.
- Then: zero signals are emitted.
- Pass criteria: signal count == 0; no stale surface used.
- Fail criteria: any signal emitted while SVI surface is None.

AT-1302
- Given: a valid SVI surface; one instrument has `market_iv = NaN` (unparseable quote).
- When: the vol surface scanner evaluates that instrument.
- Then: the instrument is skipped; no signal is emitted for it; other valid instruments still produce signals normally.
- Pass criteria: NaN instrument skipped; valid instruments unaffected.
- Fail criteria: NaN propagates to signal output, or scanner halts entirely.

AT-1303
- Given: `signal_min_iv_edge` is missing from configuration.
- When: the vol surface scanner runs.
- Then: zero signals are emitted and `SIGNAL_CONFIG_MISSING` is logged.
- Pass criteria: zero signals; log present.
- Fail criteria: signals emitted without valid threshold configuration.

AT-1304
- Given: a valid SVI surface and instruments where all have `abs(iv_edge) < signal_min_iv_edge`.
- When: the vol surface scanner runs.
- Then: zero signals are emitted (threshold not met).
- Pass criteria: signal count == 0.
- Fail criteria: any signal emitted below threshold.

### §4.6.2 TradeSignal Schema

**TradeSignal** is the output of the signal layer and input to intent construction.

```rust
pub struct TradeSignal {
    pub signal_id: Uuid,
    pub signal_ts: i64,           // epoch ms (wall-clock, not monotonic)
    pub instrument_id: InstrumentId,
    pub side: Side,               // Buy | Sell
    pub iv_edge: f64,             // market_iv - model_iv (signed)
    pub edge_usd_est: f64,        // estimated USD edge before fees/slippage
    pub model_iv: f64,            // SVI-derived IV at this strike/maturity
    pub market_iv: f64,           // observed mid-IV
    pub signal_size_usd: f64,     // advisory size (pre-gate)
    pub svi_fit_id: Uuid,         // links to the SVI fit that produced model_iv
    pub strategy_id: String,      // for attribution (§4.3.1) and churn tracking (§1.2.3)
    pub l2_snapshot_ts: i64,      // L2 book timestamp used for market_iv extraction
}
```

**Invariants:**
- `signal_id` MUST be unique (UUID v4 or v7).
- `signal_ts` MUST be epoch milliseconds (same convention as `fee_model_cached_at_ts` in §4.2).
- `svi_fit_id` MUST reference the exact fit used; if a newer fit arrives mid-scan, the signal references the fit that was valid at scan start (snapshot consistency).
- `strategy_id` MUST be non-empty and MUST match the strategy registry used by §1.2.3 Self-Impact Feedback Loop Guard.

**Acceptance Test (REQUIRED):**

AT-1305
- Given: a `TradeSignal` is emitted.
- When: the signal is inspected.
- Then: `signal_id` is a valid UUID, `signal_ts` is epoch ms, `svi_fit_id` references a known valid fit, `strategy_id` is non-empty, and all float fields are finite.
- Pass criteria: all invariants hold.
- Fail criteria: any field violates its invariant.

### §4.6.3 Signal Staleness Gate

**Requirement:** A `TradeSignal` has a bounded validity window. If the signal is not consumed by the execution pipeline within `signal_max_age_ms` (Appendix A), it MUST be discarded.

**Rationale:** Vol surfaces, quotes, and greeks shift rapidly. A stale signal references outdated market state and could produce losing trades.

**Rules:**
- `signal_age_ms = now_epoch_ms - signal_ts`
- If `signal_age_ms > signal_max_age_ms` → discard signal before intent construction; log `SIGNAL_STALE_DISCARD`.
- If `signal_ts` is missing, unparseable, or in the future (beyond a `signal_clock_skew_tolerance_ms` buffer) → discard; log `SIGNAL_TS_INVALID`.

**Where:** `crates/soldier_core/src/strategy/signal.rs :: is_signal_fresh(...)`

**Acceptance Tests (REQUIRED):**

AT-1306
- Given: a `TradeSignal` with `signal_age_ms > signal_max_age_ms`.
- When: the staleness gate evaluates the signal.
- Then: the signal is discarded; no intent is constructed; `SIGNAL_STALE_DISCARD` is logged.
- Pass criteria: discard + log; dispatch count remains 0.
- Fail criteria: stale signal proceeds to intent construction.

AT-1307
- Given: a `TradeSignal` with `signal_ts` in the future (beyond `signal_clock_skew_tolerance_ms`).
- When: the staleness gate evaluates the signal.
- Then: the signal is discarded; `SIGNAL_TS_INVALID` is logged.
- Pass criteria: discard + log.
- Fail criteria: future-dated signal accepted.

AT-1308
- Given: a `TradeSignal` with `signal_age_ms <= signal_max_age_ms` and valid `signal_ts`.
- When: the staleness gate evaluates the signal.
- Then: the signal proceeds to intent construction.
- Pass criteria: signal not discarded; intent construction invoked.
- Fail criteria: valid fresh signal discarded.

### §4.6.4 Signal Rate Limiter (Anti-Churn at Source)

**Requirement:** The signal layer MUST NOT emit signals faster than `signal_max_rate_per_instrument` (Appendix A) per instrument per rolling window `signal_rate_window_s` (Appendix A). This is a source-side complement to the §1.2.3 Self-Impact Feedback Loop Guard and §1.2.2 Churn Circuit Breaker.

**Rules:**
- Track signal count per `instrument_id` over a rolling `signal_rate_window_s` window.
- If emitting a new signal for an instrument would exceed `signal_max_rate_per_instrument` → suppress signal; log `SIGNAL_RATE_LIMITED`.
- Rate limit state is in-memory only; loss on restart is acceptable (fail-safe: zero signals until window fills).

**Where:** `crates/soldier_core/src/strategy/signal.rs :: rate_limiter`

**Acceptance Tests (REQUIRED):**

AT-1309
- Given: `signal_max_rate_per_instrument = 5` and `signal_rate_window_s = 60`.
- When: 6 signals are generated for the same instrument within 60 seconds.
- Then: the 6th signal is suppressed; `SIGNAL_RATE_LIMITED` is logged; the first 5 proceed.
- Pass criteria: exactly 5 signals emitted; 6th suppressed with log.
- Fail criteria: 6th signal emitted, or fewer than 5 emitted.

AT-1310
- Given: rate limiter state is empty (e.g., after restart).
- When: signals are generated within the first `signal_rate_window_s`.
- Then: signals proceed normally up to the rate limit; no signals are emitted from stale pre-restart state.
- Pass criteria: rate limiter starts clean; signals proceed within limit.
- Fail criteria: stale pre-restart counts suppress valid post-restart signals.

### §4.6.5 Signal-to-Intent Bridge (Handoff Contract)

**Requirement:** The bridge between signal generation and intent construction (§1) MUST:
1. Attach `signal_id` to the `OrderIntent` for full traceability (signal → intent → dispatch → fill → attribution).
2. Pass `strategy_id` through to the intent for §1.2.3 Self-Impact tracking.
3. Pass `edge_usd_est` to the Net Edge Gate (§1.4.1) as the gross edge input.
4. Record `signal_id` + `svi_fit_id` in the TruthCapsule (§4.3.2) for post-hoc attribution.

**Fail-Closed Rule:** If the bridge cannot attach `signal_id` to the intent (e.g., schema mismatch, missing field), the intent MUST NOT be constructed. Log `SIGNAL_BRIDGE_FAIL`.

**Where:** `crates/soldier_core/src/strategy/signal_bridge.rs`

**Acceptance Tests (REQUIRED):**

AT-1311
- Given: a valid, fresh `TradeSignal` passes the staleness gate and rate limiter.
- When: the signal-to-intent bridge constructs an `OrderIntent`.
- Then: `signal_id`, `strategy_id`, and `svi_fit_id` are present on the intent and in the TruthCapsule.
- Pass criteria: all three IDs are present and valid on the dispatched intent; TruthCapsule contains `signal_id`.
- Fail criteria: any ID is missing or mismatched.

AT-1312
- Given: signal-to-intent bridge encounters a schema error (e.g., `signal_id` field cannot be attached).
- When: the bridge attempts intent construction.
- Then: no intent is constructed; `SIGNAL_BRIDGE_FAIL` is logged; dispatch count remains 0.
- Pass criteria: no dispatch; log present.
- Fail criteria: intent constructed without signal traceability.

### §4.6.6 CSP Isolation (Non-Negotiable)

Profile: CSP

**Hard Rule:** Signal generation failures MUST NOT degrade CSP safety protections.

**Specific isolation requirements:**
1. If the signal layer panics, crashes, or returns errors → execution pipeline receives zero signals; CSP gates and emergency close (§3.1) remain fully operational.
2. Signal-layer configuration errors → zero signals emitted (fail-closed for signals, not for safety).
3. Signal-layer latency (slow scan) → signals may age out via §4.6.3; hot loop MUST NOT block waiting for signal generation.
4. Signal-layer memory usage → bounded by `signal_scan_max_instruments` (Appendix A); unbounded instrument iteration is forbidden.

**Runtime isolation mechanism:**
- Signal generation runs on a separate task/thread from the hot loop.
- Communication is via a bounded channel (`signal_channel_capacity`, Appendix A).
- If channel is full, new signals are dropped (not blocking the producer or consumer).

**Acceptance Tests (REQUIRED):**

AT-1313
Profile: CSP
- Given: signal generation is completely unavailable (task crashed / channel broken).
- When: PolicyGuard computes TradingMode and the execution pipeline evaluates intents.
- Then: `TradingMode` MUST NOT be forced to ReduceOnly/Kill solely due to signal-layer failure. Existing CLOSE/HEDGE/CANCEL intents proceed normally. Emergency close (§3.1) proceeds normally. No OPEN intents are generated (because no signals), but this is a natural consequence, not a safety downgrade.
- Pass criteria: no TradingMode/RiskState degradation from signal failure; emergency close unaffected.
- Fail criteria: TradingMode degraded or emergency close blocked due to signal-layer unavailability.

AT-1314
Profile: CSP
- Given: signal generation is producing signals, but one signal references a stale SVI fit (fit was invalidated by §4.1 between scan start and intent construction).
- When: the intent passes through CSP gates.
- Then: CSP gates evaluate the intent independently using current market data; the stale fit reference does not bypass any gate.
- Pass criteria: all CSP gates evaluate independently; no gate skipped due to signal-layer state.
- Fail criteria: any CSP gate is skipped or weakened based on signal-layer metadata.

---

## Appendix A Additions (Signal Generation)

### A.8 Signal Generation

**`signal_min_iv_edge`** (§4.6.1 Vol Surface Mispricing Scanner)
- **Default**: `0.02` (2 vol points)
- **Purpose**: Minimum absolute IV edge to emit a signal.
- **Rationale**: Below 2 vol points, fees and slippage typically consume the edge.

**`signal_min_edge_usd`** (§4.6.1 Vol Surface Mispricing Scanner)
- **Default**: `5.00` (USD)
- **Purpose**: Minimum estimated USD edge to emit a signal.
- **Rationale**: Sub-$5 edges are not worth the execution risk and venue fees.

**`signal_size_scale`** (§4.6.1 Vol Surface Mispricing Scanner)
- **Default**: `1.0`
- **Purpose**: Multiplier from `edge_usd_est` to advisory signal size. Policy may scale up/down.

**`signal_max_age_ms`** (§4.6.3 Signal Staleness Gate)
- **Default**: `5000` (5 seconds)
- **Purpose**: Maximum age of a signal before it is discarded.
- **Rationale**: Vol surface and quotes can shift materially in seconds; 5s provides a reasonable execution window without excessive staleness risk.

**`signal_clock_skew_tolerance_ms`** (§4.6.3 Signal Staleness Gate)
- **Default**: `1000` (1 second)
- **Purpose**: Maximum allowed future timestamp before signal is rejected as invalid.

**`signal_max_rate_per_instrument`** (§4.6.4 Signal Rate Limiter)
- **Default**: `5`
- **Purpose**: Maximum signals per instrument per rate window.

**`signal_rate_window_s`** (§4.6.4 Signal Rate Limiter)
- **Default**: `60` (seconds)
- **Purpose**: Rolling window for per-instrument rate limiting.

**`signal_scan_max_instruments`** (§4.6.6 CSP Isolation)
- **Default**: `500`
- **Purpose**: Upper bound on instruments scanned per cycle to bound memory/CPU.
- **Rationale**: Deribit lists ~300-400 options at a time; 500 provides headroom without unbounded iteration.

**`signal_channel_capacity`** (§4.6.6 CSP Isolation)
- **Default**: `64`
- **Purpose**: Bounded channel capacity between signal producer and execution consumer.
- **Rationale**: Small enough to drop stale signals quickly; large enough to handle burst scans.

---

## Implementation Roadmap Integration

**Phase 3 (GOP Data Loop)** — add:
- Signal generation module (`crates/soldier_core/src/strategy/signal.rs`)
- Signal-to-intent bridge (`crates/soldier_core/src/strategy/signal_bridge.rs`)
- Signal staleness gate and rate limiter
- TruthCapsule integration (signal_id linkage)
- Attribution pipeline updates (iv_edge, model_iv, market_iv fields)

**Phase 3 AT Subset (Signal Layer):**
- AT-1300 through AT-1314 (all required for Phase 3 signal-layer completion)

**Dependencies:**
- §4.1 SVI Stability Gates MUST be implemented and passing before signal generation is activated.
- §4.2 Fee-Aware Execution MUST be implemented (edge estimation requires fee awareness).
- §4.3.2 TruthCapsule MUST be implemented (signal traceability requirement).

---

## CONTRACT_CHANGE_LEDGER Entry (Draft)

| Change ID | Date | Summary | Sections | ATs Added |
|-----------|------|---------|----------|-----------|
| ADD-SIG-001 | TBD | Signal generation layer: vol surface mispricing scanner, staleness gate, rate limiter, intent bridge, CSP isolation | §4.6.0–§4.6.6, A.8 | AT-1300 through AT-1314 |
