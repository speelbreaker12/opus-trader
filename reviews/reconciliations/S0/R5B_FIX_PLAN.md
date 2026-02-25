# R5B Fix Plan — Slice 0

**Generated**: 2026-02-24
**Head**: e04a39f9150316caa2a97a5e371cbb5ab7284f5a
**Source**: `reviews/reconciliations/S0/SELF_REVIEW_R5b.md`

## Finding summary

- Blocking count: `P1 = 0`
- Advisory count: `P2 = 10`
- `P0 = 0`

## Conflict resolution notes

No contradictory findings across the six skill artifacts were observed for this slice; items below are merged by severity and domain.

## Ordered fix list

### P1 (must fix before R5b re-run) — all resolved

1. **F1 — S0-005 contract metadata scope alignment** [DONE]
    - **File(s)**: `plans/prd.json`
    - **Issue resolved**: `plans/prd.json:390-421` had endpoint-oriented labeling (`StatusEndpoint`) inconsistent with slice-0 CLI-only scope.
    - **Implementation**: Updated `S0-004.enforcement_point` to `StatusCommand` and retained explicit `partial_coverage_notes` for AT-022 transport deferral.
    - **Why this matters**: Keeps contract metadata aligned with the actual CLI-only proof surface in slice 0.

2. **F2 — Verify harness script coverage regression** [DONE]
    - **File(s)**: `plans/verify_fork.sh`
    - **Issue**: Missing/incorrect full-verify test path referenced at `plans/verify_fork.sh:683` (`test_story_review_gate.sh`).
    - **Implementation completed**: Added `plans/tests/test_story_review_gate.sh` shim to call `plans/tests/test_slice_review_gate.sh`.
    - **Current status**: CLOSED (path resolution restored in full-verify workflow).

3. **F3 — Slice-0 receipt completion risk behind `passes=true`** [DONE]
    - **File(s)**: `plans/prd_set_pass.sh` and workflow receipts (`.wf/receipts`)
    - **Issue**: `plans/prd_set_pass.sh:279-287` risks pass-flip while workflow receipts are incomplete for slice stories.
    - **Implementation completed**: `passes=true` path now verifies WF_STEP validity, required receipt files (`00..07_*.json`), and required receipt metadata (`head_sha`, `timestamp_utc`) before updating PRD status.
    - **Current status**: CLOSED (false-positive pass state path is now blocked unless receipts are complete).

4. **F4 — AT-023 transport-level proof gap** [DONE]
    - **File(s)**: `reviews/reconciliations/S0/GAP_LIST.json`, `reviews/reconciliations/S0/DEBT_REGISTER.json`, `reviews/reconciliations/S0/SELF_REVIEW_R5b.md`
    - **Issue**: `AT-023` transport/endpoint-level enforcement proof remains partial in this slice.
    - **Required action**: Keep AT-023 as explicit deferred debt with owner + target scope; do not claim PROVEN until transport proofs land in the target slice.
    - **Implementation**: `GAP-S0-004-007` was moved to `DEFERRED` and explicitly bound to `DEBT-S0-004-007` (`S8-9`).
    - **Why this is not blocking for this slice**: Transport evidence for AT-023 is out of scope in slice 0; deferral to S8-9 preserves traceability.
    - **Status**: **DONE**

5. **F5 — Probe key metadata validation hardening** [DONE]
    - **File(s)**: `stoic-cli` (probe/key validation paths)
    - **Issue resolved**: `_cmd_keys_check` now rejects malformed `env/exchange/key_id` values and missing/falsy `timestamp_utc` + `operator`.
    - **Implementation**: Added strict string-type metadata checks and a focused regression test in `crates/soldier_infra/tests/test_phase0_runtime.rs`.
    - **Why this matters**: Keeps AT-023/privilege enforcement claims from becoming permissive on partial probe data.

### P2 (should fix / debt candidate)

- **F5**: Fill governance ownership placeholders in `docs/launch_policy.md:11-12`.
- **F6**: Add/restore policy version cross-checks between `docs/launch_policy.md:8`, `config/policy.json`, `evidence/phase0/policy/policy_config_snapshot.json`.
- **F7**: Add policy loader numeric upper-bound validation for critical limits in `tools/policy_loader.py` (`tools/policy_loader.py:146-161`).
- **F8**: Add manifest digest enforcement in `plans/validators/validate_external_manifest.py:460-477`.
- **F9**: Remove/adjust proof-graph exemption bypasses in `plans/verify_fork.sh:658-667`.
- **F10**: Resolve artifacts schema policy-version inconsistency (`plans/lib/verify_checkpoint.sh:183-185` + `docs/schemas/artifacts.schema.json:26`).
- **F11**: Resolve pr-review scope/metadata mismatch at `plans/prd.json:366-385` + `crates/soldier_infra/src/lib.rs`.
- **F12**: Improve key-privilege proof isolation in `crates/soldier_infra/tests/test_phase0_runtime.rs:200-273`.
- **F13**: Align `AT-022` transport deferral metadata in docs/PRD consistency notes.
- **F15**: Re-run affected skill receipts after each fix batch per R5b.4.

## Blast radius estimate

- **Modified files (expected)**: 3–10
- **Cross-cutting risk**: Medium
- **Primary impact**: Verification gates and documentation/metadata consistency; low runtime behavior risk if implemented narrowly by file scope.
