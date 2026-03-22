# Contract Proposals

- run_id: `phase2-mar20codexhardened-lg-20260320_211226-33896e77`
- proposals_file_hash: `5a79a7d889afd11fae35a908395a3b91bac73ff9258428696f2ce8761fbd1ea3`
- proposal_count: `2`

## P-001

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-lg-20260320_211226-33896e77/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 Pre-Trade Liquidity Gate`
- source_finding: `F-001`
- source_finding_category: `missing_fail_closed`
- change_type: `new_requirement`
- status: `rejected`
- dedupe_key: `liquidity-gate-insufficient-depth-fail-closed`

### Rationale

Step 2 requires a WAP for the full `OrderQty`, but the section does not define the deterministic outcome when the walked book has zero or insufficient executable depth. A fail-closed rule is needed so implementations do not partially price or partially size the order.

### Proposed Text

```text
After walking the L2 book, if cumulative executable depth on the walked side is zero or remains less than `OrderQty`, Liquidity Gate MUST deterministically reject before dispatch and MUST NOT partially price, partially size, or infer a synthetic WAP for any unfilled remainder. This condition MUST use `Rejected(ExpectedSlippageTooHigh)`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -16,2 +16,3 @@
 1. Walk the L2 book on the correct side (asks for buy, bids for sell).
+1a. If cumulative executable depth on the walked side is zero or remains less than `OrderQty`, Liquidity Gate MUST deterministically reject before dispatch and MUST NOT partially price, partially size, or infer a synthetic WAP for any unfilled remainder. This condition MUST use `Rejected(ExpectedSlippageTooHigh)`.
 2. Compute the Weighted Avg Price (WAP) for `OrderQty`.
```

## P-002

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-lg-20260320_211226-33896e77/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 Pre-Trade Liquidity Gate`
- source_finding: `F-002`
- source_finding_category: `gate_interaction_gap`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `liquidity-gate-staleness-precheck-replace-placement`

### Rationale

The normative prose above the algorithm already covers replace order placement, but the deterministic staleness pre-check only enumerates OPEN and CLOSE/HEDGE. The algorithm should mirror the same replace handling so stale-L2 behavior is deterministic before any book walk begins.

### Proposed Text

```text
In the staleness pre-check, replace order placement MUST follow the same deterministic handling as CLOSE/HEDGE order placement: it MUST NOT be rejected solely for missing, unparseable, or stale L2; it MUST use the §3.1 fallback price ladder and may dispatch only a strictly positive, monotonic risk-reducing quantity. If no valid §3.1 fallback price source exists, it MUST fail closed with `Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -15,1 +15,1 @@
-0. **Staleness pre-check:** If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`, reject per the rules above (OPEN → `Rejected(LiquidityGateNoL2)`; CLOSE/HEDGE → §3.1 fallback). Do not proceed to book walk.
+0. **Staleness pre-check:** If `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`, reject per the rules above (OPEN → `Rejected(LiquidityGateNoL2)`; CLOSE/HEDGE/replace order placement → §3.1 fallback, with `Rejected(EmergencyCloseNoPrice)` and `RiskState::Degraded` if no valid fallback price source exists). Do not proceed to book walk.
```
