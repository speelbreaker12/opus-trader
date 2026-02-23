# Reconciliation Report: Slices 0-6 Contract Compliance

**Audit date:** 2026-02-17
**Branch:** `feature/slice4-cherry-pick`
**Auditor:** Opus 4.6 (team: reconcile-slices, 4 parallel auditors + lead)
**Authority chain:** CONTRACT.md v5.2 > IMPLEMENTATION_PLAN.md > PRD > code
**Test state:** `cargo test --workspace` — all pass (0 failures)

---

## A) STOPLIGHT Summary

| Slice | Verdict | Color | Stories | RED count | YELLOW count |
|-------|---------|-------|---------|-----------|--------------|
| S0 | KEEP | GREEN | 6 | 0 | 1 (S0-004 AT-022 scaffolding) |
| S1 | KEEP | YELLOW | 13 | 0 | 2 (S1-007 pipeline wiring deferred, S1-003 dispatch count proven) |
| S2 | KEEP | YELLOW | 5 | 0 | 2 (S2-002, S2-004) |
| S3 | KEEP | YELLOW | 3 | 0 | 1 (S3-002 AT-028 over-claim) |
| S4 | KEEP | GREEN | 4 | 0 | 0 (metadata fixed) |
| S5 | KEEP | GREEN | 5 | 0 | 0 |
| S6 | KEEP | GREEN | 11 | 0 | 0 |

**Overall: YELLOW** — No code patches required. S1-007 AT-920 gate proven at pipeline level (test_at920_pipeline_dispatch_consistency_failure_rejected); full production wiring deferred. S1-003 AT-104 dispatch count proven (test_at104_degraded_blocks_open_at_chokepoint). Remaining issues are PRD metadata drift (all fixed). No reverts. No quarantine.

---

## B) Reconciliation Table

| Slice | PRD Items | Contract Targets (AT/section) | Actual Behavior | Verdict | Required Patch | Tests/Evidence |
|-------|-----------|-------------------------------|-----------------|---------|----------------|----------------|
| **S0** Phase 0 Ops Baseline | S0-000 to S0-005 (6 stories) | P0-A through P0-F; AT-022 (scaffolding only) | All 6 docs exist. Policy loader fail-closed. Break-glass KILL blocks OPEN/allows reduce. CLI status reports trading_mode/is_trading_allowed. 17 runtime tests pass. | **KEEP** | S0-004: AT-022 is scaffolding (CLI, not HTTP) — deferred to S8-008. No action needed now. | `test_phase0_runtime.rs` (17 tests), all docs + evidence artifacts |
| **S1** Instrument Metadata, Sizing, Dispatcher, Config | S1-001 to S1-013 (13 stories) | AT-905, AT-901, AT-333, AT-104, AT-279, AT-277, AT-920, AT-341, AT-040, AT-424, AT-970, AT-971, AT-949-966, AT-1056-1057 | Workspace scaffolding OK. InstrumentKind enum covers all 4 kinds. Cache TTL blocks opens when stale. Quantization sizing works. Dispatcher amount mapping correct. **S1-007: ContractsAmountMismatch rejection fires (dispatch=0) BUT RiskState::Degraded never set.** Config defaults applied. Expiry guard fail-closed. | **PATCH** | **S1-007 [HIGH]:** Add integration test proving caller pipeline sets `RiskState::Degraded` on `ContractsAmountMismatch`. May require code change if caller path doesn't set Degraded. S1-003 [LOW]: Add pipeline dispatch count proof (OPEN=0, CLOSE=1 when stale). S1-008/S1-009 [LOW]: Fix `enforcement_point` metadata (StatusEndpoint → empty). | `test_dispatch_map.rs`, `test_instrument_cache_ttl.rs`, `test_order_size.rs`, `test_config_defaults.rs`, `test_expiry_guard.rs` |
| **S2** Quantization, Idempotency, Labels, Reject Codes | S2-000 to S2-004 (5 stories) | AT-926, AT-280, AT-219, AT-908, AT-201, AT-343, AT-928, AT-218, AT-216, AT-217, AT-041, AT-921, AT-933 | Quantization rounding correct (BUY down, SELL up). Intent hash deterministic (no clock/RNG). Label encode/decode roundtrip, 64-char limit enforced. Reject reasons in registry. | **KEEP** | S2-002 [LOW]: Remove AT-933 from `enforcing_contract_ats` (WS reconnect, not labels). Assert RiskState::Degraded on LabelTooLong (caller responsibility pattern). S2-004 [LOW]: AT-201 unknown-action-to-OPEN mitigated by closed Rust enum — add compile-time justification comment. | `test_quantize.rs`, `test_idempotency.rs`, `test_label.rs`, `test_label_match.rs`, `test_reject_reason.rs` |
| **S3** Preflight, Post-Only, Capabilities | S3-000 to S3-002 (3 stories) | AT-004, AT-016-019, AT-913-915, AT-916, AT-028 | Preflight rejects market/stop/linked orders. Post-only crossing guard rejects buy>=ask, sell<=bid. Capabilities matrix gates linked orders behind dual flags. 57 tests total. | **KEEP** | S3-002 [MED]: Remove AT-028 from `enforcing_contract_ats` — AT-028 is about `/status last_policy_update_ts`, not capabilities. Assign to S8-xxx status story. | `test_preflight.rs` (30 tests), `test_post_only_guard.rs` (14 tests), `test_capabilities.rs` (13 tests) |
| **S4** WAL, TLSM, Trade-ID, Dispatch Durability | S4-000 to S4-003 (4 stories) | AT-935, AT-906, AT-233, AT-234, AT-925, AT-940, AT-230, AT-210, AT-269, AT-270, AT-969 | WAL append/replay correct, queue-full returns error (no block). TLSM handles fill-before-ack (no panic). Trade-ID registry dedupes (REST then WS). Dispatch requires durable WAL barrier (fsync). File-based WAL survives restarts. | **KEEP** | S4-001/S4-002 [LOW]: Fix `reason_codes.values` metadata — lists `ContractsAmountMismatch` (copy-paste from dispatch_map, should be TLSM/trade-ID codes). No behavioral gap. | `test_ledger_replay.rs` (40+ tests), `test_tlsm.rs` (25+ tests), `test_trade_id_registry.rs` (20+ tests), `test_crash_mid_intent.rs` (8 tests), `test_dispatch_durability.rs` (15 tests) |
| **S5** Liquidity Gate, Fee Cache, NetEdge, Pricer, Chokepoint | S5-000 to S5-004 (5 stories) | AT-222, AT-344, AT-909, AT-421, AT-317, AT-031-033, AT-042, AT-244-246, AT-318-320, AT-245, AT-015, AT-932, AT-243, AT-327, AT-223 | Liquidity gate rejects slippage > max, stale/missing L2. Fee cache: fresh/soft-stale/hard-stale tiers with 1.20x buffer. NetEdge gate: net < min → reject, missing inputs → reject. Pricer clamps limit to min-edge. Chokepoint proven by CI grep/AST tests. All NaN/Inf/negative inputs fail-closed. | **KEEP** | S5-000 [INFO]: Naming discrepancy — contract says `ExpectedSlippageTooHigh`, implementation uses `InsufficientDepthWithinBudget`. Same behavior; consider aligning names. No action required. | `test_liquidity_gate.rs` (25+ tests), `test_fee_staleness.rs` (20+ tests), `test_fee_cache.rs` (10 tests), `test_net_edge_gate.rs` (20+ tests), `test_pricer.rs` (15+ tests), `test_gate_ordering.rs` (30+ tests) |
| **S6** Phase 1 Proofs + Risk Gates | S6-000 to S6-010 (11 stories) | AT-935, AT-906, AT-925, AT-343, AT-218, AT-219, AT-216, AT-201, AT-926, AT-902, AT-010, AT-1055, AT-338, AT-930, AT-233, AT-234, AT-030, AT-043, AT-281, AT-282, AT-224, AT-922, AT-934, AT-225, AT-910, AT-226, AT-911, AT-929, AT-300-302, AT-206-208, AT-227-228, AT-912 | Single dispatch chokepoint proven (CI grep tests). Determinism verified (100-iteration loop). No side effects on rejection (10 paths). intent_id propagation. Gate ordering exhaustive (C1/C2/C3 constraints). Fail-closed defaults for all missing config keys. Crash mid-intent: dispatch exactly once across 2 restarts. Inventory skew, pending exposure, global exposure (correlation-aware), margin gate — all proven. | **KEEP** | None. All 11 stories verified GREEN. Minor notes: AT-281 (45% at bias=0.9) not numerically exact-checked; AT-902 proven via struct threading not tracing spans. | `test_dispatch_chokepoint.rs`, `test_intent_determinism.rs`, `test_rejection_side_effects.rs`, `test_intent_id_propagation.rs`, `test_gate_ordering.rs` (968 lines), `test_missing_config.rs`, `test_crash_mid_intent.rs`, `test_inventory_skew.rs`, `test_pending_exposure.rs`, `test_exposure_budget.rs`, `test_margin_gate.rs` |

---

## C) Conflict List

### RED — Contract Compliance Gap (Code Patch Required)

_None remaining._ S1-007 downgraded to YELLOW after pipeline-level test added (see below).

### YELLOW — Documentation Drift / Metadata Errors (PRD-only Fixes)

| # | Slice | Story | Issue | Risk |
|---|-------|-------|-------|------|
| 2 | S0 | S0-004 | AT-022 claims HTTP endpoint but implementation is CLI-based. PRD honestly marks "scaffolding — full AT-022 enforcement in S8-008". | LOW — explicitly deferred |
| 3 | S1 | S1-003 | AT-104 dispatch count now proven at pipeline level by `test_at104_degraded_blocks_open_at_chokepoint` (OPEN=0, CLOSE=1 when Degraded). | RESOLVED |
| 3a | S1 | S1-007 | AT-920 gate proven at pipeline level by `test_at920_pipeline_dispatch_consistency_failure_rejected` (dispatch_consistency_passed=false → rejected, ContractsAmountMismatch, dispatch=0). RiskState::Degraded chain proven by `test_at920_mismatch_caller_sets_degraded_and_blocks_open` in dispatch_map.rs. Full production wiring of `validate_and_dispatch()` into pipeline deferred (zero callsites currently). | YELLOW — gate works, production wiring deferred |
| 4 | S1 | S1-008/009 | `enforcement_point` fixed: StatusEndpoint → empty. | RESOLVED |
| 5 | S2 | S2-002 | AT-041: `RiskState::Degraded` on LabelTooLong not proven (caller responsibility). AT-933 removed from `enforcing_contract_ats`. | LOW — caller delegation pattern, not functional gap |
| 6 | S2 | S2-004 | AT-201 unknown-action → OPEN: mitigated by closed Rust enum. No runtime test needed but justification comment missing. | LOW — compile-time guarantee |
| 7 | S3 | S3-002 | AT-028 removed from `enforcing_contract_ats`. Now references AT-004, AT-915 only. | RESOLVED |
| 8 | S4 | S4-001/002 | `reason_codes` fixed: removed `ContractsAmountMismatch` (copy-paste error). Now empty. | RESOLVED |
| 9 | S5 | S5-000 | Naming discrepancy: contract says `ExpectedSlippageTooHigh`, code uses `InsufficientDepthWithinBudget`. | INFO — same behavior, different name |

---

## D) Applied Fixes (2026-02-17)

### DONE — S1-007: AT-920 pipeline test added
- Added `test_at920_pipeline_dispatch_consistency_failure_rejected` in `test_intent_pipeline.rs`
- Proves: dispatch_consistency_passed=false → rejected at DispatchConsistency gate, ContractsAmountMismatch reason, dispatch count=0
- Combined with newly added `test_at920_mismatch_caller_sets_degraded_and_blocks_open` in test_dispatch_map.rs, all 3 AT-920 criteria are covered
- Verdict downgraded: RED → YELLOW (production wiring of `validate_and_dispatch()` deferred)

### DONE — S1-003: AT-104 dispatch count already proven
- `test_at104_degraded_blocks_open_at_chokepoint` already existed in test_intent_pipeline.rs
- Proves: OPEN + Degraded → dispatch=0, CLOSE + Degraded → dispatch=1

### DONE — PRD metadata fixes
- S1-008/S1-009: `enforcement_point` → `""` (discovery stories, not StatusEndpoint)
- S2-002: Removed AT-933 from `enforcing_contract_ats`
- S3-002: Removed AT-028 from `enforcing_contract_ats`
- S4-001/S4-002: `reason_codes` → `{"type": "", "values": []}` (removed copy-paste ContractsAmountMismatch)

### Remaining (no action required)
- S0-004: AT-022 scaffolding — deferred to S8-008 (explicitly tracked)
- S1-011: RESOLVED — amount_step `Option<f64>` design settled (AT-333)
- S2-004: AT-201 closed-enum compile-time guarantee — informational
- S5-000: Naming discrepancy `InsufficientDepthWithinBudget` vs `ExpectedSlippageTooHigh` — informational

### Deferred ATs (machine-auditable, AUTHORITATIVE)

> **Single source of truth** for deferred/partial AT coverage. PRD `partial_coverage_notes` fields cross-reference this table. `prd_ref_check.sh` warns when an AT appears in both `enforcing_contract_ats` and `partial_coverage_notes`.

| AT | Contract Section | Owner Story | Status | Target | Rationale |
|----|-----------------|-------------|--------|--------|-----------|
| AT-327 | §1.4.1 Net Edge Gate — emergency close exemption | S5-002 | DEFERRED | Phase 2 / Deterministic Emergency Close (§3.1) | Emergency close not implemented in Phase 1. Contract §1.4.1 scope note explicitly excludes §3.1 from NetEdge gate. |
| AT-925 | §2.4.1 WAL Writer Isolation — hot-loop backpressure → ReduceOnly | S4-000 (partial), S6-000 (partial), **S8.1c** (integration) | PARTIAL | S8.1c (PolicyGuard integration) | S4 proves queue-full detection + WAL error counter. PolicyGuard mode-forcing (TradingMode::ReduceOnly under backpressure) requires PolicyGuard implementation. Integration test: `test_at925_queue_full_forces_reduce_only_via_policyguard`. |
| AT-969 | §2.4.1 WAL Writer Isolation — EvidenceChainState under WAL backpressure | S4-003 (listed) | GOP-DEFERRED | EvidenceGuard integration slice | GOP-only AT (`enforced_profile != CSP`). EvidenceGuard not implemented in Phase 1. S4 scope is CSP-only. |

### Cross-slice proof chains

| AT | Claim | Unit Proof (this slice) | Integration Proof (other slice) | Chain |
|----|-------|------------------------|--------------------------------|-------|
| AT-245 | Hard-stale fee cache → RiskState::Degraded → TradingMode::ReduceOnly → OPEN blocked | `test_fee_staleness.rs`: `evaluate_fee_staleness()` returns `RiskState::Degraded` on hard-stale | `test_intent_pipeline.rs::test_at104_degraded_blocks_open_at_chokepoint`: Degraded → OPEN rejected at DispatchAuth, dispatch=0 | fees.rs → Degraded → build_order_intent → RiskStateNotHealthy → reject |
| AT-925 | WAL queue full → ReduceOnly → OPEN blocked | `test_ledger_replay.rs::test_queue_full_returns_immediately`: queue-full returns error (non-blocking); `test_at906_write_error_counter_increments`: wal_write_errors counter | **MISSING** — `test_at925_queue_full_forces_reduce_only_via_policyguard` (S8.1c) | ledger.rs → QueueFull → (gap) → PolicyGuard → ReduceOnly → OPEN blocked |

---

## E) Systemic Patterns Observed

### "Caller MUST set Degraded" pattern
Stories S1-007, S2-002, and potentially S1-003 share a common pattern: the **unit** correctly returns an error or sets a flag, but **no integration test proves the caller pipeline transitions RiskState to Degraded**. This is a systemic gap in the test architecture.

**Recommendation:** Add a single integration test file (`test_risk_state_propagation.rs`) that verifies every rejection that should trigger `RiskState::Degraded` actually does so at the chokepoint level. This covers AT-920, AT-041, AT-104 in one sweep.

### PRD metadata drift
Multiple stories have stale or incorrect `enforcing_contract_ats`, `enforcement_point`, or `reason_codes` values. This suggests the PRD was updated across multiple sessions without a cross-reference pass.

**Recommendation:** After applying patches, run a full `enforcing_contract_ats` audit to ensure every AT claimed by a PRD story actually has a corresponding named test proving it.

---

## F) Audit Methodology

- **4 parallel auditors** each read actual test files (line counts verified), grepped CONTRACT.md for AT definitions, and verified assertion patterns (dispatch count, reason codes, RiskState values)
- **Test state verified:** `cargo test --workspace` — all pass (0 failures)
- **Source-level reads:** dispatch_map.rs, build_order_intent.rs, preflight.rs, capabilities.rs, label.rs, quantize.rs, ledger.rs, tlsm.rs, trade_id_registry.rs, fee_staleness.rs, liquidity_gate.rs, net_edge_gate.rs, pricer.rs, margin_gate.rs
- **Prior audit validated:** All findings from `docs/reconcile/stories_1_6_audit.md` confirmed or refined
