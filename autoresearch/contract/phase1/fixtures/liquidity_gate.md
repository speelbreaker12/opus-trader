### **1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)**

**Phase applicability (Normative):**
§1.3 Liquidity Gate is **NOT** a Phase 1 completion requirement. §1.3 becomes mandatory beginning in **Phase 2** and later deployable phases, together with the required stale-L2 CLOSE/HEDGE integration points that use the applicable fallback pricing rules. Before Phase 2, absence of §1.3 implementation MUST NOT, by itself, fail Phase 1 completion. Phase 1 remains non-deployable and foundation-gated.

**Council Weakness Covered:** No Liquidity Gate (Low) \+ Taker Bleed (Critical). **Requirement:** Before any order is sent (including IOC), the Soldier must estimate book impact for the requested size and reject trades that exceed max slippage. **Where:** `crates/soldier_core/src/execution/gate.rs` **Input:** `OrderQty`, `L2BookSnapshot`, `max_slippage_bps = 10` (default: see Appendix A)

If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms` (Appendix A), LiquidityGate MUST reject OPEN intents with `Rejected(LiquidityGateNoL2)`. CLOSE/HEDGE/replace order placement MUST NOT be rejected solely for missing or stale L2; they MUST use the deterministic §3.1 fallback price ladder and may dispatch only a strictly positive, monotonic risk-reducing quantity. If no valid §3.1 fallback price source exists, the intent MUST fail closed with `Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded`. CANCEL-only intents remain allowed.
OPEN rejections due to missing/unparseable/stale L2 MUST use `Rejected(LiquidityGateNoL2)`.

**Output:** `Allowed | Rejected(reason=ExpectedSlippageTooHigh)`

**Algorithm (Deterministic):**

1. Walk the L2 book on the correct side (asks for buy, bids for sell).  
2. Compute the Weighted Avg Price (WAP) for `OrderQty`.  
3. Compute expected slippage: `slippage_bps = (WAP - BestPrice) / BestPrice * 10_000` (sign adjusted)  
4. Reject if `slippage_bps` > `max_slippage_bps` (default 10bps; `max_slippage_bps` from Appendix A).  
5. If rejected, log `LiquidityGateReject` with computed WAP \+ slippage.

**Scope (explicit):**
- Applies to normal dispatch and containment rescue IOC orders (see §1.1 containment Step A).
- Does NOT apply to Deterministic Emergency Close (§3.1) or containment Step B; emergency close MUST NOT be blocked by profitability gates.
- Emergency close still requires a valid price source; missing/stale L2 MUST use the §3.1 fallback price source and MUST block only if no fallback source is valid.

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
- Then: the intent is rejected (no dispatch) and a LiquidityGate rejection is logged.
- Pass criteria: no OPEN dispatch occurs; rejection reason recorded.
- Fail criteria: OPEN dispatch proceeds without a valid L2 snapshot.

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

AT-1216
- Given: `L2BookSnapshot` is present, parseable, and fresh; expected slippage is <= `max_slippage_bps`; all non-liquidity gates are forced pass.
- When: Liquidity Gate evaluates an OPEN intent.
- Then: the intent is allowed through Liquidity Gate and proceeds to dispatch.
- Pass criteria: dispatch count increases by 1 and no liquidity reject reason is emitted.
- Fail criteria: intent is rejected by Liquidity Gate despite valid/fresh L2 and in-budget slippage.



