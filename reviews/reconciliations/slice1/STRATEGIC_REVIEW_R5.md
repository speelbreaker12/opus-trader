---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R7b-strategic-review
  cycle: recon-v1.x (original)
  phase_equivalent: R7b
artifact_type: strategic_review
scope: slice 1 systemic risks
---

# Strategic Failure Review: Slice 1 Reconciliation

> Reviewer: Claude Opus 4.6 (adversarial strategic review)
> Date: 2026-02-21
> Scope: All 13 Slice 1 stories (S1-001 through S1-013), the reconciliation process itself, and the resulting debt register
> Sections applied: **ALWAYS** (SS2, SS12, SS20, SS22) + **SS3** (Hidden Assumptions) + **SS5** (Compounding Failures) + **SS4b** (Point-in-Time vs Continuous)

---

## Architectural Findings

### High

- **H1: No story wires the end-to-end safety pipeline -- "island of guards" problem**
  - Risk: Slice 1 builds individual guards (cache TTL, expiry guard, config defaults, contracts/amount mismatch, dispatch mapping) and tests each in isolation. But **no story wires them into a production-path pipeline that actually enforces safety**. The critical connective tissue is missing:
    - `PolicyGuard` does not exist as code. It is referenced exclusively in comments (`state.rs:3,11,17,20,23`, `cache.rs:62,259`, `margin_gate.rs:8`). The `TradingMode` enum (`Active | ReduceOnly | Kill`) is never defined.
    - `validate_and_dispatch` (S1-007, AT-920) has **zero production callsites** (`dispatch_map.rs:179`). It is exported in `mod.rs:41` but never called outside of tests.
    - `resolve_config_value` (S1-010) is tested but not wired into any runtime that feeds parameters to guards.
    - `opens_blocked` (S1-003) returns a bool but has no caller in the production dispatch path -- the pipeline receives `risk_state` as a caller-provided input (`pipeline.rs:34`) and checks `RiskState::Healthy` directly (`pipeline.rs:166`).
  - Impact: **The reconciliation process certified 13 stories as RECONCILED, but the system has no operational safety pipeline.** Each guard works in isolation. A production deployment of Slice 1 alone would have guards that are structurally correct but functionally inert. The blast radius is not a single guard failing -- it is the entire safety layer being absent.
  - Why the reconciliation missed it: Each story was audited against its own ATs. No AT says "this guard is called from the production pipeline." The process checks whether guard X blocks intent Y in a test, not whether guard X is reachable from production code. The `TODO(AT-920-PROD)` comment at `test_dispatch_map.rs:591` is the most honest artifact in the codebase -- it acknowledges the gap explicitly.
  - Mitigation: This is already partially tracked as GAP-003-2 (PolicyGuard integration, Slice 2), GAP-010-4 (config wired into runtime, Slice 2), and GAP-007-1 (validate_and_dispatch callsites, Slice 2). But framing these as three independent P1/DEFERRED items **understates the systemic nature of the gap**. Together, they represent the absence of a safety pipeline. Slice 2 must have a mandatory integration story that wires all Slice 1 guards into the production path, with an AT that proves end-to-end: "stale cache -> Degraded -> ReduceOnly -> OPEN rejected in production code path."

- **H2: `dispatch_consistency_passed` is a caller-provided boolean with no upstream enforcement**
  - Risk: The pipeline at `base_gates.rs:39` accepts `dispatch_consistency_passed: bool` as a plain input. The caller is trusted to have run `validate_and_dispatch` and passed the result. But since `validate_and_dispatch` has zero production callsites, **every production caller could pass `true` without ever running the mismatch check**. The AT-920 enforcement exists only in test code where the test manually constructs the boolean.
  - Impact: The contracts/amount mismatch guard (AT-920) is provably correct as a function, but the "proof token" pattern that would force callers to prove they ran it does not exist. Any caller can bypass it by passing `dispatch_consistency_passed: true`.
  - Why the reconciliation missed it: S1-007's audit correctly noted "zero production callsites" and "Degraded is caller convention." But the systemic risk -- that the boolean input pattern makes bypass trivial -- was classified as P1-INFO rather than a design defect.
  - Mitigation: When wiring in Slice 2, `dispatch_consistency_passed` should be replaced with a proof token (a `ValidatedDispatch` struct that can only be constructed by calling `validate_and_dispatch`). The type `ValidatedDispatch` already exists at `dispatch_map.rs:74` -- it just needs to be threaded through the pipeline input instead of a bare bool.

### Medium

- **M1: RiskState::Degraded is a "should" convention, not a "must" enforcement**
  - Risk: The `RiskState` enum comments say "PolicyGuard should resolve to `TradingMode::ReduceOnly`" (emphasis on "should"). Since PolicyGuard doesn't exist, the mapping from Degraded -> ReduceOnly is entirely aspirational. The pipeline checks `risk_state == RiskState::Healthy` (`pipeline.rs:166`) but `risk_state` is provided by the caller. Nothing prevents a caller from passing `RiskState::Healthy` when the cache is stale.
  - Impact: Medium. The pattern works if callers are honest, and the open_runtime.rs code does compute effective_risk_state from margin gate results (`open_runtime.rs:103-111`). But this is an ad-hoc computation, not a centralized PolicyGuard.
  - Mitigation: Acceptable for Slice 1 if Slice 2 introduces PolicyGuard as the single authoritative source of RiskState. The open_runtime ad-hoc computation should be consolidated.

- **M2: 897 tests but pipeline-level integration coverage is thin**
  - Risk: Of 897 tests, only ~52 calls to `evaluate_intent_pipeline` or `build_open_order_intent_runtime` exist across 5 test files. The overwhelming majority of tests are unit tests that exercise individual guards. This creates the illusion of comprehensive coverage while the integration layer -- where guards compose and interact -- has relatively sparse testing.
  - Impact: Individual guard correctness is well-proven. Guard composition correctness is weakly proven. For example, the interaction between expiry guard rejection and fee cache staleness in the same pipeline invocation has no dedicated test.
  - Mitigation: Slice 2 should include integration tests that exercise multi-guard failure scenarios (e.g., stale cache + expired instrument + mismatch simultaneously).

- **M3: GAP-012-7 decision divergence accepted without quantifying the escape surface**
  - Risk: The premortem chose "strict allowlist with expiry-dependent fallback" for `Other` venue errors. The implementation at `lifecycle.rs:171-183` always maps `Other` to `Retryable`. The reconciliation accepted this as "safe" because Retryable is conservative for non-expired instruments. But for **expired instruments**, mapping `Other` to `Retryable` means the system will retry an order on an expired instrument -- which is not conservative, it is wasteful and could delay position unwinding.
  - Impact: Low under normal conditions (unknown venue errors are rare). Could become medium during exchange delistings when unfamiliar error codes appear precisely for expired instruments.
  - Mitigation: Already tracked as DEFERRED to Slice 2+. The risk assessment of "safe" should be qualified: "safe for non-expired instruments; potentially harmful for expired instruments during delisting events."

### Low

- **L1: S1-013 (PR gate) enforcement_point was "DispatcherChokepoint" -- a metadata integrity issue**
  - Risk: The PRD had a wrong enforcement_point for a CI script, which was caught and fixed. But the error suggests that PRD metadata was not validated against a controlled vocabulary before reconciliation. If the vocabulary had been enforced by a linter, this would have been caught at write time.
  - Mitigation: Fixed. Consider adding CI-time validation of prd.json enforcement_point values against the allowed set.

- **L2: Several DECISION_DIVERGENCE items accepted as INFO without formal acknowledgment**
  - Risk: S1-002 (InstrumentKindInput booleans vs metadata), S1-003 (per-entry vs cache-wide freshness), S1-010 (enum vs struct), S1-011 (Deribit names with bridge method) -- all are noted as "improvement" or "INFO" divergences. While individually correct, a pattern of informal divergence from premortems could erode the value of the premortem process.
  - Mitigation: Consider a "Decision Divergence Register" that explicitly ratifies divergences. This normalizes the pattern and makes it auditable.

---

## Hidden Assumptions

- [ ] **"All 74 ConfigParam variants have Appendix A defaults" remains true**: GAP-010-1 was marked P1 because the Err path of `resolve_config_value` is structurally unreachable (all params have defaults). The fix added a test that iterates all params to confirm this. But the assumption is fragile: adding a single new `ConfigParam` variant without a default would make the Err path reachable *and untested in context*. The reconciliation added a regression guard (`test_all_config_params_fail_closed_when_missing_without_default`), but this test checks the error path by constructing the error manually -- it does not prove that `resolve_config_value(new_param, None)` returns Err for a real param without a default.
  - Violated when: A developer adds a new ConfigParam variant and forgets to add a default in `appendix_a_default`.
  - Current protection: `test_all_appendix_a_params_have_defaults` iterates ALL_PARAMS and asserts each has a default. This *should* catch the addition of a param without a default, assuming ALL_PARAMS is updated. If the developer adds a variant to the enum but forgets to add it to ALL_PARAMS, the test won't catch it.

- [ ] **Pipeline callers correctly compute RiskState before passing it**: The pipeline trusts its caller to provide the correct `risk_state`. There is no mechanism to verify that the caller actually ran cache freshness checks, fee staleness checks, and config validation before constructing the RiskState.
  - Violated when: A new caller is added that hardcodes `RiskState::Healthy` or computes it from a subset of signals.

- [ ] **Saturating arithmetic in expiry guard is always conservative**: `lifecycle.rs:136-137` uses `saturating_mul` and `saturating_sub` to prevent overflow. If `expiry_delist_buffer_s * 1000` overflows u64, it saturates to `u64::MAX`, making `opens_blocked_from_ms = expiration_ms.saturating_sub(u64::MAX) = 0`, which means OPENs are blocked from time 0 -- fail-closed. This is correct. But the assumption that buffer_s is a u64 multiplied by 1000 is only safe because buffer values are small. If a config error sets buffer_s to `u64::MAX / 500`, the saturating behavior silently blocks all OPENs with no diagnostic.
  - Violated when: Config error sets unreasonably large buffer. Protection: config defaults from Appendix A keep values sane.

- [ ] **Evidence window proves ongoing correctness**: The reconciliation proves that at commit `1b85f25`, all guards are correct and all 897 tests pass. It does not prove that the guards remain correct after the next commit. See SS4b below.

---

## Systemic Risks

- [ ] **Complexity ratio**: The reconciliation process itself deployed 4 parallel agents + 4 cross-reviewers across 6 phases to audit 13 stories. This produced ~1200 lines of evidence ledgers, ~300 lines of gap list, and 7 new tests. The process is proportionate for the initial slice of a safety-critical trading system, but it is not sustainable at this cadence for every slice. The 7 new tests (the concrete output) could have been identified by a single experienced reviewer in a fraction of the time. See SS20.

- [ ] **Dual-mechanism interaction: `opens_blocked()` vs pipeline `risk_state == RiskState::Healthy` check**: Two independent mechanisms exist for blocking OPENs based on health state. `opens_blocked()` in `cache.rs:265` is a standalone function that maps RiskState to a boolean. The pipeline at `pipeline.rs:166` checks `risk_state == RiskState::Healthy` directly. These are semantically equivalent today (both block non-Healthy), but if RiskState gains new variants or if "Maintenance allows some OPENs" logic is introduced, they could diverge.
  - Current protection: Both are pure functions of RiskState, so they agree by construction. Risk is low until semantics diverge.

---

## Compounding Failures

- [ ] **Chain 1: Missing PolicyGuard + Caller-provided RiskState + Zero validate_and_dispatch callsites**
  1. Root cause: PolicyGuard is not implemented (no code, only comments)
  2. Propagation: RiskState is caller-provided to the pipeline, so the pipeline trusts callers to set it correctly
  3. Amplification: `validate_and_dispatch` has zero callsites, so the contracts/amount mismatch check never runs in production
  4. Detection gap: All tests pass because each guard is tested in isolation with correct inputs
  5. Impact: A production deployment could dispatch orders with mismatched contracts/amount sizing to Deribit while the system reports "all guards green" -- because no guard is actually wired into the dispatch path

  This is the most dangerous compounding chain in Slice 1. Each individual story is RECONCILED, but together they form a system where safety enforcement is aspirational rather than operational.

- [ ] **Chain 2: Config defaults all present + Err path dead + Future param without default**
  1. Root cause: All 74 ConfigParam variants have Appendix A defaults
  2. Propagation: `resolve_config_value` Err path is structurally unreachable in production
  3. Amplification: Tests construct errors manually rather than exercising the real code path
  4. Detection gap: Adding a new ConfigParam requires updating both the enum AND `appendix_a_default` AND `ALL_PARAMS` -- three places that must stay synchronized
  5. Impact: A new param without a default silently returns Ok with an incorrect value (if `appendix_a_default` match falls through) or panics (if match is non-exhaustive)

  Current protection: `test_all_appendix_a_params_have_defaults` would catch a missing default IF the param is in ALL_PARAMS. The reconciliation's new test `test_all_config_params_fail_closed_when_missing_without_default` adds a second guard. Combined, these are adequate but not watertight.

- [ ] **Chain 3: Per-story reconciliation focus + deferred cross-story items + no integration story**
  1. Root cause: Reconciliation audits each story against its own ATs
  2. Propagation: Cross-story wiring items are deferred to "Slice 2"
  3. Amplification: No mandatory "integration story" exists in Slice 2 PRD that would force the wiring
  4. Detection gap: All 13 stories show RECONCILED, creating confidence that the system works
  5. Impact: Slice 2 could implement its own stories without ever wiring the Slice 1 guards, pushing the integration debt further

---

## Maintenance Hazards

- [ ] **Debug path for "why was this OPEN blocked?"**: Currently requires tracing through: (1) who provided `risk_state` to the pipeline, (2) whether `dispatch_consistency_passed` was honestly computed, (3) which guard in `evaluate_base_gates` rejected, (4) whether the rejection reason code is accurate. This is 4 steps across 3 modules. A centralized PolicyGuard would reduce this to 1 step.

- [ ] **Reconciliation process cost**: 6 phases, 8+ agent invocations, ~1500 lines of markdown produced. The marginal value per line of evidence decreases as the process scales. For Slice 2+, consider a lighter process (see SS20).

- [ ] **DEFERRED items lack forcing functions**: The 9 DEFERRED items are tracked in `GAP_LIST.md` but have no CI enforcement. Nothing prevents Slice 2 from shipping without addressing them. Consider adding a CI check that fails if DEFERRED items targeted at the current slice remain open.

---

## Safety Invariants

### Invariants Established by Slice 1

| # | Invariant | Mechanically Enforced? | Evidence |
|---|-----------|----------------------|----------|
| 1 | **OrderSize canonical fields are correct per instrument kind** (option -> qty_coin, perpetual -> qty_usd) | **YES** -- `build_order_size` match arms, 15 tests in `test_order_size.rs` including boundary/NaN/zero/negative | `order_size.rs:97-133`, table-driven tests |
| 2 | **Dispatch mapping selects correct amount field per instrument kind** | **YES** -- `map_to_dispatch` match arms, 28 tests in `test_dispatch_map.rs` | `dispatch_map.rs:140-163` |
| 3 | **Contracts/amount mismatch is detected and rejected** | **YES at function level, NO at system level** -- `validate_and_dispatch` is tested (11 tests) but has zero production callsites | `dispatch_map.rs:179-224`, zero callers in src/ |
| 4 | **Stale instrument cache produces RiskState::Degraded** | **YES at cache level, NO at pipeline level** -- `InstrumentCache.get_at()` correctly reports staleness, `opens_blocked()` maps Degraded to blocked, but no production code calls `opens_blocked()` or feeds cache staleness into the pipeline's `risk_state` | `cache.rs:162-176`, `cache.rs:265` |
| 5 | **Expired/delisted instruments block OPEN intents** | **YES at guard level AND pipeline level** -- `evaluate_expiry_guard` is called from `evaluate_base_gates` at `base_gates.rs:363`, which is called from both `pipeline.rs` and `open_runtime.rs`. This is the **only Slice 1 guard that is fully wired.** | `lifecycle.rs:95-148`, `base_gates.rs:356-386` |
| 6 | **Config parameters fail-closed when missing without a default** | **YES at function level, NO at system level** -- `resolve_config_value` returns Err, but no production code calls it | `config.rs:452-455`, 19 tests in `test_config_defaults.rs` |
| 7 | **NaN/Inf/negative inputs are rejected by all numeric guards** | **YES** -- OrderSize, dispatch map, cache TTL, and config all validate for non-finite/non-positive values | Multiple enforcement points, tested |
| 8 | **CLOSE/HEDGE/CANCEL are never blocked by instrument cache staleness** | **YES** -- `opens_blocked()` only blocks OPEN; `evaluate_expiry_guard` allows non-OPEN through buffer; `base_gates.rs:375-386` only blocks OPEN when expiry data is missing | `cache.rs:265`, `lifecycle.rs:120-126`, `base_gates.rs:375` |
| 9 | **Intent classification defaults to OPEN (most restrictive) when uncertain** | **YES** -- exhaustive enum match on `ChokeIntentClass` with no default arm; `reduce_only` mapping in dispatch uses closed enum | Structural: Rust enum exhaustiveness |
| 10 | **PR merge gate fails-closed on missing/pending check-runs** | **YES** -- `pr_gate.sh` treats empty/null/pending as failure with reason tokens, 29 test cases | `pr_gate.sh:830-835`, `test_pr_gate.sh:217-226` |

**Summary**: Of 10 safety invariants, **3 are fully enforced end-to-end** (invariants 5, 7, 10). **4 are enforced at the function level but not wired into production** (invariants 3, 4, 6, and partially 8). **2 are enforced by type system/exhaustiveness** (invariants 8, 9). **1 requires PolicyGuard to be meaningful** (invariant 4's pipeline integration).

The reconciliation correctly identifies the function-level enforcement as PROVEN. The gap is that "PROVEN at function level" and "enforced in production" are different claims, and the reconciliation process does not distinguish between them.

---

## Simpler Alternative

- [ ] **80/20 alternative for the reconciliation process**: A single reviewer reading all 13 stories' test files and running `cargo test` could have identified the 7 missing tests and the compilation error in approximately 2-4 hours. The 6-phase process with 8+ agents was more thorough (137 citations spot-checked, cross-reviewer agreement) but the marginal findings over a single careful review were small: the systemic pattern GAP-SYSTEMIC-1 (dead error paths) and some PRD metadata corrections.

  **Recommendation for Slice 2+**: Use the full multi-agent process only for the initial audit. For subsequent slices, a single-reviewer pass with a checklist derived from the Slice 1 findings (check for zero callsites, check for caller-provided booleans that should be proof tokens, check that guards are reachable from production code) would capture 90% of the value at 20% of the cost.

- [ ] **80/20 alternative for the DEFERRED items**: Instead of tracking 9 deferred items in a markdown file, add a `#[cfg(test)] compile_error!("GAP-007-1: validate_and_dispatch has zero production callsites")` in the code itself. This would make the debt self-documenting and would fail if someone attempts to ship without addressing it. (This is aggressive but illustrates the principle: debt tracked in markdown is easily ignored; debt tracked in code is harder to forget.)

---

## Mental Model Mismatches

| What someone reading the verdicts thinks | What is actually true | Impact |
|----------------------------------------|----------------------|--------|
| "All 13 stories RECONCILED = the system enforces safety" | The system has well-tested guards that are not wired into a production pipeline | **HIGH** -- false confidence that Slice 1 is production-ready |
| "897 tests pass = comprehensive coverage" | ~52 of 897 tests exercise the pipeline; most are unit tests on individual guards | **MEDIUM** -- test count is not a proxy for integration coverage |
| "PROVEN = the guard works end-to-end" | PROVEN means the guard's function is correct and its AT is satisfied *at the test level*; it does not mean the guard is called in production | **HIGH** -- the term "PROVEN" suggests more than what was actually proved |
| "DEFERRED = low priority, can wait" | Three of the DEFERRED items (GAP-003-2, GAP-010-4, GAP-007-1) together represent the absence of a safety pipeline | **HIGH** -- the P1/DEFERRED classification disperses a systemic risk across separate line items |
| "0 P0, 0 P1 open = clean bill of health" | The highest-risk items were reclassified as DEFERRED rather than P1 precisely because they are "future slice" work | **MEDIUM** -- the priority system conflates "not fixable in this slice" with "not urgent" |

---

## Open Questions

1. **Is there a Slice 2 story that mandates wiring all Slice 1 guards into a production dispatch path?** If not, the deferral of GAP-003-2, GAP-010-4, and GAP-007-1 has no forcing function and could be deferred indefinitely.

2. **What is the definition of "RECONCILED"?** The current implicit definition is "all ATs satisfied at function level, no P0/P1 gaps open." Should it be "all ATs satisfied AND the guard is reachable from production code"? If the definition is tightened, 4 of the 13 stories would not qualify.

3. **Should `dispatch_consistency_passed: bool` be replaced with a proof token before Slice 2 ships?** The `ValidatedDispatch` type already exists but is not used as a pipeline input gate. This is a structural fix that prevents bypass by construction.

4. **Is the reconciliation process designed to be repeated per-slice, or was this a one-time exercise?** If per-slice, the cost needs to decrease (see Simpler Alternative). If one-time, the DEFERRED items need a different tracking mechanism.

5. **Should "PROVEN" be split into "PROVEN-UNIT" and "PROVEN-INTEGRATED" to avoid the mental model mismatch?** This would force the reconciliation to explicitly state when a guard is tested but not wired.

---

## Verdict on the Specific Questions

### 1. Are the RECONCILED verdicts honest?

**Partially.** The verdicts are honest about what they claim to prove: each guard function is correct, each AT is satisfied by a test, and each test passes. The verdicts are **not honest about what they imply**: that the system enforces safety. The gap between "each guard works" and "the system works" is not captured by the RECONCILED/NOT-RECONCILED binary.

Specifically: S1-003 (cache), S1-007 (mismatch), and S1-010 (config) are RECONCILED at the unit level but their safety properties are not enforced in production. This is noted in the DEFERRED register but not reflected in the verdict.

### 2. What does the debt register actually cost?

The 9 DEFERRED items hide one **structural gap** (no safety pipeline) behind three separate line items. Individually, each item looks deferrable. Together, they mean the system has no production safety enforcement beyond the expiry guard and NaN/Inf input validation.

Items that should NOT have been deferred without explicit systemic acknowledgment:
- GAP-007-1 (zero callsites for validate_and_dispatch)
- GAP-003-2 (PolicyGuard integration)
- GAP-010-4 (config wired into runtime)

The remaining 6 DEFERRED items (per-instrument TTL, CI param count check, reconcile loop integration, DelistingSoon state, discovery doc enhancement, decision divergence) are genuinely deferrable.

### 3. Cross-story dependencies creating a gap?

**Yes.** This is the most important finding. S1-003 + S1-007 + S1-010 together defer all three components needed for a working safety pipeline (cache -> PolicyGuard -> dispatch enforcement). The expiry guard (S1-012) is the only Slice 1 guard that is actually wired into `evaluate_base_gates` and thus reachable from production code. Every other Slice 1 safety guard exists as a tested-but-unwired function.

### 4. The "all tests pass" illusion?

**Confirmed.** 897 tests pass, but the vast majority are unit tests. Pipeline-level integration tests exist (5 test files, ~52 callsites) but they test the pipeline with **caller-provided** inputs -- they do not test that the inputs are correctly computed from upstream signals. The test for AT-920 mismatch even has an explicit `TODO(AT-920-PROD)` acknowledging this.

### 5. GAP-SYSTEMIC-1 (dead error paths)?

**More dangerous than classified.** The "structurally correct but unreachable" pattern appears in:
- `resolve_config_value` Err path (all params have defaults)
- `classify_lifecycle_error` duplicate-call path (pure function)
- `validate_and_dispatch` as a whole (zero production callsites)

The first two are genuine dead code risks. The third is not dead code -- it is *unused* code. The distinction matters: dead code is harmless until the path becomes reachable; unused code is harmless until someone believes it is active. The reconciliation process believed `validate_and_dispatch` was doing its job because it passed all tests. A developer reading the RECONCILED verdict for S1-007 could reasonably believe AT-920 is enforced in production.

### 6. Process effectiveness?

**The process was effective at finding function-level gaps** (7 new tests, 1 compilation fix, 4 PRD corrections). **It was ineffective at finding systemic gaps** (the "island of guards" problem, the proof-token gap, the mental model mismatch in PROVEN verdicts).

The cross-reviewer phase (R3) achieved unanimous agreement on all verdicts -- but unanimous agreement on function-level correctness does not compensate for a missing system-level check. The process would have been more effective with one fewer parallel agent and one additional "system integration" phase that checks: "For each guard marked PROVEN, is it reachable from production code?"
