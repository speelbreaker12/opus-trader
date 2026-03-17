# Contract Proposals

- run_id: `phase2-mar17-20260317_141745-bb818649`
- proposals_file_hash: `ba9d219a96e093411939e86944555dfea8a96610bd60e8bdc04fb7a10c1ed5a0`
- proposal_count: `19`

## P-100

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.4.3 Margin Headroom Gate`
- source_finding: `F-001`
- source_finding_category: `missing_fail_closed`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `margin-headroom-nan-missing-fail-closed`

### Rationale

The Margin Headroom Gate specifies threshold rules for mm_util but has no fail-closed clause for missing, unparseable, or NaN inputs. An implementation could silently default mm_util to 0.0 (Active) when equity is missing or NaN. This is a P0 gap because a silent Active default under bad inputs is an avoidable loss path.

### Proposed Text

```text
**Fail-closed rule (Non-Negotiable):** If any of `maintenance_margin`, `equity`, or `initial_margin` returned by `/private/get_account_summary` is missing, unparseable, or NaN, the gate MUST treat `mm_util` as `>= mm_util_reduceonly` (fail-closed: force ReduceOnly at minimum) and set `RiskState::Degraded`. Rejections for missing/unparseable/NaN inputs MUST use `Rejected(MarginHeadroomInputMissing)`. No OPEN dispatch MAY occur while `RiskState::Degraded` is set due to this condition.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.4.3 Margin Headroom Gate @@
 **Computed:** `mm_util = maintenance_margin / max(equity, epsilon)`
+
+**Fail-closed rule (Non-Negotiable):** If any of `maintenance_margin`, `equity`, or `initial_margin` returned by `/private/get_account_summary` is missing, unparseable, or NaN, the gate MUST treat `mm_util` as `>= mm_util_reduceonly` (fail-closed: force ReduceOnly at minimum) and set `RiskState::Degraded`. Rejections for missing/unparseable/NaN inputs MUST use `Rejected(MarginHeadroomInputMissing)`. No OPEN dispatch MAY occur while `RiskState::Degraded` is set due to this condition.
+
+AT-1254
+- Given: `/private/get_account_summary` returns a response where `equity` is NaN or `maintenance_margin` is missing.
+- When: the Margin Headroom Gate evaluates any OPEN intent.
+- Then: `RiskState::Degraded` is set, the OPEN is rejected with `Rejected(MarginHeadroomInputMissing)`, and dispatch count remains 0.
+- Pass criteria: rejection reason matches; dispatch count == 0; RiskState == Degraded.
+- Fail criteria: dispatch occurs, or gate defaults mm_util to 0.0 and allows OPEN, or rejection reason is absent.
```

## P-101

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.4.2.1 PendingExposure — Emergency Drain (PX-4)`
- source_finding: `F-002`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `pending-exposure-drain-all-at-pair`

### Rationale

Three normative MUST rules for drain_all() exist (Kill-only guard, post-drain settle returns false, no Healthy resume until pre-drain TLSMs are terminal) but no acceptance test covers any of them. AT-225 and AT-910 only cover normal paths. This is a P1 gap because the fail-closed drain_all() guard is contract-level invariant with no coverage proof.

### Proposed Text

```text
Add the following acceptance tests after AT-910 in §1.4.2.1:

AT-1255
- Given: `RiskState::Healthy` is active (not Kill).
- When: `drain_all()` is called on PendingExposure.
- Then: `drain_all()` MUST be refused; no reservations are cleared; pending_delta is unchanged; dispatch count is unaffected.
- Pass criteria: drain_all() returns an error or no-op result; no reservation state is modified.
- Fail criteria: drain_all() executes and clears reservations while RiskState != Kill.

AT-1256
- Given: `RiskState::Kill` is active and one or more in-flight TLSMs exist from before drain_all() was called; drain_all() has executed and cleared all reservations.
- When: the system evaluates whether normal trading (TradingMode::Active / RiskState::Healthy) may resume.
- Then: normal trading MUST NOT resume until all pre-drain TLSMs have reached a terminal state.
- Pass criteria: TradingMode remains Kill or ReduceOnly; no OPEN is dispatched while pre-drain TLSMs are non-terminal.
- Fail criteria: TradingMode transitions to Active or RiskState returns to Healthy before all pre-drain TLSMs are terminal.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.4.2.1 PendingExposure — Emergency Drain (PX-4) @@
 AT-910
 - Given: a reservation would breach the exposure budget.
 ...
 - Fail criteria: dispatch occurs or reason missing/mismatched.
+
+AT-1255
+- Given: `RiskState::Healthy` is active (not Kill).
+- When: `drain_all()` is called on PendingExposure.
+- Then: `drain_all()` MUST be refused; no reservations are cleared; pending_delta is unchanged; dispatch count is unaffected.
+- Pass criteria: drain_all() returns an error or no-op result; no reservation state is modified.
+- Fail criteria: drain_all() executes and clears reservations while RiskState != Kill.
+
+AT-1256
+- Given: `RiskState::Kill` is active and one or more in-flight TLSMs exist from before drain_all() was called; drain_all() has executed and cleared all reservations.
+- When: the system evaluates whether normal trading (TradingMode::Active / RiskState::Healthy) may resume.
+- Then: normal trading MUST NOT resume until all pre-drain TLSMs have reached a terminal state.
+- Pass criteria: TradingMode remains Kill or ReduceOnly; no OPEN is dispatched while pre-drain TLSMs are non-terminal.
+- Fail criteria: TradingMode transitions to Active or RiskState returns to Healthy before all pre-drain TLSMs are terminal.
```

## P-102

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.4 Fee-Aware IOC Limit Pricer`
- source_finding: `F-003`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `pricer-input-missing-nan-at-pair`

### Rationale

The Pricer has a normative MUST for fail-closed behavior on missing/NaN/invalid inputs but no acceptance test proves it. AT-223 only covers the happy path. This is a P1 gap because the dispatch-count-0 proof and specific reject reason codes are unverified by contract-level tests.

### Proposed Text

```text
Add the following acceptance test after AT-223 in §1.4:

AT-1257
- Given: a pricer input where `fair_price` is NaN, or `qty <= 0`, or `fee_estimate_usd` is missing/unparseable.
- When: the pricer evaluates the intent.
- Then: the intent is rejected with `Rejected(PricerInputMissing)` or `Rejected(PricerInputInvalid)` and dispatch count remains 0.
- Pass criteria: specific reject reason is one of `PricerInputMissing` or `PricerInputInvalid`; dispatch count == 0.
- Fail criteria: dispatch occurs, or reject reason is absent or is a different reason code.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.4 Fee-Aware IOC Limit Pricer @@
 AT-223
 - Given: a widened spread and an IOC limit order.
 ...
 - Fail criteria: fill worse than `limit_price` or realized edge below minimum.
+
+AT-1257
+- Given: a pricer input where `fair_price` is NaN, or `qty <= 0`, or `fee_estimate_usd` is missing/unparseable.
+- When: the pricer evaluates the intent.
+- Then: the intent is rejected with `Rejected(PricerInputMissing)` or `Rejected(PricerInputInvalid)` and dispatch count remains 0.
+- Pass criteria: specific reject reason is one of `PricerInputMissing` or `PricerInputInvalid`; dispatch count == 0.
+- Fail criteria: dispatch occurs, or reject reason is absent or is a different reason code.
```

## P-103

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.4.2 Inventory Skew Gate`
- source_finding: `F-004`
- source_finding_category: `weak_normative`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `inventory-skew-sell-formula-weak-normative`

### Rationale

The SELL-when-long edge-loosening rule is vague ('Allow slightly lower edge within bounds') with no formula, parameter, or bound, while the BUY-when-long path has an exact formula. An implementer cannot derive the correct adjustment from the contract text alone, and AT-224 does not prove the SELL edge-adjustment formula.

### Proposed Text

```text
Replace the vague SELL loosening description in §1.4.2 with a precise formula:

**SELL intents when `inventory_bias > 0` (already long; risk-reducing trade):**
- Allow lower edge: `min_edge_usd := min_edge_usd * max(1 - inventory_skew_k * inventory_bias, inventory_skew_sell_floor)` where `inventory_skew_sell_floor >= 0` (see Appendix A; default: `0.5` meaning edge floor is 50% of base `min_edge_usd`)
- May be more aggressive on price: shift `limit_price` **toward** the touch by `bias_ticks(inventory_bias)` (same `bias_ticks()` function as BUY side, applied in the risk-reducing direction)

Add `inventory_skew_sell_floor` to Appendix A with default value `0.5`.

Add the following acceptance test after AT-224:

AT-1258
- Given: `inventory_bias = 1.0` (fully long, at delta_limit), `inventory_skew_k = 0.5`, `inventory_skew_sell_floor = 0.5`, and a SELL intent whose base `min_edge_usd` would initially fail the Net Edge Gate.
- When: Inventory Skew applies the SELL edge-loosening formula and the Net Edge Gate is re-evaluated.
- Then: the adjusted `min_edge_usd = base_min_edge_usd * max(1 - 0.5 * 1.0, 0.5) = base_min_edge_usd * 0.5`; if the adjusted value allows the SELL, it proceeds.
- Pass criteria: adjusted min_edge_usd equals exactly `base_min_edge_usd * 0.5`; re-evaluation uses this adjusted value.
- Fail criteria: adjusted value differs from formula, or re-evaluation does not use the adjusted value.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.4.2 Inventory Skew Gate @@
-- Allow slightly lower edge (within bounds) and/or be more aggressive to **flatten** inventory
+- Allow lower edge: `min_edge_usd := min_edge_usd * max(1 - inventory_skew_k * inventory_bias, inventory_skew_sell_floor)` where `inventory_skew_sell_floor >= 0` (see Appendix A; default: `0.5`)
+- May be more aggressive on price: shift `limit_price` **toward** the touch by `bias_ticks(inventory_bias)` (risk-reducing direction)
+
+AT-1258
+- Given: `inventory_bias = 1.0`, `inventory_skew_k = 0.5`, `inventory_skew_sell_floor = 0.5`, and a SELL intent whose base `min_edge_usd` initially fails Net Edge Gate.
+- When: Inventory Skew applies the SELL edge-loosening formula and the Net Edge Gate is re-evaluated.
+- Then: adjusted `min_edge_usd = base_min_edge_usd * 0.5`; if adjusted value allows SELL, it proceeds.
+- Pass criteria: adjusted min_edge_usd equals exactly base_min_edge_usd * 0.5; re-evaluation uses this value.
+- Fail criteria: adjusted value differs from formula or re-evaluation does not use adjusted value.
```

## P-104

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.1 Labeling & Idempotency Contract — Recovery / Matching Rule`
- source_finding: `F-005`
- source_finding_category: `cross_ref_broken`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `recovery-matching-rule-cross-ref-dedup`

### Rationale

The Recovery / Matching Rule block appears verbatim at two locations (lines 250-254 and lines 329-333) with no CSP-### anchor and no cross-reference between them. If one copy diverges on amendment, implementations built against either copy may diverge silently. The fix assigns a canonical CSP anchor to the §1.1 copy and replaces the duplicate with a cross-reference redirect.

### Proposed Text

```text
Assign CSP-063 anchor to the canonical Recovery / Matching Rule block at §1.1 (lines 250-254). Replace the duplicate copy at §1.1.1 (lines 329-333) with: "See CSP-063 Recovery / Matching Rule (§1.1). The normative rule is defined once; reproduced here only as a cross-reference to prevent divergence."
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.1.1 after AT-1098 @@
-**Recovery / Matching Rule (Normative):**
-- For canonical `s4` labels, recovery and reconciliation MUST require exact full parsed identity `{sid8, gid12, leg_idx, ih16}`.
-- Canonical `s4` labels MUST NOT use heuristic or tie-breaker fallback once parsed.
-- Legacy fallback tie-breakers MAY be used only for explicitly non-canonical legacy labels recovered from pre-v5.2 history.
-- If the applicable matcher yields none or more than one candidate, the system MUST fail closed with `RiskState::Degraded` and OPENs blocked until ambiguity is resolved.
+**Recovery / Matching Rule (Normative):** <!-- CSP-063: canonical copy is in §1.1; see anchor below -->
+See **CSP-063** Recovery / Matching Rule (§1.1). The normative rule is defined once at the §1.1 block tagged `<!-- CSP-063 -->` and reproduced here only as a cross-reference to prevent divergence.
```

## P-105

- fixture: `s1_execution_pipeline_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s1_execution_pipeline_latest/proposals.json`
- section: `§1.4.3 Margin Headroom Gate`
- source_finding: `F-006`
- source_finding_category: `stale_input_unspecified`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `margin-headroom-stale-input-ttl`

### Rationale

The Margin Headroom Gate specifies no staleness TTL for account_summary data, no gauge metric, and no fail-closed behavior for stale inputs. All other staleness-sensitive subsystems (§1.0.X, §1.3, §1.2.3) define an explicit *_max_age_ms parameter and fail-closed rule. The margin gate is the only gate that can silently use arbitrarily stale data, creating an avoidable loss path under connectivity issues.

### Proposed Text

```text
**Account Summary Staleness (Non-Negotiable):**
- `account_summary_max_age_ms` (Appendix A): maximum age in milliseconds of the last successful response from `/private/get_account_summary`. Default: `5000` ms.
- If the last successful fetch of `/private/get_account_summary` is older than `account_summary_max_age_ms`, the gate MUST treat `mm_util` as `>= mm_util_reduceonly` (fail-closed: force ReduceOnly at minimum) and set `RiskState::Degraded`. No OPEN dispatch MAY occur while this stale condition holds.
- **Required observability (contract-bound names):**
  - `account_summary_age_s` (gauge): seconds since last successful account_summary fetch
  - `account_summary_stale_total` (counter): incremented each evaluation cycle where age > threshold

Add the following acceptance test after AT-208 in §1.4.3:

AT-1259
- Given: `account_summary_age_s > account_summary_max_age_ms / 1000` (last successful fetch is stale).
- When: an OPEN intent is evaluated by the Margin Headroom Gate.
- Then: `RiskState::Degraded` is set, TradingMode is at minimum ReduceOnly, and the OPEN is blocked before dispatch.
- Pass criteria: OPEN dispatch count remains 0; RiskState == Degraded; account_summary_stale_total counter incremented.
- Fail criteria: OPEN dispatches while account_summary is stale, or RiskState remains Healthy.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.4.3 Margin Headroom Gate @@
 **Inputs:** `/private/get_account_summary` → `maintenance_margin`, `initial_margin`, `equity`
 **Computed:** `mm_util = maintenance_margin / max(equity, epsilon)`
+
+**Account Summary Staleness (Non-Negotiable):**
+- `account_summary_max_age_ms` (Appendix A): maximum age in milliseconds of the last successful response from `/private/get_account_summary`. Default: `5000` ms.
+- If the last successful fetch of `/private/get_account_summary` is older than `account_summary_max_age_ms`, the gate MUST treat `mm_util` as `>= mm_util_reduceonly` (fail-closed: force ReduceOnly at minimum) and set `RiskState::Degraded`. No OPEN dispatch MAY occur while this stale condition holds.
+- **Required observability (contract-bound names):**
+  - `account_summary_age_s` (gauge): seconds since last successful account_summary fetch
+  - `account_summary_stale_total` (counter): incremented each evaluation cycle where age > threshold
+
+AT-1259
+- Given: `account_summary_age_s > account_summary_max_age_ms / 1000` (last successful fetch is stale).
+- When: an OPEN intent is evaluated by the Margin Headroom Gate.
+- Then: `RiskState::Degraded` is set, TradingMode is at minimum ReduceOnly, and the OPEN is blocked before dispatch.
+- Pass criteria: OPEN dispatch count remains 0; RiskState == Degraded; account_summary_stale_total counter incremented.
+- Fail criteria: OPEN dispatches while account_summary is stale, or RiskState remains Healthy.
```

## P-200

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.3.2 Axis Computation / MarketIntegrityAxis`
- source_finding: `F-200`
- source_finding_category: `stale_input_unspecified`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f200-bunker-mode-staleness-threshold`

### Rationale

bunker_mode_active has no companion timestamp field and no freshness threshold in §2.2.1.2. Line 485 references a staleness threshold that does not exist, making the fail-closed check unimplementable. AT-1249 tests the stale case but cannot pass without the field and threshold being defined.

### Proposed Text

```text
Add `bunker_mode_last_update_ts_ms` (monotonic-epoch ms) to the §2.2 inputs list alongside `bunker_mode_active`. Add `bunker_mode_max_age_ms = 10_000` to the §2.2.1.2 freshness defaults table. The MarketIntegrityAxis STRESSED predicate at line 485 is then implementable: treat `bunker_mode_active` as missing/stale when `now_ms - bunker_mode_last_update_ts_ms > bunker_mode_max_age_ms`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §2.2 inputs
+- `bunker_mode_last_update_ts_ms` (monotonic-epoch ms; timestamp when bunker_mode_active was last updated by §2.3.2)
 @@ §2.2.1.2 Freshness defaults
+- `bunker_mode_max_age_ms = 10_000`
```

## P-201

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2 PolicyGuard — field rename transition`
- source_finding: `F-201`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f201-rate-limit-session-kill-alias-at`

### Rationale

Lines 37-42 define a MUST-level dual-name acceptance rule for contract version 5.2, but no AT validates that the old field name `rate_limit_session_kill_active` is correctly aliased to `session_termination_active`. Without this AT, the normative aliasing rule is untested and can silently fail.

### Proposed Text

```text
Add an acceptance test after line 42: AT-1260 — Given contract_version=5.2 and a policy payload that uses only the old field name `rate_limit_session_kill_active=true` (new name absent), When PolicyGuard computes TradingMode, Then PolicyGuard MUST treat it identically to `session_termination_active=true` and compute Kill per the session-termination axis predicate. Pass: Kill computed. Fail: field ignored and Active or ReduceOnly returned.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §2.2 Field rename transition (contract version 5.2) after line 42
+AT-1260
+- Given: contract_version=5.2 and policy payload contains `rate_limit_session_kill_active=true` with `session_termination_active` absent.
+- When: PolicyGuard computes TradingMode.
+- Then: TradingMode == Kill (alias is honoured).
+- Pass criteria: Kill computed via alias. Fail criteria: old field ignored.
```

## P-202

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.3.3 TradingMode Resolution`
- source_finding: `F-202`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `pending_scope_review`
- dedupe_key: `f202-shall-to-must-lines-412-513`

### Rationale

Two safety-critical resolution rules use SHALL where all other normative rules in this section use MUST. The parenthetical '(no other rules are permitted)' at line 513 already signals non-negotiable intent; SHALL is weaker than MUST under RFC 2119 and creates an inconsistency that could be cited to justify deviation.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -412,1 +412,1 @@
-PolicyGuard SHALL compute TradingMode from three independent health axes:
+PolicyGuard MUST compute TradingMode from three independent health axes:
@@ -513,1 +513,1 @@
-TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } SHALL be computed from axes by the following rules (no other rules are permitted):
+TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } MUST be computed from axes by the following rules (no other rules are permitted):
```

## P-210

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.3.3 TradingMode Resolution`
- source_finding: `F-202`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `pending_scope_review`
- dedupe_key: `f202-shall-to-must-line-513`

### Rationale

Second mechanical substitution for F-202: line 513 uses SHALL where MUST is required for this non-negotiable computation rule.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -513,1 +513,1 @@
-TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } SHALL be computed from axes by the following rules (no other rules are permitted):
+TradingMode ∈ { `Active`, `ReduceOnly`, `Kill` } MUST be computed from axes by the following rules (no other rules are permitted):
```

## P-203

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.6 RejectReasonCode Registry`
- source_finding: `F-203`
- source_finding_category: `cross_ref_broken`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f203-tradingmode-blocked-open-reject-code`

### Rationale

AT-931 (line 747) requires a reject reason that 'indicates TradingMode gate', but no such token exists in the §2.2.6 registry. AT-1101 mandates 1:1 completeness between contract tokens and enum variants, so AT-931 creates an untestable and internally inconsistent requirement. Adding the token resolves both the cross-reference gap and the AT-1101 completeness constraint.

### Proposed Text

```text
Add `TradingModeBlockedOpen` to the §2.2.6 RejectReasonCode registry allowed-values list. Update AT-931 pass criteria to read: 'dispatch count remains 0 and reject_reason_code == TradingModeBlockedOpen'. This satisfies AT-1101 completeness and makes AT-931 unambiguously testable.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §2.2.6 Allowed values list
+- `TradingModeBlockedOpen`
@@ AT-931 pass criteria line 747
-- Pass criteria: dispatch count remains 0 and reject reason indicates TradingMode gate.
+- Pass criteria: dispatch count remains 0 and reject_reason_code == TradingModeBlockedOpen.
```

## P-204

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.4 Open Permission Latch — AT-1243 duplicate ID`
- source_finding: `F-204`
- source_finding_category: `cross_ref_broken`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `f204-duplicate-at-1243-renumber-line-1037`

### Rationale

AT-1243 is used for two entirely different test scenarios (line 954: reconcile-stall observability; line 1037: runtime-binding cert concurrent with reconcile-class reason code). Duplicate AT IDs break automated traceability tools and PRD linkage. The second occurrence (line 1037) must be assigned a new unique ID.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -1037,1 +1037,1 @@
-AT-1243
+AT-1253
```

## P-205

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.3.2 SystemIntegrityAxis / 2.2 inputs — fee model staleness`
- source_finding: `F-205`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f205-fee-model-hard-stale-at`

### Rationale

The SystemIntegrityAxis DEGRADED predicate `fee_model_cache_age_s > fee_model_hard_stale_s` (line 502) produces REDUCEONLY_FEE_MODEL_HARD_STALE but has no acceptance test. No AT proves this predicate actually forces ReduceOnly with the correct reason code.

### Proposed Text

```text
Add after the fee-model staleness predicate (line 502): AT-1261 — Given `fee_model_cache_age_s > fee_model_hard_stale_s` and all other axis inputs are nominal (no other DEGRADED/FAILING predicates active), When TradingMode is computed, Then TradingMode == ReduceOnly and mode_reasons includes REDUCEONLY_FEE_MODEL_HARD_STALE. Pass: OPEN blocked with correct reason. Fail: Active returned or reason code absent.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ after SystemIntegrityAxis fee-model staleness predicate
+AT-1261
+- Given: `fee_model_cache_age_s > fee_model_hard_stale_s`; all other SystemIntegrityAxis inputs nominal.
+- When: TradingMode is computed.
+- Then: TradingMode == ReduceOnly and mode_reasons includes REDUCEONLY_FEE_MODEL_HARD_STALE.
+- Pass criteria: OPEN blocked; correct reason code emitted. Fail criteria: Active returned or reason missing.
```

## P-206

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2 inputs / 2.2.1.2 — cortex_override missing/unparseable behavior unspecified`
- source_finding: `F-206`
- source_finding_category: `stale_input_unspecified`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f206-cortex-override-missing-unparseable-rule`

### Rationale

`cortex_override` drives CapitalRiskAxis CRITICAL (ForceKill) and SystemIntegrityAxis DEGRADED (ForceReduceOnly) but is not listed as a critical input in §2.2.1.2, has no companion timestamp, and has no explicit missing/unparseable handling rule. A corrupted ForceKill signal could be silently dropped — a direct fail-open risk on a capital-loss path.

### Proposed Text

```text
Add `cortex_override` to the §2.2.1.2 critical inputs list. Add an explicit rule: 'If `cortex_override` is missing or unparseable, PolicyGuard MUST treat it as `ForceReduceOnly` (fail-closed) and include REDUCEONLY_INPUT_MISSING_OR_STALE in mode_reasons.' Add AT-1262: Given `cortex_override` payload is absent or cannot be deserialized, When PolicyGuard computes TradingMode, Then TradingMode == ReduceOnly and REDUCEONLY_INPUT_MISSING_OR_STALE is present. Pass: ReduceOnly with reason. Fail: Active returned or reason absent.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §2.2.1.2 Critical inputs list
+- `cortex_override` (from §2.3 producers) — if missing or unparseable MUST be treated as ForceReduceOnly; set REDUCEONLY_INPUT_MISSING_OR_STALE
```

## P-207

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.4 Open Permission Latch — reconciliation REST failure`
- source_finding: `F-207`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f207-reconcile-rest-failure-at`

### Rationale

Line 944 defines a MUST-level fail-closed rule: if the REST `/get_user_trades` query fails (network/timeout/HTTP/parse error), latch MUST remain set. AT-1100 covers missing trades, not REST failure. This separate fail-closed code path has no AT coverage.

### Proposed Text

```text
Add AT-1263 after AT-1100: Given `open_permission_blocked_latch == true` and the REST `/get_user_trades` call returns a network error, timeout, HTTP error, or unparseable response, When reconciliation success criteria are evaluated, Then reconciliation MUST fail and `open_permission_blocked_latch` MUST remain true; OPEN intents MUST remain blocked. Pass: latch stays set, reconciliation reported as failed. Fail: reconciliation succeeds on transport error, or latch clears.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ after AT-1100 (line 967)
+AT-1263
+- Given: `open_permission_blocked_latch == true`; REST `/get_user_trades` returns network error, timeout, HTTP error, or unparseable response.
+- When: reconciliation success criteria are evaluated.
+- Then: reconciliation fails; `open_permission_blocked_latch` remains true; OPEN blocked.
+- Pass criteria: latch held; reconciliation reported failed. Fail criteria: latch clears on transport failure.
```

## P-208

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2.3.3 Recovery Rule`
- source_finding: `F-208`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f208-recovery-slower-than-degradation-at`

### Rationale

The Recovery Rule (lines 565-570) is a MUST-level cross-cutting invariant with no dedicated AT. AT-1053 tests monotonicity (worse axes never produce less-restrictive mode) but does not test the recovery direction — that a recovering axis cannot return to Active faster than the applicable hysteresis window allows.

### Proposed Text

```text
Add AT-1264 after the Recovery Rule: Given `bunker_mode_active` becomes true (entering Bunker Mode via §2.3.2) and all other axis inputs are nominal (no other STRESSED/DEGRADED/FAILING predicates active), and then `bunker_mode_active` clears to false before `bunker_exit_stable_s` has elapsed, When TradingMode is computed on subsequent ticks, Then TradingMode MUST remain ReduceOnly until the full `bunker_exit_stable_s` window has elapsed since the bunker entry condition cleared. Pass: ReduceOnly held for full `bunker_exit_stable_s` duration; Active not returned prematurely. Fail: Active returned before `bunker_exit_stable_s` elapses.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ after Recovery Rule (line 570)
+AT-1264
+- Given: `bunker_mode_active` becomes true (Bunker Mode entry via §2.3.2); all other axis inputs nominal.
+- And then: `bunker_mode_active` clears to false before `bunker_exit_stable_s` has elapsed.
+- When: TradingMode is computed on subsequent ticks.
+- Then: TradingMode == ReduceOnly until full `bunker_exit_stable_s` window elapses since bunker entry condition cleared.
+- Pass criteria: ReduceOnly held for full stable-exit window; Active not returned prematurely.
+- Fail criteria: Active returned before `bunker_exit_stable_s` elapses.
```

## P-209

- fixture: `s2_2_policyguard_latest`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/s2_2_policyguard_latest/proposals.json`
- section: `2.2 inputs — emergency_reduceonly_active clear condition`
- source_finding: `F-209`
- source_finding_category: `missing_fail_closed`
- change_type: `new_requirement`
- status: `rejected`
- dedupe_key: `f209-emergency-reduceonly-trigger-reconcile-table`

### Rationale

Line 30 qualifies the clear condition with '(if reconciliation is required by trigger source)' but never defines which trigger sources require reconciliation. An implementer could choose to never require reconciliation, allowing the flag to clear on cooldown alone in all cases — a fail-open risk. AT-132 repeats the same ambiguous qualifier without resolving it.

### Proposed Text

```text
Add a normative table in §2.2 inputs under the `emergency_reduceonly_active` entry enumerating trigger sources and their reconciliation requirement. Example: POST /api/v1/emergency/reduce_only → reconciliation required before clear; automated policy-derived triggers → reconciliation required before clear. If all sources require reconciliation, replace the parenthetical with the unconditional rule: 'clears only after cooldown expires AND reconciliation confirms exposure is safe.' This eliminates the per-source ambiguity while preserving or tightening the fail-closed invariant.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §2.2 inputs — emergency_reduceonly_active state transition
-  - State transition: automatically clears to false after cooldown duration expires AND reconciliation confirms exposure is safe (if reconciliation is required by trigger source).
+  - State transition: automatically clears to false after cooldown duration expires AND reconciliation confirms exposure is safe.
+  - **Trigger source reconciliation table (normative):** all trigger sources require reconciliation before clearing (unconditional). If a future trigger source is added that does not require reconciliation, it MUST be explicitly listed here as an exception.
```

## P-400

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/sample_contract_patch/proposals.json`
- section: `Sample Contract Fixture`
- source_finding: `F-400`
- source_finding_category: `cross_ref_broken`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `cross_ref_broken:sample_contract_patch:line3:AT-999->AT-101`

### Rationale

AT-999 does not exist in the AT registry; AT-101 is the correct target reference.

### Diff Preview

```diff
-AT-999 is referenced here
+AT-101 is referenced here
```

## P-401

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar17-20260317_141745-bb818649/sample_contract_patch/proposals.json`
- section: `Sample Contract Fixture`
- source_finding: `F-401`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `weak_normative:sample_contract_patch:line4:SHOULD->MUST:PolicyGuard`

### Rationale

PolicyGuard rejection on missing data is a safety-critical fail-closed path; SHOULD permits omission and must be strengthened to MUST.

### Diff Preview

```diff
-PolicyGuard SHOULD reject when data is missing.
+PolicyGuard MUST reject when data is missing.
```
