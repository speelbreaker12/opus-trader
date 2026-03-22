### **3.1 Deterministic Emergency Close**

**Requirement**: When an atomic group fails, we must exit the position *immediately* and *safely*.

**Where:** `crates/soldier_core/src/execution/emergency_close.rs`

**Price Source (Deterministic, fail-closed):**
- Primary: `L2BookSnapshot` best bid/ask when present and fresh (age <= `l2_book_snapshot_max_age_ms`; Appendix A).
- Fallback: `L1TickerSnapshot` best bid/ask (REST/WS ticker) when present and fresh (age <= `l2_book_snapshot_max_age_ms`; Appendix A).
- Emergency fallback: instrument metadata venue price bands when no fresh L2/L1 is available AND `instrument_cache_age_s <= instrument_cache_ttl_s` (Appendix A):
  - reduce-only BUY close uses quantized venue `max_price`,
  - reduce-only SELL close uses quantized venue `min_price`.
  - This fallback MUST use bounded IOC attempts only and MUST remain monotonic risk-reducing.
  - This fallback is valid only when instrument metadata freshness holds (`instrument_cache_age_s <= instrument_cache_ttl_s`); stale instrument metadata MUST make venue-band fallback unavailable.
- The `best` price in step 1 uses the selected source (asks for buy, bids for sell).
- If no valid source is available from L2/L1 and no valid venue band is available (missing/unparseable/unquantizable metadata), emergency close MUST NOT dispatch and MUST return `Rejected(EmergencyCloseNoPrice)` and log `EmergencyCloseNoPrice`.

**Algorithm (Deterministic, 3 tries):**
1. Attempt **IOC limit close** at best ± `close_buffer_ticks` (default 5 ticks; see Appendix A for `close_buffer_ticks`). This is attempt 1.
2. If partial fill: repeat for remaining qty (max 3 total attempts including the initial; buffer doubles each retry: attempt 2 = 10 ticks, attempt 3 = 20 ticks).
3. If still exposed after retries: submit **reduce-only perp hedge** to neutralize delta (bounded size). If hedge dispatch fails (rejected, timeout, or venue error), log the failure and proceed to step 4 with exposure unchanged; the system MUST NOT retry the hedge indefinitely. If the hedge is partially filled, treat the partial fill as partial success: account for the filled quantity in exposure reduction and proceed to step 4 with the remaining exposure; MUST NOT retry for the unfilled remainder.
4. Log `AtomicNakedEvent` with group_id + exposure + time-to-delta-neutral.

**AtomicNakedEvent schema (minimum):**
- `group_id` (UUIDv4)
- `strategy_id` (string)
- `incident_ts_ms` (epoch ms)
- `exposure_usd_before` (float)
- `exposure_usd_after` (float)
- `time_to_delta_neutral_ms` (integer)
- `close_attempts` (integer; 1-3)
- `hedge_used` (bool)
- `cause` (string; non-empty; MUST be one of: `atomic_legging_failure|emergency_close_exhausted|hedge_fallback`)
- `trading_mode_at_event` (`Active|ReduceOnly|Kill`)
- `evidence_chain_state_at_event` (EvidenceChainState per §2.2.2; e.g., `GREEN|RED`; required only when `enforced_profile != CSP`)

AT-1102
- Given: an AtomicNakedEvent is emitted by the emergency close path.
- When: the event's `cause` field is inspected.
- Then: `cause` MUST be a non-empty string; empty string, null, or missing `cause` field is non-compliant.
- Pass criteria: every emitted AtomicNakedEvent has a non-empty `cause` value (e.g., `atomic_legging_failure`, `emergency_close_exhausted`, `hedge_fallback`).
- Fail criteria: any AtomicNakedEvent has an empty, null, or missing `cause` field.

AT-211
- Given: an atomic group enters mixed state (one leg filled, another rejected or none) and emergency close runs.
- When: emergency close completes (including optional hedge fallback).
- Then: exactly one AtomicNakedEvent is emitted with required schema fields present and `time_to_delta_neutral_ms` computed.
- Pass criteria: event exists with required fields, is joinable to `group_id`, and if `enforced_profile != CSP`, `evidence_chain_state_at_event` is present.
- Fail criteria: missing event or missing required fields.

Profile: GOP
AT-213
- Given: an atomic group enters mixed state (one leg filled, another rejected or none), `enforced_profile != CSP`, and emergency close runs.
- When: AtomicNakedEvent is recorded.
- Then: the event includes `strategy_id`, `cause`, `trading_mode_at_event`, and `evidence_chain_state_at_event` with valid values.
- Pass criteria: each field is present; `cause` is non-empty; `trading_mode_at_event` is one of `Active|ReduceOnly|Kill`; `evidence_chain_state_at_event` matches EvidenceChainState enum values.
- Fail criteria: any required field missing or invalid.

Profile: CSP
**Acceptance Tests (REQUIRED):**
AT-235
- Given: one leg filled and the book thins.
- When: emergency close runs.
- Then: close attempts run and fallback hedge executes if still exposed; exposure goes to ~0.
- Pass criteria: bounded close attempts then hedge fallback if needed; exposure neutralized.
- Fail criteria: no close attempts or exposure remains.

AT-1284
- Given: attempt 1 and attempt 2 partially fill while exposure remains.
- When: emergency close schedules bounded IOC retries.
- Then: at most three IOC close attempts are submitted total; attempt 1 uses `close_buffer_ticks`, attempt 2 uses `2 * close_buffer_ticks`, and attempt 3 uses `4 * close_buffer_ticks`; no fourth IOC close attempt is permitted.
- Pass criteria: dispatch records show exactly the `1x`, `2x`, `4x` buffer schedule with a hard cap of three total attempts.
- Fail criteria: any fourth IOC close attempt occurs, or any retry uses a buffer other than `close_buffer_ticks`, `2 * close_buffer_ticks`, or `4 * close_buffer_ticks`.

AT-1272
- Given: one leg filled, close attempts exhausted with remaining exposure, and hedge dispatch fails (rejected, timeout, or venue error).
- When: emergency close completes step 3 and proceeds to step 4.
- Then: exactly one `AtomicNakedEvent` is emitted with `exposure_usd_after > 0`, `hedge_used == true`, and the system does not retry the hedge indefinitely.
- Pass criteria: AtomicNakedEvent emitted with accurate remaining exposure; no retry loop; system proceeds to step 4 within bounded time.
- Fail criteria: system hangs retrying hedge, or AtomicNakedEvent omitted, or `exposure_usd_after` does not reflect remaining exposure.

AT-1273
- Given: one leg filled, close attempts exhausted, and hedge order is partially filled (partial qty filled, remainder unfilled).
- When: emergency close evaluates the hedge result.
- Then: the partial fill is treated as partial success; `exposure_usd_after` in AtomicNakedEvent reflects the reduced (but non-zero) exposure after partial hedge fill; the system MUST NOT retry for the unfilled remainder and MUST proceed to step 4.
- Pass criteria: AtomicNakedEvent emitted; `exposure_usd_after` accounts for partial hedge fill; no retry for remainder.
- Fail criteria: partial fill treated as full failure (ignoring filled portion), or system retries indefinitely for remainder.

AT-236
- Given: Liquidity Gate reject conditions are present.
- When: emergency close runs.
- Then: emergency close still submits IOC close attempts (Liquidity Gate does NOT block it).
- Pass criteria: IOC close attempts are submitted.
- Fail criteria: emergency close blocked by Liquidity Gate.

AT-937
- Given: `L2BookSnapshot` is missing/unparseable/stale and a fresh `L1TickerSnapshot` is available.
- When: emergency close runs.
- Then: IOC close attempts are submitted using the L1 best bid/ask as the `best` price.
- Pass criteria: dispatch occurs and uses the L1 ticker as the price source.
- Fail criteria: dispatch is blocked despite a valid L1 ticker or uses a stale/invalid source.

AT-938
- Given: `L2BookSnapshot` is missing/unparseable/stale, no fresh `L1TickerSnapshot` is available, venue band metadata is present/parseable, and instrument metadata freshness holds (`instrument_cache_age_s <= instrument_cache_ttl_s`).
- When: emergency close runs.
- Then: IOC close attempts are submitted using emergency venue-band fallback pricing (`max_price` for reduce-only BUY, `min_price` for reduce-only SELL), quantized to tick.
- Pass criteria: at least one bounded IOC attempt is dispatched using venue-band fallback pricing.
- Fail criteria: dispatch is blocked despite valid venue-band metadata, or fallback violates reduce-only/monotonic rules.

AT-1217
- Given: `L2BookSnapshot` is missing/unparseable/stale, no fresh `L1TickerSnapshot` is available, and venue band metadata is missing/unparseable/unquantizable.
- When: emergency close runs.
- Then: no dispatch occurs, the attempt is rejected with `Rejected(EmergencyCloseNoPrice)`, and no `AtomicNakedEvent` is emitted (no dispatch means no naked exposure to record).
- Pass criteria: dispatch count remains 0; rejection reason is recorded; no `AtomicNakedEvent` is emitted.
- Fail criteria: any dispatch occurs without a valid fallback price source, rejection reason is missing/mismatched, or an `AtomicNakedEvent` is emitted despite zero dispatch.

AT-1239
- Given: `L2BookSnapshot` is missing/unparseable/stale, no fresh `L1TickerSnapshot` is available, venue band metadata is present/parseable, and `instrument_cache_age_s > instrument_cache_ttl_s`.
- When: emergency close evaluates venue-band fallback pricing.
- Then: venue-band fallback is treated as unavailable; no dispatch occurs and the attempt is rejected with `Rejected(EmergencyCloseNoPrice)`.
- Pass criteria: dispatch count remains 0 and the rejection reason is recorded.
- Fail criteria: venue-band dispatch occurs while metadata is stale, or rejection reason is missing/mismatched.

AT-1251
- Given: an atomic group enters mixed state and emergency close runs through to the hedge fallback (step 3).
- When: the hedge quantity is computed.
- Then: `hedge_qty` MUST NOT exceed the net exposed quantity at the time of submission. The hedge MUST NOT create new net exposure.
- Pass criteria: hedge_qty <= exposed_qty; net exposure after hedge is <= net exposure before hedge.
- Fail criteria: hedge_qty > exposed_qty, or the hedge creates new net exposure in the opposite direction.

AT-1252
- Given: venue-band fallback pricing is used and emergency close executes multiple IOC retry attempts.
- When: retry attempts 1-3 are evaluated.
- Then: each successive attempt MUST be reduce-only (qty <= remaining exposure after prior fills) and MUST NOT increase net position. Retry quantities MUST be monotonically non-increasing (bounded by remaining exposure).
- Pass criteria: all retry quantities are <= remaining exposure at that point; no attempt increases delta exposure.
- Fail criteria: any attempt uses qty > remaining exposure, or any attempt increases net position.
