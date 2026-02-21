# LSP Call Chain Check — Slice 1 Production Wiring Audit

**Date**: 2026-02-21
**Method**: Grep-based callsite tracing (LSP server unavailable)
**Scope**: All Slice 1 enforcement functions and types
**Question**: For each guard/function marked PROVEN in reconciliation, is it reachable from production code (`src/`) or only from tests?

---

## Summary

| Category | Count | Percentage |
|----------|-------|------------|
| **WIRED** (production callers in `src/`) | 11 | 42% |
| **NOT-WIRED** (test-only or missing) | 15 | 58% |

**Conclusion**: The strategic review's "island of guards" finding is confirmed. Over half of Slice 1 enforcement functions have zero production callers.

---

## Part A: Functions & Methods

| Function | Defined At | Production Callsites | Verdict |
|----------|-----------|----------------------|---------|
| `validate_and_dispatch` | `soldier_core/src/execution/dispatch_map.rs:179` | NONE (exported only) | **NOT-WIRED** |
| `map_to_dispatch` | `soldier_core/src/execution/dispatch_map.rs:126` | Internal to `validate_and_dispatch` only | **NOT-WIRED** |
| `build_order_size` | `soldier_core/src/execution/order_size.rs:83` | NONE (exported only) | **NOT-WIRED** |
| `quantize` | `soldier_core/src/execution/quantize.rs:186` | `base_gates.rs:291` | **WIRED** |
| `evaluate_base_gates` | `soldier_core/src/execution/base_gates.rs:226` | `open_runtime.rs:92`, `pipeline.rs:105` | **WIRED** |
| `build_order_intent` (variants) | `soldier_core/src/execution/build_order_intent.rs:81+` | `open_runtime.rs:276` | **WIRED** |
| `derive_instrument_kind` | `soldier_core/src/venue/types.rs:54` | NONE (exported only) | **NOT-WIRED** |
| `opens_blocked` | `soldier_core/src/venue/cache.rs:265` | NONE (exported only) | **NOT-WIRED** |
| `InstrumentCache::get/get_at` | `soldier_core/src/venue/cache.rs:129-136` | NONE (exported only) | **NOT-WIRED** |
| `InstrumentCache::risk_state_for` | `soldier_core/src/venue/cache.rs:190-191` | NONE (exported only) | **NOT-WIRED** |
| `InstrumentCache::insert` | `soldier_core/src/venue/cache.rs:104` | `bootstrap.rs:592` | **WIRED** |
| `resolve_config_value` | `soldier_infra/src/config.rs:433` | NONE (test-only) | **NOT-WIRED** |
| `contract_multiplier()` | `soldier_infra/src/deribit/public/mod.rs:110` | NONE (exported only) | **NOT-WIRED** |
| `GroupLock::is_expired()` | `soldier_core/src/execution/group.rs:151` | `group.rs:395` | **WIRED** |

## Part B: Types & Enums

| Type | Defined At | Production Usages in `src/` | Verdict |
|------|-----------|----------------------------|---------|
| `PolicyGuard` | **NOT FOUND** | Comments only | **NOT-WIRED** |
| `TradingMode` | **NOT FOUND** | Comments only | **NOT-WIRED** |
| `F1CertStatus` / `F1Cert` | **NOT FOUND** | Config param ref only (`F1CertFreshnessWindowS`) | **NOT-WIRED** |
| `WatchdogTimeout` | **NOT FOUND** | Config param ref only (`WatchdogKillS`) | **NOT-WIRED** |
| `LatchReason` | **NOT FOUND** | Comments in `bootstrap.rs` only | **NOT-WIRED** |
| `ValidatedDispatch` | `soldier_core/src/execution/dispatch_map.rs:76` | Exported in `mod.rs` | **WIRED** |
| `ConfigParam` | `soldier_infra/src/config.rs:13` | `config.rs` (appendix_a_default) | **WIRED** |
| `DeribitInstrument` | `soldier_infra/src/deribit/public/mod.rs:51` | Re-exported in `deribit/mod.rs` | **WIRED** |
| `SettlementPeriod` | `soldier_infra/src/deribit/public/mod.rs:32` | Re-exported in `deribit/mod.rs` | **WIRED** |
| `RiskState` | `soldier_core/src/risk/state.rs:13` | Gates, dispatch pipeline | **WIRED** |
| `InstrumentKind` | `soldier_core/src/venue/types.rs:17` | `order_size.rs`, `dispatch_map.rs`, `cache.rs` | **WIRED** |
| `QuantizeConstraints` | `soldier_core/src/execution/quantize.rs:24` | `quantize()` calls | **WIRED** |

---

## Per-Story Wiring Verdict

| Story | Key Enforcement | Wiring Status | Impact |
|-------|----------------|---------------|--------|
| **S1-001** | PolicyGuard, TradingMode, F1Cert, Watchdog | **NOT-WIRED** — types don't exist | Fundamental types missing; blocks downstream integration |
| **S1-002** | `derive_instrument_kind` | **NOT-WIRED** — no production caller | Helper defined + tested but never called from `src/` |
| **S1-003** | `InstrumentCache::get/get_at`, TTL logic | **NOT-WIRED** — no production caller | Cache populated (`insert` WIRED) but never queried in production |
| **S1-004** | `opens_blocked`, `classify_intent`, LatchReason | **NOT-WIRED** — no production caller | Open permission check exists but never invoked |
| **S1-005** | `validate_and_dispatch`, ValidatedDispatch | **PARTIAL** — type exists, function not called | Proof token defined; validation function has explicit TODO for wiring |
| **S1-006** | `InstrumentCache::risk_state_for`, breach events | **NOT-WIRED** — no production caller | Breach detection tested but unreachable at runtime |
| **S1-007** | `QuantizeConstraints`, `quantize` | **WIRED** — called via `base_gates.rs` | Quantize pipeline is fully integrated |
| **S1-008** | `RiskState` enum | **WIRED** — used in gates + dispatch | Risk states flow through the production pipeline |
| **S1-009** | `DispatchRecord` / WAL | Needs deeper investigation | Logging infrastructure |
| **S1-010** | `ConfigParam`, `resolve_config_value` | **PARTIAL** — enum WIRED, resolver NOT-WIRED | Registry exists in production; resolution function test-only |
| **S1-011** | `DeribitInstrument`, `contract_multiplier()` | **PARTIAL** — struct WIRED, method NOT-WIRED | Struct defined + exported; `contract_multiplier()` never called |
| **S1-012** | `evaluate_base_gates`, `GroupLock::is_expired` | **WIRED** — called from `open_runtime.rs`, `pipeline.rs` | Only fully-wired guard in Slice 1 |
| **S1-013** | CI gate (out of scope for runtime wiring) | N/A | Enforcement is CI/CD, not runtime code |

---

## Existing Code Acknowledgment

The codebase already documents this gap. From `test_dispatch_map.rs:586-591`:

> *"NOTE: validate_and_dispatch() currently has zero production callsites. This test validates the AT-920 mismatch detection. TODO(AT-920-PROD): When validate_and_dispatch() is wired into the production pipeline..."*

This confirms the development team is aware and has planned wiring as a future step.

---

## Reconciliation Impact

### Stories confirmed WIRED (no change needed):
- **S1-007** (quantize), **S1-008** (RiskState), **S1-012** (base_gates + expiry)

### Stories with PARTIAL wiring (types exist, functions not called):
- **S1-005** (ValidatedDispatch defined, `validate_and_dispatch` not called)
- **S1-010** (ConfigParam enum in production, resolver function not called)
- **S1-011** (DeribitInstrument in production, `contract_multiplier()` not called)

### Stories with NO production wiring:
- **S1-001** (PolicyGuard/TradingMode don't exist as types)
- **S1-002** (`derive_instrument_kind` never called)
- **S1-003** (cache lookup functions never called)
- **S1-004** (`opens_blocked` never called)
- **S1-006** (breach detection unreachable)

### Reconciliation verdict adjustment:
The Phase R6 verdicts of RECONCILED and RECONCILED-WITH-DEBT remain honest at the **unit level** — the functions work correctly when called. However, this audit reveals that most Slice 1 work is **PROVEN-UNIT** (function-level correctness) not **PROVEN-INTEGRATED** (end-to-end enforcement).

This aligns with the Strategic Review finding H1 ("Island of Guards").

---

## Recommendation

Add to Slice 2 backlog:
1. **Integration story**: Wire all NOT-WIRED enforcement functions into the production pipeline
2. **Reconciliation process enhancement**: Add mandatory "production reachability" check — for each AT marked PROVEN, verify at least one `src/` callsite exists
3. **Verdict vocabulary expansion**: Split PROVEN into PROVEN-UNIT and PROVEN-INTEGRATED
