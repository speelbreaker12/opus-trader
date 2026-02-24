---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_INSTRUMENT_reconciliation.md
story_id: S1-011
story_title: "Deribit public instrument structs"
gate_result: GO
story_verdict: RECONCILED-WITH-DEBT (PROVEN, GAP-011-1/2 P2)
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-011 (Deribit public instrument structs)

## §10 STOPLIGHT: YELLOW
- Debt: Assumptions #1-#2 (Deribit API field names/types, serde rename correctness) pending without live API data.

## A) GATE RESULT
```
GATE: GO
Reason: YELLOW STOPLIGHT — all deferred items have owner + target.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-333 | §1.0 Instrument Units & Notional Invariants | `crates/soldier_infra/src/deribit/public/mod.rs:51::DeribitInstrument` (struct definition) | `test_btc_perpetual_deserializes` (test_deribit_instrument.rs:69), `test_contract_required_fields_present` (line 83), `test_amount_step_none_when_absent` (line 99), `test_amount_step_some_when_present` (line 108), `test_pub_reexport` (line 170) | Yes — field value assertions from JSON fixture | Yes — required fields are non-Option f64 (deserialization fails if absent) | Partial (see §5 table) | Yes (see §4 table) | **PROVEN** |

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | Deribit API includes `kind`, `tick_size`, `amount_step`, `min_trade_amount`, `contract_size` | Deserialize fixture | VALIDATED — tests at lines 69, 83 |
| 2 | `serde(rename)` correctly maps Deribit field names | Roundtrip test | PARTIALLY VALIDATED — no explicit serde(rename); `contract_multiplier()` method aliases `contract_size` |
| 3 | Struct is pub-exported | Compile check | VALIDATED — `test_pub_reexport` (line 170) |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Deribit field naming | B — contract-aligned with serde renames | Partially | DECISION_DIVERGENCE: Uses Deribit names with `contract_multiplier()` bridge method. INFO. |
| Which fields to include | A — minimal + instrument_name | Yes | mod.rs:51-104 |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| All fields as `Option<f64>`, always None | Yes (structural) | `test_contract_required_fields_present` (line 83) | Yes — required fields are f64 not Option |
| Hardcoded defaults via `#[serde(default)]` on required fields | Partial | `test_amount_step_none_when_absent` (line 99) | No explicit empty JSON fail test |
| Wrong numeric types (tick_size: i64) | Yes | `test_contract_required_fields_present` (line 83) | Yes — fixture has decimal values |

## D) DESIGN RISK NOTES

1. `amount_step` is `Option<f64>` with `#[serde(default)]` — downstream must handle None.
2. No `deny_unknown_fields` on production struct — correct per premortem §3.
3. No "empty JSON fails" test — structural prevention but explicit test recommended.

## E) REMEDIATION PLAN

```
[TEST_FIX]  GAP-011-1: Add empty JSON `{}` deserialization failure test. (P2)
[PRD_FIX]   GAP-011-2: `implementation_tests` in prd.json is empty `[]`. (P2)
[INFO]      DECISION_DIVERGENCE: Deribit names with bridge method. Not a violation.
```

## F) SCOPE CHECK

All scope.touch files exist. Test file not in scope.touch but acceptable.

```
READY FOR SELF_REVIEW
```
