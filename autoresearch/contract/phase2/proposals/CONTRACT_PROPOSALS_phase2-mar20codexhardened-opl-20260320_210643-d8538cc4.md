# Contract Proposals

- run_id: `phase2-mar20codexhardened-opl-20260320_210643-d8538cc4`
- proposals_file_hash: `fde1018477a9d622022b621aaa9ecf2ecca9d3113c99903bf96595d6a6034fb9`
- proposal_count: `2`

## P-001

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-opl-20260320_210643-d8538cc4/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001`
- source_finding: `F-001`
- source_finding_category: `cross_ref_broken`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `cp001-indirect-path-policyguard-at`

### Rationale

The current section only points to §2.2.3.2 at the section level, which leaves the latch -> SystemIntegrityAxis -> TradingMode::ReduceOnly proof obligation ambiguous. A local AT makes the indirect fail-closed path explicit and self-contained.

### Proposed Text

```text
- _Indirect path acceptance test:_ AT-1272 in this section MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into `SystemIntegrityAxis`, producing `TradingMode::ReduceOnly` and blocking OPEN dispatch through PolicyGuard authorization.

AT-1272
- Given: `open_permission_blocked_latch == true` due to any reconcile-class reason code.
- When: PolicyGuard evaluates `SystemIntegrityAxis` and dispatch authorization for an OPEN intent.
- Then: `open_permission_blocked_latch == true` MUST feed `DEGRADED` into `SystemIntegrityAxis`, `TradingMode` MUST resolve to `ReduceOnly`, and the OPEN intent MUST be rejected through PolicyGuard dispatch authorization.
- Pass criteria: `DEGRADED` input is recorded in `SystemIntegrityAxis`; `TradingMode::ReduceOnly` is computed; OPEN dispatch count remains 0.
- Fail criteria: the latch does not feed `DEGRADED`, `TradingMode` resolves to `Active`, or OPEN dispatch is allowed.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@
-- _Indirect path acceptance test:_ See §2.2.3.2 SystemIntegrityAxis ATs which MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into SystemIntegrityAxis, producing `TradingMode::ReduceOnly`.
+- _Indirect path acceptance test:_ AT-1272 in this section MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into `SystemIntegrityAxis`, producing `TradingMode::ReduceOnly` and blocking OPEN dispatch through PolicyGuard authorization.
+
+AT-1272
+- Given: `open_permission_blocked_latch == true` due to any reconcile-class reason code.
+- When: PolicyGuard evaluates `SystemIntegrityAxis` and dispatch authorization for an OPEN intent.
+- Then: `open_permission_blocked_latch == true` MUST feed `DEGRADED` into `SystemIntegrityAxis`, `TradingMode` MUST resolve to `ReduceOnly`, and the OPEN intent MUST be rejected through PolicyGuard dispatch authorization.
+- Pass criteria: `DEGRADED` input is recorded in `SystemIntegrityAxis`; `TradingMode::ReduceOnly` is computed; OPEN dispatch count remains 0.
+- Fail criteria: the latch does not feed `DEGRADED`, `TradingMode` resolves to `Active`, or OPEN dispatch is allowed.
```

## P-002

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-opl-20260320_210643-d8538cc4/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001`
- source_finding: `F-002`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `cp001-reconcile-stall-startup-default-at`

### Rationale

The section defines deterministic startup fallback for invalid `reconcile_stall_max_delay_s`, but there is no acceptance test proving the default-to-30s behavior and required startup warning. Adding a dedicated AT closes that coverage gap.

### Proposed Text

```text
AT-1273
- Given: startup occurs with `reconcile_stall_max_delay_s` missing, and separately with `reconcile_stall_max_delay_s <= 0`.
- When: runtime initializes reconciliation stall observability before reconciliation begins.
- Then: runtime MUST treat the effective threshold as the default `30s` and emit a startup warning log in both cases.
- And: if reconciliation later remains blocked continuously, `RECONCILE_STALL` emission MUST first occur only after the default `30s` threshold is exceeded.
- Pass criteria: startup warning log emitted for both invalid-input cases; effective threshold equals `30s`; later stall observability uses the default threshold.
- Fail criteria: no startup warning is emitted, effective threshold differs from `30s`, or later stall observability uses the invalid configured value.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@
 AT-1243
 - Given: `open_permission_blocked_latch == true` and reconciliation remains blocked beyond `reconcile_stall_max_delay_s`.
 - When: reconciliation stall observability evaluates.
 - Then: runtime emits structured `RECONCILE_STALL` log with the failing criterion, increments `reconcile_stall_total`, and keeps latch set with no override-clear.
 - And: for one continuous stall episode, emission occurs once at first threshold exceedance, with re-emission only on failing-criterion change; a new episode can emit again only after clear and re-stall.
 - Pass criteria: log + counter emitted with deterministic cadence and failing criterion; latch remains set.
 - Fail criteria: missing log/counter, missing failing criterion payload, repeated spam emission without criterion change/new episode, or latch cleared without reconciliation success.
+
+AT-1273
+- Given: startup occurs with `reconcile_stall_max_delay_s` missing, and separately with `reconcile_stall_max_delay_s <= 0`.
+- When: runtime initializes reconciliation stall observability before reconciliation begins.
+- Then: runtime MUST treat the effective threshold as the default `30s` and emit a startup warning log in both cases.
+- And: if reconciliation later remains blocked continuously, `RECONCILE_STALL` emission MUST first occur only after the default `30s` threshold is exceeded.
+- Pass criteria: startup warning log emitted for both invalid-input cases; effective threshold equals `30s`; later stall observability uses the default threshold.
+- Fail criteria: no startup warning is emitted, effective threshold differs from `30s`, or later stall observability uses the invalid configured value.
```
