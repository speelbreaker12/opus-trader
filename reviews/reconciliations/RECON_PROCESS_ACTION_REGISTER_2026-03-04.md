# Recon Process Action Register (2026-03-04)

Source: `reviews/reconciliations/RECON_PROCESS_REVIEW.md` recommendations section.
Baseline commit (immutable): `c61926518538be615947eb96d07084a76e57074a`.

| id | source_claim_or_recommendation | status | owner | baseline_sha | proof_command | proof_artifact_path |
|---|---|---|---|---|---|---|
| REC-01 | Keep a single full pipeline (for now). | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `plans/wf_step.sh <STORY_ID> --status` | `.wf/receipts/<STORY_ID>/` |
| REC-02 | Consolidate documentation to `PROTOCOL.md` + `REFERENCE.md`. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/recon_doc_budget.sh` | `artifacts/verify/recon_followup_20260304T214215Z/recon_doc_budget.log` |
| REC-03 | Merge artifacts aggressively (JSON-first ledger and fewer intermediates). | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/tests/test_recon_evidence_ledger.sh && bash plans/tests/test_wf_step_path_signal_scan.sh` | `artifacts/verify/recon_followup_20260304T214215Z/preflight.log` |
| REC-04 | Replace heavy debrief structure with minimal notes/friction logging. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `rg -n "Reconciliation process docs can regrow|recon_doc_budget" reviews/reconciliations/PROTOCOL.md WORKFLOW_FRICTION.md` | `artifacts/verify/recon_followup_20260304T214215Z/recon_doc_budget.log` |
| REC-05 | Flatten dual-layer naming to one workflow step layer. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/tests/test_recon_prompt_guard.sh` | `artifacts/verify/recon_followup_20260304T214215Z/recon_prompt_guard.log` |
| REC-06 | Fix P0 issues from prior process audits. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/tests/test_verify_fork_guardrails.sh` | `artifacts/verify/recon_followup_20260304T214215Z/preflight.log` |
| REC-07 | Automate mechanical checks (`--dry-run`, stale refs, guards). | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/tests/test_prd_set_pass.sh && bash plans/tests/test_prd_lint.sh && bash plans/tests/test_recon_doc_budget.sh` | `artifacts/verify/recon_followup_20260304T214215Z/preflight.log` |
| REC-08 | Make handoff template path-conditional. | DEFERRED | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `rg -n "path-conditional|base handoff" reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` | `artifacts/story/<STORY_ID>/review_resolution.md` |
| REC-09 | Increase external review parallelism where still sequential. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `plans/parallel_review.sh workflow-maintenance --tools codex,opus,kimi,gemini --uncommitted --prompt enriched -- --timeout-seconds 120` | `artifacts/story/workflow-maintenance/{codex,opus,kimi,gemini}/` |
| REC-10 | Establish and enforce a process docs budget. | ALREADY_DONE | workflow-maintainer | c61926518538be615947eb96d07084a76e57074a | `bash plans/tests/test_recon_doc_budget.sh && PREFLIGHT_FIXTURE_TEST_TIMEOUT=480 ./plans/workflow_verify.sh` | `artifacts/verify/recon_followup_20260304T214215Z/recon_doc_budget.log` |
