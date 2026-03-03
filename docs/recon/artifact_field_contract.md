# Recon Artifact Field Contract

## Purpose
Define which fields are allowed in strict JSON artifacts and why.

Principle: strict JSON is for machine-gated decisions only. Narrative context belongs in markdown artifacts.

## Field Admission Rubric
A field is allowed in strict JSON only if at least one condition is true:
1. Gate-enforced: read by a blocking gate (`wf_step`, `verify`, `prd_set_pass`, manifest/sidecar validators).
2. Binding-critical: needed to bind artifact to story/head/step and prevent cross-wire or replay mistakes.
3. Deterministic diagnostics: required to emit actionable fail-closed errors without human inference.

If none apply, the field must move to `.md` narrative artifacts.

## Field Classes
- `REQUIRED_GATE`: directly required by a blocking gate.
- `REQUIRED_BINDING`: required for story/head/step identity integrity.
- `OPTIONAL_DEBUG`: useful but not gate-critical.
- `NARRATIVE_ONLY`: not allowed in strict JSON.

## Decision Workflow For New Fields
1. Name the gate consumer (`script:file:line`) that reads the field.
2. Define deterministic failure mode when field is missing/invalid.
3. Add one positive and one negative test for that field.
4. If no gate consumer exists, field must be `NARRATIVE_ONLY`.

---

## Canonical Matrix (Current Gates + Validator Coverage)

| Artifact type | Required fields (strict JSON) | Optional fields | Gate consumer(s) | Failure mode (fail-closed) |
|---|---|---|---|---|
| Workflow receipt `.wf/receipts/<ID>/<NN>_<step>.json` | `story_id` (`REQUIRED_BINDING`), `head_sha`, `timestamp_utc` (`REQUIRED_GATE`) | `step_name`, `step_index`, `recon_mode`, `recon_relaxation`, `code_changed` | `plans/wf_step.sh`, `plans/prd_set_pass.sh` | `ERROR: workflow receipt missing required metadata`; `WF_STEP: receipt mismatch ... story_id=...` |
| Scope lock `.wf/recon_scope_lock/<ID>.scope_lock.json` | `story_id`, `scope_sha256`, `lock_head_sha` | `schema_version`, `locked_at`, `scope_source_file`, `scope` | `plans/wf_step.sh` (`check_scope_lock_matches`) | `WF_STEP: scope lock malformed`; `scope lock mismatch`; `scope lock head mismatch` |
| Verify metadata `artifacts/verify/<run>/verify.meta.json` | `mode`, `head_sha` | `schema_version`, `tool`, `run_id`, `status`, `base_ref`, `started_at`, `ended_at`, `worktree`, `failed_gate` | `plans/wf_step.sh verify_full`, `plans/prd_set_pass.sh` | `verify was mode=... need full`; `verify metadata missing head_sha`; `HEAD mismatch`; `FAILED_GATE present` |
| Contract review `artifacts/verify/<run>/contract_review.json` | `selected_story_id`, `decision`, `confidence`, `contract_refs_checked`, `scope_check`, `verify_check`, `pass_flip_check`, `violations`, `required_followups`, `rationale` | none (`additionalProperties: false`) | `plans/contract_review_validate.sh`, `plans/prd_set_pass.sh`, `plans/artifact_lint.sh` | `ERROR: contract review schema invalid`; `ERROR: contract review decision is not PASS` |
| Recon bundle manifest `artifacts/recon_bundles/<bundle>/bundle.manifest.json` | `schema_version`, `bundle_id`, `slice_id`, `source_head_sha`, `created_at_utc`, `files[]` (`path`, `sha256`, `size_bytes`) | `verify_run_id` | `plans/recon_bundle.sh import` | `invalid manifest structure`; `unsafe manifest path`; `missing payload file`; `checksum mismatch`; `source_head_sha mismatch` |
| Recon artifact (`gap_list`) | `schema_version`, `head_commit`, `created_at`, `gaps`, `systemic_gaps`, `priority_summary` | none (extras are non-gate narrative and should move to `.md`) | `plans/validate_recon_artifact.sh gap_list` (directly and via `plans/artifact_lint.sh`) | `FAIL: ... failed validation for schema 'gap_list'` |
| Recon artifact (`verify_result`) | `schema_version`, `head_commit`, `created_at`, `story_id`, `verdict`, `p0_closed`, `p1_closed_or_deferred`, `weak_proof_escalated`, `tests_pass`, `stoplight_delta`, `r5b_receipts_verified`, `evidence_ledger_updated` | none | `plans/validate_recon_artifact.sh verify_result` (directly and via `plans/artifact_lint.sh`) | `missing or null required field`; `verdict ... not in allowed values` |
| Recon artifact (`review_receipt`) | `schema_version`, `head_commit`, `created_at`, `story_id`, `review_basis`, `review_basis_cycle`, `tool`, `prompt_style`, `phase_equivalent`, `citations`, `findings`, `finding_counts` | none | `plans/validate_recon_artifact.sh review_receipt` (directly and via `plans/artifact_lint.sh`) | `missing or null required field`; `review_basis ... not in allowed values` |
| Recon artifact (`phase_mapping`) | `schema_version`, `head_commit`, `created_at`, `story_id`, `mappings`, `unmapped_count`, `unmapped_p0_p1_count` | none | `plans/validate_recon_artifact.sh phase_mapping` (directly and via `plans/artifact_lint.sh`) | validation fail on missing required fields (`unmapped_p0_p1_count != 0` is warning-only) |
| Recon artifact (`premortem_ready`) | `schema_version`, `head_commit`, `created_at`, `story_id`, `ready`, `premortem_exists`, `stoplight`, `stoplight_is_red`, `ownership_conflicts`, `ownership_conflict_details`, `sections_present`, `premortem_gate_exit_code`, `reasons` | none | `plans/premortem_ready.sh`, `plans/wf_step.sh preflight`, `plans/validate_recon_artifact.sh premortem_ready` (via `plans/artifact_lint.sh`) | preflight blocks on premortem gate failure; validator fails on missing required fields |
| Recon artifact (`lead_eval_sidecar`) | `schema_version`, `head_commit`, `created_at`, `markdown_sha256`, `markdown_path`, `story_ids`, `citation_checks_performed`, `verdict_overrides`, `red_flags`, `overall_ratings` | none | `plans/validate_recon_artifact.sh lead_eval_sidecar` (directly and via `plans/artifact_lint.sh`) | sidecar validation failure; markdown hash mismatch when markdown exists |
| Recon artifact (`self_review_sidecar`) | `schema_version`, `head_commit`, `created_at`, `markdown_sha256`, `markdown_path`, `story_id`, `skills_run`, `total_blockers`, `premortem_crosscheck`, `at_proof_gaps` | none | `plans/validate_recon_artifact.sh self_review_sidecar` (directly and via `plans/artifact_lint.sh`) | sidecar validation failure; markdown hash mismatch when markdown exists |
| Recon artifact (`review_artifact_sidecar`) | `schema_version`, `head_commit`, `created_at`, `markdown_sha256`, `markdown_path`, `story_id`, `review_type`, `review_basis`, `tool`, `phase_equivalent`, `citations_count`, `pre_existing_citations_count`, `finding_counts`, `basis_line_present` | none | `plans/review_logged.sh`, `plans/wf_step.sh`, `plans/validate_recon_artifact.sh review_artifact_sidecar` | `HARD_GATE_FAIL: Sidecar validation failed`; enum/key validation failures |
| External manifest (`r3_external_manifest`) | v2 schema shape: `provenance`, `story_id`, `slice_id`, `phase`, `cycle`, `required_combinations`, `reviews`, `validation` (plus nested schema-required members); legacy compatibility shape still accepted by bash validator | none | `plans/external_manifest_gate.sh` -> `plans/validate_recon_artifact.sh r3_external_manifest` + `plans/validators/validate_external_manifest.py` | gate blocks with `R3_EXTERNAL_MANIFEST_INCOMPLETE:<failure_code>` |
| External manifest (`r7_external_manifest`) | v2 schema shape: `provenance`, `story_id`, `slice_id`, `phase`, `cycle`, `required_combinations`, `reviews`, `regression_scope`, `validation` (plus nested schema-required members); legacy compatibility shape still accepted by bash validator | none | `plans/external_manifest_gate.sh` -> `plans/validate_recon_artifact.sh r7_external_manifest` + `plans/validators/validate_external_manifest.py` | gate blocks with `R7_EXTERNAL_MANIFEST_INCOMPLETE:<failure_code>` |
| Recon artifact (`recon_step_report`) | `schema_version`, `head_commit`, `created_at`, `story_id`, `step_name`, `step_index`, `status`, `exit_code`, `commands_run`, `files_changed`, `strongest_evidence`, `not_done` | none | `plans/recon_operator_run.sh`, `plans/recon_trace.sh` -> `plans/validate_recon_artifact.sh recon_step_report` + `plans/validate_recon_step_report.py` | validator blocks on schema/enum mismatch; trace orchestration blocks on missing/invalid step report |
| Recon artifact (`recon_trace_receipt`) | `schema_version`, `head_commit`, `created_at`, `run_id`, `story_id`, `slice_id`, `step_name`, `step_index`, `start_at`, `end_at`, `duration_seconds`, `retries`, `result`, `attempt`, `wf_receipt_path`, `wf_receipt_sha256`, `step_report_path`, `step_report_sha256` | none | `plans/recon_trace.sh` -> `plans/validate_recon_artifact.sh recon_trace_receipt` + `plans/validate_recon_step_report.py` cross-checks | validator blocks on schema mismatch; trace receipt write fails closed when hash/path binding fields are absent |

---

## Non-Gate Narrative Policy
These belong in markdown, not strict JSON:
- long-form reasoning
- remediation prose
- retrospective/debrief commentary
- duplicate summaries of machine-derivable values

Recommended markdown homes:
- `artifacts/story/<ID>/.../*.md`
- `reviews/reconciliations/<slice>/*.md`
- HANDOFF narrative sections

---

## Implementation Notes For Slimming Work
1. Writers should emit only fields listed as required above (and explicit optional debug fields where listed).
2. Run `plans/artifact_lint.sh` before `./plans/verify.sh full` to fail fast on malformed JSON/schema drift.
3. Keep strict pass gates in `plans/prd_set_pass.sh` unchanged.
4. Move narrative fields to markdown artifacts instead of expanding strict JSON payloads.
