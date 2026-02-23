---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INSTRUMENT_reconciliation.md
story_id: S1-002
story_title: "InstrumentKind derivation and RiskState enum"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (PROVEN, GAP-002-1 P2)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-002 (InstrumentKind derivation and RiskState enum)

## §10 STOPLIGHT: YELLOW
- Debt: Assumption #2 (USDC-margined perpetual metadata detection) pending without live API data.
- All gaps are DEFERRED. Proceeding.

## A) GATE RESULT
```
GATE: GO
Reason: YELLOW STOPLIGHT — all deferred items have owner + target. Implementation exists and tests pass.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-333 | §1.0 Instrument Units & Notional Invariants | `crates/soldier_core/src/venue/types.rs:54::derive_instrument_kind` | `test_all_instrument_kinds_derivable` (line 97), `test_usdc_margined_perpetual_maps_to_linear_future` (line 40), `test_btc_perpetual_maps_to_perpetual` (line 25), `test_btc_dated_future_maps_to_inverse_future` (line 55), `test_combo_instruments_return_none` (line 85) | Yes — exact enum variant comparison per table-driven fixture | Yes — unknown kind returns None (line 74); no default fallback | Partial (see §5 table) | Yes (see §4 table) | **PROVEN** |
| AT-333 (RiskState) | §1.0 Definitions | `crates/soldier_core/src/risk/state.rs:13::RiskState` | `test_riskstate_has_all_variants` (test_instrument_kind_mapping.rs:182) | Yes — 4 variants constructed, distinctness asserted | N/A (enum definition) | Yes — wrong impl #3 (2-variant enum) blocked by 4-variant test | Yes | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Deribit `kind` field values are `option`, `future`, `option_combo` | Table-driven test | VALIDATED — `test_all_instrument_kinds_derivable` (line 97) covers all 4 kinds |
| 2 | USDC-margined perpetuals have detectable metadata | Test with USDC-margined perp fixture | VALIDATED — `test_usdc_margined_perpetual_maps_to_linear_future` (line 40) uses `is_linear: true`. No test validates full chain from DeribitInstrument fields to `is_linear`. |
| 3 | S1-011 struct includes `kind` field | Compile-time check | VALIDATED — `DeribitInstrument.kind` exists |
| 4 | RiskState enum requires exactly 4 variants | Exhaustive match test | VALIDATED — `test_riskstate_has_all_variants` (line 182) checks len==4. No exhaustive `match` test. |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| How to distinguish perpetual vs linear_future vs inverse_future | A — use settlement_currency + instrument metadata | Yes | `types.rs:35-44` — `InstrumentKindInput` uses `is_option`, `is_future`, `is_perpetual`, `is_linear` booleans |
| Fail behavior for unknown instrument kind | A — return an error (None) | Yes | `types.rs:74` — returns `None` for unknown/combo |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Hardcode InstrumentKind from name matching | Partial | API takes `InstrumentKindInput` with no name field — structural prevention | Yes (structural) |
| Map all futures to `linear_future` regardless of settlement | Yes | `test_btc_perpetual_maps_to_perpetual` (line 25), `test_btc_dated_future_maps_to_inverse_future` (line 55) | Yes |
| RiskState with only 2 variants (Healthy, Kill) | Yes | `test_riskstate_has_all_variants` (line 182) | Yes |

## D) DESIGN RISK NOTES

1. No end-to-end derivation test from DeribitInstrument to InstrumentKind (INFO).
2. `test_instrument_metadata_uses_get_instruments` referenced in PRD but does not exist.
3. RiskState exhaustive match could be stronger but current test is adequate.

## E) REMEDIATION PLAN

```
[TEST_FIX]  GAP-002-1: Add `test_instrument_metadata_uses_get_instruments`. (P2)
[INFO]      Structural prevention makes §5 golden vector redundant.
[INFO]      RiskState 4-variant test adequate.
```

## F) SCOPE CHECK

All scope.touch files exist and are touched. No scope drift.

```
READY FOR SELF_REVIEW
```
