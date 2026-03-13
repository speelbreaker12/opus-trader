# PRD Gate Help

## Environment Variables

| Env var | Default | Effect |
|---------|---------|--------|
| `PRD_REF_CHECK_ENABLED` | `1` | Set to `0` to skip ref check locally (CI always blocks; `PRD_GATE_ALLOW_REF_SKIP=1` only applies outside CI) |
| `PRD_GATE_ALLOW_REF_SKIP` | `0` | Allow `PRD_REF_CHECK_ENABLED=0` outside CI |
| `PRD_LINT_STRICT_HEURISTICS` | `0` | Fail on heuristic warnings |
| `PRD_LINT_ALLOW_SCHEMA_BYPASS` | `0` | Skip schema validation inside `prd_lint.sh` (warns only); `prd_gate.sh` still runs `prd_schema_check.sh` |

## Common Lint Failure Codes

These are diagnostic codes printed in `prd_lint.sh` output (not process exit codes):

| Code | Meaning |
|------|---------|
| `CREATE_PATH_EXISTS` | `scope.create` path already exists on disk |
| `CREATE_PARENT_MISSING` | `scope.create` parent directory doesn't exist |
| `SCHEMA_FAIL` | PRD doesn't match JSON schema |
| `MISSING_ANCHOR_REF` | `contract_refs` mentions anchor title but missing `Anchor-###` ID |
| `MISSING_VR_REF` | `contract_refs` mentions validation rule title but missing `VR-###` ID |

## Ref Check Errors

From `prd_ref_check.sh` (separate script):

```
[prd_ref_check] ERROR: unresolved contract_ref ...
[prd_ref_check] ERROR: unresolved plan_ref ...
```

Preferred `contract_refs` shape:
- Use stable, mechanically resolvable tokens such as `CONTRACT.md AT-132`, `CONTRACT.md LiquidityGateNoL2`, `CONTRACT.md §1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)`, `Anchor-###`, or `VR-###`.
- Avoid free-form prose sentences in `contract_refs`, especially slash-heavy text like `missing/unparseable/stale`, because `prd_ref_check.sh` splits refs into segments and may fail to resolve otherwise-valid prose.
- Put detailed behavioral wording in `acceptance`, `steps`, or `contract_must_evidence`; keep `contract_refs` compact and tokenized.

## Quick Fixes

**CREATE_PATH_EXISTS**: The `scope.create` path already exists. Either:
- Remove the path from `scope.create` (it's not a new file)
- Delete the existing file if it was scaffolded incorrectly
- Move to `scope.touch` if editing an existing file

**CREATE_PARENT_MISSING**: The parent directory for a `scope.create` path doesn't exist:
- Create the parent directory first
- Check for typos in the path

**MISSING_ANCHOR_REF / MISSING_VR_REF**: Contract references need explicit IDs:
- Find the anchor/VR in `specs/CONTRACT.md`
- Add the ID in format: `"Anchor-001: Title"` or `"VR-001: Title"`

**unresolved contract_ref / plan_ref**: Make the ref more mechanical:
- Replace prose sentences with a stable token, section ID, or anchor, for example:
  - `CONTRACT.md LiquidityGateNoL2`
  - `CONTRACT.md AT-132`
  - `CONTRACT.md §1.3 Pre-Trade Liquidity Gate (Do Not Sweep the Book)`
- Keep the detailed sentence in `acceptance` or `steps`, not in `contract_refs`

## Pass-Gate Preview (Dry Run)

Use dry-run to execute all `passes=true` validations without mutating `plans/prd.json`:

```bash
VERIFY_ARTIFACTS_DIR="artifacts/verify/<run_id>" \
  ./plans/prd_set_pass.sh <STORY_ID> true --dry-run
```

Expected behavior:
- Returns `0` when the story is passable with provided artifacts.
- Returns non-zero with the same gate diagnostics as a real pass flip.
- Leaves `plans/prd.json` unchanged.

## See Also

- `plans/prd_lint.sh` - PRD linting rules
- `plans/prd_schema_check.sh` - Schema validation
- `plans/prd_ref_check.sh` - Reference resolution
