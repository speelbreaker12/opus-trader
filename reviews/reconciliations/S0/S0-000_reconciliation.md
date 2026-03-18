# S0-000 Reconciliation Audit (R1)

**Story:** S0-000 -- P0-A Launch Policy Baseline
**Auditor:** R1 Reconciliation Auditor (read-only)
**Date:** 2026-02-24
**Premortem:** `reviews/premortems/S0-000_premortem.md`
**PRD status:** `passes: true`

---

## A) GATE RESULT

```
GATE: GO
Reason: Documentation-only story. All scope files exist, contain concrete
        numeric constraints, snapshot is byte-for-byte identical to source,
        all four required content sections present. Two [FILL] placeholders
        in metadata (owner, prepared_by) are cosmetic and do not affect
        constraint completeness. No RED blockers.
READ_ONLY_VIOLATION: NONE
```

---

## B) AT AUDIT TABLE

Empty -- no `enforcing_contract_ats` for this story (`enforcing_contract_ats: []`).
No `implementation_tests` defined.

This is consistent with the PRD entry at `plans/prd.json:24-75` which shows
`enforcement_point: ""` and review-based acceptance criteria only.

---

## C) PREMORTEM CROSS-REFERENCE

### C1) Section 2 Assumptions

| # | Assumption | Predicted | Actual | Status |
|---|-----------|-----------|--------|--------|
| 1 | `docs/` directory exists | Dir must exist to write `docs/launch_policy.md` | File exists at `docs/launch_policy.md` (198 lines) | CONFIRMED |
| 2 | `evidence/phase0/policy/` directory exists | Dir must exist to write snapshot | File exists at `evidence/phase0/policy/launch_policy_snapshot.md` (198 lines) | CONFIRMED |
| 3 | "Literal copy" = byte-for-byte identical | `diff` between source and snapshot exits 0 | `diff docs/launch_policy.md evidence/phase0/policy/launch_policy_snapshot.md` exits 0 | CONFIRMED |
| 4 | "Allowed instruments/venues" = concrete enumerated list, not placeholder | Inline list of specific instruments, not "TBD" or external links | `docs/launch_policy.md:42-73` enumerates BTC, ETH, Options, Perpetuals (hedging only), with explicit forbidden list. Venues at lines 33-38: Deribit with specific accounts. | CONFIRMED |
| 5 | Position/loss limits are numeric, not prose | Concrete numbers, not "reasonable limits" | `docs/launch_policy.md:107-112`: `$5,000` daily loss, `$15,000` weekly loss, `10%` drawdown, `$500,000` gross notional. Per-underlying at lines 119-122: `5.0 BTC`, `50.0 ETH`, `$250,000`. | CONFIRMED |
| 6 | Document format compatible with P0-F loader | Pure Markdown with tables; P0-F creates own `config/policy.json` | `config/policy.json` exists (created by S0-005). Uses some but not all values from launch policy doc. Decision 1 (Option A) was followed. | CONFIRMED (deferred to P0-F as planned) |
| 7 | Order rate/pacing values are concrete numbers | Numeric limits, not "appropriate pacing" | `docs/launch_policy.md:127-130`: `max_orders_per_second: 5`, `max_orders_per_minute: 100`, `min_order_interval_ms: 200`, `max_order_size_contracts: 10` | CONFIRMED |
| 8 | Reviewer has domain competence | Reviewer selection criteria or second-reviewer requirement | No evidence of a formal reviewer competence gate. The Owner Sign-Off section at lines 192-197 shows `owner_signature: admin`. Single reviewer only. | ACKNOWLEDGED -- premortem flagged as "Not formally tested" |
| 9 | All numeric values include explicit units | Every numeric cell has a unit label | Most values include units: `$5,000`, `5.0 BTC`, `50.0 ETH`, `$250,000`, `10%`, `$500,000`. However: `max_order_size_contracts: 10`, `max_orders_per_second: 5`, `max_orders_per_minute: 100`, `min_order_interval_ms: 200` -- these use metric names as implicit units (contracts, per-second, per-minute, ms). Acceptable because the metric name IS the unit. | CONFIRMED (metric names serve as unit labels) |
| 10 | Document clarifies global vs. per-instrument | Explicit statement of scope applicability | `docs/launch_policy.md:107` "Global Limits" heading, and `docs/launch_policy.md:118` "Per-Underlying Limits" heading -- both global and per-underlying limits are broken out explicitly. | CONFIRMED |

### C2) Section 4 Decisions

| Decision | Chosen Option | Implemented As | Status |
|----------|---------------|----------------|--------|
| Document format: pure Markdown vs. structured data | A -- Pure Markdown prose with tables | `docs/launch_policy.md` is pure Markdown with structured tables, no embedded YAML/JSON. `config/policy.json` created separately by P0-F (S0-005). | CONFIRMED |
| Constraint specificity: concrete numeric vs. qualitative | A -- Concrete numeric values | All constraints are numeric with explicit values (see Assumption 5 above). No vague language like "conservative" or "appropriate". | CONFIRMED |
| "Literal copy" definition: byte-for-byte vs. content-equivalent | A -- Byte-for-byte identical via file copy | `diff` exits 0 between source and snapshot. No metadata annotations added. | CONFIRMED |

### C3) Section 5 Wrong Implementations

| Wrong Impl | Was it avoided? | Evidence |
|------------|----------------|----------|
| "instruments: see exchange documentation" (external delegation) | YES -- avoided | `docs/launch_policy.md:42-73` contains an inline enumerated list with specific underlyings (BTC, ETH), product types (Options, Perpetuals hedging-only), and explicit forbidden list. No external links for instrument definitions. |
| "max position: TBD pending risk review" (placeholder values) | PARTIAL -- two `[FILL]` placeholders remain | `docs/launch_policy.md:11-12`: `owner: [FILL]`, `prepared_by: [FILL]`. These are metadata fields, NOT constraint values. All constraint values are concrete. However, the premortem's FM-1 (grep for TBD/TODO/FILL) would flag these. See Finding F-1 below. |
| "Orders will be paced appropriately" (prose without numbers) | YES -- avoided | `docs/launch_policy.md:127-130` contains 4 concrete numeric pacing limits. |
| Lists only LIVE and DEV (missing STAGING/PAPER) | YES -- avoided | `docs/launch_policy.md:21-26` lists all four environments: DEV, STAGING, PAPER, LIVE. |
| Snapshot stale relative to source | YES -- avoided (at time of audit) | `diff` exits 0 as of 2026-02-24. Both files show `last_updated_utc: 2026-02-09T00:00:00Z`. |

---

## D) DESIGN RISK NOTES

**D-1: `[FILL]` placeholders in metadata (LOW)**
`docs/launch_policy.md:11-12` contain `owner: [FILL]` and `prepared_by: [FILL]`. These are metadata identity fields, not safety-critical constraint values. However, the premortem FM-1 explicitly called out grepping for placeholder tokens, and `[FILL]` is functionally equivalent to `[TBD]`. The Owner Sign-Off at line 196 shows `owner_signature: admin` which partially addresses the owner identity, but the metadata block is inconsistent with the sign-off block.

**D-2: `config/policy.json` partial coverage (LOW, owned by S0-005)**
The machine-readable `config/policy.json` contains `max_daily_loss_usd: 5000`, `max_gross_notional_usd: 500000`, `max_orders_per_minute: 100` but omits several limits defined in the launch policy doc: `max_weekly_loss_usd`, `max_drawdown_pct`, `max_orders_per_second`, `min_order_interval_ms`, `max_order_size_contracts`, per-underlying limits, Greeks limits, micro-live caps. This is noted as an observation only -- S0-005 owns the policy loader and its completeness is S0-005's concern, not S0-000's.

**D-3: `policy_version` drift between doc and JSON (LOW)**
`docs/launch_policy.md:8` shows `policy_version: 1.1`, while `config/policy.json:3` shows `policy_version: "1.2"`. This version mismatch suggests the JSON was updated independently without updating the Markdown source. The premortem FM-2 predicted exactly this scenario (snapshot/source divergence). While the snapshot is still in sync with the Markdown doc, the JSON has drifted. This is S0-005's scope but worth noting as a cross-story interface risk.

**D-4: No automated verification script (LOW, deferred per premortem)**
The premortem Section 6 noted that file-existence checks, diff verification, and section-header grep could be automated but are not. This remains true. `evidence/phase0/ci_links.md:22` shows `P0-A` marked as `Verified: YES`, but verification was manual. The premortem's debt register correctly tracks this as deferred to P0-F / cross-cutting CI hardening.

---

## E) REMEDIATION PLAN

| Finding | Severity | Recommendation | Blocking? |
|---------|----------|----------------|-----------|
| F-1: `[FILL]` placeholders in `docs/launch_policy.md:11-12` (owner, prepared_by) | LOW | Replace `[FILL]` with actual values. The sign-off at line 196 already has `owner_signature: admin`, so the metadata should be consistent. Update snapshot after fixing. | NO -- metadata only, no constraint impact |
| F-2: `policy_version` drift between `docs/launch_policy.md:8` (1.1) and `config/policy.json:3` ("1.2") | LOW | Reconcile version numbers. Either bump the Markdown doc to 1.2 or note why the JSON version differs. This is a cross-story concern (S0-005 interface). | NO -- cross-story scope, not S0-000 |
| F-3: No automated diff/existence check for Phase 0 doc stories | LOW | Per premortem debt register: create a CI script that diffs all `docs/*.md` against `evidence/phase0/*/` snapshots. This is cross-cutting debt, not S0-000-specific. | NO -- deferred per premortem debt register |

**Total findings:** 3
**Blocking findings:** 0
**Premortem-predicted findings:** All 3 were predicted (F-1 maps to FM-1/Wrong Impl 2; F-2 maps to FM-2; F-3 maps to Debt Register items 1-2)

---

## F) SCOPE CHECK

| Scope File | Exists? | Content Assessment |
|------------|---------|-------------------|
| `docs/launch_policy.md` | YES (198 lines) | Contains all four required sections: (1) Allowed Instruments at line 42, Allowed Venues at line 32; (2) Risk Limits / max position / daily loss at lines 94-137; (3) Per-Order Limits / order rate / pacing at lines 126-130; (4) Allowed Environments at lines 17-26. All values are concrete and numeric. Includes additional sections beyond minimum requirements: Micro-Live Caps, Kill/Stop Rules, Prohibited Actions, Fail-Closed Defaults, Owner Sign-Off. |
| `evidence/phase0/policy/launch_policy_snapshot.md` | YES (198 lines) | Byte-for-byte identical to source (`diff` exit code 0). Same `[FILL]` placeholders present in both. |

**Out-of-scope files touched:** None detected.
**Missing scope files:** None.

---

## Summary

S0-000 is a well-executed documentation-only story. The launch policy document is comprehensive, exceeding the minimum requirements by including micro-live caps, measurement definitions, Greeks limits, and fail-closed defaults. All premortem decisions (Option A for each) were followed correctly. The snapshot is a faithful byte-for-byte copy.

The three findings are all LOW severity and non-blocking. Notably, all three were predicted by the premortem -- the premortem's failure mode analysis and debt register accurately anticipated the residual gaps. No new unpredicted gaps were found.

The `[FILL]` placeholders (F-1) are the only item that could arguably be called a defect in the deliverable itself, but they affect metadata identity fields, not safety-critical constraint values.

---

READY FOR SELF_REVIEW
