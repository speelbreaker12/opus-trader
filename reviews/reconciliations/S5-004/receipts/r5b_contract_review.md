# Contract Review: S5-004 — Single Chokepoint

## Contract Alignment

### CSP.5.2 Enforcement Rules
| Requirement | Implementation | Status |
|-------------|---------------|--------|
| OPEN dispatch only when TradingMode Active + OpenPermissionLatch clear + RecordedBeforeDispatch | Gate 1: `risk_state != Healthy → reject OPEN`. Gate 10: `!wal_recorded → reject OPEN`. OpenPermissionLatch is reflected in `risk_state` by callers. | ALIGNED |
| ReduceOnly: OPEN forbidden, CANCEL/CLOSE/HEDGE permitted | Gate 1 blocks OPEN when Degraded/Maintenance. CLOSE/HEDGE/CANCEL pass through. | ALIGNED |
| Kill: only risk-reducing permitted | Gate 1 blocks OPEN when Kill. CLOSE/HEDGE/CANCEL still pass through. | NOTE: Kill should also block non-reducing actions. Currently CLOSE/HEDGE pass through Kill — this may be a gap if HEDGE is not always risk-reducing. Contract says "only risk-reducing actions are permitted" under Kill. S5-004's intent classification treats Hedge as always risk-reducing. |

### §1.4.1 Net Edge Gate — MUST run before dispatch
- Gate 8 (NetEdgeGate) runs before Gate 10 (RecordedBeforeDispatch) and before dispatch. | ALIGNED |

### §1.3 Liquidity Gate — MUST run before dispatch
- Gate 7 (LiquidityGate) runs before Gates 8-10. | ALIGNED |

### RecordedBeforeDispatch (CSP.3)
- Gate 10 is the last gate. OPEN intents blocked if WAL fails. | ALIGNED |
- CSP.3.2: WAL failure does NOT block CLOSE/HEDGE. Lines 443-460 implement this carve-out. | ALIGNED |

### AT-015 (Net Edge < min_edge → reject OPEN)
- `test_at506_net_edge_reject_stops_at_gate8` proves rejection at Gate 8 with correct reason. | ALIGNED |

## Fail-Open Hazard Filter

| Check | Result |
|-------|--------|
| Any `unwrap_or(TradingMode::Active)` or optimistic default? | NO — RiskState is passed as parameter, not defaulted. |
| Any gate defaulting to `true`? | NO — `GateResults::default()` sets all gates to `false` (fail-closed). |
| Any path through chokepoint that skips a gate? | CANCEL skips gates 2-10 (by design). CLOSE/HEDGE skip gates 7-9 (by design). All other gates are mandatory. |
| Any `#[allow(...)]` that hides safety issues? | Only `#[allow(deprecated)]` for the old API. `#[allow(clippy::too_many_arguments)]` for `build_gate_results`. Neither is safety-relevant. |

## Contract Gaps

### GAP-1 (INFO): Kill vs Hedge classification
Under Kill mode, contract says "only risk-reducing actions are permitted." The chokepoint treats Hedge as always permissible (same as Close). If a hedge intent could be risk-increasing in some edge case, this would be a gap. However, the intent classification logic (outside S5-004's scope) is responsible for correct classification.

**Disposition**: Not a S5-004 issue — intent classification is the responsibility of the caller and should be audited in the relevant story.

## Decision: PASS
Contract alignment confirmed. No fail-open hazards found in the chokepoint itself.
