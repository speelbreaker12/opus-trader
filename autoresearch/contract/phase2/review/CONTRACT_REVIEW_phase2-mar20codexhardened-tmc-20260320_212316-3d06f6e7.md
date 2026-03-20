# Contract Review Package

- run_id: `phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7`
- contract_file_hash: `09b3885d5af5f1d3ede265940ff2441e8964042cbfb8abe1d9b2af183c76ff55`
- proposals_file_hash: `c223b47b2e85b5444c4fbc14b5f885287b21a895aba264437d9bc8fa43792f1f`
- proposal_count: `3`

## Manual Review Checklist

1. Read every proposal below.
2. Record one decision per proposal in `REVIEW_DECISIONS_<run_id>.json`.
3. Use `accepted`, `rejected`, or `pending_scope_review` only.
4. Re-run `harness.sh contract render-review --accepted-only` after writing review decisions.
5. Do not apply any accepted-only patch if the live `CONTRACT.md` hash differs from the recorded `contract_file_hash`.
6. Keep `sample_contract_patch` proposals rejected unless explicitly moved to a first-party fixture.

## P-001 — gate_interaction_gap

- fixture: `s2_2_3_trading_mode_computation_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7/s2_2_3_trading_mode_computation_latest/proposals.json`
- section: `2.2.3.1.2`
- change_type: `new_requirement`
- source_finding: `F-001`
- current_status: `proposed`

### Rationale

Clarifies that failed corroboration on a non-capital Kill predicate downgrades only that predicate and cannot override simultaneous winning Kill-tier triggers already resolved by Section 2.2.3.3. This removes ambiguity about final mode resolution and preserves tier-pure reason emission.

### Proposed Text

```text
Add under Section 2.2.3.1.2 Unconfirmed behavior: If a watchdog or disk Kill primary predicate is true but corroboration fails, that predicate MUST be downgraded only for that predicate's contribution to `SystemIntegrityAxis`. Final `TradingMode` MUST still be resolved from the full coherent snapshot per §2.2.3.3. Therefore, if any other confirmed or authoritative Kill-tier trigger is simultaneously active in the same tick (`risk_state == Kill`, `mm_util >= mm_util_kill`, `cortex_override == ForceKill`, or `session_termination_active == true`), PolicyGuard MUST compute `TradingMode == Kill` and MUST emit only the winning-tier `KILL_*` reasons.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -53,4 +53,9 @@
 **Unconfirmed behavior (Non‑Negotiable):**
 - If the primary predicate is true but confirmation fails, PolicyGuard MUST compute `TradingMode = ReduceOnly`
   and include the appropriate `REDUCEONLY_*_UNCONFIRMED` reason code.
+- Failed corroboration on a watchdog or disk Kill predicate downgrades only that predicate's contribution to
+  `SystemIntegrityAxis`; it does not override other active Kill-tier predicates in the same coherent snapshot.
+- Final `TradingMode` MUST still be resolved per §2.2.3.3.
+- Therefore, if any simultaneous confirmed or authoritative Kill-tier trigger is active, PolicyGuard MUST compute
+  `TradingMode == Kill` and MUST emit only the winning-tier `KILL_*` reasons.
```

## P-002 — stale_input_unspecified

- fixture: `s2_2_3_trading_mode_computation_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7/s2_2_3_trading_mode_computation_latest/proposals.json`
- section: `2.2.3.1.2`
- change_type: `new_requirement`
- source_finding: `F-002`
- current_status: `proposed`

### Rationale

Specifies exact handling for stale or missing disk sample timestamps so disk corroboration failures map to one deterministic reason path instead of competing with the generic stale-input reason. This aligns disk freshness failures with the existing Disk Kill unconfirmed semantics.

### Proposed Text

```text
Add under Section 2.2.3.1.2 Disk Kill corroboration: If `disk_used_pct >= disk_kill_pct` but `disk_used_pct_secondary` is missing, unparseable, below threshold, or stale, or if either disk sample timestamp is missing, unparseable, or older than `disk_used_max_age_ms`, PolicyGuard MUST treat Disk Kill as unconfirmed and MUST emit `REDUCEONLY_DISK_KILL_UNCONFIRMED`. That disk-corroboration freshness failure MUST NOT be surfaced as `REDUCEONLY_INPUT_MISSING_OR_STALE` unless some other independent critical input is missing, unparseable, or stale in the same tick.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -47,3 +47,8 @@
 - **Disk Kill (confirmed):**
   `disk_used_pct >= disk_kill_pct` **AND** `disk_used_pct_secondary >= disk_kill_pct`,
   with both timestamps fresh per `disk_used_max_age_ms`.
+- If `disk_used_pct >= disk_kill_pct` but `disk_used_pct_secondary` is missing, unparseable, below threshold, or stale,
+  or if either disk sample timestamp is missing, unparseable, or older than `disk_used_max_age_ms`, PolicyGuard MUST
+  treat Disk Kill as unconfirmed and emit `REDUCEONLY_DISK_KILL_UNCONFIRMED`.
+- That disk-corroboration freshness failure MUST NOT be surfaced as `REDUCEONLY_INPUT_MISSING_OR_STALE` unless some
+  other independent critical input is missing, unparseable, or stale in the same tick.
```

## P-003 — missing_at_pair

- fixture: `s2_2_3_trading_mode_computation_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7/s2_2_3_trading_mode_computation_latest/proposals.json`
- section: `2.2.3.5`
- change_type: `new_requirement`
- source_finding: `F-003`
- current_status: `proposed`

### Rationale

Adds the missing acceptance coverage for simultaneous Kill predicates so the contract proves completeness, canonical ordering, and tier purity for multi-Kill `mode_reasons` emission.

### Proposed Text

```text
Add a new acceptance test under Section 2.2.3.5: `AT-1282` - Given: `risk_state == Kill`, `session_termination_active == true`, and `bunker_mode_active == true`; all other Kill-tier predicates inactive. - When: `TradingMode` and `mode_reasons` are computed for that tick. - Then: `TradingMode == Kill` and `mode_reasons == [KILL_RISKSTATE_KILL, KILL_RATE_LIMIT_SESSION_TERMINATION]`. - Pass criteria: all active Kill-tier reasons are present, listed in canonical registry order, and no `REDUCEONLY_*` reason appears despite the simultaneous ReduceOnly predicate. - Fail criteria: any active Kill-tier reason missing, order non-canonical, or any `REDUCEONLY_*` reason mixed into `mode_reasons`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -287,11 +287,18 @@
 - `mode_reasons` MUST include **all** active reasons from the **computed TradingMode tier** for that tick.
 - Reasons from non-winning tiers MUST NOT be included (tier purity).
 
 **Acceptance Tests:**
 
 AT-1244
 - Given: PolicyGuard computes `TradingMode == ReduceOnly` with multiple active reduce-only predicates (e.g., `risk_state == Degraded` AND `bunker_mode_active == true` AND `open_permission_blocked_latch == true`).
 - When: `mode_reasons` is computed for that tick.
 - Then: `mode_reasons` MUST contain all applicable `REDUCEONLY_*` reason codes, in the canonical order defined above, and MUST NOT contain any `KILL_*` codes.
 - Pass criteria: reasons are tier-pure (only `REDUCEONLY_*`), complete (all active predicates represented), and deterministically ordered per the registry above.
 - Fail criteria: missing active reason, `KILL_*` code present, or order deviates from canonical registry.
+
+AT-1282
+- Given: `risk_state == Kill`, `session_termination_active == true`, and `bunker_mode_active == true`; all other Kill-tier predicates inactive.
+- When: `TradingMode` and `mode_reasons` are computed for that tick.
+- Then: `TradingMode == Kill` and `mode_reasons == [KILL_RISKSTATE_KILL, KILL_RATE_LIMIT_SESSION_TERMINATION]`.
+- Pass criteria: all active Kill-tier reasons are emitted, canonical registry order is preserved, and no `REDUCEONLY_*` reason appears.
+- Fail criteria: any active Kill-tier reason missing, order non-canonical, or any `REDUCEONLY_*` reason mixed into `mode_reasons`.
```
