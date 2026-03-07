# Foundation Status Authority Transition Implementation Plan

> **Status:** SUPERSEDED on 2026-03-07.
> This plan encodes the withdrawn `foundation_exit_condition == (phase != foundation)` approach.
> Do not implement it. Use `docs/plans/2026-03-07-foundation-exit-runtime-design.md` instead.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the `/api/v1/status` authority transition fail-closed by defining the foundation exit predicate explicitly in the contract and proving the schema switch with acceptance tests.

**Architecture:** Treat `phase == foundation` as the only condition that keeps `/api/v1/status` in status-lite mode; every other case must use the CSP minimum schema and become the canonical authority surface. Tighten the normative contract text first, then keep the executable validator proof aligned so docs and runtime checks cannot drift.

**Tech Stack:** Markdown contract/docs, Python validator/tests, JSON fixtures, repo verify harness.

---

### Task 1: Add executable transition proof

**Files:**
- Modify: `tests/test_validate_status_manifest_override.py`
- Reuse: `tests/fixtures/status/market_data_stale.json`
- Reuse: `tools/validate_status.py`

**Step 1: Add the transition guard tests**

Add two focused tests:

```python
def test_cli_auto_schema_rejects_non_foundation_status_lite_payload(tmp_path: Path) -> None:
  status = {
    "service_up": True,
    "build_id": "phase-transition-test",
    "contract_version": "5.2",
    "dispatch_enabled": False,
    "phase": "bootstrap_complete",
  }

  proc = _run_validator_cli(status, tmp_path)
  assert proc.returncode == 1
  assert "[CSP-MIN] Missing required key: status_schema_version" in proc.stderr


def test_cli_auto_schema_accepts_csp_payload_outside_foundation(tmp_path: Path) -> None:
  status = json.loads((ROOT / "tests" / "fixtures" / "status" / "market_data_stale.json").read_text())

  proc = _run_validator_cli(status, tmp_path)
  assert proc.returncode == 0, proc.stderr
```

**Step 2: Run the targeted validator test file**

Run: `pytest tests/test_validate_status_manifest_override.py -q`

Expected: the new tests either pass immediately as executable proof or fail red and expose the missing transition behavior before any contract wording is changed.

**Step 3: Tighten assertions if needed**

If the failure message is different but still proves the CSP-minimum branch, tighten the assertion to the exact stable stderr line emitted by `tools/validate_status.py`.

**Step 4: Re-run the targeted validator test file**

Run: `pytest tests/test_validate_status_manifest_override.py -q`

Expected: green proof for both the `phase == foundation` branch and the `phase != foundation` branch.

**Step 5: Commit**

```bash
git add tests/test_validate_status_manifest_override.py
git commit -m "test: prove foundation status authority transition"
```

### Task 2: Make the contract predicate explicit

**Files:**
- Modify: `specs/CONTRACT.md`
- Modify: `specs/IMPLEMENTATION_PLAN.md`
- Modify: `docs/health_endpoint.md`
- Conditionally modify: `plans/prd.json`

**Step 1: Define the exit predicate in the contract**

In `specs/CONTRACT.md`, add explicit normative wording near the status authority matrix / precedence block:

```md
For `/api/v1/status`, `foundation_exit_condition` is satisfied when `phase != foundation`.
While `foundation_exit_condition` is false, `/api/v1/status` MUST remain status-lite.
When `foundation_exit_condition` is true, `/api/v1/status` MUST satisfy the full §7.0 CSP minimum schema.
```

**Step 2: Replace ambiguous wording**

Replace each ambiguous “after foundation mode exits” reference in:

- `specs/CONTRACT.md`
- `specs/IMPLEMENTATION_PLAN.md`
- `docs/health_endpoint.md`

with predicate-backed wording such as ``when `phase != foundation` `` or ``once `foundation_exit_condition` is true``.

**Step 3: Add a transition acceptance clause**

Add a compact acceptance clause near the existing P0-E / §7.0 status authority text, for example:

```md
**AT-P0E-TRANSITION**
- Given: `/api/v1/status` is emitted with `phase != foundation`.
- When: the payload is validated for authority/readiness use.
- Then: it MUST satisfy the full §7.0 CSP minimum schema.
- And: P0 owner scaffolding MUST remain non-authoritative for readiness/dispatch decisions.
```

**Step 4: Keep traceability consistent**

If you introduce a new AT identifier instead of extending existing text, update `plans/prd.json` story `S0-004` so the new acceptance/proof requirement is traceable.

**Step 5: Run the contract/PRD checks that match the touched files**

Run:

```bash
rg -n "after foundation mode exits|foundation_exit_condition" specs docs plans
./plans/prd_gate.sh
./plans/prd_audit_check.sh
```

Expected:
- ambiguous wording is gone from canonical files
- PRD validation passes if `plans/prd.json` changed
- audit check stays green or fails only for an expected stale-audit reason that must then be regenerated

**Step 6: Commit**

```bash
git add specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md docs/health_endpoint.md plans/prd.json
git commit -m "docs: define foundation status authority transition"
```

### Task 3: Mirror the rule in validator control flow

**Files:**
- Modify: `tools/validate_status.py`
- Test: `tests/test_validate_status_manifest_override.py`

**Step 1: Make the branch explicit in code**

If the contract introduces `foundation_exit_condition`, mirror that terminology in `tools/validate_status.py` so schema selection is self-documenting:

```python
def is_foundation_status(status: dict[str, Any]) -> bool:
    return status.get("phase") == "foundation"


def foundation_exit_condition(status: dict[str, Any]) -> bool:
    return not is_foundation_status(status)
```

**Step 2: Reuse the explicit helper at both branch points**

Use the explicit predicate where the validator:
- selects the default schema path
- chooses between `check_foundation_status_contract(...)` and CSP minimum/invariant checks

**Step 3: Preserve fail-closed behavior**

Do not add any fallback that reclassifies unknown or missing phase values as foundation. Missing/unknown phase must continue to route to the CSP-minimum branch, which fails closed unless the full authority payload is present.

**Step 4: Re-run the targeted tests**

Run: `pytest tests/test_validate_status_manifest_override.py -q`

Expected: the behavior stays unchanged, but the code now matches the contract vocabulary exactly.

**Step 5: Commit**

```bash
git add tools/validate_status.py tests/test_validate_status_manifest_override.py
git commit -m "refactor: name foundation exit predicate in status validator"
```

### Task 4: Verify and review the full change set

**Files:**
- Review: `specs/CONTRACT.md`
- Review: `specs/IMPLEMENTATION_PLAN.md`
- Review: `docs/health_endpoint.md`
- Review: `tools/validate_status.py`
- Review: `tests/test_validate_status_manifest_override.py`

**Step 1: Run targeted status validation tests**

Run:

```bash
pytest tests/test_validate_status_manifest_override.py tests/test_validate_status_semantics_versioning.py -q
```

Expected: all status-validator tests pass, including the new transition proof.

**Step 2: Run repository verification**

Run: `./plans/verify.sh quick`

Expected: quick verify passes, or it fails only on unrelated pre-existing repo issues that are captured as artifacts and called out explicitly.

**Step 3: Run the required review step**

Run the `code-review-expert` skill on the final diff before any merge/pass-flow claims.

**Step 4: If this is a story branch, continue the workflow contract loop**

Follow `specs/WORKFLOW_CONTRACT.md`:
- self review
- review cycle 1
- quick verify
- review cycle 2
- quick verify
- full verify
- `plans/prd_set_pass.sh`

**Step 5: Commit the final verify-ready state**

```bash
git status --short
git log --oneline -n 5
```

Expected: only the intended contract/doc/test changes remain in scope, with evidence-backed verification.

---

## Assumptions

- `phase == foundation` remains the only status-lite condition for `/api/v1/status`.
- The desired fix is contract clarity + proof, not a broader redesign of phase enumeration.
- The existing validator behavior is directionally correct; the missing piece is explicit contract wording and transition coverage.

## Open Questions

- If maintainers want a closed enum of post-foundation phase values, that should be a separate follow-up from this review fix.
- If the new transition clause receives its own AT identifier, confirm whether `S0-004` should own that traceability or whether it belongs to a later CSP status story.
