---
provenance:
  tool: claude-code
  model: claude-opus-4-6
  prompt_style: R1-preflight-audit (reconciliation)
  cycle: recon-v3.1
  phase_equivalent: R1
story_id: S1-008
story_title: "S1.2 OrderSize discovery"
gate_result: GO
story_verdict: RECONCILED (PROVEN, no gaps)
audit_date: "2026-02-23"
---

# RECONCILIATION PREFLIGHT AUDIT: S1-008 (S1.2 OrderSize discovery)

## READ-ONLY INTEGRITY CHECK

```
Initial git status: captured (tracked modifications pre-existing, none from this audit)
Final git status: will verify at end (no new modifications expected)
READ_ONLY_VIOLATION: NONE
```

---

### A) GATE RESULT

```
GATE: GO
Reason: Discovery story — deliverable exists, covers both AT-277 and AT-920 requirements
  from CONTRACT.md section 1.0, all three PRD acceptance criteria are met (fields/callsites/gaps,
  required tests, minimal diff). Premortem sections 0-10 align with delivered artifact. No runtime
  enforcement applies (documentation-only story). Downstream implementation (S1-004 commit 5642138)
  confirms the discovery report was consumed.
READ_ONLY_VIOLATION: NONE
```

---

### B) AT AUDIT TABLE (adapted for discovery)

Since S1-008 is a discovery/documentation story, the AT audit verifies that the discovery document
*addresses* the ATs rather than *enforces* them. Actual enforcement lives in S1-004 (AT-277) and
S1-007 (AT-920).

| AT ID | Contract section | Document coverage (file:line) | What the doc says | Complete? | Downstream enforcement verified? | Verdict |
|-------|-----------------|-------------------------------|-------------------|-----------|--------------------------------|---------|
| AT-277 | CONTRACT.md:844-854 (section 1.0 Dispatcher Rules) | `docs/order_size_discovery.md:58` ("AT-277: option uses amount=qty_coin, perp uses amount=qty_usd; option qty_usd unset; mismatches rejected") | Document reproduces the AT-277 worked examples (option qty_coin=0.3, perp qty_usd=30_000), lists the per-instrument-kind canonical field mapping table (lines 36-39), and explicitly flags option qty_usd must be unset (line 42). | **Yes** -- all three sub-clauses of AT-277 covered: (1) option sizing uses qty_coin, (2) perp sizing uses qty_usd, (3) option qty_usd unset. | **Yes** -- `crates/soldier_core/src/execution/order_size.rs:124-131` enforces option qty_usd=None; `crates/soldier_core/tests/test_order_size.rs:17-29` (`test_at277_option_sizing`) proves it. Implementation was created in S1-004 (commit `5642138`), after the discovery (commit `7e4c88d`). | **PROVEN** |
| AT-920 | CONTRACT.md:856-861 (section 1.0 Dispatcher Rules) | `docs/order_size_discovery.md:59` ("AT-920: contracts/amount mismatch beyond tolerance -> Rejected(ContractsAmountMismatch), dispatch count 0, RiskState::Degraded") | Document covers: tolerance value 0.001 (line 47), exact formula (line 48), rejection reason code (line 49), RiskState::Degraded transition (line 49), and explicitly lists this as gap #5 and #6 in the gaps section (lines 69-70). | **Yes** -- AT-920 full acceptance criteria covered: rejection reason, dispatch count=0, RiskState::Degraded. | **Yes** -- `crates/soldier_core/src/execution/dispatch_map.rs` enforces ContractsAmountMismatch; `crates/soldier_core/tests/test_dispatch_map.rs` tests it. Created in S1-005/S1-007 after discovery. | **PROVEN** |

---

### C) PREMORTEM CROSS-REFERENCE (section 2, section 4, section 5)

#### Section 2 Assumptions

| # | Assumption | Predicted validation | Actual status |
|---|-----------|---------------------|---------------|
| 1 | "The current codebase has some form of order sizing logic to discover" | Report content review | **VALIDATED** -- The discovery report correctly determined there was NO existing OrderSize logic at time of writing (`docs/order_size_discovery.md:10`: "None. Crates were reset to empty scaffolding (bootstrap commit 02b5f6c)"). The report pivoted to a gap-analysis framing: contract requirements vs empty state. This matches the premortem's section 9 exploit: "Frame the report as contract requirements vs. current state (even if empty)." |
| 2 | "CONTRACT.md section 1.0 OrderSize struct definition is stable" | Report references contract anchors for traceability | **VALIDATED** -- The contract section 1.0 OrderSize struct definition at `specs/CONTRACT.md:822-830` matches exactly what the discovery doc quotes at `docs/order_size_discovery.md:25-31`. Both show the same 4 fields (`contracts: Option<i64>`, `qty_coin: Option<f64>`, `qty_usd: Option<f64>`, `notional_usd: f64`). The struct definition has remained stable through all subsequent implementation stories. |

#### Section 4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Report format and depth | Option A -- High-level summary with explicit gap list | **Yes** | `docs/order_size_discovery.md` is structured as a high-level summary (7 sections, 111 lines total) with an explicit gap list (lines 61-73, 9 enumerated gaps), a required tests table (lines 75-90, 9 tests + 1 alias), and a minimal implementation diff (lines 92-110). It does NOT include line-by-line code audit (Option B was rejected). This matches the premortem's chosen option exactly. |

#### Section 5 Wrong Implementation Gate

| AT | Wrong impl identified | Blocked by what? | Actually blocked? | Evidence |
|----|----------------------|-------------------|-------------------|----------|
| AT-277 | "Report lists OrderSize fields but omits instrument-kind-specific population rules" | "Report must include per-instrument-kind field population table" | **Yes -- blocked** | `docs/order_size_discovery.md:36-39` contains the per-instrument-kind canonical field population table, covering all 4 kinds (option, linear_future, perpetual, inverse_future) with canonical field and notional_usd derivation formula. Additionally, line 42 explicitly states "For instrument_kind == option, qty_usd MUST be unset." This directly blocks the identified wrong impl. |
| AT-920 | "Report mentions mismatch rejection in passing without detailing the contracts/amount consistency invariant" | "Report must flag AT-920 as out of scope for struct discovery -- see S1-009/S1-007 with explicit handoff" | **Yes -- blocked** | `docs/order_size_discovery.md:44-49` contains a dedicated "Contracts/amount consistency" subsection that details: (1) match-within-tolerance requirement, (2) exact tolerance value 0.001, (3) exact formula, (4) rejection reason code, (5) RiskState::Degraded transition. Lines 59 and 84 explicitly reference AT-920. Lines 69-70 (gap list items 5-6) flag the consistency check and mismatch rejection as gaps requiring implementation. Line 110 notes dependency coordination with S1-007. The report goes further than the premortem's minimum requirement of just flagging AT-920 as out-of-scope -- it actually details the invariant AND flags it as a gap. |

---

### D) DESIGN RISK NOTES

1. **Stale anchors in PRD contract_refs**: The PRD entry for S1-008 (`plans/prd.json:1251-1254`) references `Anchor-021` and `VR-024` in its `contract_refs` array. Neither anchor exists in `specs/CONTRACT.md` (grep returns no matches). These appear to be placeholder or outdated references. **Impact**: Minimal -- the actual contract section reference ("CONTRACT.md 1.0 Instrument Units & Notional Invariants (Deribit Quantity Contract)") is correct and sufficient. The stale anchors do not affect the story's deliverable or AT coverage. **Severity**: Informational (P3).

2. **Discovery doc states "None" for current implementation**: At the time of writing (commit `7e4c88d`), this was correct. The codebase had been reset to scaffolding (commit `02b5f6c`). The discovery doc makes no claim about post-discovery state. The subsequent implementation in S1-004 (commit `5642138`) created `crates/soldier_core/src/execution/order_size.rs` which aligns with the discovery doc's gap list and proposed implementation diff. **Impact**: None -- correct sequencing confirmed via git history.

3. **enforcement_point is empty in PRD**: The PRD entry (`plans/prd.json:1300`) has `"enforcement_point": ""`. This is correct for a discovery story -- there is no runtime enforcement. The `enforcing_contract_ats` field lists AT-277 and AT-920, but these are informational references, not enforcement claims. The premortem correctly states this at line 9: "informational references -- discovery feeds future stories, no enforcement in this story."

4. **No implementation_tests in PRD**: The PRD entry (`plans/prd.json:1307`) has `"implementation_tests": []`. This is correct -- the only "tests" for this story are structural (file existence + content grep), which are listed in the `verify` array (`plans/prd.json:1278-1281`).

---

### E) REMEDIATION PLAN

| # | Finding | Severity | Action | Owner | Target |
|---|---------|----------|--------|-------|--------|
| 1 | PRD `contract_refs` contains stale anchors `Anchor-021` and `VR-024` that do not exist in CONTRACT.md | P3 (Informational) | Remove or update stale anchor references in `plans/prd.json` S1-008 entry lines 1253-1254 | Process owner | Next PRD cleanup pass |

No P0, P1, or P2 findings. The single P3 finding is cosmetic and does not affect story correctness or safety.

---

### F) SCOPE CHECK

| Check | Result | Evidence |
|-------|--------|----------|
| Deliverable exists? | **YES** | `docs/order_size_discovery.md` -- 111 lines, 7 sections |
| Deliverable within declared scope.touch? | **YES** | PRD `scope.touch` = `["docs/order_size_discovery.md"]` (`plans/prd.json:1261`); file exists at declared path |
| Deliverable outside scope.avoid? | **YES (no violations)** | PRD `scope.avoid` = `[]` (`plans/prd.json:1263`); no restrictions to violate |
| No runtime code changes? | **YES** | Discovery story -- no .rs files modified. Git log for `docs/order_size_discovery.md` shows only doc commits (97217a6, 7e4c88d, 09ddf00, 24738ba, 19a9523). |
| PRD acceptance criteria 1: "lists current fields, call sites, and gaps vs the contract OrderSize struct" | **MET** | `docs/order_size_discovery.md:8-19` (current implementation = None, call sites = None), lines 21-59 (contract requirements with field definitions), lines 61-73 (9 enumerated gaps) |
| PRD acceptance criteria 2: "lists required tests to add for canonical sizing" | **MET** | `docs/order_size_discovery.md:75-90` (9 named tests + 1 alias in a table with "What it proves" column) |
| PRD acceptance criteria 3: "names the minimal implementation diff needed for OrderSize canonical sizing" | **MET** | `docs/order_size_discovery.md:92-110` (target file, 6 implementation steps, test file, dependency notes) |
| AT-277 addressed? | **YES** | Covered at lines 36-42 (canonical field mapping table + option constraint) and line 58 (explicit AT-277 reference) |
| AT-920 addressed? | **YES** | Covered at lines 44-49 (contracts/amount consistency section) and line 59 (explicit AT-920 reference) |
| Premortem failure mode 1 (omits contract-required field)? | **MITIGATED** | All 4 OrderSize fields enumerated at lines 25-31 with exact types |
| Premortem failure mode 2 (fails to distinguish instrument-kind-specific rules)? | **MITIGATED** | Per-instrument-kind table at lines 36-39; option-specific constraint at line 42 |
| Premortem failure mode 3 (report never read before implementation)? | **MITIGATED** | S1-004 PRD entry (`plans/prd.json:865`) lists step 1 as "Review docs/order_size_discovery.md for current gaps and proposed tests" and depends on S1-008 (`plans/prd.json:882-883`) |
| Premortem failure mode 4 (conflates struct fields with dispatch mapping)? | **MITIGATED** | Report scope statement at line 5: "OrderSize struct, sizing invariants, and mapping to contract sizing rules." Dispatch mapping details are minimal -- only enough to establish what the OrderSize struct feeds into. |
| Premortem failure mode 5 (omits derivation invariants)? | **MITIGATED** | Derivation rules section at lines 53-54; canonical unit rules table includes notional_usd derivation formulas (lines 38-39) |

---

## READ-ONLY INTEGRITY FINAL CHECK

```
Final git status: only new file is reviews/reconciliations/S1/S1-008_reconciliation.md (this artifact)
READ_ONLY_VIOLATION: NONE
```

---

**READY FOR SELF_REVIEW**
