# SKILL: /contract-audit-full (Full Contract Coverage + Conflict Audit)

## Purpose
Answer two questions with receipts:
1) **Coverage:** Does the PRD fully cover the contract requirements for the declared compliance profile (CSP / GOP / FULL)?
2) **Conflicts/Ambiguities:** Does the PRD contradict the contract, underspecify contract semantics, or leave "unknowns" that will cause rework later?

This is an *exhaustive* audit. It is allowed to produce a long report.

## Related skills
- Use **/contract-review** for fast PR-level "fail-open hazard" checks on code diffs.
  - /contract-audit-full is exhaustive and slower; /contract-review is the quick safety filter.

## Required inputs
- `CONTRACT.md` (canonical)
- `prd.json` (PRD stories)
- Optional but recommended:
  - `IMPLEMENTATION_PLAN.md`
  - `ROADMAP.md` / `roadmap.json`
  - Repo checkout (so the auditor can verify test file existence)

## Core principles (non-negotiable)
- **Fail-closed on CSP:** Any missing CSP acceptance test coverage is a BLOCKER.
- **GOP is profile-gated:** GOP failures must disable GOP features, but must not break CSP safety.
- **No "hand-wavy mapping":** A contract requirement is covered only if it maps to:
  - a PRD story AND
  - a concrete implementation surface AND
  - a concrete test or acceptance proof (AT-* or explicit test path)

## Step 0 — Determine target compliance profile
The audit must declare:
- `target_enforced_profile`: CSP | GOP | FULL
- `target_supported_profiles`: set
Then interpret requirements accordingly.

## Step 1 — Extract contract obligations
Build two inventories:

### 1A) Acceptance tests inventory
Extract every `AT-###` from CONTRACT.md and record:
- AT id
- nearest `Profile:` tag (CSP or GOP)
- title / "Given/When/Then" summary
- referenced section (§)

### 1B) Non-AT normative obligations
Extract requirements that may not be expressed as ATs, including:
- explicit "MUST" invariants
- repo-level harness requirements
- endpoint key lists + semantics
- profile isolation rules
For each, create a synthetic requirement id:
- `REQ-<section>-<slug>`

## Step 2 — Build PRD coverage matrix

### 2a) Run the mechanical matrix tool (mandatory first step)
```bash
./plans/contract_prd_matrix.sh
```
This emits four files into `evidence/doc_sync/`:
- `contract_prd_matrix.tsv` / `.json` — per-AT rows with owners, `suggested_status`, proof/enforcement flags
- `prd_invalid_at_refs.tsv` — phantom ATs (referenced by PRD but absent in CONTRACT.md), with `passes` state
- `prd_story_index.tsv` — per-story summary of AT refs, proof, enforcement, scope

Use the tool's `suggested_status` as your starting point. The tool handles the mechanical O(AT × stories) cross-join across all three PRD fields (`enforcing_contract_ats`, `contract_refs`, `contract_must_evidence.anchor`). Your job is to **validate and override** the suggestions — the tool cannot judge deferred items, ambiguity resolution, or conflict detection.

### 2b) Audit the matrix
For each contract AT / REQ, review the tool's suggested status and finalize:
Mark status:
- **COVERED**: mapped to story + enforcement point named + test/proof specified
- **DEFERRED**: explicitly deferred with reason + target phase AND allowed by profile rules
- **MISSING**: no story owns it
- **AMBIGUOUS**: multiple stories claim ownership without a clear primary OR story references are too vague
- **INVALID_REF**: PRD references an AT-* that does not exist in CONTRACT.md (planned/phantom AT)

### Coverage definition (strict)
An item is COVERED only if PRD provides:
- owner story id(s)
- enforcement point (PolicyGuard / DispatcherChokepoint / StatusEndpoint / etc.)
- test proof:
  - AT id mapped to at least one concrete test path, OR
  - explicit endpoint-level test requirement and a named test file/function

Without enforcement point AND proof, the item is **CLAIMED**, not COVERED.

### Contract AT existence rule (hard)
- If a PRD story references an `AT-*` that is **not present** in CONTRACT.md:
  - mark that mapping as **INVALID_REF**
  - do **not** count it toward coverage
  - if the story is `passes=true`, treat as a **BLOCKER** (completed against a phantom contract)

## Step 3 — Detect conflicts and ambiguities
You MUST report:
- PRD acceptance text that contradicts contract semantics (fields missing, wrong types, wrong staleness rule, etc.)
- PRD that gates CSP decisions on GOP-only signals when `enforced_profile == CSP`
- Endpoint mismatches:
  - `/api/v1/health` required keys + semantics must match contract
  - `/api/v1/status` CSP minimum + GOP extension behavior must match contract
- Missing paired tests for guards:
  - contract requires TRIP + NON-TRIP for any guard that can block OPEN / change mode / emit override
- "Undefined terms" in PRD (reason codes, modes, latches) not grounded in contract registries

## Step 4 — Test existence + causality checks (if repo available)
For each PRD story that claims coverage:
- Verify referenced test files exist
- Verify TRIP/NON-TRIP exists where required
- Verify tests prove causality (dispatch count OR reason code OR latch code OR override field)

### Story state rule for test existence (hard)
- If the PRD story is `passes=true`:
  - referenced tests MUST exist (missing tests = **BLOCKER**)
  - coverage can be marked VERIFIED only when tests exist and are relevant
- If the PRD story is `passes=false`:
  - missing tests may be marked **EXPECTED-MISSING**
  - BUT the audit must keep the contract items in status **MISSING** or **CLAIMED**, not VERIFIED/COVERED

If repo is not available, mark coverage as:
- **CLAIMED** (not verified) and list what is needed to verify.

## Step 5 — Output a synchronization verdict
Provide:
- Coverage % for CSP ATs (must be 100% to ship CSP)
- Coverage % for GOP ATs (only required to enable GOP)
- List of blockers (must-fix)
- List of de-risk items (recommended improvements)
- Exact patch recommendations:
  - PRD edits (story ownership, refs, acceptance, tests)
  - Contract clarifications (only if contract is ambiguous)
  - Plan/roadmap updates (only if drift exists)

## Output format (required)
```markdown
# Contract <-> PRD Full Audit

## Declared target profile
- enforced_profile: <CSP|GOP|FULL>
- supported_profiles: [...]

## Summary
- CSP coverage: <x>/<y> ATs covered (must be 100%)
- GOP coverage: <x>/<y> ATs covered
- Blockers: <count>
- Conflicts: <count>
- Ambiguities: <count>

## Blockers (must fix)
### AT-### / REQ-...
- Why missing/conflicting
- PRD owner story needed or patch needed
- Required test/proof

## Conflicts
### <title>
- Contract reference
- PRD story reference
- Exact contradiction
- Patch recommendation

## Ambiguities
- Multiple owners, unclear enforcement point, vague acceptance criteria
- Patch recommendation (choose one owner; add explicit acceptance + tests)

## Coverage Matrix
| Contract Item | Profile | Status | PRD Owner | Enforcement Point | Proof/Test |
|---|---|---|---|---|---|

## Recommended PRD patches (ready-to-apply)
- Provide unified diff patches when requested
```

## Quick commands (optional helpers)
```bash
# Contract AT inventory
rg -n "AT-[0-9]{3,4}" CONTRACT.md

# PRD ownership (includes passes state and contract_must_evidence anchors)
jq -r '.items[]
  | [
      .id,
      (.passes|tostring),
      ((.enforcing_contract_ats // []) | join(",")),
      ((.contract_refs // []) | join("|")),
      ((.contract_must_evidence // []) | map(.anchor // "") | join("|"))
    ]
  | @tsv' prd.json

# Find AT mentions in PRD quickly
rg -n "AT-[0-9]{3,4}" prd.json
```
