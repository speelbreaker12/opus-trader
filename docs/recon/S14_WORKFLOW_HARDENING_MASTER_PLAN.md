# S14 Workflow Hardening Master Plan

## Status
- Last updated: 2026-02-26
- Goal: consolidate artifact hardening and reconciliation portability into one executable plan.
- Execution model: one master plan, multiple scoped PR phases.

## Locked Decisions
1. Contract review auto-seed default is `BLOCKED`.
2. Bundle scope is slice-core artifacts.
3. Import head policy is strict by default; explicit override flag allowed.
4. Canonical bundle format is directory + manifest (no tarball as canonical output).
5. `prd_set_pass.sh` semantics remain unchanged (`decision == PASS` still required).

## Scope
In scope:
1. Artifact lint + contract parity + workflow self-proof.
2. Full verify contract-review auto-seeding and validation.
3. Deterministic recon bundle export/import portability.
4. Canonical recon artifact field matrix and parity enforcement.

Out of scope:
1. Auto-promoting seeded contract review to `PASS`.
2. Relaxing any pass-flip safety gates.
3. Tarball-first bundle workflow.

## Phase Plan

### Phase A (Completed)
Delivered in PR #132 (`817ab70`):
1. Added `plans/artifact_lint.sh` with quick/full mode and strict full-mode checks.
2. Added `docs/recon/artifact_field_contract.md`.
3. Wired `artifact_lint` into `plans/verify_fork.sh` quick/full flow.
4. Updated workflow contract and parity checks:
   - `specs/WORKFLOW_CONTRACT.md`
   - `plans/verify_gate_contract_check.sh`
5. Added workflow self-proof wiring and tests:
   - `plans/workflow_verify.sh`
   - `plans/workflow_files_allowlist.txt`
   - `plans/tests/test_workflow_allowlist_coverage.sh`
   - `plans/tests/test_artifact_lint.sh`

### Phase B (Next): Contract Review Auto-Seed in Full Verify
1. Finalize `plans/contract_review_emit.sh`:
   - required: `--out <path>`
   - defaults: `--decision BLOCKED`, `--story-id VERIFY_FULL`
   - guarantee: output passes `plans/contract_review_validate.sh`
2. Wire full-only gates in `plans/verify_fork.sh`:
   - `contract_review_generate`
   - `contract_review_validate`
3. Update contract/doc parity:
   - `plans/verify_gate_contract_check.sh`
   - `specs/WORKFLOW_CONTRACT.md`
   - `docs/PRD_STORY_WORKFLOW.md`

### Phase C (Next): Recon Bundle Portability
1. Add `plans/recon_bundle.sh` with:
   - `export --slice <S#> [--verify-run <run_id>] [--bundle-id <id>] [--out-root <path>]`
   - `import --bundle <bundle_dir> [--allow-head-mismatch] [--dry-run]`
2. Export payload scope:
   - `reviews/reconciliations/<slice>/**`
   - `.wf/receipts/<slice>-*/**`
   - `.wf/recon_scope_lock/<slice>-*.scope_lock.json`
   - `artifacts/story/<slice>-*/**`
   - optional `artifacts/verify/<run_id>/**`
3. Manifest requirements (`bundle.manifest.json`):
   - `schema_version`, `bundle_id`, `slice_id`, `source_head_sha`, `created_at_utc`, optional `verify_run_id`
   - sorted `files[]` with `path`, `sha256`, `size_bytes`
4. Import behavior:
   - fail-closed on path safety, missing payload entries, checksum mismatch, invalid manifest
   - block on head mismatch unless `--allow-head-mismatch`

## Workflow Self-Proof Wiring (Phases B/C)
Update and keep green:
1. `plans/preflight.sh` (fixture/test inclusion as needed)
2. `plans/workflow_verify.sh` (syntax checks for new scripts)
3. `plans/workflow_files_allowlist.txt`
4. `plans/tests/test_workflow_allowlist_coverage.sh`

## Tests
Required:
1. `bash plans/tests/test_contract_review_emit.sh`
2. `bash plans/tests/test_recon_bundle.sh`
3. `bash plans/tests/test_workflow_allowlist_coverage.sh`
4. `bash plans/verify_gate_contract_check.sh`
5. `./plans/workflow_verify.sh`

Behavior checks:
1. `./plans/verify.sh full` always emits `artifacts/verify/<run_id>/contract_review.json` and it is schema-valid.
2. Default seeded decision is `BLOCKED`.
3. Bundle tamper/head mismatch failures are deterministic and fail-closed.

## Acceptance Criteria
1. Full verify always leaves a schema-valid `contract_review.json`.
2. Seeded `BLOCKED` does not weaken `prd_set_pass.sh` pass requirements.
3. Recon bundle replaces manual cross-worktree sync for slice-core evidence.
4. Import is deterministic, integrity-checked, and strict by default.
5. Workflow contract/docs/parity/allowlist checks remain green.

## Execution Order
1. Merge Phase A (PR #132).
2. Implement Phase B in a dedicated follow-up branch from updated `main`.
3. Implement Phase C in a dedicated follow-up branch (or stacked on Phase B if simpler).
4. Keep each phase independently verifiable and reviewable.
