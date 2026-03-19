# Contract Proposals

- run_id: `phase2-p4-lg3-20260319_034811-85f8f65e`
- proposals_file_hash: `32147384fc59174fbbc891a52e5475c84b593b10f3effcb6afbaa8f4ccae6ba4`
- proposal_count: `5`

## P-001

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-p4-lg3-20260319_034811-85f8f65e/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 Stale-L2 fail-closed path`
- source_finding: `F-001`
- source_finding_category: `missing_fail_closed`
- change_type: `new_requirement`
- status: `rejected`
- dedupe_key: `f001-emergencyclosenoprice-degraded-atomicity`

### Rationale

F-001 identifies an actor ambiguity: line 8 implies LiquidityGate directly sets RiskState::Degraded on EmergencyCloseNoPrice, while line 26 attributes the set to §2.2.3.2 SystemIntegrityAxis via axis resolver. Without an explicit ordering clause, the Degraded transition may not be atomic with the rejection, leaving RiskState inconsistent between gate return and the next axis evaluation cycle. This proposal designates SystemIntegrityAxis as the authoritative setter and requires LiquidityGate to trigger it synchronously before returning.

### Proposed Text

```text
**RiskState transition atomicity (§1.3):** When LiquidityGate emits `Rejected(EmergencyCloseNoPrice)`, it MUST synchronously call into the SystemIntegrityAxis to record the no-price fault before returning the rejection. The SystemIntegrityAxis is the authoritative setter for `RiskState::Degraded` on this path; LiquidityGate is the required and sole trigger. The `RiskState::Degraded` state MUST be observable to any subsequent gate or dispatcher invocation within the same evaluation cycle.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ §1.3 stale-L2 fail-closed @@
+**RiskState transition atomicity (§1.3):** When LiquidityGate emits `Rejected(EmergencyCloseNoPrice)`, it MUST synchronously call into the SystemIntegrityAxis to record the no-price fault before returning the rejection. The SystemIntegrityAxis is the authoritative setter for `RiskState::Degraded` on this path; LiquidityGate is the required and sole trigger. The `RiskState::Degraded` state MUST be observable to any subsequent gate or dispatcher invocation within the same evaluation cycle.
```

## P-002

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-p4-lg3-20260319_034811-85f8f65e/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 CLOSE/HEDGE/replace stale-L2 AT coverage`
- source_finding: `F-002`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f002-replace-stale-l2-at-coverage`

### Rationale

F-002 identifies that line 8 normatively requires CLOSE/HEDGE/replace order placement MUST NOT be rejected solely for missing or stale L2, yet no AT covers the replace path. AT-421 tests only CANCEL and CLOSE/HEDGE. A replace order is entirely uncovered: an implementation could incorrectly block replace orders on stale L2, or dispatch them without a valid price source, and no AT would detect the regression.

### Proposed Text

```text
AT-PROP-001
- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`; a valid §3.1 fallback price source exists.
- When: Liquidity Gate evaluates a replace order placement intent.
- Then: the replace intent is NOT rejected solely for stale/missing L2; it uses the §3.1 fallback price ladder and dispatches a strictly positive, monotonic risk-reducing quantity.
- Pass criteria: dispatch count >= 1; dispatched quantity > 0 and risk-reducing; no `LiquidityGateNoL2` rejection reason is emitted.
- Fail criteria: replace is blocked despite a valid §3.1 fallback source, or dispatched quantity is 0 or risk-increasing.

AT-PROP-003
- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms`; no valid §3.1 fallback price source exists.
- When: Liquidity Gate evaluates a replace order placement intent.
- Then: the intent MUST be rejected with `Rejected(EmergencyCloseNoPrice)` and `RiskState` MUST transition to `Degraded`.
- Pass criteria: dispatch count remains 0; rejection reason is `EmergencyCloseNoPrice`; `RiskState == Degraded`.
- Fail criteria: dispatch occurs without a valid price source, rejection reason is missing/mismatched, or `RiskState` does not transition to `Degraded`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -§1.3 after AT-421 @@
+AT-PROP-001
+- Given: `L2BookSnapshot` missing/unparseable/stale; valid §3.1 fallback exists.
+- When: Liquidity Gate evaluates a replace order placement intent.
+- Then: replace NOT rejected solely for stale L2; uses §3.1 fallback; dispatches strictly positive risk-reducing quantity.
+- Pass criteria: dispatch count >= 1; quantity > 0 and risk-reducing; no LiquidityGateNoL2 emitted.
+- Fail criteria: replace blocked despite valid fallback, or quantity 0 or risk-increasing.
+
+AT-PROP-003
+- Given: `L2BookSnapshot` missing/unparseable/stale; no valid §3.1 fallback exists.
+- When: Liquidity Gate evaluates a replace order placement intent.
+- Then: rejected with Rejected(EmergencyCloseNoPrice); RiskState -> Degraded.
+- Pass criteria: dispatch count 0; reason EmergencyCloseNoPrice; RiskState == Degraded.
+- Fail criteria: dispatch occurs or reason missing/mismatched.
```

## P-003

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-p4-lg3-20260319_034811-85f8f65e/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 AT-344 / AT-909 duplication`
- source_finding: `F-003`
- source_finding_category: `missing_at_pair`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `f003-at909-replace-boundary-scenario`

### Rationale

F-003 identifies AT-909 and AT-344 as near-identical, providing no distinct coverage. The replacement tests the exact staleness threshold boundary (age == l2_book_snapshot_max_age_ms) which existing ATs cannot detect as a regression vector for off-by-one boundary handling.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -44,6 +44,6 @@
-AT-909
-- Given: `L2BookSnapshot` is missing, unparseable, or older than `l2_book_snapshot_max_age_ms` for an OPEN.
-- When: Liquidity Gate evaluates the order.
-- Then: the intent is rejected with `Rejected(LiquidityGateNoL2)` and no dispatch occurs.
-- Pass criteria: rejection reason matches; dispatch count remains 0.
-- Fail criteria: dispatch occurs or reason missing/mismatched.
+AT-909
+- Given: `L2BookSnapshot` age is exactly `l2_book_snapshot_max_age_ms` milliseconds (at staleness threshold boundary) for an OPEN intent.
+- When: Liquidity Gate evaluates the order.
+- Then: the intent is rejected with `Rejected(LiquidityGateNoL2)` and no dispatch occurs.
+- Pass criteria: rejection reason is `LiquidityGateNoL2`; dispatch count remains 0.
+- Fail criteria: dispatch occurs or intent is allowed despite snapshot age equaling `l2_book_snapshot_max_age_ms`.
```

## P-004

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-p4-lg3-20260319_034811-85f8f65e/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 AT-222 emergency close bypass clause`
- source_finding: `F-004`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `f004-at222-emergency-bypass-pass-fail-criteria`

### Rationale

F-004 identifies that AT-222's 'And' clause asserting emergency close bypass is unenforceable: no measurable outcome is specified. A conforming implementation can satisfy AT-222 without ever exercising the bypass path. Adding explicit pass/fail criteria with dispatch count and reject-reason checks makes the clause machine-verifiable.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -35,1 +35,3 @@
-- And: emergency close proceeds even if Liquidity Gate would reject under the same slippage conditions.
+- And: emergency close proceeds even if Liquidity Gate would reject under the same slippage conditions.
+  - Pass criteria: emergency close dispatch count >= 1; no `LiquidityGateNoL2` or `ExpectedSlippageTooHigh` rejection reason is emitted for the emergency close path.
+  - Fail criteria: emergency close is blocked by the slippage gate or a liquidity rejection reason is emitted for the emergency close path.
```

## P-005

- fixture: `s1_3_liquidity_gate_latest`
- source_path: `contract/phase2/outputs/phase2-p4-lg3-20260319_034811-85f8f65e/s1_3_liquidity_gate_latest/proposals.json`
- section: `§1.3 Algorithm step 4 — slippage equality boundary`
- source_finding: `F-005`
- source_finding_category: `stale_input_unspecified`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `f005-slippage-equality-boundary-at`

### Rationale

F-005 identifies that algorithm step 4 uses strict greater-than (slippage_bps > max_slippage_bps), so equality must be allowed. No existing AT tests this boundary. An implementation using >= instead of > would silently over-reject valid at-boundary orders without any AT detecting the regression. A boundary AT makes the strict inequality mechanically verifiable.

### Proposed Text

```text
AT-PROP-002
- Given: an L2 book where `OrderQty` consumes multiple levels resulting in `slippage_bps` exactly equal to `max_slippage_bps`; all non-liquidity gates are forced pass.
- When: Liquidity Gate evaluates an OPEN intent.
- Then: the intent is allowed (not rejected), because `slippage_bps == max_slippage_bps` does not exceed the rejection threshold.
- Pass criteria: dispatch count >= 1; no `ExpectedSlippageTooHigh` rejection reason is emitted.
- Fail criteria: intent is rejected with `Rejected(ExpectedSlippageTooHigh)` despite `slippage_bps` being exactly at the boundary.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -§1.3 after AT-1216 @@
+AT-PROP-002
+- Given: L2 book where OrderQty yields slippage_bps exactly == max_slippage_bps; all non-liquidity gates forced pass.
+- When: Liquidity Gate evaluates an OPEN intent.
+- Then: intent is allowed (not rejected); slippage_bps == max_slippage_bps does not exceed threshold.
+- Pass criteria: dispatch count >= 1; no ExpectedSlippageTooHigh emitted.
+- Fail criteria: intent rejected with Rejected(ExpectedSlippageTooHigh) at exact boundary.
```
