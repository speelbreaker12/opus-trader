# LOSS-RISK CONTRACT AUDIT — Phase 1 Focus (Consolidated)
## CONTRACT.md v5.2 | Audit Date: 2026-03-05 | Revision: R2 (merged Codex cross-audit findings)

---

## A. EXECUTIVE VERDICT

**`CONTRACT_NO_GO_BLOCKING_GAPS`**

**Verdict upgraded from R1's `CONTRACT_GO_WITH_HARDENING` to `NO_GO` after cross-audit reconciliation.** The Codex/GPT-5 audit identified 8 BLOCKING gaps that this audit's R1 missed — most critically, the contract text itself permits stale L2 to block CLOSE/HEDGE (stranding exposure), and the identity chain (hash → label → WAL → dedupe → reconcile) has internal inconsistencies that can cause silent loss through misattribution, false dedupe, or unapplied fills.

**Risk summary**:
- Avoidable loss paths: 8 identified (3 Phase 1 contract-text bugs, 5 Phase 2+ spec gaps)
- Silent profit blocking paths: 4 identified (2 Phase 1, 2 Phase 2)
- Fail-open hazards: 2 identified (both Phase 2+ scope)
- Identity/reconciliation defects: 4 identified (all affect Phase 1 contract text)
- Implementation ambiguity creating loss risk: 4 identified

**Self-audit note**: R1 of this audit rated Phase 1 as "clean" — this was wrong. Three systematic failures in R1 caused 8 BLOCKING misses:
1. **"PASS" bias on existing ATs**: Seeing tests pass caused premature stop; didn't check whether the contract *specification* was itself the bug.
2. **No Capital Supremacy cross-cut**: Never systematically asked "which gates can block CLOSE/HEDGE?" — missed G5-LIQEXIT and G6-FEEPROOF.
3. **No identity/reconciliation thread**: Never traced hash → label → WAL → restart → dedupe → reconcile as a single chain — missed G2-HASH, G4-LABELMATCH, G7-RESTART, G10-STARTUPLATCH, G11-TRADEDEDUPE.

---

## B. CLAUSE AUDIT TABLE

### B.1 Phase 1 Clauses — BLOCKING Findings (Missed in R1, from Cross-Audit)

| Gap ID | Clause | Severity | Category | Finding | Remediation |
|--------|--------|----------|----------|---------|-------------|
| **G5-LIQEXIT** | §1.3 Liquidity Gate | **BLOCKING** | **Loss + Profit-block** | **CONTRACT TEXT BUG.** L1366 says "CLOSE/HEDGE/replace order placement is rejected" on stale/missing L2. AT-421 codifies this: "CLOSE/HEDGE order placement is rejected (no dispatch)." This violates Capital Supremacy (§0.Z.2.2 F) — stale L2 can strand exposure by blocking all non-emergency risk-reducing exits. Emergency Close is exempt but normal CLOSE/HEDGE is not, creating a gap between "degraded but not emergency" scenarios. | **REPLACE** L1366 rule: Missing/stale L2 blocks OPEN only; CLOSE/HEDGE use §3.1 fallback price ladder and may dispatch only monotonic risk-reducing quantity. If no fallback price valid, fail-closed with `Rejected(EmergencyCloseNoPrice)`. **REPLACE** AT-421 accordingly. |
| **G2-HASH** | §1.1.1 Hash Identity | **BLOCKING** | **Loss** | **CONTRACT-CODE MISMATCH.** Contract L966 says `intent_hash = xxhash64(... + qty_q + limit_price_q + ...)` using float-like names. Code (`idempotency/hash.rs:22-24`) correctly hashes `qty_steps: i64` and `price_ticks: i64`. L1082 repeats the float naming. Two reasonable implementations reading the contract could hash floats (non-deterministic across platforms) vs integers (correct). False dedupe = lost trade; false non-dedupe = duplicate order. | **REPLACE** L966 and L1082: `intent_hash` MUST be computed from `qty_steps` and `price_ticks` (integer canonical values). `qty_q` and `limit_price_q` MAY appear in observability but MUST NOT be hashed directly. |
| **G4-LABELMATCH** | §1.1.2 Label Disambiguation | **BLOCKING** | **Loss** | Contract L1039-1046 specifies a legacy/repair fallback that matches by `{gid12, leg_idx}` only (dropping `sid8` and `ih16`). On canonical `s4` labels, this heuristic can merge distinct intents into one match — misattributing an exchange order to the wrong local intent. Misattribution = wrong position tracking = wrong risk. | **ADD**: For canonical `s4:` labels, match MUST use full identity `{sid8, gid12, leg_idx, ih16}`. If count != 1, set `RiskState::Degraded`, block OPEN, require REST reconcile. Legacy fallback ONLY for non-canonical labels. |
| **G1-IKIND** | §1.0 Instrument-Kind Derivation | **BLOCKING** | **Loss** | `derive_instrument_kind()` exists in `venue/types.rs` but line 46 has `// TODO(slice-N): Wire into production dispatch — currently only called from unit tests`. The production dispatch path does NOT use the normative derivation function. Two implementations could classify the same instrument differently → wrong `amount_semantics` → wrong dispatch amount → loss. | **ADD normative clause**: `amount_semantics ∈ {Coin, Usd}` MUST be derived from `derive_instrument_kind()` and MUST be the sole dispatch/sizing branch input in the production path. **Wire the existing function** into production. |
| **G8-CHOKEORDER** | §1.4/§1.4.1 Gate Order | **BLOCKING** | **Loss** | Contract does not normatively bind the full OPEN gate sequence. Two implementations could disagree on ordering. Also, `expected_slippage_usd` used by Net Edge (§1.4.1) may come from a different liquidity evaluation than the one that authorized the OPEN — proxy slippage enables "gross edge hallucination" that the gate exists to prevent. | **ADD normative clause** binding exact gate order (1-10). `expected_slippage_usd` MUST come from the same Liquidity Gate evaluation that authorized the OPEN. Pricer MUST NOT make independent profitability decisions. |
| **G7-RESTART** | §2.4/AT-935 WAL Restart | **BLOCKING** | **Loss** | AT-935 is ambiguous about whether WAL replay alone can dispatch unsent OPENs. If an OPEN is WAL-recorded but never sent, restart reconciliation could auto-dispatch a stale OPEN against a market that has moved. | **REPLACE** AT-935 THEN/PASS: WAL-recorded unsent OPENs MUST NOT auto-dispatch from replay alone. Dispatch after restart ONLY if fresh post-restart evaluation re-authorizes the OPEN and all gates pass. |
| **G10-STARTUPLATCH** | §2.2.4 Startup Latch | **BLOCKING** | **Loss** | CP-001 latch must be PROVEN causal — set before any dispatch path is reachable, not just documented. Also, ACK-lost recovery is unspecified: if crash happens after venue ACK but before local `ack_ts` update, the system may resend (duplicate order) or suppress the ACK'd order (orphaned exposure). | **ADD**: Runtime MUST set `open_permission_blocked_latch = true` with `RESTART_RECONCILE_REQUIRED` after WAL replay and before any OPEN-capable path. If reconciliation finds ACK evidence for an intent with absent local `ack_ts`, runtime MUST record `ack_ts`, advance TLSM, and MUST NOT resend. |
| **G11-TRADEDEDUPE** | Trade-ID Registry | **BLOCKING** | **Loss** | If crash occurs between recording `trade_id` in the dedup registry and applying the fill state update (position, TLSM, attribution), restart dedup will suppress the trade event as "already seen" — but the fill was never applied. Silent loss of a real fill. | **REPLACE** trade handler rule: Duplicate suppression MUST apply only to fully-applied trades. System MUST commit `{trade_id, group_id, leg_idx, qty, price}` and TLSM/position/attribution updates atomically. If atomic commit unavailable, record with `apply_pending = true`, enter `RiskState::Degraded`, and reconciliation MUST complete before any later NOOP on that `trade_id`. |

### B.2 Phase 1 Clauses — HARDENING Findings (from Cross-Audit)

| Gap ID | Clause | Severity | Category | Finding | Remediation |
|--------|--------|----------|----------|---------|-------------|
| **G6-FEEPROOF** | §4.2 Fee Cache | HARDENING | Profit-block | Fee cache hard-stale blocks ALL intents including CLOSE/HEDGE (confirmed: `base_gates.rs:343-360` has no Close/Hedge skip for Gate 5). Same Capital Supremacy pattern as G5-LIQEXIT. | Hard-stale fee cache blocks OPEN only; CLOSE/HEDGE/CANCEL remain legal unless Kill applies. |
| **G3-S4SCHEMA** | §1.1.2 s4 Schema | HARDENING | Loss | s4 label schema validation proof gaps: wrong width, charset, version labels may not be exhaustively tested for deterministic rejection before dispatch. | Add exhaustive schema validation tests: wrong segment count, wrong token widths, invalid characters all reject before dispatch with `RiskState::Degraded`. |
| **G12-LINKEDORDERS** | Phase 1 Linked Orders | HARDENING | Loss | Linked-order gate shape issues not fully specified for Phase 1 scope. | Specify gate shape for linked orders in Phase 1. |

### B.3 Phase 1 Clauses — Original Findings (from R1)

| Gap ID | Clause | Severity | Category | Finding | Remediation |
|--------|--------|----------|----------|---------|-------------|
| G-1-001 | §1.0 Instrument Units | HARDENING | Profit-block | No minimum profitable trade size relative to fee floor. 0.1-contract trade with $0.50 fee on $0.01 edge = guaranteed loss. | Add: "Minimum order size MUST exceed `fee_floor_usd / expected_edge_per_contract` or be rejected by NetEdgeGate." |
| G-1-005 | §1.2 Atomic Group Executor | HARDENING | Loss | `atomic_qty_epsilon` not specified relative to instrument tick size. Too large = naked leg; too small = false flatten = fee loss. | Add: "`atomic_qty_epsilon` MUST be <= instrument `min_amount` / 2." |
| G-1-010 | §1.4.2 Inventory Skew | HARDENING | Profit-block | No staleness guard on `current_delta`. Stale position data → bad inventory skew decision → loss or profit-block. | Add position staleness guard: stale `current_delta` blocks OPEN but allows CLOSE/HEDGE. |
| G-1-012 | §1.4.3 Margin Headroom | HARDENING | Loss | Margin check doesn't specify whether to use exchange-reported or locally-computed margin. Stale exchange margin can permit OPENs causing liquidation. | Use MORE CONSERVATIVE of exchange-reported and locally-estimated. Stale = 100% utilization. |
| G-1-014 | §1.2.2 Churn Breaker | HARDENING | Loss | Churn counter resets on restart. Bug/attacker can bypass by repeated restarts. | Churn counter MUST persist via WAL or equivalent durable store. |

### B.4 Phase 2+ Clauses — BLOCKING (from R1, unchanged)

| Gap ID | Clause | Severity | Category | Finding | Remediation |
|--------|--------|----------|----------|---------|-------------|
| G-2-001 | §2.2 PolicyGuard | BLOCKING | Loss | No implementation. Expected for Phase 1. | Phase 2 task. Add: "PolicyGuard MUST be SOLE writer of TradingMode." |
| G-2-002 | §2.2.3 Kill Corroboration | BLOCKING | Loss | No timeout for corroboration. System stuck if signal B never arrives. | Add `kill_corroboration_timeout_ms` (5000ms default) → ReduceOnly on timeout. |
| G-2-003 | §2.2.4 CP-001 Hold Duration | BLOCKING | Profit-block | No max hold duration. Broken reconciliation = permanent profit block. | Add `open_permission_latch_max_hold_ms` (300000ms) → alert, remain ReduceOnly. |
| G-2-004 | §2.2.4 CP-001 Scope | BLOCKING | Profit-block | Global latch. WS gap on one instrument blocks all instruments. | Per-instrument latch for instrument-scoped triggers. |
| G-2-005 | §3.1 Emergency Close | BLOCKING | Loss | No implementation. Expected for Phase 1. | Phase 2 task. Contract spec adequate. |
| G-2-006 | §3.3 Session + Exposure | BLOCKING | Loss | Session termination blocks emergency close dispatch. | Emergency close MUST use dedicated session or prioritize reconnection. |
| G-2-007 | §3.1 Hedge Partial Fill | BLOCKING | Loss | No partial fill handling on hedge itself. Residual naked delta. | Re-hedge with bounded retry. Alert if residual > threshold. |
| G-2-008 | §0.Z.7 CSP_ONLY Build | BLOCKING | Infra | No Cargo feature flags. Expected for Phase 1. | Phase 3 task. |

### B.5 Cross-Cutting Findings (from R1, unchanged)

| Gap ID | Clause | Severity | Category | Finding | Remediation |
|--------|--------|----------|----------|---------|-------------|
| G-X-001 | §2.2.3 ModeReasonCode | HARDENING | Drift | Generated enum may drift from contract registry. | CI gate for registry match. |
| G-X-002 | Appendix A Defaults | HARDENING | Loss | 8 "implementation-defined" parameters risk fail-open. | Audit and add explicit fail-closed defaults. |
| G-X-003 | §1.2.3 Echo Chamber | HARDENING | Loss | No staleness bound on attribution data for self-impact detection. | Add `self_impact_attribution_max_age_ms` (60000ms). |
| G-X-004 | §1.5 Sequencer | HARDENING | Profit-block | No maximum reorder delay. Unbounded delay = stale prices. | Add `sequencer_max_delay_ms` (500ms), reject on exceed. |
| G-X-005 | CSP Invariant F | HARDENING | Loss | No AT for all-containment-paths-exhausted scenario. | Add AT for hold-and-alert terminal state. |
| G-X-006 | §2.2.1 Runtime Binding | HARDENING | Infra | No AT for corrupted/truncated binding cert. | Add AT: corrupted cert → force ReduceOnly. |

---

## C. MISSING PROTECTIONS

### C.1 Protections Present in Contract (Verified)
- [x] RecordedBeforeDispatch (WAL-first) for all OPEN intents
- [x] Idempotency keys derived from deterministic fields only (no RNG/clock)
- [x] Fail-closed quantization (BUY rounds down, SELL rounds up)
- [x] Fail-closed on missing instrument metadata
- [x] No market orders (IOC limit only)
- [x] Emergency close exempt from profitability gates
- [x] CANCEL allowed when CLOSE/HEDGE blocked by stale L2
- [x] Capital Supremacy Invariant stated (but violated by G5-LIQEXIT and G6-FEEPROOF)
- [x] Churn circuit breaker (flatten storm guard)
- [x] Group intent pre-persist before leg dispatch
- [x] Monotonic timebase for safety-critical interval checks

### C.2 Protections Missing from Contract

**Capital Supremacy violations (stale data strands exposure):**
1. **Stale/missing L2 blocks CLOSE/HEDGE** — G5-LIQEXIT (BLOCKING)
2. **Hard-stale fee cache blocks CLOSE/HEDGE** — G6-FEEPROOF (HARDENING)

**Identity chain defects (misattribution, false dedupe, lost fills):**
3. **Hash inputs named as floats, code uses integers** — G2-HASH (BLOCKING)
4. **Canonical label disambiguation uses heuristic fallback** — G4-LABELMATCH (BLOCKING)
5. **Trade-ID dedup can suppress unapplied fills** — G11-TRADEDEDUPE (BLOCKING)

**Restart/reconciliation gaps:**
6. **WAL-recorded unsent OPENs may auto-dispatch on restart** — G7-RESTART (BLOCKING)
7. **Startup latch not proven causal + ACK-lost recovery missing** — G10-STARTUPLATCH (BLOCKING)

**Implementation wiring gaps:**
8. **Instrument-kind derivation not wired to production** — G1-IKIND (BLOCKING)
9. **OPEN gate order not normatively bound** — G8-CHOKEORDER (BLOCKING)

**Phase 2+ specification gaps:**
10. **No maximum CP-001 latch hold duration** — G-2-003 (BLOCKING)
11. **No per-instrument latch scoping** — G-2-004 (BLOCKING)
12. **No session fallback for emergency close** — G-2-006 (BLOCKING)
13. **No hedge partial fill handling** — G-2-007 (BLOCKING)
14. **No Kill corroboration timeout** — G-2-002 (BLOCKING)
15. **No staleness guard on `current_delta`** — G-1-010 (HARDENING)
16. **No `atomic_qty_epsilon` relative to instrument tick** — G-1-005 (HARDENING)
17. **No churn counter persistence across restarts** — G-1-014 (HARDENING)
18. **No all-containment-paths-exhausted AT** — G-X-005 (HARDENING)

---

## D. EXACT CONTRACT PATCHES (Priority Order)

### Patch 1: Liquidity Gate CLOSE/HEDGE Carveout (G5-LIQEXIT) — BLOCKING/Loss

**Location**: §1.3 L1366, replace the stale-L2 rule

```markdown
REPLACE the second sentence of the stale-L2 paragraph WITH:

If `L2BookSnapshot` is missing, unparseable, or older than
`l2_book_snapshot_max_age_ms` (Appendix A), LiquidityGate MUST reject
OPEN intents with `Rejected(LiquidityGateNoL2)`.
CLOSE/HEDGE intents MUST NOT be rejected solely for missing or stale L2;
they MUST use the bounded fallback price ladder in §3.1 and may dispatch
only monotonic risk-reducing quantity.
If no valid fallback price source exists, the intent MUST fail closed with
`Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded`.
CANCEL-only intents remain allowed regardless.

REPLACE AT-421:
AT-421
- Given: `L2BookSnapshot` is missing/unparseable/stale.
- When: CANCEL, CLOSE, and HEDGE intents are evaluated.
- Then: CANCEL is allowed. CLOSE/HEDGE are allowed using §3.1
  fallback price; they dispatch only risk-reducing quantity.
  OPEN is rejected.
- Pass criteria: cancel proceeds; close/hedge proceed with fallback
  price; OPEN blocked.
- Fail criteria: close/hedge blocked when fallback price is available,
  or OPEN proceeds.
```

### Patch 2: Hash Identity Integer Canonicalization (G2-HASH) — BLOCKING/Loss

**Location**: §1.1.1 L966 and §1.1.2 L1082

```markdown
REPLACE L966:
  `intent_hash = xxhash64(instrument + side + qty_steps + price_ticks
   + group_id + leg_idx)`
  where `qty_steps = floor(raw_qty / amount_step)` and
  `price_ticks = round(raw_price / tick_size)` are integer values.
  `qty_q` and `limit_price_q` MAY be emitted for observability but
  MUST NOT be hashed directly.

REPLACE L1082:
  `intent_hash`: `xxhash64(instrument + side + qty_steps + price_ticks
   + group_id + leg_idx)` (see §1.1.1 for integer canonicalization)
```

### Patch 3: Canonical Label Exact-Match Rule (G4-LABELMATCH) — BLOCKING/Loss

**Location**: §1.1.2 L1039 (modify fallback algorithm step 4)

```markdown
ADD after step 3:
3a) For canonical `s4:` labels, if primary candidate set size != 1:
    set `RiskState::Degraded`, block OPEN, and require REST reconcile.
    Do NOT proceed to legacy fallback.
    Legacy/repair fallback (steps 4-7) MUST be used ONLY for
    explicitly non-canonical labels (no `s4:` prefix).
```

### Patch 4: Instrument-Kind Production Wiring (G1-IKIND) — BLOCKING/Loss

**Location**: §1.0 (extend instrument metadata requirements)

```markdown
ADD normative clause:
`InstrumentMeta` MUST expose `instrument_family` and `amount_semantics`.
`amount_semantics ∈ {Coin, Usd}` is the sole dispatch/sizing branch input.
Venue metadata derivation MUST use `derive_instrument_kind()` (or
equivalent normative function) in the production normalization and
dispatch path, not test-only helpers.
If any required field is missing, contradictory, or unrecognized, the
instrument MUST be rejected before cache insert and any dependent OPEN
intent MUST fail closed.
```

### Patch 5: OPEN Gate Normative Order (G8-CHOKEORDER) — BLOCKING/Loss

**Location**: New clause or §1.4 preamble

```markdown
ADD normative clause:
For every OPEN intent, the only permitted gate order is:
1. Dispatch authorization (TradingMode check)
2. Preflight (instrument metadata, sizing validation)
3. Quantize (canonical rounding)
4. DispatchConsistency (contracts/amount match)
5. FeeCacheCheck (fee freshness)
6. ExpiryGuard (instrument lifecycle)
7. LiquidityGate (L2 book impact)
8. NetEdgeGate (fees + slippage)
9. Pricer (limit price computation)
10. RecordedBeforeDispatch (WAL)

If any gate rejects, evaluation MUST stop; no outbound side effect.
`expected_slippage_usd` used by Net Edge MUST come from the same
Liquidity evaluation that authorized the OPEN intent.
Pricer MUST NOT make an independent profitability eligibility decision.
```

### Patch 6: WAL Recovered-Unsent OPEN Rule (G7-RESTART) — BLOCKING/Loss

**Location**: §2.4 / AT-935

```markdown
REPLACE AT-935 THEN/PASS RULE:
If an OPEN intent reaches `WALRecorded` but has no evidence of any send
attempt, restart reconciliation MUST NOT auto-dispatch that intent.
The record MUST remain available for audit and dedupe only.
A dispatch after restart is permitted ONLY IF a fresh post-restart
strategy evaluation re-authorizes the OPEN and all OPEN gates pass.
This rule MUST NOT block `reduce_only == true` risk-reducing intents.
```

### Patch 7: Startup Latch Causality + ACK Recovery (G10-STARTUPLATCH) — BLOCKING/Loss

**Location**: §2.2.4 (extend CP-001 startup rules)

```markdown
ADD normative clause:
After WAL replay and before any OPEN-capable dispatch path is reachable,
the runtime MUST set `open_permission_blocked_latch = true` with reason
`RESTART_RECONCILE_REQUIRED`.
The latch MUST clear ONLY AFTER reconciliation of WAL intents, venue
open orders, venue trades, and venue positions succeeds.

ADD ACK recovery rule:
If reconciliation finds ACK evidence for an intent whose local `ack_ts`
is absent, the runtime MUST:
1. Record `ack_ts`
2. Advance TLSM to `Acked` or later
3. MUST NOT resend that intent
```

### Patch 8: Trade-ID Atomic Dedupe (G11-TRADEDEDUPE) — BLOCKING/Loss

**Location**: Trade-ID registry handler (new normative clause)

```markdown
REPLACE the Trade-ID registry handler rule:
On trade or fill event, duplicate suppression MUST apply only to
fully-applied trades.
The system MUST durably commit {trade_id, group_id, leg_idx, qty, price}
and the corresponding TLSM, position, and attribution updates in one
atomic unit.
If atomic commit is unavailable, the system MUST durably record the trade
with `apply_pending = true`, enter `RiskState::Degraded`, and
reconciliation MUST complete the missing updates before any later event
for that `trade_id` may NOOP as a duplicate.
```

### Patch 9: Fee Cache CLOSE/HEDGE Carveout (G6-FEEPROOF) — HARDENING/Profit-block

**Location**: §4.2 / base_gates.rs Gate 5

```markdown
ADD normative clause:
Hard-stale fee cache MUST block OPEN intents only.
CLOSE/HEDGE/CANCEL intents MUST remain dispatchable when fee cache is
hard-stale, unless TradingMode is Kill.
```

### Patches 10-14: Session Emergency Close, CP-001 Bounds, Kill Corroboration, Hedge Partial Fill, Stale Position Guard

*(Unchanged from R1 — see Patches 1-5 in original report. Renumbered to 10-14.)*

**Patch 10** (G-2-006): Emergency close session independence — dedicated session or reconnection priority.
**Patch 11** (G-2-003/G-2-004): CP-001 max hold duration (300s) + per-instrument scope.
**Patch 12** (G-2-002): Kill corroboration timeout (5000ms) → ReduceOnly.
**Patch 13** (G-2-007): Hedge partial fill re-hedge with bounded retry.
**Patch 14** (G-1-010): Position staleness guard for Inventory Skew.

---

## E. PROOF REQUIREMENTS

### E.1 Phase 1 Proof Chain (15 ATs)

| AT | Clause | Implementation | Test Location | Proof Type | Status |
|----|--------|----------------|---------------|------------|--------|
| AT-216 | §1.1 Label | label.rs | label_tests.rs | Unit + Parse | PASS |
| AT-218 | §1.1 Idempotency | idempotency/hash.rs | test_idempotency.rs | Determinism | PASS |
| AT-219 | §1.1.1 Quantize | quantize.rs | quantize_tests.rs | Direction | PASS |
| AT-230 | §1.2 TLSM | tlsm.rs | tlsm_tests.rs:307 | State Machine | PASS |
| AT-277 | §1.0 Dispatch Map | dispatch_map.rs, order_size.rs | dispatch_map_tests.rs:347 | Round-trip | PASS |
| AT-333 | §1.0 Instrument Meta | — | test_instrument_kind_mapping.rs | No Hardcode | PASS |
| AT-343 | §1.1 Hash No Clock | idempotency/hash.rs:37 | test_idempotency.rs:95 | Field Absence | PASS |
| AT-905 | Repo Layout | — | — | Structure | PASS |
| AT-906 | §2.4 WAL Block OPEN | wal.rs | — | Fail-closed | PASS |
| AT-908 | §1.1.1 Quantize Min | quantize.rs:312 | quantize_tests.rs | Reject | PASS |
| AT-920 | §1.4 Dispatch Consistency | intent_assembly.rs:125 | dispatch_map_tests.rs:388+ | Mismatch Reject | PASS |
| AT-921 | §1.1.2 Label Prefix | label.rs | label_tests.rs:352 | Unknown Reject | PASS |
| AT-926 | §1.1.1 Meta Missing | quantize.rs:251 | — | Fail-closed | PASS |
| AT-928 | §1.1 Dedup NOOP | — | — | Idempotency | PASS |
| AT-1097 | §1.0 Mixed Sizing | order_size.rs | order_size_tests.rs | Reject | PASS |

### E.2 New Proof Requirements (from Cross-Audit)

| Clause | Required enforcement point | Required proving test | Missing today? |
|--------|---------------------------|----------------------|----------------|
| Instrument-kind derivation (G1-IKIND) | `venue/types.rs` wired into production dispatch path | Same metadata → same `amount_semantics` → same dispatch amount | **Yes** (TODO on line 46) |
| Hash identity inputs (G2-HASH) | `idempotency/hash.rs` | Equivalent floats → identical integer steps → identical hash; different steps → different hash | **Yes** (contract text wrong) |
| Canonical label matching (G4-LABELMATCH) | `recovery/label_match.rs` | Canonical `s4` count != 1 → Degraded + OPEN blocked; no heuristic fallback on canonical | **Yes** |
| Liquidity exit carveout (G5-LIQEXIT) | `execution/gate.rs` | Stale L2 blocks OPEN not CLOSE/HEDGE; fallback price used | **Yes** (AT-421 wrong) |
| Fee cache carveout (G6-FEEPROOF) | `execution/base_gates.rs` Gate 5 | Hard-stale blocks OPEN only; CLOSE/HEDGE remain | **Yes** (no skip) |
| OPEN gate ordering (G8-CHOKEORDER) | `build_order_intent.rs` chokepoint | Exact contract order; Net Edge consumes slippage from same liquidity result | **Yes** |
| Recovered unsent OPEN (G7-RESTART) | Restart reconciler + dispatch gate | Crash after WAL, before send; replay dispatch count = 0; fresh eval may re-open | **Yes** |
| Startup latch causality (G10-STARTUPLATCH) | Bootstrap → runtime wiring | OPEN blocked until reconcile; ACK evidence suppresses resend | **Yes** |
| Trade-ID atomic dedupe (G11-TRADEDEDUPE) | Fill application pipeline | `trade_id` + crash before apply + restart → state converges exactly once | **Yes** |

### E.3 Phase 2+ Proof Requirements (unchanged from R1)

| AT/Requirement | What Must Be Proven | Proof Method |
|----------------|---------------------|--------------|
| AT-104 | Stale instrument metadata blocks OPEN via TradingMode | PolicyGuard integration test |
| AT-233 | Crash after send, before ACK → WAL restart reconcile | Crash injection + recovery |
| AT-234 | Crash after fill, before local update → WAL reconcile | Crash injection + recovery |
| AT-935 | RecordedBeforeDispatch + restart → dispatch exactly once | WAL lifecycle test |
| AT-1095 | Idempotency key deterministic across restarts/machines | Cross-process test |
| AT-1096 | WAL crash recovery (SIGKILL between stages) | Fault injection |
| Capital Supremacy | exposure != 0 always has legal risk-reducing path | Exhaustive state enumeration |
| Emergency Close | 3-try escalation with correct price fallback | Integration + fault test |
| PolicyGuard | 27-state axis resolver is deterministic | Table-driven exhaustive test |

---

## F. FINAL DECISION

### Verdict: `CONTRACT_NO_GO_BLOCKING_GAPS`

### Justification

1. **Phase 1 has 8 BLOCKING contract-text defects**: Unlike R1's assessment, Phase 1 is NOT clean. The contract itself contains specification bugs (G5-LIQEXIT blocks risk-reducing exits, G2-HASH uses float names for integer hash inputs, G4-LABELMATCH allows heuristic merge of canonical labels) and implementation wiring gaps (G1-IKIND derivation not in production path).
2. **The identity chain is internally inconsistent**: Hash → label → WAL → dedupe → reconcile must be a single consistent chain. Currently, the contract names float hash inputs while the code uses integers (G2-HASH), label matching falls through to heuristic on canonical labels (G4-LABELMATCH), WAL replay may auto-dispatch stale OPENs (G7-RESTART), and trade-ID dedup can suppress unapplied fills (G11-TRADEDEDUPE). Any one of these alone causes silent loss.
3. **Capital Supremacy is violated by two profitability gates**: The contract's stated invariant (exposure != 0 → legal risk-reducing path exists) is violated by §1.3 (stale L2 blocks CLOSE/HEDGE) and §4.2 via base_gates.rs (fee cache stale blocks CLOSE/HEDGE). These are contract-text bugs, not implementation bugs.

### Remediation Sequence (Priority Order)

**Tier 1: Capital-risk and stranded-exit paths (fix before ANY implementation continues)**
1. **Patch 1** (G5-LIQEXIT) — Liquidity Gate CLOSE/HEDGE carveout
2. **Patch 6** (G7-RESTART) — WAL recovered-unsent OPEN rule
3. **Patch 7** (G10-STARTUPLATCH) — Startup latch causality + ACK recovery

**Tier 2: Identity, replay, and dedup defects**
4. **Patch 2** (G2-HASH) — Hash identity integer canonicalization
5. **Patch 3** (G4-LABELMATCH) — Canonical label exact-match rule
6. **Patch 8** (G11-TRADEDEDUPE) — Trade-ID atomic dedupe

**Tier 3: Implementation wiring and gate ordering**
7. **Patch 4** (G1-IKIND) — Instrument-kind production wiring
8. **Patch 5** (G8-CHOKEORDER) — OPEN gate normative order
9. **Patch 9** (G6-FEEPROOF) — Fee cache CLOSE/HEDGE carveout

**Tier 4: Phase 2+ specification hardening**
10. **Patch 10** (G-2-006) — Session emergency close
11. **Patch 11** (G-2-003/G-2-004) — CP-001 latch bounds
12. **Patch 12** (G-2-002) — Kill corroboration timeout
13. **Patch 13** (G-2-007) — Hedge partial fill
14. **Patch 14** (G-1-010) — Stale position guard

**Tier 5: Remaining hardening (close while touchpoints are open)**
15. G3-S4SCHEMA, G12-LINKEDORDERS, G-1-001, G-1-005, G-1-012, G-1-014
16. G-X-001 through G-X-006

### Strong Proof Chains Already Present

These claims are reproducible against the current tree:

- **CSP.3.2** WAL degradation: `cargo test -p soldier_core test_close_intent_approved_despite_wal_failure` / `test_hedge_intent_approved_despite_wal_failure`
- **AT-233/AT-234** restart recovery: `cargo test -p soldier_infra test_at233_sent_intent_not_resent_on_durable_restart` / `test_at234_fill_detected_on_restart_updates_tlsm`
- **Structural chokepoint**: `cargo test -p soldier_core test_dispatch_chokepoint_no_bypass_approved` / `test_constraint_wal_is_last_gate_open`
- **Integer hash stability**: `cargo test -p soldier_core gi_020_intent_hash_is_deterministic`

### Summary Statistics
- **Total findings**: 33 (16 BLOCKING + 17 HARDENING)
- **Phase 1 BLOCKING**: 8 (all from cross-audit — R1 missed these)
- **Phase 2+ BLOCKING**: 8 (from R1)
- **Phase 1 HARDENING**: 8 (5 from R1 + 3 from cross-audit)
- **Phase 2+ HARDENING**: 6 (from R1)
- **Cross-cutting HARDENING**: 6 (from R1)
- **False positives from R1 agents**: 2 (corrected: RiskState::Kill exists, reduce_only set correctly)
- **Contract patches proposed**: 14 (9 Phase 1, 5 Phase 2+)

### Audit Provenance
- **R1**: Claude Opus 4.6 (6 parallel agents) — 2026-03-05 — found 8 BLOCKING + 14 HARDENING
- **Cross-audit**: Codex GPT-5 — 2026-03-05 — found 8 BLOCKING + 3 HARDENING that R1 missed
- **R2** (this document): Claude Opus 4.6 reconciliation — merged all findings, verified claims against code, upgraded verdict to NO_GO
