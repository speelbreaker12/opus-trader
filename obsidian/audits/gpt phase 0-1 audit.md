AUDIT_STATUS: COMPLETE

|Area|Clauses reviewed|Attack lens used|Result|Loss path IDs|Profit-block IDs|No-finding rationale|
|---|---|---|---|---|---|---|
|intent classification|Definitions (`reduce_only`, `CANCEL intent`, `Fail-closed intent classification`); AT-201; §2.4 migration note; AT-1231|Ambiguity attack; Fail-closed attack|NO_CREDIBLE_FINDING|NONE|NONE|The contract is explicit that unknown or under-specified intent classification fails to OPEN, and legacy recovery defaults are conservative.|
|OPEN vs CLOSE/HEDGE/CANCEL behavior|§1.3 stale-L2 split; §2.2.4 CP-001 semantics; §2.2.5 Cancel/Replace Permission Rules; AT-421; AT-010|Missing-protection attack; Profit-suppression attack|NO_CREDIBLE_FINDING|NONE|NONE|The text clearly preserves CLOSE/HEDGE/CANCEL paths while blocking OPEN under latch or stale-L2 conditions; the weakness is milestone proof, not clause meaning.|
|dispatch authorization|§2.2.3.4 Dispatch Authorization; §7.0 Foundation status-lite mode; AT-1230; AT-931|Ambiguity attack; Fail-closed attack|NO_CREDIBLE_FINDING|NONE|NONE|The canonical hot-path rule is explicit: consult PolicyGuard immediately before dispatch, and foundation mode says `dispatch_enabled == false`. The deeper defects sit in bootstrap authority and gate-ordering contradictions, captured elsewhere.|
|TradingMode / PolicyGuard|Phase 0 P0-E; P0-E clarifications; Status authority matrix; Status authority precedence; Definitions (`TradingMode`); §7.0 `/status` CSP minimum; AT-1220; Phase 1 rule; Phase 2 rule|Ambiguity attack; Contradiction attack; Complexity attack|FINDINGS_FOUND|L-02|P-02|N/A|
|fail-closed behavior|Phase 0 intro (`Before live-trading enablement... MUST be completed and evidenced`); P0-A, P0-B, P0-C, P0-D, P0-F; P0 rationale; P0-E/AT-P0E-NEG for contrast|Missing-protection attack; Fail-closed attack|FINDINGS_FOUND|L-03|NONE|N/A|
|restart / replay / reconciliation|Phase 1 profile note; Phase 1 AT Subset; Phase 1 deferred list; §2.4 Durable Intent Ledger; AT-233; AT-234; AT-935|Missing-protection attack; Fail-closed attack|FINDINGS_FOUND|L-04|NONE|N/A|
|idempotency / duplicate prevention|§1.1 Labeling & Idempotency Contract; §1.1.1; Idempotency Rules 1-4; AT-928; AT-933; AT-269; AT-270; Phase 1 AT Subset|Missing-protection attack; Ambiguity attack|FINDINGS_FOUND|L-05|NONE|N/A|
|emergency containment|P0-D Break-Glass Runbook + Drill; §3.2 Smart Watchdog (`POST /api/v1/emergency/reduce_only`); §7.0 Testing Requirement (`Any new endpoint...`); AT-132; AT-203; specs/IMPLEMENTATION_PLAN.md S8.7|Missing-protection attack; Fail-closed attack|FINDINGS_FOUND|L-06|NONE|N/A|
|risk reduction priority|§0.Z.2.2(F/G); §2.2.3.6 Kill Semantics; §3.1; §3.2; AT-1049; AT-338|Missing-protection attack|NO_CREDIBLE_FINDING|NONE|NONE|The contract repeatedly makes capital supremacy explicit and keeps at least one legal risk-reducing path available while exposed.|
|kill / reduce-only semantics|Definitions (`TradingMode`, `reduce_only`); §2.2.3.4; §2.2.3.6; AT-338; AT-339; AT-346; AT-347|Contradiction attack; Fail-closed attack|NO_CREDIBLE_FINDING|NONE|NONE|The semantics are spelled out crisply: no new exposure in Kill/ReduceOnly, but containment remains authorized while exposed.|
|stale data / stale state|§1.0.X AT-104; Phase 1 stub test note (AT-104); §2.2.3.4 Dispatch Authorization; §1.4 OPEN chokepoint sequence|Contradiction attack; Profit-suppression attack; Complexity attack|FINDINGS_FOUND|L-07|P-03|N/A|
|gate ordering|§1.4 OPEN chokepoint sequence; §2.4 Dispatch rule (`OPEN dispatch requires WALRecorded`); §2.4.1 Architecture boundary (`hot-loop gate succeeds upon enqueue`); AT-1215|Contradiction attack; Fail-closed attack; Profit-suppression attack|FINDINGS_FOUND|L-01|P-01|N/A|
|reject semantics|§2.2.6 RejectReasonCode Registry; AT-930; AT-1101; Phase 1 reject-path ATs (AT-908, AT-920, AT-921, AT-926)|Ambiguity attack; Missing-protection attack|NO_CREDIBLE_FINDING|NONE|NONE|The reject-code registry is explicit and has completeness checks; the issue is closure criteria, not the registry itself.|
|observability requirements|P0-E clarifications; Status authority matrix; Status authority precedence; §7.0 Status surface split; AT-1230; AT-023|Ambiguity attack; Complexity attack|NO_CREDIBLE_FINDING|NONE|NONE|The observability text is complex, but the authority matrix and foundation `/status` test are explicit enough on their own.|
|configuration defaults|Appendix A enforcement rule; AT-341; AT-424; `contracts_amount_match_tolerance`; `instrument_cache_ttl_s`|Missing-protection attack|NO_CREDIBLE_FINDING|NONE|NONE|Relevant Phase-0/1 defaults are named, and the contract states “default if defined here, otherwise fail closed.”|
|precedence rules|Phase 1 profile note; Phase 1 bullet list; Phase 1 AT Subset; Phase 2 bullet list (`liquidity safety gates`); §0.0 Normative Scope; §0.Z.2.5 Precedence rule|Contradiction attack; Complexity attack|FINDINGS_FOUND|L-08|P-04|N/A|
|definitions and units|Definitions (`instrument_kind`, `amount_semantics`); §1.0 Instrument Units & Notional Invariants; Dispatcher Rules; AT-277; AT-920; AT-1097|Ambiguity attack|NO_CREDIBLE_FINDING|NONE|NONE|The sizing discriminator, canonical amount rules, and mismatch rejects are explicit and acceptance-tested.|
|acceptance tests inside the contract|Acceptance Test Isolation Requirements; Phase 1 AT Subset; AT-1215; AT-1216|Profit-suppression attack; Missing-protection attack; Complexity attack|FINDINGS_FOUND|NONE|P-05|N/A|

### C) Executive verdict

CONTRACT_NOT_CLEAR_BLOCKING_GAPS

Core bottleneck: the contract does not keep a single authoritative chokepoint through Phase 0 and Phase 1. Bootstrap status authority, Phase 1 completion scope, and RecordedBeforeDispatch each admit more than one reasonable implementation. That is the constraint. This is not bulletproof.

Top 3 ways this contract could cause loss:

1. `RecordedBeforeDispatch` is contradictory: §2.4 says OPEN needs `WALRecorded`, while §2.4.1 says the hot-loop gate succeeds on enqueue. That can dispatch live risk before durable local truth exists.
    
2. Phase 1 scope is contradictory on Liquidity Gate: the profile note includes it, the bullet list omits it, the Phase 1 AT subset omits it, and Phase 2 lists liquidity safety gates again. A team can ship foundation work without slippage protection.
    
3. Phase 0 requires owner-facing `trading_mode` / `opens_globally_permitted` before Phase 2 canonical PolicyGuard authority exists, which allows false-safe readiness signaling.
    

Top 3 ways this contract could block valid profit:

1. Phase 1 closure is reject-heavy and omits paired positive pass-path proofs, so a reject-only implementation can satisfy the milestone and silently over-block valid opens.
    
2. The `WALQueueAccepted` versus `WALRecorded` contradiction invites overly conservative implementations that wait too long or fail inconsistently, suppressing good dispatches.
    
3. The AT-104 Phase 1 stale-metadata stub creates a second stale-state authority outside PolicyGuard, increasing false rejects once the real resolver exists.
    

Top 3 simpler-safer rewrites:

1. In Phase 0/1, expose only `dispatch_enabled=false` and `phase=foundation`; do not expose canonical `trading_mode` / `opens_globally_permitted` before PolicyGuard is authoritative.
    
2. Define `RecordedBeforeDispatch` once: OPEN dispatch happens after `WALRecorded`, never on enqueue.
    
3. Make the authoritative Phase 1 deliverables list and the Phase 1 AT subset identical, and require paired TRIP/NON-TRIP tests for every included OPEN-blocking guard.
    

### D) Loss-path table

|ID|Area|Clause / Topic|How this could cause loss|Why the contract allows it|Severity|Exact clause(s)|Safer rewrite direction|
|---|---|---|---|---|---|---|---|
|L-01|gate ordering|`RecordedBeforeDispatch` / WAL gate|If implementation dispatches on `WALQueueAccepted`, a crash after enqueue but before `WALRecorded` can leave a live OPEN at the venue without authoritative local truth, creating replay drift or duplicate exposure.|Two normative clauses conflict on the dispatch gate.|BLOCKING|§2.4 Dispatch rule; §2.4.1 Architecture boundary; AT-1215|Make `WALRecorded` the sole OPEN dispatch authorizer.|
|L-02|TradingMode / PolicyGuard|Bootstrap `trading_mode` / `opens_globally_permitted`|An operator or bootstrap tool can trust a placeholder `trading_mode` / `opens_globally_permitted` before PolicyGuard exists and enable live readiness off a false-safe surface.|P0-E requires those fields before Phase 2 canonical status authority exists, but does not define their derivation or prohibit them from being treated as authoritative.|BLOCKING|Phase 0 P0-E; P0-E clarifications; Status authority matrix; Status authority precedence; §7.0 CSP minimum `/status`; Phase 1 rule; Phase 2 rule|Remove canonical mode/open-permission fields from pre-Phase-2 scaffolding.|
|L-03|fail-closed behavior|Phase 0 operational prerequisites are doc-evidence only|Live trading can be enabled with missing or stale launch policy, environment isolation, key/secret rules, break-glass evidence, or strict-loader proof because the contract does not mechanically block enablement on those failures.|P0-A/B/C/D/F require evidence artifacts, but Phase 0 does not define a preflight or acceptance test that must fail closed if they are absent.|BLOCKING|Phase 0 intro; P0-A; P0-B; P0-C; P0-D; P0-F; P0 rationale|Add a mandatory live-enable preflight that keeps dispatch disabled until all P0 artifacts verify.|
|L-04|restart / replay / reconciliation|Phase 1 closure defers crash-path restart proofs|The foundation WAL path can be called “complete” without proving no-resend or fill-recovery behavior after crash, so unsafe ledger behavior can be carried forward into later phases.|Phase 1 says WAL/durable ledger is a safety-critical primitive, but explicitly defers AT-233/234/935.|HARDENING|Phase 1 profile note; Phase 1 AT Subset; Deferred to Phase 2 list; §2.4; AT-233; AT-234; AT-935|Either require minimal crash-path proofs in Phase 1 or state the WAL is plumbing-only until Phase 2.|
|L-05|idempotency / duplicate prevention|Remote dedupe foundation omitted from Phase 1 closure|A later WS reconnect or duplicate trade replay can produce duplicate dispatch or duplicate fill accounting because the foundation never proved reconnect matching or trade-id dedupe.|Phase 1 closure requires local hash determinism and local NOOP duplicate, but omits reconnect/trade-id proofs despite §1.1 claiming dedupe across reconnects and race conditions.|HARDENING|§1.1 Requirement; Idempotency Rules 1-4; AT-928; AT-933; AT-269; AT-270; Phase 1 AT Subset|Move reconnect/trade-id dedupe proofs into the foundation exit gate or narrow the Phase 1 claim.|
|L-06|emergency containment|S8.7 emergency reduce-only endpoint needs endpoint-proof plus runbook sync when promoted to operator use|If the later HTTP emergency control is exposed to operators without a verified mode-transition proof or a runbook refresh, incident response can drift from runtime reality and delay containment while exposure is live.|The contract intentionally keeps Phase 0 break-glass CLI-based, but a later operator-facing HTTP path still needs a canonical proof point. The right binding is the S8.7 endpoint story with its endpoint-level test requirement, not P0-D itself.|HARDENING|§3.2 `POST /api/v1/emergency/reduce_only`; §7.0 Testing Requirement; AT-132; specs/IMPLEMENTATION_PLAN.md S8.7|Refile to S8.7: require an endpoint-level test proving the POST drives `emergency_reduceonly_active`/`TradingMode=ReduceOnly`, and refresh the runbook when that endpoint becomes operator-facing.|
|L-07|stale data / stale state|AT-104 Phase 1 stale-metadata stub|A split-brain stale-data gate can survive into later phases; one path can clear earlier than the other and allow or deny dispatch on stale state depending on code path.|The stub note authorizes OPEN blocking by `RiskState::Degraded` alone outside the canonical PolicyGuard resolver.|HARDENING|§1.0.X AT-104; Phase 1 stub test note; §2.2.3.4; §1.4 OPEN chokepoint sequence|Make the stub test-only and explicitly non-authoritative once PolicyGuard exists.|
|L-08|precedence rules|Phase 1 Liquidity Gate scope contradiction|A reasonable implementation can declare Phase 1 complete without a working Liquidity Gate and send unsafe opens without the slippage guard.|The contract assigns Liquidity Gate to Phase 1 in the profile note, omits it from the Phase 1 bullets and AT subset, and lists liquidity safety gates again in Phase 2, with no local precedence rule resolving the conflict.|BLOCKING|Phase 1 profile note; Phase 1 bullet list; Phase 1 AT Subset; Phase 2 bullet list (`liquidity safety gates`); §0.0; §0.Z.2.5|Make Phase 1 scope singular and self-consistent.|

### E) Profit-block table

|ID|Area|Clause / Topic|How this could block valid profit|Why the contract allows it|Severity|Exact clause(s)|Safer rewrite direction|
|---|---|---|---|---|---|---|---|
|P-01|gate ordering|`RecordedBeforeDispatch` / WAL gate|To stay “safe” under contradictory text, an implementer can wait for extra barriers or reject good opens whenever enqueue and record timing diverge, causing unnecessary latency or zero-dispatch on valid trades.|The contract leaves both enqueue and `WALRecorded` looking authoritative.|BLOCKING|§2.4 Dispatch rule; §2.4.1 Architecture boundary; AT-1215|Define one dispatch gate only: `WALRecorded`.|
|P-02|TradingMode / PolicyGuard|Bootstrap `trading_mode` / `opens_globally_permitted`|Conservative placeholder values on owner scaffolding can freeze valid bootstrap/foundation execution or readiness smoke tests because the contract does not define pre-Phase-2 derivation.|P0-E requires the fields before canonical §7.0 semantics exist.|BLOCKING|Phase 0 P0-E; P0-E clarifications; Status authority matrix; Status authority precedence; §7.0 `/status` CSP minimum; AT-1220|Do not expose canonical mode/open-permission semantics before PolicyGuard is authoritative.|
|P-03|stale data / stale state|AT-104 Phase 1 stale-metadata stub|If the RiskState-only stub persists after Phase 2, fresh metadata can still be blocked by a lingering `Degraded` path even when PolicyGuard would return `Active`.|The stub note explicitly authorizes OPEN blocking via `RiskState::Degraded` alone.|HARDENING|§1.0.X AT-104; Phase 1 stub test note; §2.2.3.4|Make the stub test-only and remove it from runtime authority.|
|P-04|precedence rules|Phase 1 Liquidity Gate scope contradiction|A cautious implementer can freeze or defer valid opens until the Liquidity Gate ambiguity is resolved, because the contract says Phase 1 both does and does not include it.|Phase 1 note, bullets, AT subset, and Phase 2 bullets do not agree.|BLOCKING|Phase 1 profile note; Phase 1 bullet list; Phase 1 AT Subset; Phase 2 bullet list|Use one authoritative milestone scope and one matching AT set.|
|P-05|acceptance tests inside the contract|Phase 1 closure lacks paired pass-path proofs|A reject-only foundation can satisfy the milestone and still block good trades, because Phase 1 completion does not require the NON-TRIP/pass-path proofs for included OPEN-blocking guards.|The global AT isolation rule requires paired TRIP/NON-TRIP tests, but the Phase 1 closure list omits pass-path ATs like AT-1215 and AT-1216.|BLOCKING|Acceptance Test Isolation Requirements; Phase 1 AT Subset; AT-1215; AT-1216|Require paired pass/fail ATs in the Phase 1 closure gate.|

### F) Simpler-safer alternatives

|ID|Area|Clause / Topic|Why current design is riskier or too complex|Simpler/safer contract shape|Why better|
|---|---|---|---|---|---|
|S-01|gate ordering|`RecordedBeforeDispatch`|Two normative gate states (`WALQueueAccepted` and `WALRecorded`) create split implementations and replay ambiguity.|`RecordedBeforeDispatch` for OPEN MUST equal `WALRecorded` only; enqueue is telemetry/backpressure only.|One chokepoint, no split-brain dispatch timing.|
|S-02|TradingMode / PolicyGuard|Phase 0 / Phase 1 bootstrap status|Pre-canonical `trading_mode` / `opens_globally_permitted` creates fake authority before PolicyGuard exists.|In Phase 0/1, expose only `dispatch_enabled=false`, `phase=foundation`, and optionally `mode_authority=NOT_ENFORCED`.|Removes false authority and keeps bootstrap semantics fail-closed.|
|S-03|precedence rules|Phase 1 deliverables vs AT subset|Note, bullets, Phase 2 bullets, and closure ATs disagree on whether Liquidity Gate is in Phase 1.|One authoritative Phase 1 deliverables list, mirrored exactly by the Phase 1 AT subset.|Eliminates milestone ambiguity and retrofit risk.|
|S-04|acceptance tests inside the contract|Phase 1 closure criteria|Reject-heavy closure criteria let false rejects pass milestone completion.|For every Phase 1 OPEN-blocking guard, require one TRIP AT and one NON-TRIP AT in the closure gate.|Prevents reject-only implementations from looking compliant.|
|S-05|emergency containment|S8.7 operator emergency endpoint rollout|A later HTTP emergency control can drift from the documented response path if the endpoint lands without proof and the runbook stays CLI-only.|Before any operator-facing HTTP emergency control is enabled, require a passing endpoint-level proof of the ReduceOnly transition and a synchronized runbook/drill update.|Keeps operator playbook and runtime reality aligned under stress without mis-scoping Phase 0.|

### G) Exact patch proposals

**Patch for L-01 / P-01**

For any OPEN intent, `RecordedBeforeDispatch` MUST mean `WALRecorded`.

`WALQueueAccepted` MAY be emitted for telemetry or backpressure handling but MUST NOT authorize venue or network dispatch.

If `WALRecorded` is not obtained, the OPEN MUST FAIL CLOSED.

If durable-before-dispatch is configured, OPEN dispatch MUST additionally wait for `WALDurable`.

**Patch for L-02 / P-02**

During Phase 0 and Phase 1 foundation mode, owner scaffolding surfaces MUST NOT expose `trading_mode` or `opens_globally_permitted` as authoritative execution-permission fields.

Until PolicyGuard is active and `/api/v1/status` satisfies the §7.0 CSP minimum schema, the only canonical dispatchability signal MUST be `dispatch_enabled=false` with `phase=foundation`.

Any bootstrap surface that cannot satisfy this MUST FAIL CLOSED.

**Patch for L-03**

Live trading MUST NOT be enabled unless P0-A, P0-B, P0-C, P0-D, P0-E, and P0-F evidence artifacts exist and a release preflight verifies them.

Missing, unreadable, or failed evidence for any P0 item MUST keep `dispatch_enabled=false` and MUST block promotion or live enablement.

Otherwise FAIL CLOSED.

**Patch for L-06**

S8.7, not P0-D, MUST be the canonical binding point for `POST /api/v1/emergency/reduce_only` when that endpoint is promoted to operator-facing use.

Before that rollout is considered complete, a passing endpoint-level test MUST prove the POST drives `emergency_reduceonly_active=true` and `TradingMode=ReduceOnly` per AT-132.

At the same rollout point, the break-glass runbook and drill MUST be refreshed to either cite that endpoint as the canonical action or remain explicitly CLI-only.

**Patch for L-08 / P-04**

The authoritative Phase 1 deliverables list MUST be exactly the list used by the Phase 1 AT Subset.

If Liquidity Gate is a Phase 1 deliverable, the Phase 1 bullet list MUST include `Liquidity Gate`, and the Phase 1 AT Subset MUST include its required tests.

If Liquidity Gate is not a Phase 1 deliverable, the Phase 1 profile note MUST NOT list it.

**Patch for P-05**

For every Phase 1 guard that can block OPEN, Phase 1 completion MUST require one TRIP acceptance test and one NON-TRIP acceptance test from the canonical acceptance-test set.

If RecordedBeforeDispatch remains in Phase 1, Phase 1 completion MUST include AT-1215.

If Liquidity Gate remains in Phase 1, Phase 1 completion MUST include at least one Liquidity Gate TRIP test and AT-1216.

### H) Coverage summary

- Total inspection areas required: 18
    
- Total inspection areas completed: 18
    
- Areas with findings: 9
    
- Areas with no credible finding: 9
    
- Loss paths found: 8
    
- Profit-block paths found: 5
    
- BLOCKING findings count: 9
    
- HARDENING findings count: 4
    

### I) Final decision

NO-GO

smallest-first remediation order

1. Fix the §2.4 / §2.4.1 RecordedBeforeDispatch contradiction.
    
2. Remove pre-Phase-2 canonical `trading_mode` / `opens_globally_permitted` from bootstrap surfaces, or mark them non-authoritative and fail closed.
    
3. Make Phase 1 scope singular: align the profile note, bullet list, Phase 1 AT subset, and Phase 2 bullets on Liquidity Gate.
    
4. Add paired NON-TRIP closure tests for Phase 1, especially AT-1215 and AT-1216 if those guards remain in scope.
    
5. Add a mechanical Phase 0 live-enable preflight for P0-A through P0-F and bind P0-D to one tested emergency action.
    
6. Remove the AT-104 runtime-authority ambiguity by making the Phase 1 stub explicitly test-only.
    
7. Pull minimal crash/restart and reconnect/dedupe proofs forward before any foundation exit.
