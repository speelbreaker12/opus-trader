# Workflow Anti-Skip Hardening v2 (Contract-Aligned)

## Status
- Draft v2
- Supersedes intent in `plans/proposals/workflow_anti_skip_hardening.md`

## Why v2
v1 identified the right problem (skippable review/verify steps) but introduced contract and operational conflicts:
1. It made `verify` write story state (conflicts with workflow contract read-only verify rule).
2. It changed `./plans/verify.sh` interface shape beyond `quick|full`.
3. It added a new required CI check coupled to local ignored artifacts.

This v2 keeps the anti-skip objective while staying compatible with current workflow contract and harness guardrails.

## Objectives
1. Enforce required workflow step order mechanically.
2. Block `passes=true` and local pre-PR readiness if sequence is incomplete.
3. Keep merge checks repo-backed; do not make CI depend on local-only workflow state.
4. Preserve merge-path story-review evidence enforcement when moving to repo-backed CI checks.
5. Prevent HEAD drift between review set, full verify run, and pass flip.
6. Keep one workflow SSOT and deterministic diagnostics.

## Non-Goals
1. No changes to trading runtime behavior.
2. No slice acceptance criteria changes.
3. No replacement of existing required gates (`story_review_gate`, `pre_pr_review_gate`, `pr_gate`, `verify`).

## Contract Alignment First (Mandatory)
Before anti-skip wiring, align workflow contract to enforced branch reality.

Current mismatch:
- `specs/WORKFLOW_CONTRACT.md` still references `slice1/<STORY_ID>-<slug>`.
- Active enforcement in gates/CI accepts `story/<STORY_ID>[/<slug>]` and legacy `story/<PRD_STORY_ID>-<slug>`.

v2 decision:
1. Make `specs/WORKFLOW_CONTRACT.md` authoritative for canonical naming: `story/<STORY_ID>[/<slug>]`.
2. Keep legacy `story/<PRD_STORY_ID>-<slug>` support in v2 as deprecated compatibility (warning path), with explicit sunset in Phase E.1 (legacy branch-form removal) and coordinated docs/gates/tests updates.
3. Update `plans/workflow_contract_map.json` in the same change.
4. Run `./plans/workflow_contract_gate.sh` in that change.
5. Any legacy-removal phase must change docs, gates, and fixture tests together in one fail-closed commit.

No anti-skip state logic ships before this alignment commit.

## Design Constraints (Hard)
1. `./plans/verify.sh` remains thin wrapper and stable `quick|full` interface only.
2. `plans/verify_fork.sh` remains read-only with respect to story state/events.
3. All new enforcement is fail-closed with deterministic error codes/messages.
4. No separate required CI status that depends on non-repo workflow state or mutable off-repo evidence inputs. CI trust-root secrets used only for signing/verification (for example attestor private key) are allowed; merge evidence validation inputs must remain repo/API derived.
5. Trusted required context `trusted/pr-gate-enforced` remains a merge blocker and must consume repo-backed inputs only.
6. `--ci-repo-only` must never bypass story-review evidence checks; it must enforce a repo-backed `story_review_gate`-equivalent attestation for the same story and current PR content fingerprint.
7. CI attestation provenance verification must be anchored to immutable PR base commit verifier/key material (`$PR_BASE_SHA`), not PR-modifiable verifier files.
8. Attestor signing code must execute from immutable trusted base commit checkout (`$PR_BASE_SHA`) only; PR HEAD files are data inputs only and must never be executed in signer context.
9. Attestation updates must be idempotent for unchanged subject content (fingerprint+digest), so bot commits cannot self-trigger unstable CI loops.
10. Attestor write path must be serialized with deterministic concurrency keys (PR + story scope), and unresolved write races must fail closed with deterministic diagnostics.
11. Unsigned or provenance-invalid attestations must fail closed.
12. `pr-gate-enforced` orchestration code (`plans/pr_gate.sh`, `plans/pre_pr_review_gate.sh`, `plans/review_attestation_verify.sh`) must execute from immutable trusted base commit checkout (`$PR_BASE_SHA`) only.
13. If trusted base-ref checkout or trusted script resolution fails, merge-path gate must fail closed.
14. The required merge check must come from a base-controlled workflow definition (`pull_request_target` or equivalent), not from PR-controlled `pull_request` workflow YAML.
15. Branch protection must require trusted contexts (`trusted/pr-gate-enforced`, `trusted/verify-full`), remove legacy PR-controlled contexts, and scope required checks to trusted app/source when platform support exists.
16. If app/source-scoped required checks are unavailable on the host platform, branch-protection context names are necessary but not sufficient: trusted merge gate runtime provenance checks (`plans/trusted_contexts_gate.sh`) are authoritative and must fail closed with `TRUSTED_CONTEXT_SOURCE_SCOPE_UNSUPPORTED` when provenance cannot be established for required contexts.
17. Trusted merge gating must not pass/fail from generic PR-head check-run conclusions emitted by PR-controlled workflows.
18. Verification readiness for merge must come from base-controlled trusted workflow context(s) and/or direct trusted execution, with required-context presence checked fail-closed.
19. Trusted required context names must be unique (for example `trusted/pr-gate-enforced`, `trusted/verify-full`) and collision with PR workflows must be linted as an error.
20. Trusted check provenance must be validated at runtime (context name + app/source + workflow ref) and fail closed on mismatch.
21. Trusted workflows that execute PR subject code must declare explicit least-privilege permissions (`contents:read`, `pull-requests:read`, `checks:read` only), set `actions/checkout` with `persist-credentials: false`, and avoid secret inheritance.
22. Before any PR subject code execution, trusted workflows must scrub credentials (`GITHUB_TOKEN` unset for execution steps, git credential helpers removed) and pass only allowlisted env vars.
23. `trusted/verify-full` must be bound to PR subject HEAD via deterministic post-run checks (`verify.meta.json` fields) and fail closed on mismatch.
24. Trusted verify execution must use trusted scripts with explicit subject-root override; fallback to verifying trusted checkout contents is forbidden.
25. Trusted `pr_gate_enforced.yml` must retrigger on trusted events (`pull_request_target`, `pull_request_review`, `pull_request_review_comment`, and PR `issue_comment`) so late comments/reviews cannot leave stale passing contexts.
26. On `issue_comment` retriggers, trusted gate execution must bind conclusions/check updates to the current PR HEAD SHA at evaluation time; stale-SHA updates are invalid and fail closed.
27. Any required-context migration (job/context rename or workflow split) must update fail-closed parity guards (`plans/readme_ci_parity_check.sh` and fixtures) in the same change.

## Canonical State Model
Use one append-only local event ledger per story:
- `artifacts/story/<STORY_ID>/workflow_events.jsonl`

Scope boundary:
1. This ledger is local operator state for readiness/pass-flip gates.
2. CI merge gating must not require this ledger unless/until a repository-backed attestation is introduced.

Merge-path trust boundary (required):
1. Trusted required check is emitted by dedicated workflow `.github/workflows/pr_gate_enforced.yml` running from base-ref definition (`pull_request_target` or equivalent).
2. Trusted workflow creates two checkouts:
  - trusted checkout: immutable PR base commit (`$PR_BASE_SHA` from PR event payload)
  - subject checkout: PR HEAD
3. Execute merge gate scripts from trusted checkout only (`plans/pr_gate.sh`, `plans/pre_pr_review_gate.sh`, `plans/review_attestation_verify.sh`).
4. Subject checkout is read-only data input for fingerprint/digest calculations and artifact reads; it must not supply executed scripts.
5. Any fallback to executing gate scripts from subject checkout is a fail-closed error.
6. `pull_request` workflows (for example `.github/workflows/ci.yml`) are non-authoritative for merge gating and must not own the required trusted gate context.
7. Trusted merge gate in CI mode evaluates direct trusted gate steps and trusted required contexts only; generic PR check-run status aggregation is informational and non-blocking.
8. Trusted required contexts are currently:
  - `trusted/pr-gate-enforced`
  - `trusted/verify-full`
9. Missing trusted required contexts or context provenance mismatch is fail-closed.
10. Required trusted contexts are accepted only when emitted by expected trusted app/source and workflow ref; context-name-only matches are insufficient.
11. Trusted `pr_gate_enforced.yml` includes event triggers: `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, and PR `issue_comment` (`issue.pull_request` guard).
12. Trusted `pr_gate_enforced.yml` must not use `needs` dependencies on pull_request-only jobs, preventing skipped evaluation on review/comment events.
13. New review/comment activity must deterministically rerun trusted gate evaluation; stale green contexts are invalidated by rerun, not cached.
14. `issue_comment` reruns must post conclusions/check updates for the latest PR HEAD SHA only; stale context updates for older SHAs are fail-closed.
15. Trusted workflows (`pr_gate_enforced.yml`, `verify_trusted.yml`, `story_review_attestor.yml`) must set explicit least-privilege `permissions` and `persist-credentials: false` for all checkouts.
16. Trusted workflows must not expose repo/environment secrets to steps that execute subject checkout code.
17. Trusted verify wrapper runs trusted verify scripts with explicit subject-root override (`VERIFY_SUBJECT_ROOT=<subject_root>`) and then validates `verify.meta.json` against PR subject HEAD and recomputed subject fingerprint.
18. Missing or mismatched subject-binding metadata in `verify.meta.json` is fail-closed for `trusted/verify-full`.

Trusted verify execution model (normative, fail-closed):
1. Entrypoint scripts (`plans/verify_ci_base_ref.sh`, `plans/verify_fork.sh`, `plans/lib/*.sh`, `plans/preflight.sh`, `plans/verify_gate_contract_check.sh`) are always loaded/executed from trusted checkout at `$PR_BASE_SHA`.
2. Subject checkout is data root only (`VERIFY_SUBJECT_ROOT=<subject_root>`):
  - Allowed from subject root: source files, manifests, lockfiles, and test targets.
  - Forbidden from subject root: `plans/**`, `scripts/**`, and workflow orchestration code execution.
3. If trusted verify cannot map a gate to trusted script execution plus subject data input, it must fail closed with deterministic diagnostics (`TRUSTED_VERIFY_EXEC_MODEL_VIOLATION`).
4. Verifying trusted checkout content instead of subject content is forbidden; wrappers must assert subject-bound execution and fail closed on mismatch.
5. Subject execution steps run with credential scrubbing and allowlisted env vars only.

Repo-backed merge attestation (required before CI switch):
1. Add tracked attestations under `plans/review_attestations/<STORY_ID>.json` (single rolling file per story, not SHA-keyed filename).
2. CI must not trust unsigned attestation content. Attestation payload includes:
  - `story_id`
  - `reviewed_head_sha` (provenance)
  - `subject_tree_fingerprint` computed from tracked files excluding `plans/review_attestations/**`
  - `evidence_manifest_digest` over repo-backed evidence bundle `plans/review_evidence/<STORY_ID>/`
3. Attestation provenance fields include:
  - `issuer` (fixed: `story-review-attestor`)
  - `workflow_ref` (fixed: `.github/workflows/story_review_attestor.yml`)
  - `run_id`
  - `signed_at_utc`
  - `signature` over canonical payload+provenance
4. Signature is produced only by a dedicated attestor CI workflow running in protected context from base-ref workflow definition (for example `pull_request_target`; PR changes to the attestor workflow are ignored). Private key stays in CI secret/env; public key is tracked at `plans/review_attestation_pubkey.pem`.
5. Attestor implementation (`plans/story_review_attest.sh` and helper scripts) is loaded from trusted base commit checkout at `$PR_BASE_SHA`; PR HEAD checkout is mounted read-only for fingerprint/digest input only and MUST NOT provide executed code in signing steps.
6. `--ci-repo-only` validation loads verifier + public key from immutable trusted base checkout at `$PR_BASE_SHA`, verifies signature/provenance, and recomputes `subject_tree_fingerprint` plus `evidence_manifest_digest` for PR HEAD.
7. CI requires payload and recomputed values to match exactly; `reviewed_head_sha` remains audit provenance (non-binding for equality).
8. If attestation is missing, unsigned, signature-invalid, provenance-invalid, or digest/fingerprint-mismatched, CI fails closed.
9. Attestor write path is idempotent: if an existing attestation already verifies for current fingerprint+digest under base-ref verifier/key, skip rewrite/commit.
10. Attestor workflow enforces deterministic concurrency grouping keyed by repository + PR number + story id (or deterministic equivalent) to serialize attestation writes for the same PR/story.
11. On write race (for example non-fast-forward push), attestor performs bounded deterministic fetch/rebase/retry; if retries are exhausted it fails closed with `ATTESTATION_PUSH_RACE`.
12. This prevents self-invalidating loops, forged in-PR attestation edits, and bot-triggered commit churn.
13. Fork PR policy (deterministic): automatic attestation commit is supported only for same-repository PR branches in v2. Fork PRs fail closed with `FORK_ATTESTATION_UNSUPPORTED` and remediation to run `plans/fork_attestation_mirror.sh --pr <number> --story <STORY_ID>` (maintainer-owned mirror branch flow) before merge gating.
14. Fork remediation ownership is explicit and mandatory:
  - PR author responsibility: mark PR as fork-attestation-blocked and request maintainer mirror remediation.
  - Maintainer responsibility: run `plans/fork_attestation_mirror.sh`, push mirror updates, and post mirror branch/ref + attestation commit evidence in PR.
  - Merge gate responsibility: reject fork PRs as not-ready until maintainer remediation evidence is present and attestation verification passes.
15. Fork remediation must produce tracked machine-readable metadata at `plans/review_attestations/fork_remediation/pr_<PR_NUMBER>.json` that conforms to `plans/schemas/fork_attestation_remediation.schema.json`.
16. Trusted merge gate must verify fork-remediation metadata in addition to comments; comments are supplemental and non-authoritative evidence.

Story-review equivalence matrix (mandatory before Phase D cutover):
`--ci-repo-only` MUST enforce repository-backed checks that are equivalent to current `story_review_gate` semantics for the same story and subject content fingerprint.

Mapping (current requirement -> attested/evidence representation -> verifier enforcement):
1. Self review exists for story/head with `Decision: PASS` -> self-review artifact included in `plans/review_evidence/<STORY_ID>/` and covered by `evidence_manifest_digest` -> `repo_story_review_gate.sh` validates exact fields; `review_attestation_verify.sh` revalidates digest/signature/fingerprint.
2. Self-review failure-mode + strategic markers are `DONE` -> same self-review artifact + digest coverage -> `repo_story_review_gate.sh` enforces exact marker lines; verifier fails closed on digest mismatch.
3. Kimi review exists for story/head -> kimi review artifact included in evidence bundle + digest -> `repo_story_review_gate.sh` validates story/head binding; verifier fails closed on missing/mismatched evidence.
4. At least two Codex reviews exist for story/head -> codex review artifacts included in evidence bundle + digest -> `repo_story_review_gate.sh` enforces cardinality `>=2` and story/head binding.
5. Code-review-expert review exists for story/head and status COMPLETE -> code-review-expert artifact included in evidence bundle + digest -> `repo_story_review_gate.sh` enforces status + story/head and placeholder checks.
6. Resolution file exists for story/head with `Blocking addressed: YES` and `Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0` -> `review_resolution.md` included in evidence bundle + digest -> `repo_story_review_gate.sh` enforces exact required lines.
7. Resolution references Kimi/Codex/Codex-second/code-review-expert files that exist, are in expected directories, match story/head, and codex refs are distinct -> referenced files included in evidence bundle + digest -> `repo_story_review_gate.sh` enforces path constraints, existence, HEAD consistency, and codex-ref distinctness.
8. SHA/content consistency across review evidence and PR subject content -> attestation payload includes `subject_tree_fingerprint` and `evidence_manifest_digest` -> `review_attestation_verify.sh` recomputes both values for PR subject checkout and fails closed on mismatch.

Equivalence enforcement rule:
1. Phase D cutover is blocked until every matrix row has a deterministic failing-path test.
2. Any future `story_review_gate` requirement change must update this matrix and corresponding repo-backed verifier checks in the same change.
3. Matrix rows are materialized as tracked SSOT data (`plans/story_review_equivalence_matrix.json`) consumed by tests and guards.
4. Deterministic parity guard `plans/story_review_equivalence_check.sh` must fail closed with `STORY_REVIEW_EQUIVALENCE_DRIFT` when `story_review_gate` requirements and matrix rows diverge.

Event schema (one JSON object per line):
- `schema_version`
- `event_id` (ULID or UUIDv7)
- `story_id`
- `head_sha`
- `branch`
- `event_type`
- `timestamp_utc`
- `run_id` (required for verify-backed sequence-credit events: all `quick_*` events and `full_verify_pass`)
- `verify_mode` (`quick|full`; required when `run_id` is present)
- `idempotency_key` (required for non-verify events)
- `producer` (script name)
- `details` (object; includes `changed=true|false` for sync)

Append semantics:
1. Append via single helper script only.
2. Use file lock (`flock` when available; deterministic fallback lock-dir on macOS/bash 3.2).
3. Lock fallback must be self-healing and deterministic:
  - lock directory stores owner metadata (`pid`, `host`, `created_utc`).
  - stale threshold is controlled by `WORKFLOW_EVENT_LOCK_STALE_SECS` (default 900; integer > 0).
  - if lock owner is non-existent and lock age exceeds threshold, recover lock with diagnostic `WORKFLOW_EVENT_LOCK_STALE_RECOVERED`.
  - if lock cannot be acquired within bounded retries, fail closed with `WORKFLOW_EVENT_LOCK_TIMEOUT`.
4. Reject malformed JSON or unknown `event_type`.
5. Verify-backed sequence-credit events must include `run_id` + `verify_mode`; dedupe key = (`story_id`, `head_sha`, `event_type`, `run_id`).
6. Evaluator must verify each `run_id` maps to a real verify artifact run (`artifacts/verify/<run_id>/verify.meta.json`) and that metadata is consistent with event `head_sha` and `verify_mode`; mismatch/missing artifacts fail closed.
7. Non-verify events must include `idempotency_key`; dedupe key = (`story_id`, `head_sha`, `event_type`, `idempotency_key`).
8. Recovery path for mistaken append is append-only invalidation event (`event_type=event_invalidated`, `details.invalidates_event_id=<event_id>`, `details.reason=<text>`); evaluator ignores invalidated events in sequence checks and fails closed if invalidation target is missing.

Derived state is computed by:
- `plans/workflow_state_eval.py`

It returns machine-readable pass/fail plus:
- missing transitions
- out-of-order transitions
- branch/story/head mismatches

No tracked `.workflow_state/*.json` file is introduced.

## Required Event Sequence
Evaluator-required chain for one `(story_id, head_sha)` execution unit:
1. `self_review_pass`
2. `quick_pre_reviews`
3. `codex_review_1_pass`
4. `kimi_review_pass`
5. `quick_post_review_fixes`
6. `codex_review_2_pass`
7. `quick_post_second_codex`
8. `code_review_expert_complete`
9. `quick_post_findings_fixes`
10. `sync_with_integration` (records `changed`)
11. `quick_post_sync` (required iff `changed=true`)
12. `full_verify_pass`

Notes:
1. `implemented_marker` is optional and non-blocking (informational only).
2. A sync that changes HEAD starts a new `(story_id, head_sha)` unit; evaluator must enforce full re-review chain for the new HEAD (matching current contract SHA-consistency rules).
3. A unit created by `sync_with_integration changed=true` may terminate at `full_verify_pass` without another sync event; `sync_with_integration` in the new unit is required only if another integration sync is actually executed for that unit.
4. If a unit emits `sync_with_integration changed=true`, that same unit must include `quick_post_sync` before `full_verify_pass`; missing `quick_post_sync` is fail-closed.
5. `pre_pr_gate_pass` is an audit/checkpoint event appended only after evaluator PASS and MUST NOT be part of the evaluator-required set (avoids bootstrap deadlock).

## Script Changes (v2)
### New files
1. `plans/workflow_event_log.sh`
2. `plans/workflow_state_eval.py`
3. `plans/story_sync_logged.sh`
4. `plans/workflow_quick_step.sh`
5. `plans/workflow_full_story.sh`
6. `plans/story_review_attest.sh`
7. `plans/repo_story_review_gate.sh`
8. `plans/repo_content_fingerprint.sh`
9. `plans/review_attestation_verify.sh`
10. `plans/review_attestation_pubkey.pem`
11. `.github/workflows/story_review_attestor.yml`
  - Must declare deterministic `concurrency` keyed by PR/story scope to serialize attestation writes.
  - Must implement bounded deterministic push-race retries and fail closed with `ATTESTATION_PUSH_RACE` when unresolved.
12. `.github/workflows/pr_gate_enforced.yml`
13. `.github/workflows/verify_trusted.yml`
14. `plans/pr_gate_ci_base_ref.sh`
15. `plans/verify_ci_base_ref.sh`
16. `plans/trusted_contexts_gate.sh`
17. `plans/fork_attestation_mirror.sh`
18. `plans/tests/test_workflow_event_log.sh`
19. `plans/tests/test_workflow_state_eval.sh`
20. `plans/tests/test_workflow_quick_step.sh`
21. `plans/tests/test_workflow_full_story.sh`
22. `plans/tests/test_repo_story_review_gate.sh`
23. `plans/tests/test_repo_content_fingerprint.sh`
24. `plans/tests/test_review_attestation_verify.sh`
25. `plans/tests/test_pr_gate_ci_base_ref.sh`
26. `plans/tests/test_verify_ci_base_ref.sh`
27. `plans/tests/test_trusted_contexts_gate.sh`
28. `plans/tests/test_verify_trusted_workflow_hardening.sh`
29. `plans/tests/test_verify_subject_binding.sh`
30. `plans/tests/test_readme_ci_parity_check.sh`
31. `plans/tests/test_fork_attestation_mirror.sh`
32. `plans/story_review_equivalence_matrix.json`
33. `plans/story_review_equivalence_check.sh`
34. `plans/fork_attestation_remediation_verify.sh`
35. `plans/tests/test_story_review_equivalence_check.sh`
36. `plans/tests/test_fork_attestation_remediation_verify.sh`
37. `plans/tests/test_toggle_policy_wiring.sh`
38. `plans/schemas/fork_attestation_remediation.schema.json`

### Modified files
1. `plans/self_review_logged.sh`
  - On `--decision PASS`, append `self_review_pass`.
2. `plans/codex_review_logged.sh`
  - Add `--stage first|second` support.
  - Transition policy: optional in Phase A (infer `first` with deprecation warning), required by Phase B before hard local sequence gating.
  - Wire `CODEX_STAGE_POLICY=warn|require` with deterministic invalid-value failure (`INVALID_CODEX_STAGE_POLICY`).
  - Append `codex_review_1_pass` or `codex_review_2_pass` on success.
3. `plans/kimi_review_logged.sh`
  - Append `kimi_review_pass` on success.
4. `plans/code_review_expert_logged.sh`
  - On `--status COMPLETE`, append `code_review_expert_complete`.
5. `plans/story_review_gate.sh`
  - Add read-only call to `workflow_state_eval.py`.
  - Wire `WORKFLOW_SEQUENCE_ENFORCEMENT=warn|block` policy for evaluator findings.
  - Invalid policy value fails closed with `INVALID_WORKFLOW_SEQUENCE_ENFORCEMENT`.
  - `WORKFLOW_SEQUENCE_ENFORCEMENT=warn`: emit deterministic evaluator diagnostics but do not block local gate progression.
  - `WORKFLOW_SEQUENCE_ENFORCEMENT=block`: fail on missing/out-of-order state in addition to existing artifact SHA checks.
6. `plans/pre_pr_review_gate.sh`
  - Local mode (default) is policy-driven:
    - `WORKFLOW_SEQUENCE_ENFORCEMENT=warn`: evaluator findings are warning-only and non-blocking; `pre_pr_gate_pass` is appended only if evaluator status is `PASS`.
    - `WORKFLOW_SEQUENCE_ENFORCEMENT=block`: require evaluator PASS for supplied story/head, then append `pre_pr_gate_pass`.
  - CI mode (`--ci-repo-only`): enforce repo-backed checks only, including `repo_story_review_gate.sh` + `review_attestation_verify.sh` provenance/signature validation for the same story and current PR content fingerprint.
  - `--slice-id` behavior is no-regression in both modes: if supplied, slice-close evidence enforcement (`slice_review_gate.sh`) remains mandatory and fail-closed.
  - Wire `CI_REPO_ONLY_ENFORCEMENT=off|on` in trusted path; invalid policy value fails closed with `INVALID_CI_REPO_ONLY_ENFORCEMENT`.
  - On fork PRs, require `fork_attestation_remediation_verify.sh` success before CI repo-only PASS.
  - CI mode does not read/write local workflow event ledger, and it must fail closed if repo-backed attestation is missing.
7. `plans/prd_set_pass.sh`
  - Keep sole mutator.
  - Verify `verify.meta.json.head_sha == current HEAD` before allowing `true`.
  - Continue requiring `story_review_gate` PASS (which now includes state evaluation).
8. `plans/review_resolution_template.md`
  - Add required fields:
    - `Verify run id: <run_id>`
    - `Verify head sha: <sha>`
9. `.github/workflows/ci.yml`
  - Remove/rename legacy `pr-gate-enforced` pull_request job context so it is not branch-protection authoritative.
  - Keep CI checks informational/non-required for merge gating.
10. `.github/workflows/pr_gate_enforced.yml`
  - New trusted required-gate workflow (`pull_request_target` or equivalent) that executes base-ref merge-gate entrypoint (`plans/pr_gate_ci_base_ref.sh`) and passes PR checkout as data root.
  - MUST trigger on `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, and PR `issue_comment` events.
  - On `issue_comment` reruns, MUST re-resolve PR HEAD and update trusted status/checks for that SHA only.
  - MUST avoid pull_request-only `needs` so review/comment events always run gate evaluation.
  - Emits trusted context name `trusted/pr-gate-enforced`.
11. `.github/workflows/verify_trusted.yml`
  - New trusted verification workflow (`pull_request_target` or equivalent) that executes base-ref verification entrypoint (`plans/verify_ci_base_ref.sh`) against PR subject checkout.
  - MUST set explicit minimal `permissions`, use `persist-credentials: false` on all checkout steps, and avoid secret exposure to subject-code execution.
  - Emits trusted context name `trusted/verify-full`.
12. `plans/pr_gate.sh`
  - Add trusted-mode support so CI wrapper can run gate orchestration from trusted checkout while inspecting a separate subject checkout.
  - In trusted mode, do not gate on generic PR check-run aggregation; require trusted context/provenance gate instead.
13. `plans/pre_pr_review_gate.sh`
  - Add trusted-mode support to enforce `--ci-repo-only` against explicit subject root and prohibit script execution from subject checkout.
14. `plans/trusted_contexts_gate.sh`
  - Fail-closed validator that required trusted contexts exist exactly once, have expected names, and map to base-controlled trusted workflows.
  - Wire `TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=require|fallback_runtime_fail_closed`; invalid policy value fails closed with `INVALID_TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY`.
15. `plans/pr_gate_ci_base_ref.sh`
  - Own trusted-entrypoint interpretation of `CI_REPO_ONLY_ENFORCEMENT=off|on` and pass deterministic mode to downstream trusted gate flow.
  - Invalid `CI_REPO_ONLY_ENFORCEMENT` value fails closed with `INVALID_CI_REPO_ONLY_ENFORCEMENT` before gate orchestration.
16. `plans/verify_ci_base_ref.sh`
  - Trusted wrapper to run `./plans/verify.sh full` from base-ref scripts against subject checkout via explicit subject-root override.
  - Validates `verify.meta.json` binding (`subject_head_sha == PR_HEAD_SHA`, `worktree == SUBJECT_ROOT`, `subject_tree_fingerprint` matches recomputed subject fingerprint) before reporting success.
  - Enforces trusted-vs-subject execution model and fails with `TRUSTED_VERIFY_EXEC_MODEL_VIOLATION` if any gate path would execute subject checkout orchestration code.
17. `plans/verify_fork.sh`
  - Add `VERIFY_SUBJECT_ROOT` support (no CLI interface change) so trusted wrappers can target PR subject checkout while using trusted scripts.
  - Extend `verify.meta.json` with deterministic subject-binding fields consumed by `verify_ci_base_ref.sh`.
18. `plans/readme_ci_parity_check.sh`
  - Migrate parity assertions from legacy `.github/workflows/ci.yml:pr-gate-enforced` to trusted workflows (`pr_gate_enforced.yml`, `verify_trusted.yml`).
  - Fail closed if trusted trigger matrix (`pull_request_review`, `pull_request_review_comment`, PR `issue_comment`) or trusted context names drift.
19. `plans/preflight.sh`
  - Wire trusted parity fixture test(s) so CI/workflow migration fails early when parity guard expectations are stale.
  - Wire fork-attestation mirror fixture test to validate deterministic remediation path for fork PRs.
  - Wire equivalence/toggle/remediation verifier fixture tests so policy wiring and matrix parity regressions fail early.
20. `plans/story_review_findings_guard.sh`
  - Update Story-loop token checks so command migration to sequence-bound wrappers (`plans/workflow_quick_step.sh`) remains accepted and fail-closed.
  - Keep explicit harness-level `./plans/verify.sh quick` token expectation in the canonical non-sequence note.
21. `plans/tests/test_story_review_findings_guard.sh`
  - Add/adjust fixtures for wrapper-command migration and guard fail-closed behavior.

Toggle wiring map (required implementation binding):
1. `WORKFLOW_SEQUENCE_ENFORCEMENT=warn|block`
  - Owned by: `plans/story_review_gate.sh`, local mode in `plans/pre_pr_review_gate.sh`.
  - Deterministic invalid-value code: `INVALID_WORKFLOW_SEQUENCE_ENFORCEMENT`.
  - Minimum coverage: warn path non-blocking evidence + block path fail-closed + invalid value fail.
2. `CODEX_STAGE_POLICY=warn|require`
  - Owned by: `plans/codex_review_logged.sh`.
  - Deterministic invalid-value code: `INVALID_CODEX_STAGE_POLICY`.
  - Minimum coverage: phase-A compat warning + phase-B required enforcement + invalid value fail.
3. `CI_REPO_ONLY_ENFORCEMENT=off|on`
  - Owned by: trusted CI path in `plans/pr_gate_ci_base_ref.sh` and `plans/pre_pr_review_gate.sh`.
  - Deterministic invalid-value code: `INVALID_CI_REPO_ONLY_ENFORCEMENT`.
  - Minimum coverage: off path no CI repo-only enforcement + on path enforced + invalid value fail.
4. `TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=require|fallback_runtime_fail_closed`
  - Owned by: `plans/trusted_contexts_gate.sh`.
  - Deterministic invalid-value code: `INVALID_TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY`.
  - Minimum coverage: require path success/fail + fallback fail-closed path + invalid value fail.

### Wrapper behavior (keeps verify contract intact)
1. `plans/workflow_quick_step.sh <STORY_ID> <step>`
  - Runs `./plans/verify.sh quick`.
  - On success appends one of:
    - `quick_pre_reviews`
    - `quick_post_review_fixes`
    - `quick_post_second_codex`
    - `quick_post_findings_fixes`
    - `quick_post_sync`
2. `plans/workflow_full_story.sh <STORY_ID>`
  - Enforces clean tree precondition.
  - Runs `./plans/verify.sh full`.
  - On success appends `full_verify_pass` with `run_id` from verify artifacts.

`plans/verify_fork.sh` is not modified to append events.

## Gate Enforcement Model
1. Local completion path
  - `story_review_gate` and `pre_pr_review_gate` enforce derived state.
  - `prd_set_pass.sh` remains final blocker and verifies head/verify-state consistency.
2. Merge path
  - Required contexts are emitted only by trusted workflows `.github/workflows/pr_gate_enforced.yml` and `.github/workflows/verify_trusted.yml` (base-controlled definitions), not by PR-controlled `pull_request` workflow YAML.
  - `trusted/pr-gate-enforced` must remain independent of local-only `artifacts/story/*/workflow_events.jsonl`.
  - Branch protection requires trusted contexts `trusted/pr-gate-enforced` and `trusted/verify-full`, removes legacy PR-controlled merge-gate/verify contexts, and is app/source-scoped where platform capabilities allow.
  - When app/source-scoped required checks are not supported by the platform, trusted merge gate treats context-name protection as necessary but insufficient and fails closed with `TRUSTED_CONTEXT_SOURCE_SCOPE_UNSUPPORTED` if required-context provenance cannot be established at runtime.
  - `trusted/verify-full` is authoritative only when `verify_ci_base_ref.sh` validates subject binding (`verify.meta.json` head/fingerprint/worktree) against PR subject checkout.
  - Trusted required-gate workflow runs trusted merge-gate entrypoint from immutable trusted base checkout at `$PR_BASE_SHA` (not from PR checkout).
  - Trusted `pr_gate.sh` calls trusted `pre_pr_review_gate.sh --ci-repo-only` only with repo-backed story-review attestation checks enabled (no evidence bypass).
  - Trusted required-gate workflow retriggers on `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, and PR `issue_comment` events to eliminate stale-pass races after late comments.
  - `issue_comment` retriggers must bind conclusions/check updates to the current PR HEAD SHA; stale-SHA updates are treated as gate failure.
  - Trusted required-gate workflow must not depend on pull_request-only `needs`; review/comment events must evaluate gate logic directly.
  - Subject PR checkout is passed as explicit data root; merge gate must not execute any script from that checkout.
  - PR-controlled `pull_request` workflows may run additional CI but are non-authoritative for merge gating.
  - Trusted merge gate must not treat generic PR check-run aggregation as required-pass evidence.
  - Trusted context validator (`plans/trusted_contexts_gate.sh`) enforces required trusted-context presence/provenance fail-closed.
  - Context-name matches alone are insufficient; trusted merge gate must verify app/source + workflow-ref provenance for each required context.
  - Parity guard (`plans/readme_ci_parity_check.sh`) validates trusted workflow trigger matrix and context naming; migration is blocked if parity expectations are stale.
  - `--ci-repo-only` is not rollout-eligible until repo-backed attestation validation is implemented and fixture-tested.
  - CI attestation verifier and public key are loaded from immutable trusted checkout at `$PR_BASE_SHA` so PRs cannot weaken provenance checks by editing verifier logic or key files.
  - Trusted workflows executing subject code run in credential-hardened mode (minimal permissions, `persist-credentials: false`, no secret exposure, and credential scrubbing before subject execution).
  - Attestation signing workflow runs from protected base-ref definition and executes signing scripts from base-ref checkout only (PR code is data-only input).
  - CI attestation matching is fingerprint-based (excluding attestation path), so the attestation commit itself does not invalidate merge checks.
  - Attestation commit step is idempotent for unchanged fingerprint+digest, preventing bot synchronize loops.
  - Attestation writer enforces PR/story-scoped concurrency and deterministic bounded write-race retries; unresolved races fail closed with `ATTESTATION_PUSH_RACE`.
  - Merge-time sequence enforcement remains local-only until a repository-backed equivalent is defined; CI must not silently downgrade required review-evidence enforcement.

## Deterministic Diagnostics
`workflow_state_eval.py` should emit JSON with fixed keys/order:
- `status`: `PASS|FAIL`
- `story_id`
- `head_sha`
- `missing_events`: []
- `out_of_order_events`: []
- `mismatch_events`: []
- `notes`: []

Exit codes:
- `0` pass
- `2` input/runtime/schema error
- `3` missing or out-of-order required events
- `4` story/head/branch mismatch

## Harness Self-Proving Requirements
Because this touches workflow/harness files, implementation must also include:
1. `plans/workflow_files_allowlist.txt` updates.
2. `plans/tests/test_workflow_allowlist_coverage.sh` updates.
3. `plans/preflight.sh` fixture wiring for new tests.
4. `plans/workflow_verify.sh` syntax checks for new scripts.
5. `plans/verify_gate_contract_check.sh` token updates if workflow contract/gates change.
6. Deterministic workflow-hardening check that fails if trusted workflows miss minimal `permissions`, use `persist-credentials: true`, or expose secrets to subject-code steps.
7. Deterministic subject-binding check that fails if trusted verify artifacts omit/mismatch `verify.meta.json` subject head/fingerprint/worktree fields.
8. Deterministic parity-guard migration check that fails if trusted workflow trigger/context expectations diverge from `plans/readme_ci_parity_check.sh`.
9. Deterministic equivalence-parity guard (`plans/story_review_equivalence_check.sh`) that fails with `STORY_REVIEW_EQUIVALENCE_DRIFT` when `story_review_gate` required invariants and matrix rows diverge.
10. Deterministic toggle-policy wiring tests that cover valid/invalid values for all rollout toggles and fail closed on invalid values.
11. Deterministic fork-remediation metadata verification for fork PR path; missing/invalid metadata must fail closed even if human comment evidence exists.
12. Fork-remediation metadata verifier validates against tracked schema (`plans/schemas/fork_attestation_remediation.schema.json`) and fails closed on schema mismatch.

## Test Matrix (Minimum)
1. With `WORKFLOW_SEQUENCE_ENFORCEMENT=block`, missing `quick_pre_reviews` blocks first Codex/Kimi stage.
2. With `WORKFLOW_SEQUENCE_ENFORCEMENT=block`, missing `quick_post_review_fixes` blocks second Codex stage.
3. With `WORKFLOW_SEQUENCE_ENFORCEMENT=block`, missing `quick_post_second_codex` blocks code-review-expert COMPLETE acceptance.
4. With `WORKFLOW_SEQUENCE_ENFORCEMENT=block`, missing `quick_post_findings_fixes` blocks pre-PR gate and pass flip.
5. With `WORKFLOW_SEQUENCE_ENFORCEMENT=block`, a unit that emits `sync_with_integration changed=true` fails if `quick_post_sync` is missing before `full_verify_pass`.
6. A new unit started by `sync_with_integration changed=true` may pass by ending at `full_verify_pass` without an additional sync event when no further sync occurs.
7. Full-story wrapper with dirty tree fails deterministically.
8. Duplicate event append from retry is idempotent (no double-credit).
9. Concurrent append attempts do not corrupt JSONL.
10. Out-of-order injected event fails evaluator.
11. Non-verify event missing `idempotency_key` fails append.
12. Verify-backed sequence-credit event missing `run_id` or `verify_mode` fails append.
13. Invalidated-event recovery path works: evaluator ignores invalidated event and enforces corrected sequence.
14. `prd_set_pass.sh true` fails when verify head differs from current HEAD.
15. `pre_pr_review_gate.sh --ci-repo-only` fails when repo-backed review attestation is missing for story/fingerprint.
16. `pre_pr_review_gate.sh --ci-repo-only` fails on attestation story mismatch, fingerprint mismatch, or missing required evidence fields.
17. `pre_pr_review_gate.sh --ci-repo-only` passes when PR HEAD differs from `reviewed_head_sha` only by attestation-path updates and fingerprint still matches.
18. `pre_pr_review_gate.sh --ci-repo-only` fails when non-attestation files change after attestation generation.
19. Hand-edited/forged attestation content without valid signature/provenance is rejected in CI mode.
20. PR attempts to modify attestation verifier/public key do not affect CI outcome (trusted base SHA verifier/key is authoritative).
21. PR attempts to modify attestor workflow logic or signing scripts in PR checkout do not affect signing trust (base-checkout workflow+scripts are authoritative).
22. Re-running attestor on unchanged fingerprint+digest does not create a new commit.
23. Attestor workflow serializes per PR/story and avoids parallel write corruption under simultaneous review/comment-triggered runs.
24. Attestor workflow fails closed with `ATTESTATION_PUSH_RACE` after bounded deterministic retries on non-fast-forward push races.
25. PR attempts to modify `plans/pr_gate.sh` or `plans/pre_pr_review_gate.sh` do not affect merge-path result because CI executes trusted base-checkout gate scripts.
26. Merge-path gate fails closed when trusted/base checkout cannot be resolved.
27. PR modifications to `.github/workflows/ci.yml` cannot satisfy the required merge gate context.
28. Green PR-controlled check runs without trusted contexts cannot satisfy merge gating.
29. Context-name collision attempts (`pr-gate-enforced` lookalikes) are rejected by trusted-context validator.
30. Contexts with matching names but wrong app/source or workflow-ref provenance are rejected fail-closed.
31. On platforms lacking app/source-scoped branch-protection support, missing runtime provenance for required contexts fails closed with `TRUSTED_CONTEXT_SOURCE_SCOPE_UNSUPPORTED`.
32. Trusted `pr_gate_enforced.yml` reruns on `pull_request_target`, `pull_request_review`, `pull_request_review_comment`, and PR `issue_comment` events.
33. `issue_comment` reruns bind status/check updates to the current PR HEAD SHA; stale-SHA updates are rejected fail-closed.
34. New blocking bot/review comment after a prior green run forces trusted gate re-evaluation and fails until addressed.
35. Trusted workflow hardening check fails when `verify_trusted.yml` or `pr_gate_enforced.yml` permissions exceed allowed read-only scopes.
36. Trusted workflow hardening check fails when trusted workflows use `persist-credentials: true` or expose secrets to subject-code steps.
37. `verify_ci_base_ref.sh` fails when `verify.meta.json.subject_head_sha` does not equal PR HEAD SHA.
38. `verify_ci_base_ref.sh` fails when `verify.meta.json.worktree` or `subject_tree_fingerprint` does not match the subject checkout.
39. Trusted verify path fails closed when explicit subject-root override is missing/unusable.
40. Trusted verify path fails with `TRUSTED_VERIFY_EXEC_MODEL_VIOLATION` if any gate would execute subject-checkout orchestration code.
41. Parity guard fails when trusted workflow trigger matrix/context names drift during legacy `ci.yml` merge-gate demotion.
42. Fork PRs produce deterministic `FORK_ATTESTATION_UNSUPPORTED` when automatic attestation commit path is unavailable.
43. `plans/fork_attestation_mirror.sh --pr <number> --story <STORY_ID>` produces deterministic mirror branch/ref and attestation update metadata consumed by trusted gate path.
44. `--ci-repo-only` equivalence matrix rows are each covered by deterministic fail-closed tests (one negative test per row and at least one positive integration path).
45. Equivalence-parity guard fails with `STORY_REVIEW_EQUIVALENCE_DRIFT` when matrix rows and `story_review_gate` requirements drift.
46. Invalid values for `WORKFLOW_SEQUENCE_ENFORCEMENT`, `CODEX_STAGE_POLICY`, `CI_REPO_ONLY_ENFORCEMENT`, or `TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY` fail closed with deterministic diagnostics.
47. Fork PR with comment-only remediation evidence (no valid machine-readable remediation metadata) fails closed in trusted merge gate.
48. Fork remediation metadata that violates `plans/schemas/fork_attestation_remediation.schema.json` fails closed in trusted merge gate.
49. `WORKFLOW_SEQUENCE_ENFORCEMENT=warn` keeps local evaluator findings non-blocking in Phase A; `block` enforces fail-closed behavior in Phase B+.
50. Story-loop command migration does not break findings-guard enforcement (`plans/story_review_findings_guard.sh`) and fails closed when required wrapper/verify tokens are missing.
51. Happy path complete chain passes all gates.
52. Evaluator fails when a `quick_*` event references missing verify artifacts for its `run_id`.
53. Evaluator fails when event `verify_mode` and verify artifact metadata disagree for the same `run_id`.
54. Local `pre_pr_review_gate.sh` with `--slice-id` fails when required slice-close evidence is missing.
55. `pre_pr_review_gate.sh --ci-repo-only` with `--slice-id` preserves the same fail-closed slice-close enforcement semantics.
56. Stale lock-dir is deterministically recovered only when owner is dead and age exceeds `WORKFLOW_EVENT_LOCK_STALE_SECS` (emits `WORKFLOW_EVENT_LOCK_STALE_RECOVERED`).
57. Active/unrecoverable lock contention fails deterministically with `WORKFLOW_EVENT_LOCK_TIMEOUT`.
58. Legacy branch form (`story/<PRD_STORY_ID>-<slug>`) is accepted in v2 with a deterministic deprecation warning, and strict rejection is enforced only after Phase E.1 migration.

## Rollout
1. Phase 0 (alignment)
  - Branch naming contract/map alignment.
  - Keep legacy branch form (`story/<PRD_STORY_ID>-<slug>`) accepted with deterministic deprecation warning until Phase E.1 removal.
  - Story-loop command migration in `specs/WORKFLOW_CONTRACT.md` and `plans/PRD_WORKFLOW.md`:
    - quick runs use `plans/workflow_quick_step.sh` for sequence-bound checkpoints.
    - full run uses `plans/workflow_full_story.sh`.
  - Migrate `plans/story_review_findings_guard.sh` and `plans/tests/test_story_review_findings_guard.sh` in the same change so Story-loop command-token enforcement stays aligned and fail-closed.
  - Codex loop command migration to staged invocations (`--stage first|second`) with temporary compatibility shim.
2. Phase A (early hardening + observability)
  - Enforce verify-head binding in `prd_set_pass.sh` (high-ROI drift control) before broader CI migration.
  - Add event logger + evaluator + tests in passive mode (warnings only in local gates).
  - Land rollout-toggle wiring (`WORKFLOW_SEQUENCE_ENFORCEMENT`, `CODEX_STAGE_POLICY`, `CI_REPO_ONLY_ENFORCEMENT`, `TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY`) with deterministic invalid-value fail-closed tests.
  - `plans/codex_review_logged.sh --stage` remains optional in this phase with deprecation warning.
3. Phase B (hard local gates)
  - Enforce evaluator in `story_review_gate` and local `pre_pr_review_gate` mode.
  - Make `plans/codex_review_logged.sh --stage` required.
4. Phase C (repo-backed review attestation)
  - Add `story_review_attest.sh` + `repo_story_review_gate.sh` + `repo_content_fingerprint.sh` + `review_attestation_verify.sh` + fixture tests.
  - Add protected attestor workflow + key management (`story_review_attestor.yml`, repo public key, CI private key) with trusted-base-checkout script execution and idempotent write policy.
  - Add deterministic attestor concurrency + bounded write-race retry/fail-closed behavior (`ATTESTATION_PUSH_RACE`) before enabling merge-path dependency.
  - Pin trusted execution to immutable `$PR_BASE_SHA` for verifier/key/script resolution.
  - Add trusted verify subject-binding support (`VERIFY_SUBJECT_ROOT` in trusted verify path + `verify.meta.json` binding fields).
  - Add trusted verify execution-model checks that guarantee trusted scripts + subject data semantics.
  - Enforce deterministic fork policy (`FORK_ATTESTATION_UNSUPPORTED`) for non-supported automatic attestation write paths.
  - Land `plans/fork_attestation_mirror.sh` + fixture coverage for deterministic maintainer remediation path.
  - Land machine-readable fork-remediation metadata + verifier (`fork_attestation_remediation_verify.sh`) and require it for fork-path merge readiness.
  - Keep merge path unchanged until repo-backed attestation checks are green in CI.
5. Phase D (merge-path CI repo-only switch)
  - Route merge path through base-ref wrapper (`plans/pr_gate_ci_base_ref.sh`) -> trusted `pr_gate.sh` -> trusted `pre_pr_review_gate.sh --ci-repo-only` with required repo-backed story-review attestation validation.
  - Introduce trusted required workflows `.github/workflows/pr_gate_enforced.yml` and `.github/workflows/verify_trusted.yml`; set branch protection to require contexts `trusted/pr-gate-enforced` + `trusted/verify-full` with app/source scoping where supported, and enforce runtime fail-closed fallback (`TRUSTED_CONTEXT_SOURCE_SCOPE_UNSUPPORTED`) where unsupported.
  - Demote/remove legacy PR-controlled merge gate/verify jobs in `.github/workflows/ci.yml` so they are non-authoritative.
  - Update `plans/readme_ci_parity_check.sh` + parity fixtures in the same change so preflight/verify remain fail-closed and blocking on trusted-workflow drift.
  - Enforce trusted context uniqueness via `plans/trusted_contexts_gate.sh` in trusted merge gate.
  - Enforce trusted workflow credential hardening rules (minimal permissions, `persist-credentials: false`, no subject-step secrets) before enabling required contexts.
6. Phase E (cleanup)
  - Remove temporary warn compatibility paths.
  - Remove legacy branch-form compatibility (`story/<PRD_STORY_ID>-<slug>`) in coordinated docs/gates/tests migration (Phase E.1).

Rollout toggle table (normative; no implicit mode switches):
1. `WORKFLOW_SEQUENCE_ENFORCEMENT=warn|block`
  - Scope: `plans/story_review_gate.sh`, local mode of `plans/pre_pr_review_gate.sh`.
  - Phase A default: `warn`.
  - Phase B+ default: `block`.
  - Invalid value: fail closed with `INVALID_WORKFLOW_SEQUENCE_ENFORCEMENT`.
2. `CODEX_STAGE_POLICY=warn|require`
  - Scope: `plans/codex_review_logged.sh --stage first|second` enforcement.
  - Phase A default: `warn` (compat shim allowed).
  - Phase B+ default: `require`.
  - Invalid value: fail closed with `INVALID_CODEX_STAGE_POLICY`.
3. `CI_REPO_ONLY_ENFORCEMENT=off|on`
  - Scope: trusted CI path in `plans/pr_gate_ci_base_ref.sh` and downstream `pre_pr_review_gate.sh --ci-repo-only`.
  - Phases A-C default: `off`.
  - Phase D+ default: `on` only after equivalence matrix tests are green.
  - Invalid value: fail closed with `INVALID_CI_REPO_ONLY_ENFORCEMENT`.
4. `TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=require|fallback_runtime_fail_closed`
  - Scope: trusted context provenance validation in `plans/trusted_contexts_gate.sh`.
  - Default: `require` when platform supports app/source-scoped required checks; otherwise `fallback_runtime_fail_closed` with deterministic `TRUSTED_CONTEXT_SOURCE_SCOPE_UNSUPPORTED`.
  - Invalid value: fail closed with `INVALID_TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY`.

Fork PR pre-merge checklist (mandatory when `FORK_ATTESTATION_UNSUPPORTED` is observed):
1. Tracked remediation metadata file `plans/review_attestations/fork_remediation/pr_<PR_NUMBER>.json` exists, is valid, and records mirror remediation actor/timestamp/branch/head/attestation-commit fields.
  - Validity is schema-based against `plans/schemas/fork_attestation_remediation.schema.json`.
2. Attestation artifact update commit SHA from mirror flow is recorded in metadata and consumed by trusted gate run.
3. Trusted gate rerun after remediation is green for required contexts before merge.
4. Maintainer PR comment linking remediation run is recommended but supplemental (non-authoritative).

## Verification Commands
During iteration:
- `./plans/workflow_contract_gate.sh` (when contract/map touched)
- `./plans/workflow_verify.sh`
- `./plans/workflow_quick_step.sh <STORY_ID> <quick_step>`
- `./plans/verify.sh quick` (harness-level check; not a substitute for sequence-bound quick-step wrappers)

Before merge-grade:
- `./plans/workflow_full_story.sh <STORY_ID>`
- `./plans/verify.sh full` (repository/harness confidence check)

## Acceptance Criteria (v2)
1. Required workflow steps cannot be skipped for local readiness/pass-flip flow without deterministic gate failure.
2. `verify` contract remains read-only and `quick|full` only.
3. `passes=true` is blocked on incomplete sequence and verify/head mismatch.
4. Trusted contexts `trusted/pr-gate-enforced` and `trusted/verify-full` remain reproducible in CI without local-only ledger files.
5. `trusted/pr-gate-enforced` still blocks merges lacking required story-review evidence for PR content via repo-backed attestation checks.
6. Repo-backed attestation enforcement is stable under the attestation commit itself (no SHA self-invalidation loop).
7. Repo-backed attestation provenance is non-forgeable in CI (invalid signature/provenance fails closed, verifier/key anchored to immutable `$PR_BASE_SHA` trusted checkout).
8. Attestor signing logic cannot be replaced by PR checkout code during secret-bearing signing runs.
9. Attestation generation is idempotent for unchanged fingerprint+digest and does not cause bot-triggered commit loops.
10. Merge-path required gate orchestration cannot be replaced by PR-modified `plans/pr_gate.sh`/`plans/pre_pr_review_gate.sh` code.
11. Required merge-gate context comes from base-controlled workflow definition and cannot be no-oped by PR edits to `.github/workflows/ci.yml`.
12. Trusted merge gate does not rely on PR-controlled check-run aggregation as required-pass evidence.
13. Required trusted contexts are present/provenance-validated and collision-resistant.
14. Trusted required contexts are enforced with both context-name and app/source + workflow-ref provenance checks; name-only matches are rejected, and platforms without app/source-scoped branch protection still fail closed via runtime provenance validation.
15. Trusted workflows that execute subject code enforce credential hardening (minimal permissions, `persist-credentials: false`, no subject-step secret exposure).
16. `trusted/verify-full` is authoritative only when verify artifacts are bound to PR subject HEAD/worktree/fingerprint via fail-closed checks.
17. Trusted `pr_gate_enforced.yml` retriggers on `pull_request_target` + review/comment/issue-comment events so late feedback cannot leave stale passing contexts.
18. `issue_comment` retriggers must resolve and update the latest PR HEAD SHA only; stale-SHA status updates are rejected fail-closed.
19. Parity guard migration (`plans/readme_ci_parity_check.sh` + fixtures) lands in the same change as trusted-workflow cutover, keeping preflight/verify fail-closed and green on intended config.
20. Trusted verify execution model is enforced: trusted scripts execute from trusted checkout only, subject checkout is data-only, and execution-model violations fail closed.
21. Attestor write path is deterministic under concurrent triggers (PR/story-scoped serialization + bounded retries + fail-closed `ATTESTATION_PUSH_RACE`).
22. Automatic attestation commit behavior for fork PRs is deterministic and fail-closed (`FORK_ATTESTATION_UNSUPPORTED`) unless maintainer-owned mirror flow is used.
23. Workflow harness changes are self-proving under existing verify gates.
24. Phase D cutover is blocked unless `story_review_gate` equivalence matrix coverage is complete and green (all rows enforced by deterministic repo-backed verifier tests).
25. Equivalence-matrix anti-drift guard is active and fail-closed (`STORY_REVIEW_EQUIVALENCE_DRIFT`) before and after Phase D cutover.
26. Rollout toggles are wired to owning scripts/workflows with deterministic invalid-value fail-closed behavior and test coverage.
27. Fork-path merge readiness requires valid machine-readable remediation metadata; comment-only evidence is insufficient.
28. Fork remediation metadata is schema-validated (`plans/schemas/fork_attestation_remediation.schema.json`) and fails closed on mismatch.
29. Phase A local sequence policy remains warning-only (`WORKFLOW_SEQUENCE_ENFORCEMENT=warn`), while Phase B+ is fail-closed (`WORKFLOW_SEQUENCE_ENFORCEMENT=block`).
