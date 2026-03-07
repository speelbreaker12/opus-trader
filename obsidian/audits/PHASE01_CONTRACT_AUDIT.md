# Red-Team Contract Loss-Risk Audit — Phase 0 & Phase 1 Scope

**Contract:** `specs/CONTRACT.md` v5.2 ("The Antifragile Standard")
**Audit scope:** Phase 0 (Operational Prerequisites) and Phase 1 (Foundation, Non-Deployable) only.
**Sections in scope:** Definitions, Phase 0, §0.0, §1.0–§1.4, §1.5, §2.1, §2.4, §3.1 (as referenced by Phase 1 gates), §7.0 (AT-1230 foundation status-lite), Appendix A (CSP defaults), Phase 1 AT Subset.
**Sections explicitly out of scope:** §2.2 PolicyGuard axis resolver (Phase 2), §2.2.4 Open Permission Latch (Phase 2), §2.3 Cortex (Phase 2), §3.2–§3.4 reconciliation (Phase 2), §4–§6 (Phase 3+), §8 release gates, Appendix CSP cross-map.
**Date:** 2026-03-06

---

## A) Audit Completeness Gate

`AUDIT_STATUS: COMPLETE`

---

## B) Inspection Coverage Matrix

| # | Area | Clauses reviewed | Attack lens used | Result | Loss path IDs | Profit-block IDs | No-finding rationale |
|---|---|---|---|---|---|---|---|
| 1 | Intent classification | Definitions (`reduce_only`, `CANCEL intent`, AT-201, AT-1055); §2.4 WAL migration note (line 3272); §1.4 OPEN chokepoint sequence | Ambiguity attack, Missing-protection attack | FINDINGS_FOUND | L-04 | NONE | — |
| 2 | OPEN vs CLOSE/HEDGE/CANCEL behavior | §1.3 LiquidityGate (CLOSE/HEDGE fallback to §3.1); Phase 1 profile note (line 4614); Phase 1 AT Subset (lines 4628–4643); CCL-2026-03-05-03 | Contradiction attack, Fail-closed attack | FINDINGS_FOUND | L-02 | P-02 | — |
| 3 | Dispatch authorization | §1.4 OPEN chokepoint sequence (line 1468); Phase 1 stub note AT-104 (line 774); Definitions TradingMode/RiskState | Ambiguity attack, Missing-protection attack | FINDINGS_FOUND | L-03 | NONE | — |
| 4 | TradingMode / PolicyGuard | §2.2.3 (out of Phase 1); Phase 1 stub note (line 774); Definitions TradingMode | Missing-protection attack | FINDINGS_FOUND | L-03 | NONE | — |
| 5 | Fail-closed behavior | §1.1.1 quantization fail-closed; §1.0 contracts/amount mismatch; §2.4 WAL enqueue failure (AT-906); §2.4.1 hot-loop backpressure (AT-925); §1.1.2 label schema fail-closed | Fail-closed attack | NO_CREDIBLE_FINDING | NONE | NONE | Phase 1 fail-closed rules are explicit: missing metadata → reject, WAL full → block OPEN, label invalid → reject + Degraded. Each has a matching AT in the Phase 1 subset. No ambiguity found. |
| 6 | Restart / replay / reconciliation | §2.4 (line 3229–3230 startup replay rule); Phase 1 AT Subset (AT-233/234/935 deferred); §1.2.1 GroupState WAL-replay qualifier (line 1124) | Missing-protection attack, Fail-closed attack | FINDINGS_FOUND | L-01 | NONE | — |
| 7 | Idempotency / duplicate prevention | §1.1.1 intent_hash (line 977); §1.1 Idempotency Rules (lines 1021–1025); AT-928 (Phase 1 required); AT-343 (Phase 1 required); §2.4 Trade-ID Idempotency Registry | Ambiguity attack | NO_CREDIBLE_FINDING | NONE | NONE | Local dedup via intent_hash in WAL is Phase 1 (AT-928). Remote dedup via label matching is Phase 1 (AT-218). Trade-ID registry is Phase 2 (requires WS reconnect). Hash inputs are deterministic and wall-clock-free (AT-343). No credible Phase 1 ambiguity. |
| 8 | Emergency containment | §1.2 Atomic Group Executor (containment Step A/B); §3.1 Deterministic Emergency Close (referenced by §1.2 and §1.3); Phase 1 deliverables (line 4616–4620) | Missing-protection attack, Complexity attack | FINDINGS_FOUND | NONE | P-03 | — |
| 9 | Risk reduction priority | §2.2.5 Cancel/Replace Permission Rules; §3.2 Smart Watchdog; Phase 1 scope | Missing-protection attack | NO_CREDIBLE_FINDING | NONE | NONE | Cancel/replace rules and watchdog are Phase 2 infrastructure. Phase 1 is explicitly non-deployable (line 4622) and has no dispatch, so no runtime risk-reduction priority decisions occur. No Phase 1 AT addresses this area. The absence is consistent with the phase boundary. |
| 10 | Kill / reduce-only semantics | §2.2.3.6 Kill Mode Semantics; §2.2.3.4 dispatch authorization; Phase 1 scope | Missing-protection attack | NO_CREDIBLE_FINDING | NONE | NONE | Kill and ReduceOnly enforcement require PolicyGuard (Phase 2). Phase 1 is non-deployable. The Phase 1 stub note (AT-104) only requires RiskState::Degraded to block OPENs as a precondition. No Phase 1 code can enter Kill mode. Absence is phase-appropriate. |
| 11 | Stale data / stale state | §1.0.X Instrument Metadata Freshness (AT-104 deferred, AT-333 Phase 1); §1.3 `l2_book_snapshot_max_age_ms`; §2.4 WAL freshness; Appendix A `instrument_cache_ttl_s` default | Ambiguity attack, Profit-suppression attack | FINDINGS_FOUND | NONE | P-04 | — |
| 12 | Gate ordering | §1.4 OPEN chokepoint sequence (line 1468); §1.4.1 Net Edge Gate hard rule (line 1486); §1.4.2 Inventory Skew re-check (line 1539); Phase 1 deliverables | Ambiguity attack, Complexity attack | FINDINGS_FOUND | L-05 | NONE | — |
| 13 | Reject semantics | §2.2.6 RejectReasonCode Registry (lines 2915–2957); AT-930; Phase 1 rejection codes (TooSmallAfterQuantization, InstrumentMetadataMissing, ContractsAmountMismatch, LabelTooLong) | Ambiguity attack | NO_CREDIBLE_FINDING | NONE | NONE | The registry is normatively complete and maintained by a completeness rule (line 2924). Phase 1 rejection codes are well-defined with matching ATs. No ambiguity. |
| 14 | Observability requirements | §7.0 AT-1230 (foundation status-lite); Phase 0 P0-E; AT-P0E-NEG; Status authority matrix (lines 159–170) | Profit-suppression attack, Ambiguity attack | FINDINGS_FOUND | NONE | P-01 | — |
| 15 | Configuration defaults | Appendix A.CSP (AT-341, AT-424); `instrument_cache_ttl_s=3600`; `contracts_amount_match_tolerance=0.001`; `atomic_qty_epsilon=1e-9` | Fail-closed attack | NO_CREDIBLE_FINDING | NONE | NONE | Appendix A enforcement rule (line 5385) is clear: missing safety-critical config → use Appendix A default if defined, else fail-closed. Phase 1 parameters have documented defaults. AT-341 and AT-424 enforce this. |
| 16 | Precedence rules | Status authority precedence (lines 167–170); §0.0 Normative Scope; Phase 0 P0-E clarifications (lines 148–151) | Ambiguity attack | FINDINGS_FOUND | L-06 | NONE | — |
| 17 | Definitions and units | Definitions `amount_semantics` (line 85–88); `instrument_kind` (line 83–84); `qty_steps`/`price_ticks` (§1.1.1); OrderSize struct (lines 888–896) | Ambiguity attack | NO_CREDIBLE_FINDING | NONE | NONE | The `amount_semantics` discriminator is explicit (line 88): authoritative for sizing/quantization/outbound only. `instrument_kind` retains authority for non-sizing rules. The split is clean and AT-277 Phase 1 exercises both paths. |
| 18 | Acceptance tests inside the contract | Phase 1 AT Subset (lines 4624–4649); Phase 0 AT-P0E-NEG, AT-1230, AT-022 | Missing-protection attack, Contradiction attack | FINDINGS_FOUND | L-02 | P-05 | — |

---

## C) Executive Verdict

**`CONTRACT_CLEAR_WITH_HARDENING`**

**Core bottleneck:** Phase 1 scope boundaries are ambiguous in two critical spots: (1) the Liquidity Gate is listed as a Phase 1 deliverable in the profile note but omitted from the deliverable bullets and the Phase 1 AT Subset; (2) the §3.1 fallback price ladder is referenced by Phase 1 gates (§1.3, §1.1.1 note) but is a Phase 2 implementation. These create circular dependencies and implementation ambiguity.

**Top 3 ways this contract could cause loss (Phase 0/1 scope):**

1. **L-01 — Restart without reconciliation (Phase 1 WAL orphan state).** Phase 1 builds RecordedBeforeDispatch WAL infrastructure but defers restart reconciliation ATs (AT-233/234/935) to Phase 2. A crash-after-WALRecorded scenario has no Phase 1 acceptance test enforcing the "MUST NOT authorize fresh OPEN dispatch" rule. An implementation could silently re-dispatch.

2. **L-02 — Liquidity Gate scope contradiction.** The profile note says Liquidity Gate is Phase 1; the deliverable list and AT subset say it is not. If built in Phase 1, its CLOSE/HEDGE stale-L2 path requires §3.1 which doesn't exist yet. If not built, the profile note is wrong and downstream Phase 2 planning is misinformed.

3. **L-03 — Phase 1 stub has no contract-bound dispatch-auth mechanism.** The Phase 1 stub note for AT-104 says `RiskState::Degraded` alone blocks OPENs, but the only normative dispatch-authorization mechanism is PolicyGuard (Phase 2). Two Phase 1 implementations could legitimately differ on how (or whether) RiskState gates dispatch.

**Top 3 ways this contract could block valid profit (Phase 0/1 scope):**

1. **P-01 — Foundation mode exit criteria undefined.** `dispatch_enabled: false` is permanent in foundation status-lite. The contract specifies no transition predicate from foundation → CSP minimum `/status`. Integration testing with downstream systems that rely on CSP keys is blocked.

2. **P-02 — Conservative quantization rounding for CLOSE/HEDGE with no Phase 1 compensation.** BUY rounds price DOWN, SELL rounds UP unconditionally. The contract note says `close_buffer_ticks` in §3.1 compensates, but §3.1 is Phase 2. Phase 1 tests that exercise CLOSE/HEDGE paths get systematically worse fill prices.

3. **P-05 — Phase 1 AT subset omits Liquidity Gate non-trip test.** Even if Liquidity Gate is Phase 1, AT-1216 (the NON-TRIP test proving valid OPENs pass the gate) is absent from the subset. Without it, a too-aggressive implementation could reject all OPENs and pass all listed Phase 1 ATs.

**Top 3 simpler-safer alternatives:** See Section F below.

---

## D) Loss-Path Table

| ID | Area | Clause / Topic | How this could cause loss | Why the contract allows it | Severity | Exact clause(s) | Safer rewrite direction |
|---|---|---|---|---|---|---|---|
| L-01 | Restart / replay / reconciliation | Phase 1 WAL orphan state after crash | Phase 1 builds WAL with RecordedBeforeDispatch but defers AT-233/234/935 to Phase 2. A crash between WALRecorded and network send leaves an orphan record. On Phase 1 restart, no AT enforces the "MUST NOT authorize fresh OPEN dispatch" rule (§2.4 line 3230), so an implementation could re-dispatch the recorded intent. | §2.4 line 3230 states the normative rule ("MUST NOT... authorize a fresh OPEN dispatch after restart") but Phase 1 AT Subset has no AT exercising restart after WALRecorded-but-unsent. The rule exists in prose but is untested. | BLOCKING | §2.4 line 3230; Phase 1 AT Subset (lines 4628–4643); AT-935 (deferred, line 4649) | Add a Phase 1 AT requiring: on restart, if WAL contains a recorded-but-unsent OPEN, dispatch count MUST remain 0 until a fresh evaluation (stub or manual) re-authorizes. Simpler than full AT-935 but closes the gap. |
| L-02 | OPEN vs CLOSE/HEDGE/CANCEL; Acceptance tests | Liquidity Gate scope contradiction | Phase 1 profile note (line 4614) lists "Liquidity Gate" as a deliverable. Phase 1 bullet list (lines 4616–4620) and Phase 1 AT Subset (lines 4628–4643) do not. If Liquidity Gate is built in Phase 1, §1.3's CLOSE/HEDGE fallback requires §3.1 (Phase 2), creating an impossible dependency. If not built, the profile note misinforms implementation planning. | The profile note parenthetical and the deliverable bullet list contradict. The AT Subset is silent on Liquidity Gate ATs (AT-222/344/909/421/1216 absent). | BLOCKING | Phase 1 profile note (line 4614); Phase 1 deliverables (lines 4616–4620); Phase 1 AT Subset (lines 4628–4643); §1.3 (line 1378 "MUST use the deterministic §3.1 fallback price ladder") | Either (a) add Liquidity Gate to the Phase 1 deliverable bullet list and add AT-909 + AT-1216 to the Phase 1 AT Subset (with a Phase 1 stub for the §3.1 fallback: "reject CLOSE/HEDGE with `Rejected(LiquidityGateNoL2)` in Phase 1; §3.1 fallback deferred to Phase 2"), or (b) remove "Liquidity Gate" from the profile note parenthetical and clarify it is Phase 2. |
| L-03 | Dispatch authorization; TradingMode / PolicyGuard | Phase 1 stub dispatch-auth mechanism undefined | §1.0.X Phase 1 stub note (line 774) says "OPEN intents are blocked by `RiskState::Degraded` alone (without requiring the full PolicyGuard TradingMode axis resolver)." But the contract never specifies HOW `RiskState::Degraded` blocks OPENs in the Phase 1 dispatch path. The only normative dispatch-authorization is §2.2.3.4 (PolicyGuard, Phase 2). | The stub note uses "MAY" language and leaves the enforcement mechanism unspecified. Two implementations could differ: one checks RiskState in the dispatch path, another does not. | HARDENING | §1.0.X Phase 1 stub note (line 774); §2.2.3.4 (Phase 2 dispatch authorization) | Add a Phase 1-scoped normative rule: "In Phase 1 (before PolicyGuard is implemented), any dispatch path MUST check `RiskState != Degraded` before OPEN dispatch. This check MUST be replaced by the full PolicyGuard dispatch authorization in Phase 2." |
| L-04 | Intent classification | WAL `reduce_only` field written but not exercised in Phase 1 | §2.4 mandates `reduce_only: bool` in the WAL minimum record (line 3268). The migration note (line 3272) says missing `reduce_only` defaults to `false` (OPEN). But AT-1231 (Phase 2) is the only AT verifying correct `reduce_only` persistence and recovery. Phase 1 writes WAL records but has no AT confirming `reduce_only` is correctly populated, creating a risk that Phase 1 always writes `false` and Phase 2 inherits wrong classifications. | AT-1231 is deferred to Phase 2. No Phase 1 AT in the subset verifies `reduce_only` field content in WAL records. | HARDENING | §2.4 WAL minimum record (line 3268); Migration note (line 3272); AT-1231 (Phase 2, line 3318) | Add a Phase 1 AT: "Given an OPEN intent and a CLOSE/HEDGE intent are WAL-recorded, when WAL records are read back, then the OPEN record has `reduce_only == false` and the CLOSE/HEDGE record has `reduce_only == true`." |
| L-05 | Gate ordering | OPEN chokepoint sequence includes Phase 2 gates without phase annotation | §1.4 line 1468 defines the normative OPEN chokepoint: `DispatchAuth -> Preflight -> Quantize -> DispatchConsistency -> FeeCache/Policy -> Expiry -> Liquidity -> NetEdge -> InventorySkew -> ... -> Pricer -> RecordedBeforeDispatch -> dispatch`. This sequence includes DispatchAuth (Phase 2), FeeCache/Policy (Phase 2), Liquidity (scope ambiguous), NetEdge (Phase 2), InventorySkew (Phase 2), and Pricer (Phase 2). The contract doesn't define a Phase 1 subset of the chokepoint. | The normative chokepoint is monolithic. No phase annotation or subset definition exists. A Phase 1 implementation must guess which gates to stub/skip. | HARDENING | §1.4 OPEN chokepoint sequence (line 1468) | Add a Phase 1 chokepoint subset annotation: "Phase 1 OPEN path: `Quantize -> DispatchConsistency -> RecordedBeforeDispatch -> dispatch`. All other gates are Phase 2 stubs that MUST pass-through in Phase 1." |
| L-06 | Precedence rules | Foundation → CSP status transition lacks a testable predicate | Status authority precedence (lines 167–170) says "After foundation mode exits, `/api/v1/status` MUST satisfy the §7.0 CSP minimum schema." But the contract never defines when foundation mode exits. The transition from `phase == foundation` to CSP minimum is a critical safety boundary (it enables dispatch authority), and it has no AT or predicate. | The contract defines the two states (foundation status-lite, CSP minimum) and their schemas but not the transition trigger. | HARDENING | Status authority precedence (lines 167–170); AT-1230 (foundation mode); AT-023 (CSP minimum) | Add a normative transition predicate: "Foundation mode MUST exit only when: (a) all Phase 1 ATs pass, (b) PolicyGuard is operational, and (c) startup reconciliation has succeeded. The transition MUST be atomic: either the full CSP minimum schema is served or foundation status-lite continues." |

---

## E) Profit-Block Table

| ID | Area | Clause / Topic | How this could block valid profit | Why the contract allows it | Severity | Exact clause(s) | Safer rewrite direction |
|---|---|---|---|---|---|---|---|
| P-01 | Observability requirements | Foundation mode `dispatch_enabled: false` permanent in Phase 1 | Foundation status-lite (AT-1230) requires `dispatch_enabled == false` and `phase == foundation`. Phase 1 is non-deployable by design. But the contract provides no transition criteria for exiting foundation mode. Any downstream tooling, CI gate, or integration test that reads `/status` will see "not ready" indefinitely, blocking integration testing of dispatch-path code even in paper/testnet modes. | Phase 1 is explicitly non-deployable (line 4622). The contract defines foundation-mode exit ("After foundation mode exits...") but never defines the predicate. | HARDENING | AT-1230 (lines 4730–4735); Status authority precedence (lines 167–170); Phase 1 rule (line 4622) | Define a testable exit predicate (see L-06 safer rewrite). Alternatively, allow a `phase == foundation_dispatch_test` mode for paper/testnet that permits `dispatch_enabled: true` without claiming CSP compliance. |
| P-02 | OPEN vs CLOSE/HEDGE/CANCEL behavior | Quantization rounding suppresses CLOSE/HEDGE fills with no Phase 1 compensation | §1.1.1 rounds BUY limit price DOWN, SELL limit price UP (line 974). The note (line 983) says `close_buffer_ticks` in §3.1 compensates, but §3.1 is Phase 2. A Phase 1 CLOSE/HEDGE intent gets a limit price that is systematically worse than mid, reducing fill probability for risk-reducing orders. In thin books, this could mean a containment close doesn't fill. | The rounding rule is unconditional (no phase gate). The compensation mechanism is Phase 2. | HARDENING | §1.1.1 rounding rules (lines 973–983); §3.1 `close_buffer_ticks` (line 3388) | Add to the Phase 1 stub note: "For Phase 1 tests exercising CLOSE/HEDGE paths, an implementation MAY apply a temporary `close_buffer_ticks` offset. The full §3.1 buffer mechanism supersedes this in Phase 2." |
| P-03 | Emergency containment | Liquidity Gate 10 bps default applies to rescue IOC, forcing premature escalation | §1.3 scope (line 1392): "Applies to normal dispatch and containment rescue IOC orders." Default `max_slippage_bps = 10` (Appendix A). In the atomicity-break scenario that triggers rescue IOC, spreads are typically wider than normal. A 10 bps gate on rescue orders will reject them, forcing escalation to §3.1 emergency close (which bypasses the gate). The rescue path exists to avoid emergency close overhead; the tight default defeats it. | The 10 bps default is in Appendix A with no rescue-specific override. The scope statement explicitly includes rescue IOC. | HARDENING | §1.3 scope (line 1392); Appendix A `max_slippage_bps` | Add a separate `rescue_max_slippage_bps` parameter (default: 30 bps) to Appendix A, and amend §1.3 scope: "For containment rescue IOC (§1.2 Step A), use `rescue_max_slippage_bps` instead of `max_slippage_bps`." |
| P-04 | Stale data / stale state | `instrument_cache_ttl_s = 3600` default may be too aggressive for Phase 1 testing | Appendix A sets `instrument_cache_ttl_s = 3600` (1 hour). In a Phase 1 test or paper-trading environment, metadata fetches may not run on a live cadence. If the test harness doesn't mock freshness, every test that takes >1 hour from metadata fetch will trip Degraded and block OPENs. This is correct behavior for production but creates friction in Phase 1 development. | The default is production-calibrated. Phase 1 tests must either mock freshness or run within 1 hour of a fetch. The contract does not acknowledge this Phase 1 testing implication. | HARDENING | Appendix A `instrument_cache_ttl_s` default (line 5449); AT-104 Phase 1 stub note (line 774) | No contract change needed; add a Phase 1 testing note: "Phase 1 test harnesses SHOULD inject a mock `instrument_cache_age_s` to avoid false Degraded triggers from ambient staleness." |
| P-05 | Acceptance tests | Phase 1 AT subset missing Liquidity Gate non-trip test | Even if Liquidity Gate is Phase 1 (per profile note), AT-1216 (non-trip: valid OPEN passes gate) is absent from the Phase 1 AT Subset. Only trip/reject ATs exist. A Phase 1 implementation could reject ALL intents at the Liquidity Gate and pass all listed ATs. | The Phase 1 AT Subset (lines 4628–4643) is explicitly listed and does not include AT-1216. The contract's Acceptance Test Isolation Requirements (line 62) mandate paired TRIP/NON-TRIP ATs for any new guard, but this enforcement is structural, not phase-gated. | HARDENING | Phase 1 AT Subset (lines 4628–4643); Acceptance Test Isolation Requirements (lines 62–80); AT-1216 (line 1426) | If Liquidity Gate is Phase 1, add AT-1216 to the Phase 1 AT Subset. |

---

## F) Simpler-Safer Alternatives

| ID | Area | Clause / Topic | Why current design is riskier or too complex | Simpler/safer contract shape | Why better |
|---|---|---|---|---|---|
| S-01 | Restart / replay / reconciliation; Acceptance tests | Phase 1 WAL restart gap | Phase 1 builds full RecordedBeforeDispatch WAL but defers ALL restart ATs. This creates a system that records intents to a durable log but has no tested restart behavior — a state that is riskier than having no WAL at all, because the WAL's existence invites replay. | Add one Phase 1 restart AT: "On restart, WAL-recorded-but-unsent OPENs MUST NOT dispatch. Dispatch count == 0." This is a strict subset of AT-935 that requires no reconciliation infrastructure. | Closes the most dangerous loss path (accidental re-dispatch) with a single, simple test. No Phase 2 dependency. |
| S-02 | OPEN vs CLOSE/HEDGE/CANCEL; Gate ordering | Liquidity Gate Phase 1 scope ambiguity | The profile note, deliverable bullets, and AT subset disagree on whether Liquidity Gate is Phase 1. Resolving this requires either adding missing ATs + a §3.1 stub, or removing the gate from Phase 1 — both are multi-file changes. | Remove "Liquidity Gate" from the Phase 1 profile note parenthetical. Add it explicitly to Phase 2 deliverables alongside §3.1. Phase 1's OPEN chokepoint becomes: `Quantize → RecordedBeforeDispatch → dispatch`. | Eliminates the circular dependency (§1.3 → §3.1 → Phase 2). Simplifies Phase 1 scope to exactly what the AT subset tests. No safety regression because Phase 1 is non-deployable. |
| S-03 | Dispatch authorization; TradingMode / PolicyGuard | Phase 1 dispatch-auth ambiguity | The Phase 1 stub note says `RiskState::Degraded` "alone" can block OPENs, but the mechanism is unspecified. This leaves two implementations: one that checks RiskState before dispatch (safe) and one that does not (unsafe). | Define a simple Phase 1 dispatch guard: `fn phase1_dispatch_authorized(risk_state: RiskState) -> bool { risk_state != Degraded }`. This runs at the `DispatchAuth` position in the chokepoint. Add one AT proving it works. Replace with PolicyGuard in Phase 2. | Removes ambiguity. One function, one check, one test. PolicyGuard replaces it cleanly in Phase 2 because the check position (DispatchAuth) is already defined in the chokepoint sequence. |

---

## G) Exact Patch Proposals (BLOCKING findings only)

### Patch for L-01 (Phase 1 WAL restart — no dispatch of orphan intents)

**Location:** Phase 1 AT Subset (after line 4643)

```
- AT-935-P1 (Phase 1 subset of AT-935; WAL-recorded-but-unsent OPEN MUST NOT dispatch on restart)
```

**Location:** New AT definition (after AT-935, near line 3296)

```
AT-935-P1 (Phase 1 stub for AT-935)
Profile: CSP
- Given: an OPEN intent reaches `WALRecorded` but no network send occurs (`sent_ts` is absent),
  then the process restarts.
- When: the system replays the WAL on startup.
- Then: dispatch count for the WAL-recorded-but-unsent OPEN MUST remain 0.
  The WAL record MUST be preserved for audit/dedup purposes but MUST NOT
  trigger a network dispatch.
- Pass criteria: dispatch count == 0 after restart; WAL record intact.
- Fail criteria: any OPEN dispatch occurs from WAL replay alone.
- Note: This is a Phase 1 subset of AT-935. The full AT-935 (including reconciliation
  and double-restart scenarios) MUST pass before Phase 2 completion.
```

### Patch for L-02 (Liquidity Gate scope contradiction)

**Option A (recommended): Remove from Phase 1.**

**Location:** Phase 1 profile note (line 4614)

Replace:
```
Phase 1 deliverables (TLSM, `s4:` labeling schema, WAL/durable ledger, Liquidity Gate)
```
With:
```
Phase 1 deliverables (TLSM, `s4:` labeling schema, WAL/durable ledger)
```

**Location:** Phase 2 deliverables (near line 4651), add:
```
* Pre-Trade Liquidity Gate (§1.3) including §3.1 fallback price ladder for CLOSE/HEDGE under stale L2.
```

**Option B (alternative): Add to Phase 1 with stub.**

**Location:** Phase 1 deliverable bullet list (after line 4620), add:
```
* Pre-Trade Liquidity Gate (§1.3) — Phase 1 stub: OPEN rejected if L2 missing/stale;
  CLOSE/HEDGE/CANCEL pass-through (§3.1 fallback deferred to Phase 2).
```

**Location:** Phase 1 AT Subset (after line 4643), add:
```
- AT-909 (OPEN rejected with `Rejected(LiquidityGateNoL2)` when L2 missing/stale)
- AT-1216 (valid OPEN passes Liquidity Gate when L2 fresh and slippage in budget)
```

---

## H) Coverage Summary

| Metric | Value |
|---|---|
| Total inspection areas required | 18 |
| Total inspection areas completed | 18 |
| Areas with findings | 11 |
| Areas with no credible finding | 7 |
| Loss paths found | 6 |
| Profit-block paths found | 5 |
| BLOCKING findings count | 2 |
| HARDENING findings count | 9 |

---

## I) Final Decision

**NO-GO** — Two BLOCKING gaps must be resolved before Phase 1 can be considered contract-complete.

**Smallest-first remediation order:**

1. **L-02 (Liquidity Gate scope contradiction):** One-line edit to the profile note parenthetical (Option A). Resolves the contradiction and eliminates the §3.1 circular dependency. ~30 seconds.

2. **L-01 (Phase 1 restart AT):** Add AT-935-P1 to the Phase 1 AT Subset. Write the AT definition (template provided above). ~5 minutes.

3. **L-03 (Phase 1 dispatch-auth stub):** Add a normative Phase 1 dispatch guard definition and one AT. ~10 minutes.

4. **L-06 (Foundation mode exit predicate):** Add transition criteria to status authority precedence. ~10 minutes.

5. **L-04 (WAL `reduce_only` Phase 1 AT):** Add a simple WAL field-correctness AT to Phase 1 subset. ~5 minutes.

6. **L-05 (Phase 1 chokepoint subset):** Annotate §1.4 chokepoint with phase tags. ~5 minutes.

7. **P-01 through P-05:** Hardening items; address after BLOCKING items are resolved.
