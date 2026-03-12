# Operator Surface Contract Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add contract-backed operator presentation surface rules that preserve `/api/v1/status` as the sole runtime authority, keep P0 owner scaffolding separate, and make dashboard / derived-operator-surface semantics explicit and fail-closed.

**Architecture:** Keep the patch centered in `specs/CONTRACT.md`, primarily in the existing status authority material and §7.0. Preserve the existing distinction between P0 owner scaffolding and downstream operator presentation surfaces. If `runtime_state.v1` remains in the proof path, define it as an explicitly derived operator-state document whose semantics must match canonical status conclusions even when field names are renamed or reshaped. Prove the change through existing status-contract and publisher tests so the new operator-surface semantics are validated by fixtures and contract-model checks, not just prose.

**Tech Stack:** Markdown contract docs, Python/pytest status-contract tests, TypeScript status contract probe, existing contract-crossref and verify scripts

---

### Task 1: Prepare A Clean Execution Context

**Files:**
- Modify: none
- Test: none

**Step 1: Check worktree cleanliness**

Run:

```bash
git status --short
```

Expected:
- No unresolved merge entries like `UU`.
- No unrelated dirty files in paths that will interfere with a focused contract patch.

**Step 2: Move to a clean worktree if needed**

Run:

```bash
git worktree list
```

Expected:
- A clean worktree is available, or a new one can be created from the intended integration branch.

**Step 3: Confirm the current authority baseline before edits**

Run:

```bash
rg -n "Status authority matrix|Status surface split|Foundation status-lite mode|7\\.0 Owner Control Plane Endpoints|runtime_state\\.v1|P0 owner scaffolding" specs/CONTRACT.md dashboard tests
```

Expected:
- Existing status authority material, the P0 owner-scaffolding carve-out, and the current publisher/runtime-state surfaces are visible and ready for patching.

**Step 4: Commit**

```bash
git status --short
```

Expected:
- Still clean before starting the contract patch.

### Task 2: Add Operator Presentation Surface Rules To The Contract

**Files:**
- Modify: `specs/CONTRACT.md`
- Test: `scripts/check_contract_crossrefs.py`

**Step 1: Write the failing expectation by locating the insertion points**

Run:

```bash
sed -n '140,190p' specs/CONTRACT.md
sed -n '4697,4805p' specs/CONTRACT.md
```

Expected:
- The current status authority matrix and §7.0 text do not yet define operator presentation surfaces.

**Step 2: Add the minimal contract text**

Implement:
- extend the status authority matrix with `Operator Presentation Surfaces`
- add `7.0.1 Runtime Authority vs Operator Presentation Surfaces`
- add normative rules for:
  - non-authoritative consumption
  - P0 owner scaffolding remaining a separate category
  - direct vs derived operator-state consumption
  - freshness and fail-closed presentation semantics
  - semantic equivalence for renamed/reshaped fields
  - conflict prohibition for canonical fields reused by name
  - foundation-mode boundary preservation
- add `AT-OP1`, `AT-OP2`, `AT-OP3`, and `AT-OP4`

**Step 3: Update the contract change ledger**

Implement:
- add a short entry describing the operator-surface authority clarification and the risk it prevents

**Step 4: Run contract cross-reference checks**

Run:

```bash
python scripts/check_contract_crossrefs.py
```

Expected:
- PASS with no broken anchors or missing references.

**Step 5: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: define operator presentation surface semantics"
```

### Task 3: Align The Implementation Plan If The New Contract Text Needs Traceability

**Files:**
- Modify: `specs/IMPLEMENTATION_PLAN.md`
- Test: `plans/contract_check.sh`

**Step 1: Write the failing expectation**

Run:

```bash
rg -n "status authority|dashboard|owner status|presentation surface|status-lite" specs/IMPLEMENTATION_PLAN.md
```

Expected:
- The plan references status authority and dashboards, but does not yet mention operator presentation surface rules explicitly.

**Step 2: Add only the minimum traceability updates**

Implement:
- add one short traceability note tying the new operator-surface contract rules to existing status/dashboard work
- state explicitly that P0 owner scaffolding remains separate from downstream operator presentation surfaces
- if `runtime_state.v1` remains in scope, note that it is derived/non-authoritative rather than a second canonical source
- do not broaden the roadmap into bot lifecycle or multi-exchange scope

**Step 3: Run contract-plan consistency checks**

Run:

```bash
./plans/contract_check.sh
```

Expected:
- PASS, or a clear actionable failure pointing to any missing traceability.

**Step 4: Commit**

```bash
git add specs/IMPLEMENTATION_PLAN.md
git commit -m "docs: align implementation plan with operator surface rules"
```

### Task 4: Add Status-Contract Tests For Operator Presentation Semantics

**Files:**
- Modify: `tests/test_status_contract_model.py`
- Modify: `tests/test_publisher_contract.py`
- Create or Modify: `tests/fixtures/runtime_state/*.json`
- Create or Modify: `tests/fixtures/status/*.json`
- Test: `tests/probes/status_contract_probe.ts`

**Step 1: Write the failing tests**

Implement tests that express:
- stale or unreadable operator-source status cannot imply OPEN eligibility
- foundation-mode presentation cannot synthesize CSP authority fields
- convenience summaries cannot contradict canonical blocked state
- reused canonical field names must match exactly, while renamed or reshaped fields must remain semantically equivalent
- if `runtime_state.v1` remains in scope, it behaves as derived operator state rather than a second authority source

Candidate test additions:
- `test_operator_surface_semantic_equivalence_without_wire_identity_requirement`
- `test_operator_surface_stale_source_degrades_to_unknown_or_stale`
- `test_operator_surface_preserves_foundation_status_lite_boundary`
- `test_operator_surface_summary_cannot_override_canonical_block_state`
- `test_runtime_state_v1_is_derived_non_authoritative_operator_state`

**Step 2: Run only the new or affected tests and verify failure**

Run:

```bash
pytest tests/test_status_contract_model.py tests/test_publisher_contract.py -q
```

Expected:
- FAIL for the newly added expectations before implementation changes land.

**Step 3: Add the minimum fixture and model changes needed**

Implement:
- update fixtures to represent fresh, stale, and foundation-mode operator presentation cases
- adjust contract-model or publisher expectations only enough to satisfy the new contract semantics
- if `runtime_state.v1` stays in scope, add or update fixtures proving it preserves canonical blocked/open conclusions
- avoid forcing dashboard or publisher schemas to match `/status` byte-for-byte unless the contract patch explicitly reuses the same canonical field names
- avoid widening P0 owner scaffolding or foundation status-lite scopes

**Step 4: Run the focused tests and verify pass**

Run:

```bash
pytest tests/test_status_contract_model.py tests/test_publisher_contract.py -q
```

Expected:
- PASS

**Step 5: Commit**

```bash
git add tests/test_status_contract_model.py tests/test_publisher_contract.py tests/fixtures/status tests/fixtures/runtime_state tests/probes/status_contract_probe.ts
git commit -m "test: prove operator surface status semantics"
```

### Task 5: Run Contract And Verify Gates

**Files:**
- Modify: none
- Test: existing gate scripts

**Step 1: Run status-specific validation**

Run:

```bash
pytest tests/test_stoic_cli_runtime_state_v1.py tests/test_validate_status_semantics_versioning.py tests/test_validate_status_manifest_override.py -q
```

Expected:
- PASS

**Step 2: Run contract and crossref gates**

Run:

```bash
./plans/contract_check.sh
python scripts/check_contract_crossrefs.py
```

Expected:
- PASS

**Step 3: Run quick verify**

Run:

```bash
./plans/verify.sh quick
```

Expected:
- PASS

**Step 4: Run full verify**

Run:

```bash
./plans/verify.sh full
```

Expected:
- PASS with artifact output under `artifacts/verify/<run_id>/`

**Step 5: Commit**

```bash
git status --short
```

Expected:
- Clean worktree with all intended commits present.

### Task 6: Run Final Review And Close The Patch

**Files:**
- Modify: none
- Test: review artifacts

**Step 1: Run code review on the changed contract/test surface**

Use:
- `code-review-expert`

Expected:
- Findings addressed before final verify.

**Step 2: Re-run quick verify after review fixes**

Run:

```bash
./plans/verify.sh quick
```

Expected:
- PASS

**Step 3: Re-run full verify**

Run:

```bash
./plans/verify.sh full
```

Expected:
- PASS

**Step 4: Commit**

```bash
git add specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md tests/test_status_contract_model.py tests/test_publisher_contract.py tests/fixtures/status tests/fixtures/runtime_state
git commit -m "docs: add operator presentation surface contract"
```

## Notes

- Keep the patch semantic, not schema-heavy.
- Do not add write endpoints in this story.
- Do not widen scope into bot lifecycle, strategy editing, or multi-exchange semantics.
- If the current worktree remains dirty or unresolved, execute this plan from a clean dedicated worktree before touching the contract.
