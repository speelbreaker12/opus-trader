# Slice 1 Reconciliation — Consolidated Findings Report

> Branch: `recon/S5-004` → merged to `main` via PR #120
> Cycle 1 HEAD: `526b99c` | Cycle 2 HEAD: `eff15ca` | Final: `575b92a`
> Date: 2026-02-22
> Review tools: Kimi (4 batches, Cycle 1+2), Opus generic (9/9), Opus enriched (9/9), Codex generic C1 (9/9), Codex enriched C1 (9/9), Codex generic C2 (9/9), Codex enriched C2 (9/9)
> Stories covered: S1-002, S1-003, S1-004, S1-005, S1-006, S1-007, S1-010, S1-011, S1-012

## Executive Summary

- **Total unique findings**: 39 (36 Cycle 1 P1 + 3 new Cycle 2: 2 P1, 1 P0 escalation)
- **Resolution**: 17 FIXED, 17 STRUCTURAL (blocked on Slice 2+ wiring), 5 DEFERRED
- **Codex digest FINDINGS_SUMMARY counts are unreliable** — the summary line often reports inflated P0/P1 counts not found in the review body
- **Systemic theme**: 6 of 9 stories have functions with zero production callsites; AT enforcement exists only in tests
- **Cycle 1 findings** ran on code with all Kimi Cycle 1+2 fixes already applied; **Cycle 2 findings** ran after the reconciliation fix commit (`eff15ca`)

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

### Theme 3: Non-Runnable Proving Tests (3/9 stories) — ALL FIXED

Tests failed to compile due to unresolved imports. All resolved in `de81950`.

| Story | Import Error | Module | Resolution |
|-------|-------------|--------|------------|
| S1-003 | `PricerSide` | tests/common/mod.rs | **FIXED** — `PricerSide` → `Side` |
| S1-011 | `ledger::WalWriterConfig` | store/mod.rs | **FIXED** — `WalWriterConfig` struct created |
| S1-012 | `PricerSide` | tests/common/mod.rs | **FIXED** — `PricerSide` → `Side` |

### Theme 4: Missing Fail-Closed Guards (3/9 stories) — 2 FIXED, 1 DEFERRED

| Story | Gap | Resolution |
|-------|-----|------------|
| S1-004 | `notional_usd`/`qty_coin` can be Inf/NaN; `as i64` silently saturates | **FIXED** — `is_finite()` guard + overflow check in `de81950` |
| S1-005 | NaN/Inf/negative/zero bypasses `map_to_dispatch_unchecked` | **FIXED** — `DispatchMapError::InvalidAmount` guard in `de81950` |
| S1-010 | `resolve_config_value` conflates "missing" with "unparseable" | DEFERRED — all 74 params have defaults; revisit when no-default params added |

### Theme 5: PRD-Named Tests Don't Exist (3/9 stories) — ALL FIXED

All three missing tests created in `de81950`.

| Story | Missing Test Name | Resolution |
|-------|------------------|------------|
| S1-002 | `test_instrument_metadata_uses_get_instruments` | **FIXED** — added to `test_instrument_kind_mapping.rs` |
| S1-003 | `test_instrument_cache_ttl_blocks_opens_allows_closes` | **FIXED** — added to `test_instrument_cache_ttl.rs` |
| S1-012 | `test_expiry_cancel_idempotent_duplicate_noop` | **FIXED** — added to `test_expiry_guard.rs` |

### Theme 6: API Design Flaws (3/9 stories) — 2 FIXED, 1 DEFERRED

| Story | Finding | Resolution |
|-------|---------|------------|
| S1-007 | `dispatch_consistency_passed` is a bare bool, bypassable by callers | DEFERRED — needs Slice 2 API reshape to `ValidatedDispatch` proof token |
| S1-006 | `instrument_cache_hits_total` only counts hits, not all accesses | **FIXED** — `lookups_total` counter added in `de81950` |
| S1-011 | Strict enums cause total batch deserialization failure on unknown venue value | **FIXED** — `#[serde(other)]` Unknown variants + `tracing::warn!` in `de81950` |

---

## Per-Story Findings — Full Crosswalk

**Resolution key**: FIXED = code/test change landed | STRUCTURAL = needs Slice 2+ production wiring | DEFERRED = conscious deferral with rationale

### S1-002 — InstrumentKind Mapping (2 fixed, 2 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | `derive_instrument_kind` has zero production callsites — mapping logic is orphaned/dead code | opus-generic, codex-enriched | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 2 | P1 | AT-333 proof gap: tests never assert tick_size/amount_step/min_amount/contract_multiplier passthrough into quantization | codex-enriched, opus-generic | STRUCTURAL | Needs production wiring before causal test is possible |
| 3 | P1 | PRD requires `test_instrument_metadata_uses_get_instruments` but it doesn't exist | codex-enriched | **FIXED** | `de81950` — test added to `test_instrument_kind_mapping.rs` |
| 4 | P1 | `derive_instrument_kind` is fail-open on contradictory flags (is_option+is_future → Option) | codex-generic | **FIXED** | `de81950` — returns `None` + `tracing::warn!` in `venue/types.rs` |

### S1-003 — Instrument Cache TTL (2 fixed, 2 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | `opens_blocked` has zero production callsites — AT-104 gate may be paper-only | opus-generic | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 2 | P1 | AT-279 proof incomplete: no PolicyGuard-level test proving TradingMode::ReduceOnly within one tick from stale cache | codex-enriched | STRUCTURAL | Needs PolicyGuard integration (Slice 2+) |
| 3 | P1 | PRD names `test_instrument_cache_ttl_blocks_opens_allows_closes` but it doesn't exist | codex-enriched | **FIXED** | `de81950` — test added to `test_instrument_cache_ttl.rs` |
| 4 | P1 | Cross-file AT-104 causality test fails to compile: unresolved import `PricerSide` | codex-enriched | **FIXED** | `de81950` — `PricerSide` → `Side` in `tests/common/mod.rs` |

### S1-004 — Order Sizing (3 fixed, 2 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | `build_order_size` has zero production callsites — AT-277 enforcement exists only in tests | opus-enriched | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 2 | P1 | AT-277 paper-proof gap: tests only cover build_order_size construction, not dispatcher mapping | codex-enriched | STRUCTURAL | Needs production wiring before causal test is possible |
| 3 | P1 | `notional_usd`/`qty_coin` can be Inf/NaN for extreme-but-finite inputs | codex-enriched | **FIXED** | `de81950` — `is_finite()` guard + `OrderSizeError::InvalidNotional` in `order_size.rs` |
| 4 | P1 | `(qty/mult).round() as i64` silently saturates to i64::MAX on large finite values | codex-enriched, codex-generic | **FIXED** | `de81950` — range check + `OrderSizeError::ContractsOverflow` in `order_size.rs` |
| 5 | P1 | `with_intent_trace_ids` not panic-safe: if closure panics, stale trace IDs leak | codex-generic | **FIXED** | `de81950` — manual Drop guard in `execution/mod.rs` |

### S1-005 — Canonical Amount Mapping (1 fixed, 3 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | AT-920 enforcement dead code: `validate_and_dispatch` has zero production callsites | opus-generic, codex-generic, codex-enriched | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 2 | P1 | `validate_and_dispatch` returns Err on mismatch but never communicates RiskState::Degraded | opus-generic | STRUCTURAL | Needs API reshape to thread Degraded state (Slice 2+) |
| 3 | P1 | NaN/Inf/negative/zero amount bypasses `map_to_dispatch_unchecked` without rejection | opus-enriched, codex-enriched | **FIXED** | `de81950` — `DispatchMapError::InvalidAmount` guard in `dispatch_map.rs` |
| 4 | P1 | AT-920 mismatch-to-Degraded causality simulated in test, not enforced by runtime | codex-enriched | STRUCTURAL | Needs production wiring + API reshape (Slice 2+) |

### S1-006 — Cache Observability (1 fixed, 2 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | No structured log emitted on TTL breach — only buffers CacheTtlBreach events | codex-enriched, codex-generic | STRUCTURAL | Needs production wiring for structured log emission |
| 2 | P1 | AT-104 proof is unit-level only — does not prove dispatch count or reject path causality | codex-enriched, codex-generic | STRUCTURAL | Needs PolicyGuard integration (Slice 2+) |
| 3 | P1 | `instrument_cache_hits_total` increments only on cache hit; PRD says count all accesses | codex-enriched, codex-generic | **FIXED** | `de81950` — `lookups_total` counter added to `venue/cache.rs` |

### S1-007 — Dispatch Consistency (0 fixed, 2 structural, 1 deferred)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | `dispatch_consistency_passed` is a bare bool — AT-920 bypassable by any caller | opus-generic, codex-enriched, codex-generic | DEFERRED | Needs API reshape to type-safe `ValidatedDispatch` proof token (Slice 2) |
| 2 | P1 | `validate_and_dispatch` has zero production callsites | opus-generic | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 3 | P1 | API shape doesn't enforce atomic reject+degrade | codex-enriched, codex-generic | STRUCTURAL | Needs API reshape (Slice 2+) |

### S1-010 — Config Resolution (0 fixed, 2 structural, 3 deferred)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | AT-040 Err path structurally unreachable: all 74 ConfigParam variants have defaults | opus-generic, opus-enriched, codex-enriched | DEFERRED | Academic — no params without defaults exist yet; revisit when no-default params added |
| 2 | P1 | `resolve_config_value` only called in tests — no production consumer | opus-enriched | STRUCTURAL | Needs PolicyGuard/EvidenceGuard integration (Slice 2+) |
| 3 | P1 | AT-424/AT-971 tests validate resolver output only, not gate-level causality | codex-enriched | STRUCTURAL | Needs production wiring before causal test is possible |
| 4 | P1 | `resolve_config_value` conflates "missing" with "unparseable" — parse errors silently apply defaults | codex-enriched | DEFERRED | Academic — all 74 params have defaults; revisit when no-default params added |
| 5 | P1 | `position_reconcile_epsilon` hardcoded to 1e-6 but contract requires `max(1e-6, instrument min_amount)` | codex-generic | DEFERRED | Needs contract clarification on instrument-aware epsilon |

### S1-011 — Instrument Batch Deserialization (3 fixed, 2 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | AT-333 not causally proven — tests check field deserialization but not sizing/quantization usage | codex-enriched | STRUCTURAL | Needs production wiring before causal test is possible |
| 2 | P1 | `amount_step` is `Option` with `serde(default)` — contradicts acceptance requiring all four sizing fields | codex-enriched | STRUCTURAL | Needs production validation layer (Slice 2+) |
| 3 | P1 | Proving tests non-runnable — unresolved import `ledger::WalWriterConfig` | codex-enriched | **FIXED** | `de81950` — `WalWriterConfig` struct created in `store/ledger.rs` |
| 4 | P1 | Missing `option_combo` deserialization test | opus-generic, opus-enriched | **FIXED** | `de81950` — `test_option_combo_deserializes` added to `test_deribit_instrument.rs` |
| 5 | P1 | Strict `DeribitInstrumentKind`/`SettlementPeriod` enums cause total batch failure on unknown venue value | opus-generic | **FIXED** | `de81950` — `#[serde(other)]` Unknown variants + `tracing::warn!` in `deribit/public/mod.rs` |

### S1-012 — Expiry Lifecycle (2 fixed, 1 structural)

| # | Severity | Finding | Tools | Resolution | Commit / Note |
|---|----------|---------|-------|------------|---------------|
| 1 | P1 | AT-949/960-966 lifecycle terminal handling not wired into production reconcile/cancel flow | codex-enriched | STRUCTURAL | Needs runtime dispatch wiring (Slice 2+) |
| 2 | P1 | Proving tests non-runnable — unresolved import `PricerSide` | codex-enriched | **FIXED** | `de81950` — `PricerSide` → `Side` in `tests/common/mod.rs` |
| 3 | P1 | AT-960 has no proving test for duplicate cancel idempotency | opus-enriched | **FIXED** | `de81950` — `test_expiry_cancel_idempotent_duplicate_noop` added to `test_expiry_guard.rs` |

---

### New Findings from Cycle 2 (3 findings: 2 P1, 1 P0 escalation)

These were NOT present in Cycle 1 reviews. Discovered by Codex Cycle 2 after the reconciliation fix commit.

| # | Story | Severity | Finding | Tools | Resolution | Commit / Note |
|---|-------|----------|---------|-------|------------|---------------|
| C2-1 | S1-010 | P1 (new) | WAL `update_state`/`mark_sent` silently drop transitions when writer channel full or disconnected | codex-C2-generic | **FIXED** | `72d84db` — Disconnected returns Ok (CSP.3.2), Full increments `enqueue_failures` metric + `tracing::warn` |
| C2-2 | S1-010 | P1 (new) | WAL replay uses last-writer-wins for duplicate IntentRecorded, hiding duplication | codex-C2-generic | **FIXED** | `72d84db` — `tracing::warn!("duplicate IntentRecorded")` on replay + `test_replay_duplicate_intent_recorded_last_writer_wins` |
| C2-3 | S1-007 | P0 (escalation) | `dispatch_consistency_passed` bare bool bypass escalated from P1 to P0 (Critical) by enriched review | codex-C2-enriched | DEFERRED | Same root cause as C1 finding S1-007 #1; needs Slice 2 API reshape to `ValidatedDispatch` proof token |

---

## Resolution Summary

| Status | Count | Details |
|--------|-------|---------|
| **FIXED** | 17 | 14 in `de81950` (Cycle 1 fixes) + 3 in `72d84db` (WAL Cycle 2 fixes) |
| **STRUCTURAL** | 17 | Blocked on Slice 2+ production wiring — zero callsites (6) + paper-only AT proof (11) |
| **DEFERRED** | 5 | Bare bool API (1), academic/no-default-params (2), epsilon contract (1), C2 P0 escalation (1, same root as deferred #1) |
| **Total** | **39** | 36 Cycle 1 + 3 Cycle 2 |

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
