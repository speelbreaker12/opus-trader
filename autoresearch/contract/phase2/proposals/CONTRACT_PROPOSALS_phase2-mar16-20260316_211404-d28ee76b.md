# Contract Proposals

- run_id: `phase2-mar16-20260316_211404-d28ee76b`
- proposals_file_hash: `bd95f7c071bdb52605d7a117ea2d0fec877f21cf1d06dda50c801782256fd2d7`
- proposal_count: `3`

## P-001

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar16-20260316_211404-d28ee76b/sample_contract_patch/proposals.json`
- section: `Sample Contract Fixture`
- source_finding: `F-001`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `proposed`
- dedupe_key: `policyguard_should_to_must_missing_data_l4`

### Rationale

Upgrading 'SHOULD' to 'MUST' closes the normative gap on PolicyGuard's rejection obligation when input data is missing. A fail-closed safety gate cannot be optional; permissive language permits compliant implementations that silently skip rejection, violating the fail-closed principle.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -4,1 +4,1 @@
-PolicyGuard SHOULD reject when data is missing.
+PolicyGuard MUST reject when data is missing.
```

## P-002

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar16-20260316_211404-d28ee76b/sample_contract_patch/proposals.json`
- section: `Sample Contract Fixture`
- source_finding: `F-002`
- source_finding_category: `cross_ref_broken`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `broken_at_ref_at999_l3`

### Rationale

AT-999 is cited inline on line 3 but no acceptance test with that identifier exists in the canonical AT registry. A broken cross-reference removes verifiable proof that the clause is tested; the reference must either be replaced with a registered AT-ID or removed and a new AT registered.

### Proposed Text

```text
Remove the dangling 'AT-999 is referenced here' line. Register a new acceptance test AT-PROP-001 in the canonical AT registry covering PolicyGuard rejection on missing data, then replace line 3 with the registered anchor 'AT-PROP-001'.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -3,1 +3,1 @@
-AT-999 is referenced here
+<!-- AT-PROP-001: PolicyGuard MUST reject on missing input — see AT registry -->
```

## P-003

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar16-20260316_211404-d28ee76b/sample_contract_patch/proposals.json`
- section: `Sample Contract Fixture`
- source_finding: `F-003`
- source_finding_category: `missing_fail_closed`
- change_type: `new_requirement`
- status: `rejected`
- dedupe_key: `missing_fail_closed_policyguard_reduce_only_l4`

### Rationale

The clause specifies rejection on missing data but omits the required safe-mode outcome. Without an explicit TradingMode transition (ReduceOnly or Kill), divergent implementations may reject the intent while leaving the system in Active mode, enabling further open-direction exposure. The fail-closed behaviour must be fully specified to be enforceable.

### Proposed Text

```text
Append to the clause on line 4: 'When any required input is absent, PolicyGuard MUST set TradingMode to ReduceOnly and hold that mode until the missing input is restored and passes staleness validation. PolicyGuard MUST NOT revert to Active without a successful input-complete evaluation tick.'
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -4,1 +4,2 @@
 PolicyGuard SHOULD reject when data is missing.
+When any required input is absent, PolicyGuard MUST set TradingMode to ReduceOnly and hold that mode until the missing input is restored and passes staleness validation. PolicyGuard MUST NOT revert to Active without a successful input-complete evaluation tick.
```
