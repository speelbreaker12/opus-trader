# Slice 1 Reconciliation — Consolidated Findings Report

> Branch: `recon/S5-004`
> HEAD: `526b99c`
> Date: 2026-02-22
> Review tools: Kimi (4 batches, Cycle 1+2), Opus generic (9/9), Opus enriched (9/9), Codex generic (9/9), Codex enriched (9/9)
> Stories covered: S1-002, S1-003, S1-004, S1-005, S1-006, S1-007, S1-010, S1-011, S1-012

## Executive Summary

- **Total unique P1 findings**: 36 (0 P0)
- **Codex digest FINDINGS_SUMMARY counts are unreliable** — the summary line often reports inflated P0/P1 counts not found in the review body
- **Systemic theme**: 6 of 9 stories have functions with zero production callsites; AT enforcement exists only in tests
- **All findings are post-fix**: reviews ran on code with all Kimi Cycle 1+2 fixes already applied

## Coverage Matrix

| Story | Kimi C1 | Kimi C2 | Opus Generic | Opus Enriched | Codex Generic | Codex Enriched |
|-------|---------|---------|--------------|---------------|---------------|----------------|
| S1-002 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-003 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-004 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-005 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-006 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-007 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-010 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-011 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| S1-012 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**9/9 stories × 6 review passes = 54 total reviews (complete)**

## Systemic Themes

### Theme 1: Zero Production Callsites (6/9 stories)

Functions exist and are tested, but never called from production code. AT enforcement is paper-only.

| Story | Dead Function | AT Affected |
|-------|--------------|-------------|
| S1-002 | `derive_instrument_kind` | AT-333 |
| S1-003 | `opens_blocked` | AT-104 |
| S1-004 | `build_order_size` | AT-277 |
| S1-005 | `validate_and_dispatch` | AT-920 |
| S1-007 | `validate_and_dispatch` | AT-920 |
| S1-010 | `resolve_config_value` | AT-040 |

**Root cause**: Slice 1 stories implemented unit-tested functions but deferred production wiring (dispatch integration) to later slices. This is structurally expected for early stories, but the ATs claim enforcement that doesn't exist yet.

### Theme 2: AT Proof is Paper-Only / Not Causally Proven (8/9 stories)

Tests claim AT compliance but don't prove causality through the enforcement point (dispatch count, reject reason, latch reason).

| Story | AT | Gap |
|-------|------|-----|
| S1-002 | AT-333 | Tests map InstrumentKind but never assert tick_size/amount_step/min_amount/contract_multiplier passthrough |
| S1-003 | AT-279 | No PolicyGuard-level test proving TradingMode::ReduceOnly within one tick from stale cache |
| S1-004 | AT-277 | Tests only cover build_order_size, not dispatcher mismatch reject/degrade |
| S1-005 | AT-920 | Mismatch-to-Degraded causality simulated in test (manual RiskState assignment), not runtime |
| S1-006 | AT-104 | Proof is unit-level (opens_blocked) — no dispatch count/reject path causality |
| S1-010 | AT-040, AT-424, AT-971 | AT-040 Err path structurally unreachable (all 74 params have defaults); AT-424/971 lack gate-level causality |
| S1-011 | AT-333 | Tests check field deserialization, not that quantization/sizing actually uses fetched metadata |
| S1-012 | AT-949/960-966 | Lifecycle terminal handling tested as enum mapping, not wired into production reconcile/cancel flow |

### Theme 3: Non-Runnable Proving Tests (3/9 stories)

Tests fail to compile due to unresolved imports:

| Story | Import Error | Module |
|-------|-------------|--------|
| S1-003 | `PricerSide` | tests/common/mod.rs |
| S1-011 | `ledger::WalWriterConfig` | store/mod.rs |
| S1-012 | `PricerSide` | tests/common/mod.rs |

### Theme 4: Missing Fail-Closed Guards (3/9 stories)

| Story | Gap |
|-------|-----|
| S1-004 | `notional_usd`/`qty_coin` can be Inf/NaN for extreme-but-finite inputs; `as i64` silently saturates |
| S1-005 | NaN/Inf/negative/zero bypasses `map_to_dispatch_unchecked` without rejection |
| S1-010 | `resolve_config_value` conflates "missing" with "unparseable" — parse errors mapped to None silently apply defaults |

### Theme 5: PRD-Named Tests Don't Exist (3/9 stories)

| Story | Missing Test Name |
|-------|------------------|
| S1-002 | `test_instrument_metadata_uses_get_instruments` |
| S1-003 | `test_instrument_cache_ttl_blocks_opens_allows_closes` |
| S1-012 | `test_expiry_cancel_idempotent_duplicate_noop` |

### Theme 6: API Design Flaws (3/9 stories)

| Story | Finding |
|-------|---------|
| S1-007 | `dispatch_consistency_passed` is a bare bool, bypassable by callers; atomic reject+degrade not enforced |
| S1-006 | `instrument_cache_hits_total` only counts hits, not all accesses (PRD semantic mismatch) |
| S1-011 | Strict `DeribitInstrumentKind`/`SettlementPeriod` enums cause total batch deserialization failure on any unknown venue value |

---

## Per-Story Findings

### S1-002 — InstrumentKind Mapping

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | `derive_instrument_kind` has zero production callsites — mapping logic is orphaned/dead code | opus-generic, codex-enriched |
| 2 | P1 | AT-333 proof gap: tests never assert tick_size/amount_step/min_amount/contract_multiplier passthrough into quantization | codex-enriched, opus-generic |
| 3 | P1 | PRD requires `test_instrument_metadata_uses_get_instruments` but it doesn't exist; `test_get_instruments_realistic_payloads` only checks enum booleans | codex-enriched |
| 4 | P1 | `derive_instrument_kind` is fail-open on contradictory flags (is_option=true AND is_future=true resolves to Option); test locks in this behavior | codex-generic |

### S1-003 — Instrument Cache TTL

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | `opens_blocked` has zero production callsites — AT-104 gate may be paper-only | opus-generic |
| 2 | P1 | AT-279 proof incomplete: no PolicyGuard-level test proving TradingMode::ReduceOnly within one tick from stale cache | codex-enriched |
| 3 | P1 | PRD names `test_instrument_cache_ttl_blocks_opens_allows_closes` but it doesn't exist; present test is non-causal | codex-enriched |
| 4 | P1 | Cross-file AT-104 causality test fails to compile: unresolved import `PricerSide` in common/mod.rs | codex-enriched |

### S1-004 — Order Sizing

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | `build_order_size` has zero production callsites — AT-277 enforcement exists only in tests | opus-enriched |
| 2 | P1 | AT-277 paper-proof gap: tests only cover build_order_size construction, not dispatcher mapping or mismatch reject/degrade | codex-enriched |
| 3 | P1 | `notional_usd`/`qty_coin` can be Inf/NaN for extreme-but-finite inputs; function returns Ok with non-finite internals | codex-enriched |
| 4 | P1 | `(qty/mult).round() as i64` silently saturates to i64::MAX on large finite values instead of returning error | codex-enriched, codex-generic |
| 5 | P1 | `with_intent_trace_ids` not panic-safe: if closure panics, stale trace IDs leak into subsequent metrics on same thread | codex-generic |

### S1-005 — Canonical Amount Mapping

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | AT-920 enforcement dead code: `validate_and_dispatch` has zero production callsites | opus-generic, codex-generic, codex-enriched |
| 2 | P1 | `validate_and_dispatch` returns Err on mismatch but never communicates RiskState::Degraded — undocumented caller convention | opus-generic |
| 3 | P1 | NaN/Inf/negative/zero amount bypasses `map_to_dispatch_unchecked` without rejection — premortem §3 mitigation missing | opus-enriched, codex-enriched |
| 4 | P1 | AT-920 mismatch-to-Degraded causality simulated in test (manual RiskState assignment), not enforced by runtime | codex-enriched |

### S1-006 — Cache Observability

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | No structured log emitted on TTL breach — implementation only buffers CacheTtlBreach events; no `tracing::warn!` in stale path | codex-enriched, codex-generic |
| 2 | P1 | AT-104 proof is unit-level only (`opens_blocked`) — does not prove dispatch count or reject path causality | codex-enriched, codex-generic |
| 3 | P1 | `instrument_cache_hits_total` increments only on cache hit; PRD says count all accesses — semantic mismatch | codex-enriched, codex-generic |

### S1-007 — Dispatch Consistency

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | `dispatch_consistency_passed` is a bare bool — AT-920 bypassable by any caller passing true without running `validate_and_dispatch` | opus-generic, codex-enriched, codex-generic |
| 2 | P1 | `validate_and_dispatch` has zero production callsites — AT-920 mismatch+Degraded never enforced in production | opus-generic |
| 3 | P1 | API shape doesn't enforce atomic reject+degrade — `validate_and_dispatch` returns error-only on mismatch; test manually sets RiskState::Degraded | codex-enriched, codex-generic |

### S1-010 — Config Resolution

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | AT-040 Err path structurally unreachable: all 74 ConfigParam variants have defaults so fail-closed branch has zero exercised coverage | opus-generic, opus-enriched, codex-enriched |
| 2 | P1 | `resolve_config_value` only called in tests — no enforcement point (PolicyGuard, EvidenceGuard, InstrumentCache) consumes the config resolver | opus-enriched |
| 3 | P1 | AT-424/AT-971 tests validate resolver output only, not gate-level causality (no reject/latch/decision path proven) | codex-enriched |
| 4 | P1 | `resolve_config_value` conflates "missing" with "unparseable" — parse errors mapped to None silently apply defaults instead of failing closed | codex-enriched |
| 5 | P1 | `position_reconcile_epsilon` hardcoded to 1e-6 but contract requires `max(1e-6, instrument min_amount)`, causing persistent latch blocks for larger-step instruments | codex-generic |

### S1-011 — Instrument Batch Deserialization

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | AT-333 not causally proven — tests check field deserialization existence but not that quantization/sizing actually uses fetched metadata values | codex-enriched |
| 2 | P1 | `amount_step` is `Option` with `serde(default)`, tests accept its absence — contradicts acceptance requiring all four sizing fields present | codex-enriched |
| 3 | P1 | Proving tests non-runnable — cargo test fails to compile: unresolved import `ledger::WalWriterConfig` in store/mod.rs | codex-enriched |
| 4 | P1 | Missing `option_combo` deserialization test — broken serde rename would not be caught; acceptance explicitly requires this variant | opus-generic, opus-enriched |
| 5 | P1 | Strict `DeribitInstrumentKind`/`SettlementPeriod` enums cause total batch deserialization failure on any unknown venue value | opus-generic |

### S1-012 — Expiry Lifecycle

| # | Severity | Finding | Tools |
|---|----------|---------|-------|
| 1 | P1 | AT-949/960/961/962/966 lifecycle terminal handling not wired into production reconcile/cancel flow — tests prove enum mapping only | codex-enriched |
| 2 | P1 | Proving tests non-runnable — cargo test fails to compile: unresolved import `PricerSide` in tests/common/mod.rs | codex-enriched |
| 3 | P1 | AT-960 has no proving test for duplicate cancel idempotency — premortem lists `test_expiry_cancel_idempotent_duplicate_noop` but it doesn't exist | opus-enriched |

---

## Tool Effectiveness Analysis

### Unique Findings by Tool (deduplicated)

| Tool × Prompt | Unique Findings | % of Total |
|---------------|----------------|------------|
| Codex enriched | 14 unique | 39% |
| Codex generic | 4 unique | 11% |
| Opus enriched | 3 unique | 8% |
| Opus generic | 5 unique | 14% |
| Multi-tool overlap | 10 | 28% |

### What Each Tool Catches Best

| Tool | Strength |
|------|----------|
| **Codex enriched** | AT clause-by-clause proof gaps, premortem conformance gaps, non-runnable test detection, missing PRD-named tests |
| **Codex generic** | Numeric edge cases (saturating casts, epsilon), panic safety, production behavior quirks |
| **Opus enriched** | Missing specific tests referenced in premortem/PRD, zero production callsite detection |
| **Opus generic** | Zero production callsite detection, API design flaws, broad code quality issues |

### Recommendation

Running both prompt styles (generic + enriched) with both tools (opus + codex) catches the widest range:
- Generic prompts find **code-level** issues (numeric overflow, panic safety, dead code)
- Enriched prompts find **contract-level** issues (AT proof gaps, premortem conformance, missing named tests)
- Codex's agent mode explores more deeply but produces noisier output
- Opus produces more structured, concise findings

---

## Note on FINDINGS_SUMMARY Reliability

Codex digest files report inflated P0 counts (e.g., P0=5 P1=3) via the `FINDINGS_SUMMARY:` line, but no P0-labeled findings appear in the actual review bodies. The summary line appears to be an auto-generated aggregate that double-counts or miscategorizes findings. **Use review body content, not digest summary counts, for severity assessment.**
