---
provenance:
  tool: codex
  model: GPT-5
  artifact_type: contract_audit
  audit_lens: loss-risk, fail-closed, profit-preservation
scope: phase-1 contract and proving artifacts
date: 2026-03-05
---

# Phase 1 Contract Loss-Risk Audit

**Verdict:** `CONTRACT_NO_GO_BLOCKING_GAPS`

**Scope:** `plans/prd.json` items where `phase == 1`, with focus on order creation/dispatch, opening or widening risk, reducing or closing risk, reconciliation, stale-state decisions, retries/replay/restart, duplicate actions, reject/degrade/latch behavior, kill/reduce-only/safety transitions, and observability for reject/degrade paths.

**Inputs reviewed**

1. `specs/CONTRACT.md`
2. `specs/DESIGN_PATTERNS.md` Section 0
3. `plans/prd.json` Phase 1 items
4. Phase 1 premortems present under `reviews/premortems/`
5. `SKILLS/slice-execute.md` (used because `slice-execute.md` was not present at repo root)
6. `plans/prompts/slice_reconcile_r1_audit.md` (used because `slice_reconcile_r1_audit.md` was not present at repo root)
7. Relevant code and tests in `crates/soldier_core` and `crates/soldier_infra`

**Input gaps**

- No single `reviews/premortems/<STORY-ID>_premortem.md` path was supplied for the whole audit; I used the Phase 1 premortems that exist.
- No dedicated premortems were present for the Phase 1 restart/replay stories under `S4-*` or the structural proof stories under `S6-*`.

## A) Executive verdict

`CONTRACT_NO_GO_BLOCKING_GAPS`

Core bottleneck: Phase 1 does not consistently preserve a deterministic risk-reducing path under degraded data and restart/replay conditions, and its identity model is internally inconsistent across sizing, hashing, labeling, and reconciliation.

Top 3 blocking risks

- Missing/stale L2 can reject `CLOSE/HEDGE`, stranding valid risk reduction.
- Canonical `s4` reconciliation can fall back to weaker heuristics and misattribute orders or fills.
- `WALRecorded` but unsent OPEN intents can be auto-dispatched after restart without fresh authorization, and the proof chain for restart latch and ACK recovery is incomplete.

Top 3 silent profit-block risks

- Liquidity gate rejects valid profitable closes when L2 is degraded.
- Hash identity still names `qty_q/limit_price_q` while code hashes integer steps/ticks, enabling false dedupe or false non-dedupe.
- Instrument-kind derivation is underspecified enough to cause false rejects or wrong dispatch-amount selection.

Top 3 simpler-safer contract improvements

- Make `amount_semantics` first-class and branch sizing/dispatch only on it.
- Require exact full-identity match for canonical `s4` labels; allow fallback only for explicitly legacy labels.
- Treat recorded-but-unsent OPEN intents as audit state only after restart unless a fresh post-restart decision re-authorizes them.

## B) Clause audit table

| Clause / Topic | Loss prevention | Profit preservation | Best design choice | Better alternative | Failure-path correctness | Fail-closed enforcement | Proof, not belief | Verdict | Gap ID |
|---|---|---|---|---|---|---|---|---|---|
| Section 1.0 canonical sizing and contracts/amount mismatch | YES | YES | YES | YES | YES | YES | YES | OK | - |
| Instrument-kind derivation plus metadata freshness | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G1-IKIND |
| Section 1.1.1 quantization plus intent-hash inputs | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G2-HASH |
| Canonical `s4` schema validation | YES | YES | YES | YES | YES | YES | NO | HARDENING | G3-S4SCHEMA |
| Section 1.1.2 label parse and disambiguation | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G4-LABELMATCH |
| Section 1.3 Liquidity Gate | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G5-LIQEXIT |
| Sections 1.4 and 1.4.1 OPEN chokepoint order and profitability authority | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G8-CHOKEORDER |
| Section 4.2 fee cache staleness | YES | YES | UNKNOWN | NO | YES | YES | NO | HARDENING | G6-FEEPROOF |
| Sections 2.4 and 2.4.1 WAL queue fail-closed semantics | YES | YES | YES | YES | YES | YES | YES | OK | - |
| `AT-935` recovered-unsent OPEN restart rule | NO | NO | NO | NO | NO | NO | NO | BLOCKING | G7-RESTART |
| Section 2.2.4 startup latch and ACK recovery | NO | UNKNOWN | NO | NO | NO | NO | NO | BLOCKING | G10-STARTUPLATCH |
| Trade-ID idempotency registry fill dedupe | NO | UNKNOWN | NO | NO | NO | NO | NO | BLOCKING | G11-TRADEDEDUPE |
| Phase 1 linked-order gate shape | YES | YES | NO | NO | YES | YES | YES | HARDENING | G12-LINKEDORDERS |

## C) Missing protections

| Missing protection | Why it matters | Loss risk | Profit-block risk | Proposed contract addition | Gap ID |
|---|---|---|---|---|---|
| Risk-reducing close and hedge path when L2 is missing or stale | Current text can forbid all non-emergency exits | High | High | Missing or stale L2 blocks OPEN only; risk-reducing intents use the Section 3.1 fallback ladder | G5-LIQEXIT |
| Integer-only hash identity | Float-like hash inputs permit divergent identities across codepaths | High | High | Hash only `qty_steps` and `price_ticks`; never hash `qty_q` or `limit_price_q` directly | G2-HASH |
| Exact canonical `s4` identity rule | Heuristic fallback can merge distinct intents | High | Medium | Canonical `s4` labels must exact-match `{sid8,gid12,leg_idx,ih16}` or fail closed | G4-LABELMATCH |
| Normative instrument-kind derivation inputs | Two reasonable implementations can classify the same instrument differently | High | Medium | Define required venue fields and fail closed on missing or contradictory metadata | G1-IKIND |
| Explicit fee-staleness carveout for risk reduction | Current safety relies on inference while one enforcement path blocks at `FeeCacheCheck` | Medium | High | Hard-stale fee cache blocks OPEN only; `CLOSE/HEDGE/CANCEL` remain legal unless `Kill` applies | G6-FEEPROOF |
| Recovered-unsent OPEN rule | Replay alone can create stale OPEN exposure or suppress valid re-entry depending on implementation choice | High | High | Replayed unsent OPENs MUST NOT dispatch from WAL alone; only fresh post-restart regeneration may open risk | G7-RESTART |
| Enforced startup latch before any OPEN-capable dispatch path | Reconcile-before-dispatch is not causal without runtime gating | High | Medium | Runtime starts with `RESTART_RECONCILE_REQUIRED`; latch clears only after successful reconcile | G10-STARTUPLATCH |
| ACK-lost recovery rule | Exact-once is unprovable without it | High | Medium | Reconcile-found ACK evidence MUST set `ack_ts`, advance TLSM, and suppress resend | G10-STARTUPLATCH |
| Atomic or recoverable fill application around `trade_id` dedupe | Duplicate suppression can hide a real fill after crash-mid-apply | High | Medium | Duplicate suppression MUST depend on fully applied state, not only `trade_id` presence | G11-TRADEDEDUPE |
| Normative OPEN gate order and slippage authority | Two reasonable implementations can differ on whether profitability uses real or proxy slippage | High | Medium | Contract MUST bind one OPEN gate order and require Net Edge to consume slippage from the same liquidity evaluation | G8-CHOKEORDER |

## D) Exact contract patch proposals

### G1-IKIND

```text
NEW CLAUSE:
`InstrumentMeta` MUST expose `instrument_family` and `amount_semantics`.
`amount_semantics ∈ {coin_sized, usd_sized}` is the sole dispatch/sizing branch input.
Derivation from venue metadata MUST use explicit fields required by this contract.
If any required field is missing, contradictory, or unrecognized, the instrument MUST be rejected before cache insert and any dependent OPEN intent MUST fail closed.
```

### G2-HASH

```text
REPLACE Section 1.1.1 hash rule WITH:
`intent_hash` MUST be computed only from `instrument`, `side`, `qty_steps`, `price_ticks`, `group_id`, and `leg_idx`.
`qty_q` and `limit_price_q` MAY be emitted for observability, but MUST NOT be hashed directly.
```

### G4-LABELMATCH

```text
NEW CLAUSE:
For a parsed canonical `s4:` label, match candidate count MUST be exactly 1 on full identity `{sid8, gid12, leg_idx, ih16}`.
If full-identity match count is not exactly 1, the system MUST set `RiskState::Degraded`, block OPEN, and require REST reconcile.
Legacy fallback matching by weaker fields MAY be used ONLY for explicitly legacy or non-canonical labels.
```

### G5-LIQEXIT

```text
REPLACE the missing/stale-L2 rule in Section 1.3 WITH:
If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`, LiquidityGate MUST reject OPEN intents with `Rejected(LiquidityGateNoL2)`.
`CLOSE/HEDGE/replace` intents MUST NOT be rejected solely for missing or stale L2; they MUST use the bounded fallback price ladder in Section 3.1 and may dispatch only monotonic risk-reducing quantity.
If no valid fallback price source exists, the intent MUST fail closed with `Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded`.
```

### G7-RESTART

```text
REPLACE `AT-935` THEN/PASS RULE WITH:
If an OPEN intent reaches `WALRecorded` but has no evidence of any send attempt, restart reconciliation MUST NOT auto-dispatch that intent.
The record MUST remain available for audit and dedupe only.
A dispatch after restart is permitted ONLY IF a fresh post-restart strategy evaluation re-authorizes the OPEN and all OPEN gates pass.
This rule MUST NOT block `reduce_only == true` risk-reducing intents.
```

### G8-CHOKEORDER

```text
NEW CLAUSE:
For every OPEN intent, the only permitted gate order is:
1. Dispatch authorization
2. Preflight
3. Quantize
4. DispatchConsistency
5. FeeCache or equivalent policy freshness gate
6. Expiry
7. Liquidity
8. Net Edge
9. Pricer
10. RecordedBeforeDispatch

If any gate rejects, evaluation MUST stop immediately and no outbound side effect MAY occur.
`expected_slippage_usd` used by Net Edge MUST come from the same Liquidity evaluation that authorized the OPEN intent.
Pricer MUST NOT make an independent profitability eligibility decision.
```

### G10-STARTUPLATCH

```text
NEW CLAUSE:
After WAL replay and before any OPEN-capable dispatch path is reachable, the runtime MUST set `open_permission_blocked_latch = true` with reason `RESTART_RECONCILE_REQUIRED`.
The latch MUST clear ONLY AFTER reconciliation of WAL intents, venue open orders, venue trades, and venue positions succeeds.
If reconciliation finds ACK evidence for an intent whose local `ack_ts` is absent, the runtime MUST record `ack_ts`, advance TLSM to `Acked` or later, and MUST NOT resend that intent.
```

### G11-TRADEDEDUPE

```text
REPLACE the Trade-ID registry handler rule WITH:
On trade or fill event, duplicate suppression MUST apply only to fully applied trades.
The system MUST durably commit `{trade_id, group_id, leg_idx, qty, price}` and the corresponding TLSM, position, and attribution updates in one atomic unit.
If atomic commit is unavailable, the system MUST durably record the trade with `apply_pending = true`, enter `RiskState::Degraded`, and reconciliation MUST complete the missing updates before any later event for that `trade_id` may NOOP as a duplicate.
```

## E) Proof requirements

| Clause | Required enforcement point | Required proving test | Causal assertion needed | Missing today? |
|---|---|---|---|---|
| Instrument-kind derivation | `crates/soldier_core/src/venue/types.rs` | Realistic venue fixtures prove the same metadata always yields the same `amount_semantics` and dispatch amount | Dispatch branches only on normative metadata, not naming guesses | Yes |
| Hash identity inputs | `crates/soldier_core/src/idempotency/hash.rs` plus `crates/soldier_core/src/execution/quantize.rs` | Equivalent float inputs that quantize to identical steps/ticks produce identical hash; different steps/ticks produce different hash | Hash identity changes only when integer canonical identity changes | Yes |
| `s4` schema validation | `crates/soldier_core/src/execution/label.rs` | Wrong width, charset, version, and leg-index labels reject before dispatch with deterministic reason | Invalid canonical labels never reach dispatch | Yes |
| Canonical label matching | `crates/soldier_core/src/recovery/label_match.rs` | Canonical `s4` exact-match count not equal to 1 degrades and blocks OPEN; no heuristic fallback on canonical labels | Recovery cannot silently map a canonical exchange order to the wrong local intent | Yes |
| Liquidity exit carveout | `crates/soldier_core/src/execution/gate.rs` | Missing or stale L2 blocks OPEN, not `CLOSE/HEDGE`; risk-reducing path uses fallback price ladder | Degraded market-data state never removes all legal risk-reducing actions | Yes |
| OPEN gate ordering and slippage authority | `crates/soldier_core/src/execution/build_order_intent.rs` or equivalent single chokepoint | OPEN trace proves exact contract order and that Net Edge consumes slippage from the same liquidity result | No alternative OPEN order or proxy slippage path can authorize dispatch | Yes |
| Fee cache carveout | `crates/soldier_core/src/execution/base_gates.rs` plus chokepoint tests | Hard-stale fee cache blocks OPEN only; `CLOSE/HEDGE/CANCEL` remain dispatchable unless `Kill` applies | ReduceOnly semantics are preserved at the actual chokepoint | Yes |
| WAL queue fail-closed | `crates/soldier_infra/tests/test_dispatch_durability.rs` | Queue-full append failure blocks OPEN, increments errors, and does not stall the hot loop | RecordedBeforeDispatch fails closed without hot-loop deadlock | No |
| Recovered unsent OPEN rule | Restart reconciler plus dispatch gate | Crash after `WALRecorded`, before send; two restarts; replay alone dispatch count stays 0; fresh reevaluation may re-open | Replay alone cannot create new OPEN exposure | Yes |
| Startup latch before dispatch | Bootstrap-to-runtime wiring | Startup with in-flight WAL; OPEN blocked until reconcile completes | No OPEN-capable path is reachable pre-reconcile | Yes |
| ACK-lost recovery | Reconcile result handler updating `ack_ts` and TLSM | Crash after ACK, before local update; restart recovers ACKed state and sends zero duplicates | ACK evidence suppresses resend | Yes |
| Trade-ID crash-mid-apply | Fill application pipeline or atomic ledger-plus-registry unit | Persist `trade_id`, crash before state apply, restart, duplicate replay, state still converges exactly once | Duplicate suppression cannot hide an unapplied fill | Yes |

## F) Final decision

`NO-GO`

Smallest-first remediation sequence

1. Fix `G5-LIQEXIT`, `G7-RESTART`, and `G10-STARTUPLATCH` first; these are the direct capital-risk and stranded-exit paths.
2. Fix `G2-HASH`, `G4-LABELMATCH`, and `G11-TRADEDEDUPE` next; these are the core identity, replay, and duplicate-application defects.
3. Fix `G1-IKIND` and `G8-CHOKEORDER`, then add the proving tests in Section E so the contract stops relying on prose.
4. Close the hardening items `G3-S4SCHEMA`, `G6-FEEPROOF`, and `G12-LINKEDORDERS` while the same touchpoints are open.

Strong complete proof chains already present

- `CSP.3.2` WAL degradation: queue-full or WAL failure blocks OPEN while allowing risk reduction.
- `AT-233` and `AT-234` crash-after-send and crash-after-fill recovery paths.
- Structural single-chokepoint and WAL-last-gate proofs for the execution path.
- Stable intent-identity proofs in the current integer-hash implementation.
