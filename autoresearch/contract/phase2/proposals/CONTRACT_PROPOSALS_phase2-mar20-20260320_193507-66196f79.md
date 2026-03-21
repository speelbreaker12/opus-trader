# Contract Proposals

- run_id: `phase2-mar20-20260320_193507-66196f79`
- proposals_file_hash: `4797f9ff0f91c86d571ec370a3c656682b9d06d5876ff0833995c6f577c1af83`
- proposal_count: `2`

## P-001

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar20-20260320_193507-66196f79/sample_contract_patch/proposals.json`
- section: `Acceptance Test References`
- source_finding: `F-001`
- source_finding_category: `cross_ref_broken`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `acceptance-test-reference-must-be-concrete`

### Rationale

The clause uses placeholder AT text rather than a concrete authoritative cross-reference, so the requirement cannot be traced deterministically to a real acceptance test.

### Proposed Text

```text
This clause MUST cite a concrete acceptance test identifier that directly validates the behavior it defines. Placeholder references such as AT-999 are invalid and MUST be replaced with the authoritative AT for the clause before the contract change is accepted.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -3,1 +3,2 @@
-AT-999 is referenced here
+This clause MUST cite a concrete acceptance test identifier that directly validates the behavior it defines.
+Placeholder references such as AT-999 are invalid and MUST be replaced with the authoritative AT for the clause before the contract change is accepted.
```

## P-002

- fixture: `sample_contract_patch`
- source_path: `contract/phase2/outputs/phase2-mar20-20260320_193507-66196f79/sample_contract_patch/proposals.json`
- section: `PolicyGuard`
- source_finding: `F-002`
- source_finding_category: `weak_normative`
- change_type: `mechanical`
- status: `pending_scope_review`
- dedupe_key: `policyguard-missing-data-must-reject`

### Rationale

The missing-data path is fail-closed behavior and must be mandatory; leaving it as SHOULD weakens enforcement and permits unsafe interpretation.

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -4,1 +4,1 @@
-PolicyGuard SHOULD reject when data is missing.
+PolicyGuard MUST reject when data is missing.
```
