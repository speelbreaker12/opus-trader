## **1\. Execution Architecture: The "Atomic Group" (Real-Time Repair)**
Profile: CSP

**Constraint**: We do not rely on API atomicity. We rely on **Runtime Atomicity**. If Leg A fills and Leg B dies, the system detects the "Mixed State" and neutralizes it immediately, without waiting for a restart.

### **1.0 Instrument Units & Notional Invariants (Deribit Quantity Contract) — MUST implement**

**Why this exists:** Unit mismatches are silent PnL killers. Deribit uses **different sizing semantics** across instruments. If we don’t encode these invariants, we will eventually ship a “correct-looking” trade that is 10–100× the intended exposure.

**Canonical internal units (single source of truth):**
- `qty_coin` (BTC/ETH): **options + linear futures** sizing.
- `qty_usd` (USD notional): **perpetual + inverse futures** sizing (Deribit `amount` is USD units for these).
- `notional_usd`:
  - For coin-sized instruments: `notional_usd = qty_coin * index_price`
  - For USD-sized instruments: `notional_usd = qty_usd`

**Hard Rules (Non‑Negotiable):**
1. **Never mix** coin sizing and USD sizing for the *same* intent. One is canonical; the other is derived.
2. If both `contracts` and `amount` are provided (internally or via strategy output), they **must match** within tolerance:
   - `amount ≈ contracts * contract_multiplier`  
   - `contract_multiplier` is instrument-specific (e.g., inverse futures contract size in USD; options contract multiplier in coin).
   - Tolerance: `abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon) <= contracts_amount_match_tolerance` where `contracts_amount_match_tolerance = 0.001` (0.1%, default) and `epsilon = 1e-9`.
3. If a mismatch is detected: **reject the intent** and set `RiskState::Degraded` (this is a wiring bug, not "market noise").
4. Rejections for contracts/amount mismatch MUST use `Rejected(ContractsAmountMismatch)`.
5. For `instrument_kind == option`, order size MUST use `qty_coin` (Deribit `amount` in base coin units); `qty_usd` MUST be unset.

**Acceptance Tests (References):**
- AT-277 (dispatcher mapping validates option sizing and `qty_usd` unset)

AT-1097
- Given: a single order intent that specifies both `qty_coin` and `qty_usd` as canonical sizing fields (i.e., the intent mixes coin sizing and USD sizing).
- When: the intent is evaluated for dispatch.
- Then: the intent MUST be rejected before dispatch with `Rejected(ContractsAmountMismatch)` and `RiskState::Degraded` is set; no order is sent to the exchange.
- Pass criteria: intent rejected; dispatch count remains 0; `RiskState::Degraded` set.
- Fail criteria: intent dispatched with mixed sizing, or rejection reason is missing/wrong.

#### **1.0.X Instrument Metadata Freshness (Instrument Cache TTL) — MUST implement**

**Purpose:** Stale instrument metadata can silently break sizing and quantization (tick_size, amount_step, min_amount), causing wrong exposure.

**Source of truth (Non-Negotiable):**
- Instrument metadata MUST be fetched from `/public/get_instruments` and cached (Deribit).
- Hardcoding `tick_size`, `amount_step`, `min_amount`, or `contract_multiplier` is forbidden; all sizing/quantization MUST use the fetched metadata.

**Invariant (Non-Negotiable):**
- The engine MUST track freshness of instrument metadata used for:
  - instrument_kind derivation
  - quantization constraints (tick_size, amount_step, min_amount)
- If instrument metadata age exceeds `instrument_cache_ttl_s`:
  - set `RiskState::Degraded`
  - PolicyGuard MUST compute `TradingMode::ReduceOnly` within one tick (closes/hedges/cancels allowed; see §2.2.3)

**Required observability (contract-bound names):**
- `instrument_cache_age_s` (gauge)
- `instrument_cache_hits_total` (counter)
- `instrument_cache_stale_total` (counter)
- `instrument_cache_refresh_errors_total` (counter, optional but recommended)

**Acceptance tests (REQUIRED):**
- AT-104 below provides comprehensive testing for stale metadata handling (blocks opens, allows closes).

AT-104
- Given: `instrument_cache_age_s > instrument_cache_ttl_s` and an OPEN intent is proposed.
- When: the system evaluates eligibility for dispatch.
- Then: `RiskState==Degraded`, `TradingMode==ReduceOnly`, and the OPEN is rejected before dispatch; CLOSE/HEDGE/CANCEL remain dispatchable (subject to Kill semantics in §2.2.3).
- Pass criteria: OPEN dispatch count remains 0; CLOSE/HEDGE/CANCEL are not blocked solely by stale metadata.
- Fail criteria: any OPEN is dispatched while metadata is stale.

**Phase 1 stub test note (AT-104):** AT-104 requires `TradingMode==ReduceOnly` (full PolicyGuard resolver, Phase 2). A Phase 1 stub test MAY prove the precondition by verifying that `RiskState::Degraded` is set when metadata is stale, and that OPEN intents are blocked by `RiskState::Degraded` alone (without requiring the full PolicyGuard TradingMode axis resolver). The full AT-104 (including `TradingMode==ReduceOnly` assertion) MUST pass before Phase 2 completion.

AT-333
- Given: instrument metadata is fetched from `/public/get_instruments`.
- When: quantization/sizing uses `tick_size`, `amount_step`, `min_amount`, and `contract_multiplier`.
- Then: values come from fetched metadata (no hardcoded defaults).
- Pass criteria: quantization/sizing uses fetched values.
- Fail criteria: any hardcoded defaults used.

#### **1.0.Y Instrument Lifecycle & Expiry Safety (Expiry Cliff Guard) — MUST implement**

**Purpose:** Instruments expire/delist. After expiry, venue APIs may return "invalid instrument"/"not_found"/"orderbook_closed".
These are **expected terminal lifecycle events**, not fatal system errors. The Soldier MUST remain panic-free and MUST protect
the rest of the portfolio from a single instrument disappearing.

**Required instrument fields (from venue metadata; cached under §1.0.X):**
- `expiration_timestamp_ms: Option<i64>` (epoch ms; null for perps)
- `is_active: bool` (or equivalent venue state)
- `instrument_state: enum { Active, DelistingSoon, ExpiredOrDelisted }` (derived)

**Delist buffer rule (fail-closed for opens):**
- If `expiration_timestamp_ms` is present and `now_ms >= expiration_timestamp_ms - (expiry_delist_buffer_s * 1000)`:
  - NEW OPEN intents for that instrument MUST be rejected before dispatch with `Rejected(InstrumentExpiredOrDelisted)`.
  - CLOSE/HEDGE/CANCEL intents remain allowed (subject to TradingMode semantics in §2.2.3 and other gates).

**Terminal error classification (panic-free):**
- Any venue response that semantically maps to {`invalid_instrument`, `not_found`, `orderbook_closed`, `instrument_not_open`}
  for an instrument with `expiration_timestamp_ms` present and `now_ms >= expiration_timestamp_ms` MUST be classified as:
  - `Terminal(InstrumentExpiredOrDelisted)`
  - MUST NOT panic
  - MUST NOT force process restart
  - MUST trigger reconciliation for that instrument only (ledger/orders/trades/positions) and then mark `instrument_state=ExpiredOrDelisted`.

**Idempotent cancel rule (expiry-safe):**
- If a CANCEL is issued for an order on an expired/delisted instrument and the venue returns a terminal lifecycle error,
  the CANCEL MUST be treated as **idempotently successful** (order is considered gone).

**Portfolio-wide reconcile/flatten (expiry-safe):**
- During any portfolio-wide reconcile/flatten procedure (restart reconcile, emergency flatten, operator shutdown flow),
  terminal lifecycle errors for expired/delisted instruments MUST NOT abort the procedure.
- The procedure MUST continue managing other instruments normally.
- If venue truth (positions snapshot) indicates no remaining position for the expired/delisted instrument, the system MUST
  mark `instrument_state=ExpiredOrDelisted` and MUST NOT enter a retry loop for that instrument.

**Acceptance Tests (REQUIRED):**
AT-949
- Given: `expiration_timestamp_ms = Texp`, `now_ms = Texp + 1000`, and a CANCEL is attempted on that instrument.
  - All other gates are configured to pass (this test isolates expiry-safe idempotent cancel handling).
- When: venue returns a terminal lifecycle error (e.g., invalid instrument / not found / orderbook_closed).
- Then: the system does not panic; the cancel is treated as idempotently successful; the instrument is marked `ExpiredOrDelisted`;
  other instruments continue to be managed normally.
- Pass criteria: no crash; instrument_state updated; other instrument loop continues.
- Fail criteria: panic/crash or global trading halted solely due to this instrument error.

AT-950
- Given: `expiration_timestamp_ms = Texp`, `expiry_delist_buffer_s = 60`, and `now_ms = Texp - 30_000`.
  - All other gates are configured to pass (this test isolates the expiry delist OPEN block).
- When: an OPEN intent for that instrument is evaluated.
- Then: the intent is rejected with `Rejected(InstrumentExpiredOrDelisted)` before dispatch; CLOSE/HEDGE/CANCEL remain allowed.
- Pass criteria: OPEN dispatch count remains 0 and reject reason matches.
- Fail criteria: OPEN dispatch occurs or reason missing/mismatched.

AT-965
- Given:
  - `expiration_timestamp_ms = Texp`, `expiry_delist_buffer_s = 60`
  - `now_ms = Texp - 120_000` (outside the delist buffer)
  - instrument is active (not expired/delisted)
  - All other gates are configured to pass (this test isolates the expiry delist OPEN block)
- When: an OPEN intent for that instrument is evaluated.
- Then: it MUST NOT be rejected with `InstrumentExpiredOrDelisted`; it proceeds to dispatch.
- Pass criteria: dispatch count becomes 1 and there is no `Rejected(InstrumentExpiredOrDelisted)`.
- Fail criteria: OPEN rejected/blocked by the lifecycle guard despite being outside the delist buffer.

AT-966
- Given:
  - instrument is active (outside delist buffer; not expired/delisted)
  - a CANCEL intent for an existing order is handled and the venue returns success (or a normal non-terminal “already closed/canceled” response)
  - All other gates are configured to pass (this test isolates expiry-safe idempotent cancel logic)
- When: the CANCEL response is processed.
- Then: the system MUST NOT mark the instrument `ExpiredOrDelisted`; it treats the cancel as a normal success path.
- Pass criteria: instrument_state remains Active (or equivalent non-expired state).
- Fail criteria: instrument is incorrectly marked `ExpiredOrDelisted` from a non-terminal cancel result.


AT-960
- Given: a CANCEL intent on an expired/delisted instrument returns `Terminal(InstrumentExpiredOrDelisted)` at T0.
  - All other gates are configured to pass (this test isolates expiry-safe idempotent cancel handling).
- When: the same CANCEL intent is retried (duplicate) at T0+1.
- Then: the second attempt is a NOOP (idempotent success) and does not change ledger correctness.
- Pass criteria: no extra dispatch; ledger remains consistent.
- Fail criteria: repeated cancels cause errors, state corruption, or repeated network dispatch.

AT-961
- Given: a portfolio-wide reconcile/flatten is invoked with two instruments:
  - Instrument A is expired/delisted (`expiration_timestamp_ms = Texp`, `now_ms = Texp + 1000`)
  - Instrument B is active and has an open position requiring management
  - All other gates are configured to pass (this test isolates expiry-safe portfolio reconciliation).
- When: reconcile attempts cancel/close actions and instrument A returns a terminal lifecycle error, while instrument B proceeds normally.
- Then: the system MUST NOT panic; it MUST continue the procedure for instrument B; and it MUST NOT globally halt solely due to A.
- Pass criteria: B continues to be managed; no crash; A marked `ExpiredOrDelisted`.
- Fail criteria: global halt, crash, or B management stops because A expired.

AT-962
- Given: instrument A returns a terminal lifecycle error as above.
  - All other gates are configured to pass (this test isolates expiry-safe reconcile termination).
- When: a positions snapshot (venue truth) shows no remaining position for instrument A.
- Then: the system marks A `ExpiredOrDelisted` and MUST NOT retry cancel/close in a loop for A.
- Pass criteria: retry count for A remains 0 after reconciliation finalizes; state marked expired.
- Fail criteria: infinite/extended retries or repeated dispatch attempts for A after venue truth indicates no position.





**OrderSize struct (MUST implement):**
```rust
pub struct OrderSize {
  pub contracts: Option<i64>,     // integer contracts when applicable
  pub qty_coin: Option<f64>,      // BTC/ETH amount when applicable
  pub qty_usd: Option<f64>,       // USD amount when applicable
  pub notional_usd: f64,          // always populated (derived)
}
```

**Note:** `contracts` values exceeding 2^53 are non-compliant due to f64 precision limits (JSON and many downstream consumers serialize integers as f64; values > 2^53 lose integer precision).

**Dispatcher Rules (Deribit request mapping):**
- Normalize instrument metadata into at least: `instrument_kind`, `amount_semantics`, `tick_size`, `amount_step`, `min_amount`, and optional `contract_size_usd`.
- Determine canonical sizing from `amount_semantics`, not directly from `instrument_kind`.
- Compute size fields:
  - `amount_semantics = coin`: canonical = `qty_coin`; derive `contracts` if contract multiplier is defined.
  - `amount_semantics = usd`: canonical = `qty_usd`; derive `contracts = round(qty_usd / contract_size_usd)` (if defined) and `qty_coin = qty_usd / index_price`.
- `instrument_kind` MAY still influence non-sizing behavior (for example expiry and linked-order policy), but it MUST NOT override `amount_semantics` for outbound amount selection.
- **Deribit outbound order size field:** always send exactly one canonical “amount” value:
  - `amount_semantics = coin` → send `amount = qty_coin`
  - `amount_semantics = usd` → send `amount = qty_usd`
- If `contracts` exists, it must be consistent with the canonical amount before dispatch (reject if not).

**Acceptance Test (REQUIRED):**
AT-277
- Given:
  1) normalized metadata yields `instrument_kind=option`, `amount_semantics=coin`, with `qty_coin=0.3` at `index_price=100_000`
  2) normalized metadata yields `instrument_kind=perpetual`, `amount_semantics=usd`, with `qty_usd=30_000` at `index_price=100_000`
- When: the dispatcher maps request fields.
- Then:
  - outbound option uses `amount=0.3` (coin), `notional_usd=30_000`, and `qty_usd` is unset
  - outbound perp uses `amount=30_000` (USD), `qty_coin=0.3`, `notional_usd=30_000`
  - if both `contracts` and `amount` are supplied and mismatch → reject + degrade
- Pass criteria: mapping rules applied; option `qty_usd` unset; mismatches rejected.
- Fail criteria: incorrect mapping or mismatch allowed.

AT-920
- Given: `contracts` and `amount` are provided and mismatch beyond `contracts_amount_match_tolerance`.
- When: the dispatcher validates sizing before dispatch.
- Then: the intent is rejected with `Rejected(ContractsAmountMismatch)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0; `RiskState==Degraded`.
- Fail criteria: dispatch occurs or reason missing/mismatched.

---

### **1.1 Labeling & Idempotency Contract**

**Requirement**: Every order must be uniquely identifiable and deduplicable across restarts, socket reconnections, and race conditions.

**Specification: The Label Schema**

**Canonical Outbound Format (MUST implement):** `s4:{sid8}:{gid12}:{li}:{ih16}`

- `sid8` = first 8 chars of stable strategy id hash (e.g., base32(xxhash(strat_id)))
- `gid12` = first 12 chars of group_id (uuid without dashes, truncated)
- `li` = leg_idx (0/1)
- `ih16` = 16-hex intent hash

**Deribit Constraint:** `label` must be <= 64 chars. (Hard limit)

**Rule:** All outbound orders to Deribit MUST use the `s4:` format. For `s4` labels, truncation MUST NOT occur. Because the canonical `s4:{sid8}:{gid12}:{li}:{ih16}` shape is fixed and <= 64 chars, any overflow indicates a schema regression; such intents MUST be rejected before dispatch and `RiskState` MUST become `Degraded`.
Rejections for schema/length violations MUST use `Rejected(LabelTooLong)` (or a stricter schema reject code if defined).

**Legacy Documentation Format (non-sent):** `s4:{strat_id}:{group_id}:{leg_idx}:{intent_hash}`  
This expanded format is for human-readable logs and internal documentation only. It MUST NOT be sent to the exchange.

**Recovery / Matching Rule (Normative):**
- For canonical `s4` labels, recovery and reconciliation MUST require exact full parsed identity `{sid8, gid12, leg_idx, ih16}`.
- Canonical `s4` labels MUST NOT use heuristic or tie-breaker fallback once parsed.
- Legacy fallback tie-breakers MAY be used only for explicitly non-canonical legacy labels recovered from pre-v5.2 history.
- If the applicable matcher yields none or more than one candidate, the system MUST fail closed with `RiskState::Degraded` and OPENs blocked until ambiguity is resolved.

### **1.1.1 Canonical Quantization (Pre-Hash & Pre-Dispatch)**

**Requirement:** All idempotency keys and order payloads MUST use canonical, exchange-valid rounded values.

**Where:** `crates/soldier_core/src/execution/quantize.rs`

**Inputs:** `instrument_id`, `raw_qty`, `raw_limit_price`
**Outputs:** `qty_steps`, `price_ticks`, `qty_q`, `limit_price_q` (quantized)

**Rules (Deterministic):**
- Fetch instrument constraints: `tick_size`, `amount_step`, `min_amount`.
- If any of `tick_size`, `amount_step`, or `min_amount` is missing or unparseable -> Reject(intent=InstrumentMetadataMissing) and do not dispatch (fail-closed).
- `qty_steps = floor(raw_qty / amount_step)` and `qty_q = qty_steps * amount_step` (never round up size).
- `price_ticks = floor(raw_limit_price / tick_size)` for BUY and `ceil(raw_limit_price / tick_size)` for SELL; `limit_price_q = price_ticks * tick_size`.
- If `qty_q < min_amount` → Reject(intent=TooSmallAfterQuantization).
- Idempotency hash must be computed ONLY from integer quantized identity fields:
  `intent_hash = xxhash64(instrument + side + qty_steps + price_ticks + group_id + leg_idx)`

**Safer rounding direction:**
- For BUY: round `limit_price_q` DOWN (never pay extra).
- For SELL: round `limit_price_q` UP (never sell cheaper).

**Note:** Side-only rounding is intentional for simplicity. For CLOSE/HEDGE orders, `close_buffer_ticks` in §3.1 compensates for the conservative rounding direction.

**Acceptance Tests (REQUIRED):**
AT-218
- Given: two codepaths compute the same intent fields.
- When: `intent_hash` is generated.
- Then: both hashes are identical.
- Pass criteria: `intent_hash` equality across codepaths.
- Fail criteria: hash mismatch for identical inputs.

AT-219
- Given: raw BUY and SELL prices that are not on tick.
- When: quantization runs.
- Then: BUY rounds down and SELL rounds up (never worse price).
- Pass criteria: BUY price never increases; SELL price never decreases.
- Fail criteria: BUY rounds up or SELL rounds down.

AT-908
- Given: `qty_q < min_amount` after quantization for an OPEN intent.
- When: quantization runs.
- Then: intent is rejected with `Rejected(TooSmallAfterQuantization)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-926
- Given: instrument metadata is missing/unparseable (`tick_size` or `amount_step` or `min_amount`).
- When: quantization runs for an OPEN intent.
- Then: the intent is rejected with `Rejected(InstrumentMetadataMissing)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or an implicit default is used.

AT-928
- Given: the WAL already contains `intent_hash` for a pending intent.
- When: the system evaluates a new intent with the same `intent_hash`.
- Then: it is a NOOP (no dispatch; no new WAL entry).
- Pass criteria: dispatch count remains 0; WAL unchanged.
- Fail criteria: a duplicate dispatch occurs or WAL duplicates the intent.

**Idempotency Rules (Non-Negotiable):**
1. **Dedupe-on-Send (Local):** Before dispatch, check `intent_hash` in the WAL. If exists → NOOP.
2. **Dedupe-on-Send (Remote):** Use Deribit `label` as the idempotency key. If WS reconnect occurs, re-fetch open orders and match by canonical parsed `s4` identity `{sid8, gid12, leg_idx, ih16}`; use legacy fallback only for explicitly non-canonical legacy labels.
3. **Replay Safe:** On restart, rebuild “in-flight intents” from WAL and complete reconciliation with exchange orders/trades before any OPEN-capable evaluation/dispatch path is reachable. Intents already shown as sent, ACKed, or filled MUST NOT resend. A recorded-but-unsent OPEN remains visible for reconciliation and later evaluation, but replay alone MUST NOT dispatch a fresh OPEN.
4. **Attribution-Keyed:** Every fill must map to `group_id` + `leg_idx`, so we can compute “atomic slippage” per group.

AT-1098
- Given: a multi-leg atomic group is dispatched and one or more fills arrive (via WS or REST trade reconciliation).
- When: fill attribution is performed.
- Then: every fill MUST map to exactly one `group_id` + `leg_idx` pair; no fill is unattributed (orphan) and no fill maps to multiple groups.
- Pass criteria: all fills have a valid `group_id` + `leg_idx`; atomic slippage per group is computable from the attributed fills.
- Fail criteria: any fill lacks `group_id` or `leg_idx`, or a fill maps to multiple groups.

**Recovery / Matching Rule (Normative):**
- For canonical `s4` labels, recovery and reconciliation MUST require exact full parsed identity `{sid8, gid12, leg_idx, ih16}`.
- Canonical `s4` labels MUST NOT use heuristic or tie-breaker fallback once parsed.
- Legacy fallback tie-breakers MAY be used only for explicitly non-canonical legacy labels recovered from pre-v5.2 history.
- If the applicable matcher yields none or more than one candidate, the system MUST fail closed with `RiskState::Degraded` and OPENs blocked until ambiguity is resolved.
#### **1.1.2 Label Parse + Disambiguation (Collision-Safe)**

**Requirement:** Label collisions can still occur (hash collisions or non-conforming labels). The Soldier must deterministically map exchange orders to local intents.

**Where:** `crates/soldier_core/src/recovery/label_match.rs`

**Note:** At 10^4 intents/day, the expected collision rate for a 64-bit hash is < 10^-15/year. The legacy fallback path exists for defense-in-depth and historical recovery, not expected current operations.

**Algorithm:**
1) Parse label.
2) If the label is canonical `s4`, extract `{sid8, gid12, leg_idx, ih16}` and build the candidate set using exact full short identity:
   - `sid8` matches,
   - `gid12` matches,
   - `leg_idx` matches,
   - `ih16` matches.
3) If the canonical candidate set size == 1 → match.
4) If a canonical `s4` label yields none or more than one candidate → mark `RiskState::Degraded`, block opens, and require REST trade/order snapshot reconcile.
5) If the label is explicitly non-canonical legacy/repair data, build the legacy fallback candidate set where:
   - `gid12` matches AND `leg_idx` matches.
6) If legacy fallback candidate size == 1 → match.
7) Else disambiguate legacy fallback candidates using tie-breakers in order:
   A) instrument match
   B) side match
   C) qty_q match
8) If legacy fallback remains ambiguous → mark `RiskState::Degraded`, block opens, and require REST trade/order snapshot reconcile.

**Acceptance Tests (REQUIRED):**
AT-216
- Given: an outbound order intent is built with a valid `s4:` label.
- When: the label parser runs.
- Then: the label starts with `s4:`, length ≤ 64 chars, and parser extracts `{sid8, gid12, li, ih16}` correctly.
- Pass criteria: parser outputs match expected components and label length is within bounds.
- Fail criteria: label format invalid, length > 64, or parsed components mismatch.

AT-217
- Given: a recovered order candidate set is matched against either canonical `s4` labels or explicitly legacy non-canonical labels.
- When: the label matcher disambiguates.
- Then: canonical `s4` labels require exact full `sid8+gid12+leg_idx+ih16` identity with no tie-breakers; legacy fallback tie-breakers are permitted only for explicitly legacy non-canonical labels; any unresolved none-or-many result forces `RiskState::Degraded` and opens blocked.
- Pass criteria: deterministic full-identity match for canonical labels; deterministic legacy-only fallback behavior when required; Degraded + opens blocked on unresolved ambiguity.
- Fail criteria: canonical labels use heuristic fallback, ambiguous mapping is accepted, or opens proceed without Degraded on unresolved ambiguity.

AT-041
- Given: an outbound label candidate does not conform to canonical `s4:{sid8}:{gid12}:{li}:{ih16}` shape (wrong segment count, wrong token widths, or invalid characters).
- When: the system validates label schema before dispatch.
- Then: the intent is rejected before dispatch and `RiskState==Degraded`.
- Pass criteria: no order is sent; schema violation is logged deterministically; `RiskState==Degraded`.
- Fail criteria: non-conforming label is dispatched OR schema violation occurs without `RiskState==Degraded`.

AT-921
- Given: an outbound label uses an unknown label version prefix (not `s4:`).
- When: pre-dispatch label validation runs.
- Then: the intent is rejected with a deterministic reject reason (`Rejected(LabelTooLong)` or stricter schema-version reject code if defined) and no dispatch occurs.
- Pass criteria: rejection reason is present, `RiskState==Degraded`, and dispatch count remains 0.
- Fail criteria: unknown-version label is dispatched.



* `strat_id`: Static ID of the running strategy (e.g., `strangle_btc_low_vol`).
* `group_id`: UUIDv4 (Shared by all legs in a single atomic attempt).
* `leg_idx`: `0` or `1` (Identity within the group).
* `intent_hash`: `xxhash64(instrument + side + qty_steps + price_ticks + group_id + leg_idx)` (see §1.1.1 for quantization)
  **Hard rule:** Do NOT include wall-clock timestamps in the idempotency hash.

AT-343
- Given: two intents with identical canonical fields (instrument, side, qty_steps, price_ticks, group_id, leg_idx) evaluated at different wall-clock times.
- When: `intent_hash` is computed for both.
- Then: the two `intent_hash` values are identical.
- Pass criteria: `intent_hash(t0) == intent_hash(t1)` for identical canonical fields.
- Fail criteria: hash differs solely due to wall-clock time.

AT-933
- Given: a WS reconnect occurs and the exchange still has open orders with canonical `s4` labels.
- When: the system re-fetches open orders and matches using exact full parsed `s4` identity (`sid8`, `gid12`, `leg_idx`, `ih16`); legacy fallback is reserved for explicitly non-canonical legacy labels per §1.1.2.
- Then: no duplicate dispatch occurs and the existing orders are treated as in-flight.
- Pass criteria: dispatch count remains 0 for duplicates; reconciliation succeeds.
- Fail criteria: duplicate dispatch occurs, canonical labels use heuristic fallback, or orders are treated as missing.

### **1.2 Atomic Group Executor**

**Requirement:** Manage multi-leg intent as a single atomic unit under messy reality (rejects, partials, WS gaps). We do **Runtime Atomicity**: detect atomicity breaks and deterministically contain/flatten.

### **1.2.1 GroupState Serialization Invariant (Seed “First Fail”)**
**Council Weakness Covered:** Premature “Complete” + naked events under concurrency.

**Hard Invariant (Non‑Negotiable):**
- A Group may be marked `Complete` **only if** every leg has reached a terminal TLSM state `{Filled, Canceled, Failed}` **AND**
  - the group has **no partial fills** and **no fill mismatch** beyond `epsilon` (atomicity restored or no-trade), **AND**
  - **no containment/rescue action is pending**.
- The **first observed failure** (reject/cancel/unfilled/partial mismatch) must “seed” the group into `MixedFailed` and **must not be overwritten** by later async updates.
- WAL/replay qualifier: the WAL layer additionally preserves `Rejected` as a WAL-only terminal state for venue-level rejections. Replay/recovery MUST treat WAL `Rejected` as terminal even though core TLSM maps `Rejected` events to `Failed`.

**Serialization Rule:**
- GroupState transitions must be **single-writer** (AtomicGroupExecutor owns state) or protected by a **group‑level lock**.
- Leg TLSM events may arrive concurrently; **only** the executor decides when/if the group can advance to `Complete`.
- Lock acquisition MUST be bounded (try_lock/timeout) with `group_lock_max_wait_ms` (Appendix A). If not acquired within the bound, the hot loop MUST NOT block and MUST force ReduceOnly until the lock clears.

**Fail-Closed Rule:**
- Group intent MUST be durably recorded before any leg dispatch. If persistence fails, the executor MUST abort and MUST NOT submit any leg orders.

**Where:** `crates/soldier_core/src/execution/atomic_group_executor.rs`

**Acceptance Test (REQUIRED):**
AT-220
- Given: leg events arrive out of order (A fills fast, B rejects late).
- When: GroupState serialization is evaluated.
- Then: the group is never recorded `Complete` before B reaches terminal, and the first failure deterministically triggers containment → flatten.
- Pass criteria: no premature `Complete`; containment triggers on first failure.
- Fail criteria: `Complete` recorded early or containment not triggered.

AT-924
- Given: the group-level lock is held longer than `group_lock_max_wait_ms`.
- When: AtomicGroupExecutor attempts to acquire the lock in the hot loop.
- Then: the hot loop does not block and TradingMode is forced to ReduceOnly until the lock clears.
- Pass criteria: no stall; ReduceOnly enforced; OPEN blocked.
- Fail criteria: hot loop blocks or OPEN dispatch occurs while lock is unavailable.

**Implementation (Rust Skeleton):** `crates/soldier_core/src/execution/group.rs`

```rust
pub enum GroupState { New, Dispatched, Complete, MixedFailed, Flattening, Flattened }

pub struct AtomicGroup {
  pub group_id: Uuid,
  pub legs: Vec<OrderIntent>,
  pub state: GroupState,
}

pub struct LegResult {
  pub leg_idx: u8,
  pub requested_qty: f64,
  pub filled_qty: f64,     // 0.0 .. requested_qty
  pub rejected: bool,
  pub unfilled: bool,
}

pub async fn execute_atomic_group(&self, group: AtomicGroup) -> Result<()> {
  // 0) Persist group intent BEFORE network
  self.ledger.append_group_intent(&group)?;

  // 1) Dispatch legs concurrently as IOC limits (never market)
  let futs = group.legs.iter().map(|leg| self.dispatch_ioc_limit(leg));
  let mut results: Vec<LegResult> = join_all(futs).await;

  // 2) Classify outcomes (qty-aware)
  let filled_qtys: Vec<f64> = results.iter().map(|r| r.filled_qty).collect();
  let max_f = filled_qtys.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
  let min_f = filled_qtys.iter().cloned().fold(f64::INFINITY, f64::min);
  let any_partial = results.iter().any(|r| r.filled_qty > 0.0 && r.filled_qty < r.requested_qty);

  // New rule: partials are common; treat mismatch as atomicity break
  let group_fill_mismatch = max_f - min_f;
  let epsilon = self.cfg.atomic_qty_epsilon;

  // 3) Atomicity broken ⇒ enter MixedFailed and run Containment
  if any_partial || group_fill_mismatch > epsilon {
    self.ledger.mark_group_state(group.group_id, GroupState::MixedFailed)?;

    // Containment Step A: bounded rescue (ONLY to remove naked risk)
    // Try up to 2 IOC rescue orders for the missing qty, crossing spread by rescue_cross_spread_ticks,
    // but ONLY if Liquidity Gate passes AND NetEdge remains ≥ min_edge.
    for _attempt in 0..2 {
      if !self.liquidity_gate_passes(&group)? { break; }
      if !self.net_edge_gate_passes(&group)? { break; }

      let rescue = self.build_rescue_intents(&group, &results, self.cfg.rescue_cross_spread_ticks)?;
      if rescue.is_empty() { break; }

      let rescue_results = self.dispatch_rescue_ioc(rescue).await?;
      results = self.merge_results(results, rescue_results);
      let filled_qtys2: Vec<f64> = results.iter().map(|r| r.filled_qty).collect();
      // Spec hardening: never seed min/max folds with 0.0 (pins wrong). Use ±INFINITY or iter::min/max.
      let max2 = filled_qtys2.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
      let min2 = filled_qtys2.iter().cloned().fold(f64::INFINITY, f64::min);
      if (max2 - min2) <= epsilon && !results.iter().any(|r| r.filled_qty > 0.0 && r.filled_qty < r.requested_qty) {
        // Containment succeeded: atomicity restored (or no-trade) and legs are terminal
        if self.is_group_safe_complete(&results, epsilon) {
          self.ledger.mark_group_state(group.group_id, GroupState::Complete)?;
          return Ok(());
        }
      }
    }

    // Containment Step B: bounded unwind using §3.1 Deterministic Emergency Close (single implementation).
    // Deterministically contain the group by closing ONLY the filled legs.
    // Hard rule: if option unwind fails after bounded attempts, delta-neutralize via reduce-only hedge per §3.1 fallback.
    let filled_legs = self.extract_filled_legs(group.group_id, &results)?;
    self.emergency_close_algorithm(group.group_id, filled_legs).await?; // MUST call the same implementation as §3.1
    return Err(Error::AtomicLeggingFailure);
  }

  // 4) Clean completion (terminal + no partial/mismatch)
  if self.is_group_safe_complete(&results, epsilon) {
    self.ledger.mark_group_state(group.group_id, GroupState::Complete)?;
    return Ok(());
  }

  // Defensive fallback: any mismatch here is naked risk
  self.ledger.mark_group_state(group.group_id, GroupState::MixedFailed)?;
  let filled_legs = self.extract_filled_legs(group.group_id, &results)?;
  self.emergency_close_algorithm(group.group_id, filled_legs).await?; // §3.1 bounded close + hedge fallback
  Err(Error::AtomicLeggingFailure)
}
```

**Acceptance Tests (REQUIRED):**
AT-116
- Given: AtomicGroup with Leg A filled and Leg B rejected.
- When: group result is evaluated.
- Then: `GroupState::MixedFailed` is recorded, containment runs, and no new OPENs are dispatched until exposure is neutral.
- Pass criteria: MixedFailed is recorded and exposure is flattened before any OPEN dispatch.
- Fail criteria: group marked Complete or OPEN dispatch occurs while exposure remains non-neutral.

AT-117
- Given: Leg A fills `0.6`, Leg B fills `0.0`.
- When: rescue IOC attempts execute.
- Then: at most **2** rescue IOC attempts occur; if mismatch persists, deterministic flatten executes.
- Pass criteria: ≤2 rescue attempts and flatten occurs if still mismatched.
- Fail criteria: >2 rescue attempts or mismatch persists without flatten.

AT-118
- Given: mixed-state where one leg is filled and another is rejected.
- When: containment path executes.
- Then: §3.1 emergency close runs with bounded attempts, then reduce-only delta hedge if still not neutral, and TradingMode is ReduceOnly.
- Pass criteria: bounded close attempts then hedge if needed; TradingMode ReduceOnly during exposure.
- Fail criteria: emergency close not executed or OPENs allowed while exposure persists.

AT-939
- Given: `append_group_intent` fails to persist the group intent.
- When: AtomicGroupExecutor attempts to dispatch legs.
- Then: no leg orders are submitted and the failure is surfaced.
- Pass criteria: dispatch count remains 0; failure is logged or returned.
- Fail criteria: any leg dispatch occurs.

AT-936
- Given: a MixedFailed group where LiquidityGate or Net Edge would reject rescue orders.
- When: containment Step A evaluates rescue dispatch.
- Then: no rescue IOC orders are submitted and Step B emergency close runs.
- Pass criteria: rescue dispatch count remains 0 under gate reject; emergency close invoked.
- Fail criteria: rescue orders are submitted when a gate rejects or Step B does not run.



### **1.2.2 Atomic Churn Circuit Breaker (Flatten Storm Guard)**
**Goal:** Prevent “death‑by‑fees” churn when a strategy repeatedly legs, partially fills, then emergency‑flattens.

**Rule (Deterministic):**
- Maintain a rolling counter keyed by `{strategy_id, structure_fingerprint}` where `structure_fingerprint` can be `(instrument_kind, tenor_bucket, delta_bucket, legs_signature)`.
- If `EmergencyFlattenGroup` triggers **> 2 times in 5 minutes** for the same key → **Blacklist** that key for **15 minutes**:
  - block new opens for that key (return `Rejected(ChurnBreakerActive)`),
  - allow closes/hedges (ReduceOnly) as normal.
- Optional early-clear behavior (deterministic, fail-closed):
  - A blacklisted key MAY clear before the 15-minute TTL only if churn-counter inputs are fresh and the key has remained below the trip threshold continuously for `churn_breaker_early_clear_stability_s`.
  - Early-clear MUST emit structured log `ChurnBreakerEarlyClear` with `{strategy_id, structure_fingerprint}`, prior trigger count, stability window, and evidence timestamps used for the decision.
  - If required churn-counter inputs are missing/stale/unparseable, early-clear MUST NOT occur; blacklist TTL remains in force.

**Where:** `crates/soldier_core/src/risk/churn_breaker.rs`

**Acceptance Test (REQUIRED):**
AT-221
- Given: 3 EmergencyFlattenGroup triggers for the same key within 5 minutes.
- When: a 4th attempt is evaluated.
- Then: the 4th attempt is rejected and logged (`ChurnBreakerTrip`), with blacklist TTL enforced.
- Pass criteria: rejection + log + TTL enforcement.
- Fail criteria: 4th attempt proceeds or TTL not enforced.

AT-1245
- Given: a key is currently blacklisted by churn breaker and churn-counter inputs are fresh.
- And: the key stays below the trip threshold continuously for at least `churn_breaker_early_clear_stability_s`.
- When: churn-breaker early-clear evaluation runs.
- Then: the blacklist is cleared before TTL expiry and structured log `ChurnBreakerEarlyClear` is emitted.
- Pass criteria: early-clear occurs only after the full stability window and the required log payload is present.
- Fail criteria: early-clear occurs before stability window, occurs without log, or does not clear despite satisfied conditions.

AT-1246
- Given: a key is currently blacklisted by churn breaker.
- And: churn-counter freshness/evidence inputs required for early-clear are missing, stale, or unparseable.
- When: churn-breaker early-clear evaluation runs.
- Then: blacklist MUST remain active (fail-closed) until normal TTL expiry; no early-clear is allowed.
- Pass criteria: key remains blocked for OPEN until TTL expiry or fresh evidence later satisfies AT-1245.
- Fail criteria: early-clear occurs while required inputs are stale/missing/unparseable.

### **1.2.3 Self-Impact Feedback Loop Guard (Echo Chamber Breaker)**

**Goal:** Prevent the bot from reacting to its own impact and recursively increasing exposure (“echo chamber”).
This is a **safety guard**, not a strategy feature.

**Where:** `crates/soldier_core/src/risk/self_impact_guard.rs`

**Inputs (minimum):**
- Rolling public market volume estimate over `feedback_loop_window_s` (USD notional): `public_notional_usd`
- Rolling self trade notional over the same window (USD notional): `self_notional_usd`
- `public_trades_last_update_ts_ms` (epoch ms; freshness timestamp for public trade feed aggregation)
- `now_ms`
- Intended action classification (OPEN vs CLOSE/HEDGE/CANCEL)

**Freshness precondition (non-negotiable):**
- If `now_ms - public_trades_last_update_ts_ms > public_trade_feed_max_age_ms` OR the field is missing/unparseable:
  - The Self-Impact guard MUST NOT compute `self_fraction`.
  - Instead, the system MUST treat this as a trades-feed liveness failure:
    - Set `RiskState::Degraded`
    - Set Open Permission Latch reason `WS_TRADES_GAP_RECONCILE_REQUIRED`
    - Block opens until reconciliation clears the latch.

**Computation (only when feed is fresh):**
- `self_fraction = self_notional_usd / max(public_notional_usd, epsilon)`
- Trip condition (any):
  A) `self_fraction >= self_trade_fraction_trip` AND `self_notional_usd >= self_trade_min_self_notional_usd`
  B) `self_notional_usd >= self_trade_notional_trip_usd`
- If trip condition is met for a proposed OPEN in the same direction as recent self trades:
  - Reject the OPEN intent before dispatch with `Rejected(FeedbackLoopGuardActive)`
  - Apply cooldown: block further OPENs for `feedback_loop_cooldown_s` for the affected `{strategy_id, structure_fingerprint}` key.

**Acceptance Tests (REQUIRED):**
AT-953
- Given: `public_trades_last_update_ts_ms` is stale beyond `public_trade_feed_max_age_ms`.
  - All other gates are configured to pass (this test isolates stale-feed handling for the Self-Impact guard).
- When: the Self-Impact guard evaluates a new OPEN intent.
- Then: it does NOT compute `self_fraction`; it sets `RiskState::Degraded` and sets Open Permission Latch reason `WS_TRADES_GAP_RECONCILE_REQUIRED`.
- Pass criteria: OPEN blocked due to latch; no `Rejected(FeedbackLoopGuardActive)` is emitted.
- Fail criteria: FeedbackLoopGuard trips (or computes) while trade feed is stale OR OPEN dispatch occurs.

AT-955
- Given:
  - `feedback_loop_window_s = 10`
  - trade feed is fresh: `public_trades_last_update_ts_ms = now_ms - 1000` and `public_trade_feed_max_age_ms = 5000`
  - `self_trade_fraction_trip = 0.25` and `self_trade_min_self_notional_usd = 10_000`
  - `public_notional_usd = 100_000` and `self_notional_usd = 40_000` (so `self_fraction = 0.40`)
  - Proposed action is an **OPEN** in the same direction as recent self trades
  - All other gates are configured to pass (this test isolates the Self-Impact guard)
- When: an OPEN intent is evaluated.
- Then: the intent is rejected with `Rejected(FeedbackLoopGuardActive)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs, rejection missing/mismatched, or guard fails to compute trip from the provided notional inputs.

AT-956
- Given:
  - trade feed is fresh (as above)
  - `self_trade_notional_trip_usd = 150_000`
  - `public_notional_usd = 10_000_000` and `self_notional_usd = 200_000` (so self_fraction is small but notional is large)
  - Proposed action is an **OPEN** in the same direction as recent self trades
  - All other gates are configured to pass
- When: an OPEN intent is evaluated.
- Then: the intent is rejected with `Rejected(FeedbackLoopGuardActive)` via the notional-trip rule.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or the guard ignores the notional-trip path.

AT-957
- Given:
  - trade feed is fresh (as above)
  - `self_trade_fraction_trip = 0.25` and `self_trade_min_self_notional_usd = 10_000`
  - `self_trade_notional_trip_usd = 150_000`
  - `public_notional_usd = 200_000` and `self_notional_usd = 20_000` (so `self_fraction = 0.10`, below threshold; notional below trip)
  - All other gates are configured to pass (isolate Self-Impact guard)
- When: an OPEN intent is evaluated.
- Then: the Self-Impact guard MUST NOT reject with `FeedbackLoopGuardActive`; the intent proceeds to dispatch.
- Pass criteria: dispatch count becomes 1 and there is no `Rejected(FeedbackLoopGuardActive)`.
- Fail criteria: guard rejects despite being below thresholds.


### **1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)**

**Phase applicability (Normative):**
§1.3 Liquidity Gate is **NOT** a Phase 1 completion requirement. §1.3 becomes mandatory beginning in **Phase 2** and later deployable phases, together with the required stale-L2 CLOSE/HEDGE integration points that use the applicable fallback pricing rules. Before Phase 2, absence of §1.3 implementation MUST NOT, by itself, fail Phase 1 completion. Phase 1 remains non-deployable and foundation-gated.

**Council Weakness Covered:** No Liquidity Gate (Low) \+ Taker Bleed (Critical). **Requirement:** Before any order is sent (including IOC), the Soldier must estimate book impact for the requested size and reject trades that exceed max slippage. **Where:** `crates/soldier_core/src/execution/gate.rs` **Input:** `OrderQty`, `L2BookSnapshot`, `max_slippage_bps = 10` (default: see Appendix A)

If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms` (Appendix A), LiquidityGate MUST reject OPEN intents with `Rejected(LiquidityGateNoL2)`. CLOSE/HEDGE/replace order placement MUST NOT be rejected solely for missing or stale L2; they MUST use the deterministic §3.1 fallback price ladder and may dispatch only a strictly positive, monotonic risk-reducing quantity. If no valid §3.1 fallback price source exists, the intent MUST fail closed with `Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded`. CANCEL-only intents remain allowed.
OPEN rejections due to missing/unparseable/stale L2 MUST use `Rejected(LiquidityGateNoL2)`.

**Output:** `Allowed | Rejected(ExpectedSlippageTooHigh) | Rejected(LiquidityGateNoL2) | Rejected(EmergencyCloseNoPrice)`

**Algorithm (Deterministic):**

0. **Staleness pre-check:** If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`, reject per the rules above (OPEN → `Rejected(LiquidityGateNoL2)`; CLOSE/HEDGE → §3.1 fallback). Do not proceed to book walk.
1. Walk the L2 book on the correct side (asks for buy, bids for sell).
2. Compute the Weighted Avg Price (WAP) for `OrderQty`.
3. Compute expected slippage: `slippage_bps = abs(WAP - BestPrice) / BestPrice * 10_000`
4. Reject if `slippage_bps` > `max_slippage_bps` (default 10bps; `max_slippage_bps` from Appendix A).
5. If rejected, log `LiquidityGateReject` with computed WAP \+ slippage.

**Scope (explicit):**
- Applies to normal dispatch and containment rescue IOC orders (see §1.1 containment Step A).
- CLOSE/HEDGE order placement intents with valid, fresh L2 ARE subject to the slippage threshold check (steps 1-4), including containment rescue IOC orders (Step A). If slippage exceeds `max_slippage_bps` for a CLOSE/HEDGE, the gate rejects with `Rejected(ExpectedSlippageTooHigh)`. Deterministic Emergency Close (§3.1) and containment Step B remain exempt.
- Does NOT apply to Deterministic Emergency Close (§3.1) or containment Step B; emergency close MUST NOT be blocked by profitability gates.
- Emergency close still requires a valid price source; missing/stale L2 MUST use the §3.1 fallback price source and MUST block only if no fallback source is valid.
- When no valid fallback source exists, `RiskState::Degraded` is set (see §2.2.3.2 SystemIntegrityAxis), producing `TradingMode::ReduceOnly` via the axis resolver.

**Acceptance Test (REQUIRED):**
AT-222
- Given: an L2 book where `OrderQty` requires consuming multiple levels causing `slippage_bps > max_slippage_bps`.
- When: Liquidity Gate evaluates the order.
- Then: intent is rejected with `Rejected(ExpectedSlippageTooHigh)` and a `LiquidityGateReject` log; no `OrderIntent` is emitted.
- Pass criteria: rejection + log; pricer/NetEdge gate does not run.
- Fail criteria: order proceeds or log missing.
- And: emergency close proceeds even if Liquidity Gate would reject under the same slippage conditions.

AT-344
- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`.
- When: Liquidity Gate evaluates an OPEN intent.
- Then: the intent is rejected with `Rejected(LiquidityGateNoL2)` (no dispatch) and a LiquidityGate rejection is logged.
- Pass criteria: no OPEN dispatch occurs; rejection reason is `LiquidityGateNoL2`.
- Fail criteria: OPEN dispatch proceeds without a valid L2 snapshot, or rejection reason is missing/mismatched.

AT-909
- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms` for an OPEN.
- When: Liquidity Gate evaluates the order.
- Then: the intent is rejected with `Rejected(LiquidityGateNoL2)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-421
- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`.
- When: a CANCEL-only intent and a CLOSE/HEDGE order placement intent are evaluated.
- Then: CANCEL is allowed; CLOSE/HEDGE order placement uses the §3.1 fallback price ladder, remains strictly monotonic risk-reducing, and OPEN remains rejected.
- Pass criteria: cancel proceeds; close/hedge dispatch count is >= 1 when a valid §3.1 fallback source exists; dispatched close/hedge size is > 0 and <= current position / exposure cap; OPEN is rejected.
- Fail criteria: close/hedge is blocked despite a valid §3.1 fallback source, dispatched size is 0 or risk-increasing, or OPEN proceeds.

AT-1241
- Given: `L2BookSnapshot` is missing/unparseable/stale, no fresh `L1TickerSnapshot` is available, and no valid venue-band fallback exists (missing/unparseable/unquantizable metadata).
- When: Liquidity Gate evaluates a CLOSE/HEDGE order placement intent.
- Then: the intent MUST be rejected with `Rejected(EmergencyCloseNoPrice)` and `RiskState` MUST transition to `Degraded`.
- Pass criteria: dispatch count remains 0; rejection reason is `EmergencyCloseNoPrice`; `RiskState == Degraded`.
- Fail criteria: dispatch occurs without a valid price source, rejection reason is missing/mismatched, or `RiskState` does not transition to `Degraded`.

AT-1216
- Given: `L2BookSnapshot` is present, parseable, and fresh; expected slippage is <= `max_slippage_bps`; all non-liquidity gates are forced pass.
- When: Liquidity Gate evaluates an OPEN intent.
- Then: the intent is allowed through Liquidity Gate and proceeds to dispatch.
- Pass criteria: dispatch count increases by 1 and no liquidity reject reason is emitted.
- Fail criteria: intent is rejected by Liquidity Gate despite valid/fresh L2 and in-budget slippage.

AT-1247
- Given: a CLOSE/HEDGE order placement intent with valid, fresh `L2BookSnapshot` and computed `slippage_bps > max_slippage_bps`.
- When: Liquidity Gate evaluates the order.
- Then: the intent is rejected with `Rejected(ExpectedSlippageTooHigh)` and no dispatch occurs.
- Pass criteria: dispatch count remains 0; rejection reason is `ExpectedSlippageTooHigh`.
- Fail criteria: CLOSE/HEDGE dispatches despite exceeding the slippage threshold with valid L2.


### **1.4 Fee-Aware IOC Limit Pricer (No Market Orders)**
**Council Weakness Covered:** Taker Bleed (Critical) + Fee Blindness (High)

**Where:** `crates/soldier_core/src/execution/pricer.rs`
**Input:** `fair_price`, `net_edge_usd` (already authorized by Net Edge Gate), `min_edge_usd`, `fee_estimate_usd`, `qty`, `side`
**Output:** `limit_price`

**Rule:**
- For OPEN intents, Net Edge Gate is the sole profitability eligibility gate. The pricer MUST NOT make an independent profitability authorization decision once an OPEN has already passed Net Edge (and any Inventory Skew re-check).
- If any required pricer numeric input is missing, unparseable, NaN, or `qty <= 0`, the pricer MUST fail closed with `Rejected(PricerInputMissing)` or `Rejected(PricerInputInvalid)` and no dispatch occurs.
- `net_edge_per_unit = net_edge_usd / qty`
- Compute per-unit bounds:
  - `fee_per_unit = fee_estimate_usd / qty`
  - `min_edge_per_unit = min_edge_usd / qty`
  - `max_price_for_min_edge`:
    - BUY: `fair_price - (min_edge_per_unit + fee_per_unit)`
    - SELL: `fair_price + (min_edge_per_unit + fee_per_unit)`
- Proposed limit from fill aggressiveness:  
  `proposed_limit = fair_price ± 0.5 * net_edge_per_unit` (sign depends on buy/sell)
- Final limit **clamped** to guarantee min edge at the limit price:
  - BUY: `limit_price = min(proposed_limit, max_price_for_min_edge)`
  - SELL: `limit_price = max(proposed_limit, max_price_for_min_edge)`
- If IOC returns unfilled/partial: **do not chase**. The missed trade is the cost of not dying.

**Acceptance Test (REQUIRED):**
AT-223
- Given: a widened spread and an IOC limit order.
- When: execution occurs.
- Then: the system never fills worse than `limit_price` and `Realized Edge >= Min_Edge` at the limit price.
- Pass criteria: no fills beyond `limit_price`; realized edge meets minimum.
- Fail criteria: fill worse than `limit_price` or realized edge below minimum.

**OPEN chokepoint sequence (Normative):**
- `DispatchAuth -> Preflight -> Quantize -> DispatchConsistency -> FeeCache/Policy -> Expiry -> Liquidity -> NetEdge -> InventorySkew -> NetEdge re-check (if Inventory Skew adjusts min_edge_usd) -> Pricer -> RecordedBeforeDispatch -> venue/network dispatch`
- No venue/network dispatch side effects may occur before `RecordedBeforeDispatch`. WAL append/acknowledgment, metrics, and reject diagnostics are permitted before dispatch because they are not venue/network side effects.
- `FeeCache/Policy` blocks OPEN when hard-stale fee state or other PolicyGuard/dispatch-authorization conditions apply. CLOSE/HEDGE/CANCEL remain governed by the contract's risk-reducing and Kill semantics.


### **1.4.1 Net Edge Gate (Fees + Expected Slippage)**
**Why this exists:** Prevent “gross edge” hallucinations from bypassing execution safety.

**Where:** `crates/soldier_core/src/execution/gates.rs`  
**Input:** `gross_edge_usd`, `fee_usd`, `expected_slippage_usd`, `min_edge_usd`  
**Output:** `Allowed | Rejected(reason=NetEdgeTooLow)`

**Rule (Non-Negotiable):**
- `net_edge_usd = gross_edge_usd - fee_usd - expected_slippage_usd`
- If any of `gross_edge_usd`, `fee_usd`, `expected_slippage_usd`, or `min_edge_usd` is missing/unparseable -> Reject(intent=NetEdgeInputMissing) and do not dispatch (fail-closed).
- Reject if `net_edge_usd < min_edge_usd`.

**Hard Rule:**
- This gate MUST run **before** any `OrderIntent` is eligible for dispatch (before AtomicGroup creation).

**Scope (explicit):**
- Applies to normal dispatch and containment rescue IOC orders (see §1.1 containment Step A).
- Does NOT apply to Deterministic Emergency Close (§3.1) or reduce-only close/hedge intents.

**Acceptance Tests (REQUIRED):**

AT-015
- Given: `net_edge_usd < min_edge_usd`.
- When: an OPEN intent is evaluated by the Net Edge Gate.
- Then: the OPEN intent is rejected and MUST NOT dispatch.
- Pass criteria: zero dispatch for that OPEN.
- Fail criteria: OPEN dispatch occurs.

AT-327
- Given: Net Edge Gate would reject under net edge conditions.
- When: Deterministic Emergency Close runs.
- Then: emergency close proceeds despite Net Edge Gate rejection.
- Pass criteria: emergency close dispatch occurs.
- Fail criteria: emergency close blocked by Net Edge Gate.

AT-932
- Given: `fee_usd` or `expected_slippage_usd` is missing/unparseable for an OPEN intent.
- When: the Net Edge Gate evaluates the intent.
- Then: the intent is rejected with `Rejected(NetEdgeInputMissing)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or an implicit default is used.


### **1.4.2 Inventory Skew Gate (Execution Bias vs Current Exposure)**
**Why this exists:** Prevent “good trades” from compounding the *wrong* inventory when already near limits.

**Input:** `current_delta`, `delta_limit`, `side`, `min_edge_usd`, `limit_price`, `fair_price`  
**Output:** `Allowed | Rejected(reason=InventorySkew)` and **adjusted** `{min_edge_usd, limit_price}`

**Input Definition:**
`delta_limit` is absolute delta in underlying units (strategy’s delta convention) and MUST be provided by policy/config; missing ⇒ reject OPEN intents (fail-closed).
Rejections for missing `delta_limit` MUST use `Rejected(InventorySkewDeltaLimitMissing)`.

**Rule:**
- `inventory_bias = clamp(current_delta / delta_limit, -1, +1)`  
  (positive = already long delta; negative = already short delta)

**Biasing behavior (deterministic):**
- **BUY intents when `inventory_bias > 0` (already long):**
  - Require higher edge: `min_edge_usd := min_edge_usd * (1 + inventory_skew_k * inventory_bias)` where `inventory_skew_k = 0.5` (default; see Appendix A)
  - Be less aggressive: shift `limit_price` **away** from the touch by `bias_ticks(inventory_bias)` where `bias_ticks(x) = ceil(abs(x) * inventory_skew_tick_penalty_max)` and `inventory_skew_tick_penalty_max = 3` (default; see Appendix A)
- **SELL intents when `inventory_bias > 0` (already long):**
  - Allow slightly lower edge (within bounds) and/or be more aggressive to **flatten** inventory
- Mirror the above for `inventory_bias < 0` (already short).

**Hard Rule:**
- Inventory Skew runs **after** Net Edge Gate and **before** pricer dispatch. If it adjusts `min_edge_usd`, the Net Edge Gate MUST be re-evaluated against the adjusted `min_edge_usd` before dispatch; the adjusted value is authoritative for dispatch eligibility.
- Inventory Skew may *tighten* requirements for risk-increasing trades and *loosen* requirements only for risk-reducing trades.
- Inventory Skew must be computed using **current + pending** exposure, or it must run **after** PendingExposure reservation (see §1.4.2.1). This prevents concurrent risk-budget double-spend.

**Acceptance Test (REQUIRED):**
AT-224
- Given: `current_delta ≈ 0.9 * delta_limit` (near limit).
- When: Inventory Skew evaluates BUY and SELL intents.
- Then: BUY intent that previously passed Net Edge is rejected; SELL intent passes (risk-reducing); SELL intent that initially fails Net Edge passes after `min_edge_usd` adjustment and re-evaluation.
- Pass criteria: BUY rejected; SELL allowed; re-evaluation uses adjusted `min_edge_usd`.
- Fail criteria: BUY allowed or SELL rejected contrary to rules.

AT-043
- Given: `delta_limit` is missing/unparseable.
- When: an OPEN intent enters Inventory Skew Gate evaluation.
- Then: intent is rejected and RiskState is Degraded (or equivalent fail-closed outcome).
- Pass criteria: no OPEN dispatch occurs.
- Fail criteria: OPEN proceeds with an implicit/zero default.

AT-922
- Given: `delta_limit` is missing/unparseable.
- When: an OPEN intent enters Inventory Skew Gate evaluation.
- Then: the intent is rejected with `Rejected(InventorySkewDeltaLimitMissing)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-030
- Given: `inventory_skew_k=0.5` and `inventory_skew_tick_penalty_max=3`.
- When: `inventory_bias=1.0` for BUY.
- Then: limit price shifts 3 ticks below best ask.
- Pass criteria: exactly 3 tick shift.
- Fail criteria: different tick shift.

AT-934
- Given: `pending_delta` is already reserved and `current_delta` alone is below the limit.
- When: Inventory Skew evaluates a new OPEN intent.
- Then: the gate uses `current + pending` exposure (or runs after reservation) and rejects or tightens as required.
- Pass criteria: decision is based on combined exposure; no dispatch when combined exposure breaches limits.
- Fail criteria: decision uses current-only exposure and allows dispatch.


### **1.4.2.1 PendingExposure Reservation (Anti Over‑Fill)**
**Why:** Without reservation, multiple concurrent signals can all observe the same “free delta” and over‑allocate risk.

**Requirement:** Before dispatching any new `AtomicGroup`, the Soldier must **reserve** the projected exposure impact of the intent, atomically, against a shared budget.

**Where:** `crates/soldier_core/src/risk/pending_exposure.rs`

**Model (Minimum Viable):**
- Maintain `pending_delta` (and optionally pending vega/gamma) per instrument + global.
- For each candidate group:
  1. Compute `delta_impact_est` from proposal greeks (or worst‑case delta bound).
  2. Attempt `reserve(delta_impact_est)`:
     - If reservation would breach limits → reject the intent with `Rejected(PendingExposureBudgetExceeded)`.
  3. On terminal outcome:
     - Filled → release reservation and convert to realized exposure.
     - Rejected/Canceled/Failed → release reservation.

**Hard Rule:** Reservation must occur **before** any network dispatch; release must be triggered from TLSM terminal transitions.

**Emergency Drain (PX-4):** <!-- CSP-062 -->
<!-- Anchors: drain_all, kill, emergency, pending_exposure, recovery -->
- A `drain_all()` method MUST exist for kill-switch recovery. It clears ALL reservations across ALL instruments.
- `drain_all()` MUST refuse to execute unless `RiskState::Kill` is active (fail-closed).
- Post-drain, `settle()` calls for drained reservation IDs return `false` (benign — budget already zeroed).
- After drain, normal trading (Healthy) MUST NOT resume until all pre-drain TLSMs have reached terminal state.

**Acceptance Test (REQUIRED):**
AT-225
- Given: 5 concurrent opens with identical pre-trade `current_delta=0`.
- When: PendingExposure reservation runs.
- Then: only the subset that fits the budget reserves; the rest reject; no over-fill occurs.
- Pass criteria: reservations limited to budget; rejected intents do not dispatch.
- Fail criteria: over-fill or reservations exceed budget.

AT-910
- Given: a reservation would breach the exposure budget.
- When: `reserve(delta_impact_est)` is attempted.
- Then: the intent is rejected with `Rejected(PendingExposureBudgetExceeded)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or reason missing/mismatched.

### **1.4.2.2 Global Exposure Budget (Cross‑Instrument, Correlation‑Aware)**
**Goal:** Prevent “safe per‑instrument” trades from stacking into unsafe portfolio exposure.

**Where:** `crates/soldier_core/src/risk/exposure_budget.rs`

**Budget Model (Pragmatic MVP):**
- Track exposures per instrument and portfolio aggregate:
  - `delta_usd` (required), `vega_usd` (optional v1), `gamma_usd` (optional v1).
- Portfolio aggregation uses conservative correlation buckets:
  - `corr(BTC,ETH)=0.8`, `corr(BTC,alts)=0.6`, `corr(ETH,alts)=0.6`.
- Gate new opens if portfolio exposure breaches limits even if single‑instrument gates pass.
  - Rejections for portfolio breach MUST use `Rejected(GlobalExposureBudgetExceeded)`.

**Integration Rule:** The Global Budget must be checked using **current + pending** exposure (see §1.4.2.1).

**Acceptance Test (REQUIRED):**
AT-226
- Given: BTC and ETH are both near limits.
- When: a new BTC trade passes the local delta gate.
- Then: the trade is rejected if the portfolio budget would breach after correlation adjustment.
- Pass criteria: portfolio-level rejection triggers.
- Fail criteria: trade proceeds despite portfolio breach.

AT-911
- Given: portfolio exposure would breach after correlation adjustment.
- When: Global Exposure Budget evaluates an OPEN intent.
- Then: the intent is rejected with `Rejected(GlobalExposureBudgetExceeded)` and no dispatch occurs.
- Pass criteria: rejection reason matches; dispatch count remains 0.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-929
- Given: `pending_delta` is already reserved near the limit and `current_delta` is within limits.
- When: Global Exposure Budget evaluates a new OPEN intent.
- Then: the intent is rejected if `current + pending` would breach the portfolio budget.
- Pass criteria: rejection occurs based on combined exposure.
- Fail criteria: intent passes using current-only exposure.

### **1.4.3 Margin Headroom Gate (Liquidation Shield) — MUST implement**

**Why this exists:** Delta-neutral ≠ safe. Deribit can hike maintenance margin; margin liquidation is the silent killer.

**Where:**
- Gate: `crates/soldier_core/src/risk/margin_gate.rs`
- Fetcher: `crates/soldier_infra/src/deribit/account_summary.rs`

**Inputs:** `/private/get_account_summary` → `maintenance_margin`, `initial_margin`, `equity`  
**Computed:** `mm_util = maintenance_margin / max(equity, epsilon)`

**Rules (deterministic):**
- If `mm_util` >= `mm_util_reject_opens` (see Appendix A for `mm_util_reject_opens`) → **Reject** any **NEW opens**
- Rejections at `mm_util_reject_opens` MUST use `Rejected(MarginHeadroomRejectOpens)`.
- If `mm_util` >= `mm_util_reduceonly` (see Appendix A for `mm_util_reduceonly`) → PolicyGuard MUST force `TradingMode = ReduceOnly` (block opens; allow close/hedge/cancel)
- If `mm_util` >= `mm_util_kill` (see Appendix A for `mm_util_kill`) → PolicyGuard MUST force `TradingMode = Kill` + trigger deterministic emergency flatten only if eligible per §2.2.3 Kill Mode Semantics (existing §3.1/§1.2 containment applies)

**Acceptance Tests (REQUIRED):**
AT-227
- Given: `equity=100k`, `maintenance_margin=72k`.
- When: Margin Headroom Gate evaluates a new OPEN.
- Then: the OPEN is rejected.
- Pass criteria: OPEN rejected at gate level.
- Fail criteria: OPEN proceeds.

AT-912
- Given: `mm_util >= mm_util_reject_opens` and `< mm_util_reduceonly`.
- When: Margin Headroom Gate evaluates a new OPEN.
- Then: the OPEN is rejected with `Rejected(MarginHeadroomRejectOpens)`.
- Pass criteria: rejection reason matches; no OPEN dispatch.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-228
- Given: `equity=100k`, `maintenance_margin=90k`.
- When: PolicyGuard computes TradingMode.
- Then: `TradingMode = ReduceOnly`.
- Pass criteria: ReduceOnly entered; OPEN blocked.
- Fail criteria: TradingMode remains Active.

AT-206
- Given: `mm_util >= mm_util_reject_opens` but below `mm_util_reduceonly`.
- When: a new OPEN intent is evaluated at the Margin Headroom Gate.
- Then: the OPEN intent is rejected; CLOSE/HEDGE/CANCEL intents remain allowed.
- Pass criteria: OPEN rejected at gate level; TradingMode may still be Active (gate rejection is independent of mode).
- Fail criteria: OPEN intent passes the Margin Headroom Gate while `mm_util >= mm_util_reject_opens`.

AT-207
- Given: `mm_util >= mm_util_reduceonly` but below `mm_util_kill`.
- When: PolicyGuard computes TradingMode.
- Then: `TradingMode = ReduceOnly`; OPEN intents blocked; CLOSE/HEDGE/CANCEL allowed.
- Pass criteria: ReduceOnly entered; opens blocked; closes/hedges allowed.
- Fail criteria: TradingMode is Active while `mm_util >= mm_util_reduceonly`.

AT-208
- Given: `mm_util >= mm_util_kill`.
- When: PolicyGuard computes TradingMode.
- Then: `TradingMode = Kill`; deterministic emergency flatten executes per §3.1/§1.2 containment rules.
- Pass criteria: Kill entered; containment executes (if eligible per §2.2.3); no new orders dispatched except containment.
- Fail criteria: TradingMode is ReduceOnly or Active while `mm_util >= mm_util_kill`.

### **1.4.4 Deribit Order-Type Preflight Guard (Artifact-Backed)**

**Purpose:** Freeze the engine against *verified* Deribit behavior and prevent “market order roulette.”

**Preflight Rules (MUST implement):**

**A) Options (`instrument_kind == option`)**
- Allowed `type`: **`limit` only**
- **Market orders:** forbidden by policy (F-01b)  
  - If `type == market` → **REJECT** with `Rejected(OrderTypeMarketForbidden)` (no rewrite/normalization).
- **Stop orders:** forbidden (F-01a)  
  - Reject any `type in {stop_market, stop_limit}` or any presence of `trigger` / `trigger_price` with `Rejected(OrderTypeStopForbidden)`.
- **Linked/OCO orders:** forbidden (F-08)  
  - Reject any non-null `linked_order_type` with `Rejected(LinkedOrderTypeForbidden)`.
- Execution policy: use **Aggressive IOC Limit** with bounded `limit_price_q` (see §1.4.1).

**B) Futures/Perps (`instrument_kind in {linear_future, inverse_future, perpetual}`)**
- **Allowed `type`:** `limit` (for this bot's execution policy)
- **Market orders:** forbidden by policy  
  - If `type == market` → **REJECT** with `Rejected(OrderTypeMarketForbidden)` (no rewrite/normalization).
- **Stop orders:** **NOT SUPPORTED** for this bot (execution policy is IOC limits only)  
  - Reject any `type in {stop_market, stop_limit}` even if `trigger` is present, with `Rejected(OrderTypeStopForbidden)`.
  - Deribit venue fact (F-09): If stop orders were enabled, venue requires `trigger` to be set.
- **Linked/OCO orders:** forbidden unless explicitly certified (F-08 currently indicates NOT SUPPORTED)  
  - Reject any non-null `linked_order_type` unless `linked_orders_supported == true` **and** feature flag `ENABLE_LINKED_ORDERS_FOR_BOT == true`, with `Rejected(LinkedOrderTypeForbidden)`.

**Linked orders gating variables (contract-bound definitions):**
- `linked_orders_supported` (bool): MUST be `false` for v5.2 (see Deribit Venue Facts Addendum F-08: VERIFIED (NOT SUPPORTED)).
- `ENABLE_LINKED_ORDERS_FOR_BOT` (bool): runtime config feature flag; default `false` (fail-closed if missing/unset).

AT-1099
- Given: runtime configuration does not include `ENABLE_LINKED_ORDERS_FOR_BOT` (key missing or unset).
- When: the linked-orders feature flag is resolved.
- Then: `ENABLE_LINKED_ORDERS_FOR_BOT` MUST default to `false` (fail-closed); any intent with non-null `linked_order_type` MUST be rejected with `Rejected(LinkedOrderTypeForbidden)`.
- Pass criteria: missing config key defaults to `false`; linked order intent rejected.
- Fail criteria: missing config key defaults to `true`, or linked order intent is dispatched.

**Acceptance Test (REQUIRED):**
AT-004
- Given: an intent with `linked_order_type` set (non-null).
- When: preflight validation runs with `linked_orders_supported==false` and `ENABLE_LINKED_ORDERS_FOR_BOT==false` (defaults).
- Then: the intent is rejected before any API call.
- Pass criteria: no outbound order is emitted and a deterministic reject reason is logged.
- Fail criteria: any order with non-null `linked_order_type` is dispatched.


**C) Post-only behavior**
- If `post_only == true` and order would cross the book, Deribit rejects (F-06).  
  - Preflight must ensure post-only prices are non-crossing (or disable post_only). If it would cross, reject with `Rejected(PostOnlyWouldCross)`.

**Enforcement points (code):**
- Centralize in a single function called by the trade dispatch path (`private/buy` + `private/sell`) before any API call.
- Violations must be **hard rejects** (do not “try anyway”).

**Regression tests (MUST):**

AT-016
- Given: an options order intent has `order_type == market`.
- When: Deribit Order-Type Preflight Guard runs.
- Then: intent MUST be rejected before dispatch.
- Pass criteria: no dispatch occurs.
- Fail criteria: market order dispatch occurs.

AT-017
- Given: a perpetual order intent has `order_type == market`.
- When: preflight runs.
- Then: intent MUST be rejected before dispatch.
- Pass criteria: no dispatch occurs.
- Fail criteria: market order dispatch occurs.

AT-018
- Given: an options order intent is `stop_market` or stop with market execution.
- When: preflight runs.
- Then: intent MUST be rejected before dispatch.
- Pass criteria: no dispatch occurs.
- Fail criteria: stop-market dispatch occurs.

AT-019
- Given: a perpetual order intent is `stop_market` or stop with market execution.
- When: preflight runs.
- Then: intent MUST be rejected before dispatch.
- Pass criteria: no dispatch occurs.
- Fail criteria: stop-market dispatch occurs.

AT-913
- Given: an intent with `order_type == market`.
- When: preflight validation runs.
- Then: the intent is rejected with `Rejected(OrderTypeMarketForbidden)`.
- Pass criteria: rejection reason matches; no dispatch occurs.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-914
- Given: an intent with `order_type in {stop_market, stop_limit}`.
- When: preflight validation runs.
- Then: the intent is rejected with `Rejected(OrderTypeStopForbidden)`.
- Pass criteria: rejection reason matches; no dispatch occurs.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-915
- Given: `linked_order_type` is non-null while linked orders are unsupported.
- When: preflight validation runs.
- Then: the intent is rejected with `Rejected(LinkedOrderTypeForbidden)`.
- Pass criteria: rejection reason matches; no dispatch occurs.
- Fail criteria: dispatch occurs or reason missing/mismatched.

AT-916
- Given: `post_only == true` and the limit price would cross the book.
- When: preflight validation runs.
- Then: the intent is rejected with `Rejected(PostOnlyWouldCross)`.
- Pass criteria: rejection reason matches; no dispatch occurs.
- Fail criteria: dispatch occurs or reason missing/mismatched.

- See AT-004 for linked orders testing (`linked_orders_oco_is_gated_off`).


### **1.5 Position-Aware Execution Sequencer (Council D3)**
**Goal:** Prevent creating *new* naked risk while repairing, hedging, or closing.

**Where:** `crates/soldier_core/src/execution/sequencer.rs`  
**Input:** `intent_kind(Open|Close|Repair)`, `current_positions`, `desired_legs`, `risk_limits`  
**Output:** An ordered list of **ExecutionSteps** with enforced prerequisites (confirmations).

**Deterministic Sequencing Rules:**
1. **Closing (Reduce-Only):** `Close -> Confirm -> Hedge (reduce-only)`
   - Place reduce-only closes first.
   - Do **not** open hedges until the close step has a terminal confirmation (Filled/Canceled/Failed) and residual exposure is computed.
2. **Opening:** `Open -> Confirm -> Hedge`
   - Place opening legs first (AtomicGroup allowed).
   - Hedge only after opens reach terminal confirmation (Filled/Failed/Canceled) and exposure is measured.
3. **Repairs (Mixed Failed / Zombies):**
   - **Flatten filled legs first** using the §3.1 Emergency Close implementation (`emergency_close_algorithm`).
   - Hedge **only if** flatten retries fail and exposure remains above limit (fallback reduce-only hedge).

**Invariant:**  
- No step may increase exposure while `RiskState != Healthy` or while a prior step is unresolved.

**Acceptance Test (REQUIRED):**
AT-229
- Given: `RiskState::Degraded`.
- When: an Open intent and a Close/Hedge intent are submitted.
- Then: Open is rejected; Close/Hedge is allowed; no exposure-increasing action occurs while `RiskState != Healthy`.
- Pass criteria: Open blocked; Close/Hedge allowed; exposure not increased.
- Fail criteria: Open allowed or exposure increases while Degraded.



---
