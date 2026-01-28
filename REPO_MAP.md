# REPO_MAP.md — Ralph Repository Survival Audit

Generated: 2026-01-27

---

## A) ENTRYPOINTS (directly invoked by humans/CI/runtime)

| Path | What it does | Wired from | Why must exist | Verdict |
|------|--------------|------------|----------------|---------|
| `ralph` | Entry point to orchestrator | Human CLI | Convenience wrapper | **KEEP** |
| `verify.sh` (root) | Redirect stub to `plans/verify.sh` | Human CLI, legacy refs | Convenience wrapper | **KEEP** (stub only) |
| `sync` | Git fetch + ff-only pull | Human CLI | Convenience | **KEEP** |
| `plans/ralph.sh` | Main iteration orchestrator | `ralph`, `workflow_acceptance.sh` (40+ calls) | Core workflow engine | **KEEP** |
| `plans/verify.sh` | Verification gate (quick/full/promotion) | CI `ci.yml:88`, `ralph.sh`, `workflow_acceptance.sh` | Canonical verification | **KEEP** |
| `plans/workflow_acceptance.sh` | Acceptance test harness | `plans/verify.sh:workflow_acceptance` | Workflow contract enforcement | **KEEP** |
| `plans/init.sh` | Baseline setup | `AGENTS.md`, optional pre-ralph | Idempotent initialization | **KEEP** |
| `.github/workflows/ci.yml` | CI pipeline | GitHub Actions | Automated gates | **KEEP** |

---

## B) CONTRACT/SPEC (normative source of truth)

| Path | What it does | Wired from | Why must exist | Verdict |
|------|--------------|------------|----------------|---------|
| `specs/CONTRACT.md` | **Canonical trading contract** | `ssot_lint.sh:25`, CI, all contract checks | Single source of truth | **KEEP** |
| `specs/IMPLEMENTATION_PLAN.md` | Phase/slice implementation plan | PRD refs, contract checks | Implementation roadmap | **KEEP** |
| `specs/WORKFLOW_CONTRACT.md` | Workflow rules (WF-*) | `workflow_contract_gate.sh`, `AGENTS.md` | Workflow enforcement | **KEEP** |
| `specs/POLICY.md` | Policy document | `ssot_lint.sh:27` | Required by SSOT | **KEEP** |
| `specs/SOURCE_OF_TRUTH.md` | SSOT definition | `ssot_lint.sh` | Meta-spec | **KEEP** |
| `specs/flows/*.yaml` | Architecture flows | `check_arch_flows.py`, `verify.sh` | Spec integrity | **KEEP** |
| `specs/flows/*.md` | Crash matrix, reconciliation | `check_crash_matrix.py`, `check_reconciliation_matrix.py` | Spec integrity | **KEEP** |
| `specs/state_machines/*.yaml` | State machine specs | `check_state_machines.py` | Spec integrity | **KEEP** |
| `specs/invariants/GLOBAL_INVARIANTS.md` | Global invariants | `check_global_invariants.py` | Spec integrity | **KEEP** |
| `specs/vendor_docs/rust/CRATES_OF_INTEREST.yaml` | Vendor docs | `vendor_docs_lint_rust.py` | Vendor tracking | **KEEP** |

---

## C) REDIRECT STUBS (must not edit content)

| Path | Points to | Evidence | Verdict |
|------|-----------|----------|---------|
| `verify.sh` (root) | `plans/verify.sh` | `exec "$ROOT/plans/verify.sh" "$@"` | **KEEP** (stub only) |
| `POLICY.md` (root) | `specs/POLICY.md` | `CANONICAL SOURCE OF TRUTH: specs/POLICY.md` | **KEEP** (stub only) |
| `CONTRACT.md` (root) | **DELETED** | `ssot_lint.sh:44` forbids root CONTRACT.md | **N/A** (correctly absent) |
| `IMPLEMENTATION_PLAN.md` (root) | **MISSING** | Should be stub per `ssot_lint.sh:42` | **CREATE** stub pointing to specs/ |

---

## D) HARNESS/TEST (gates + acceptance)

| Path | What it does | Wired from | Verdict |
|------|--------------|------------|---------|
| `plans/prd_schema_check.sh` | PRD JSON schema validation | `ralph.sh`, `prd_gate.sh`, `prd_lint.sh` | **KEEP** |
| `plans/prd_gate.sh` | PRD gating (schema + lint + refs) | `workflow_acceptance.sh`, `prd_pipeline.sh`, `cut_prd.sh` | **KEEP** |
| `plans/prd_lint.sh` | PRD linting | `prd_gate.sh` | **KEEP** |
| `plans/prd_ref_check.sh` | PRD reference resolution | `prd_gate.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/prd_ref_index.sh` | PRD reference indexing | `prd_ref_check.sh` (indirect) | **KEEP** |
| `plans/prd_pipeline.sh` | Full PRD pipeline | `workflow_acceptance.sh` | **KEEP** |
| `plans/prd_autofix.sh` | PRD auto-fix | `prd_pipeline.sh` | **KEEP** |
| `plans/prd_audit_check.sh` | PRD audit validation | `workflow_acceptance.sh`, `tests/test_prd_audit_check.sh` | **KEEP** |
| `plans/run_prd_auditor.sh` | PRD auditor runner | `workflow_acceptance.sh` | **KEEP** |
| `plans/prd_slice_prepare.sh` | Slice preparation | `run_prd_auditor.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/ssot_lint.sh` | SSOT enforcement | CI `ci.yml:18`, `workflow_acceptance.sh` | **KEEP** |
| `plans/contract_check.sh` | Contract review validation | `ralph.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/contract_review_validate.sh` | Contract review schema | `contract_check.sh`, `ralph.sh` | **KEEP** |
| `plans/contract_coverage_matrix.py` | Coverage matrix | `verify.sh`, `tests/test_contract_coverage_matrix.sh` | **KEEP** |
| `plans/contract_coverage_promote.sh` | Coverage promotion | `verify.sh` (warning ref) | **KEEP** |
| `plans/workflow_contract_gate.sh` | WF-* rule enforcement | `workflow_acceptance.sh` | **KEEP** |
| `plans/workflow_contract_map.json` | WF rule → test mapping | `workflow_contract_gate.sh` | **KEEP** |
| `plans/workflow_verify.sh` | Workflow-specific verify | `workflow_acceptance.sh` | **KEEP** |
| `plans/artifacts_validate.sh` | Artifact validation | `workflow_acceptance.sh` | **KEEP** |
| `plans/postmortem_check.sh` | Postmortem gate | `verify.sh` | **KEEP** |
| `plans/update_task.sh` | Safe PRD mutation | `ralph.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/rotate_progress.py` | Progress rotation | `ralph.sh` | **KEEP** |
| `plans/build_markdown_digest.sh` | Markdown digest builder | `build_contract_digest.sh`, `build_plan_digest.sh` | **KEEP** |
| `plans/build_contract_digest.sh` | Contract digest | `run_prd_auditor.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/build_plan_digest.sh` | Plan digest | `run_prd_auditor.sh`, `workflow_acceptance.sh` | **KEEP** |
| `plans/profile.sh` | Profile presets | Human use | **KEEP** |
| `plans/tests/*.sh` | Unit tests for harness | `workflow_acceptance.sh` | **KEEP** |
| `plans/fixtures/prd/*.json` | Test fixtures | `tests/test_prd_gate.sh`, `workflow_acceptance.sh` | **KEEP** |

---

## E) LIBRARY (imported code)

| Path | What it does | Wired from | Verdict |
|------|--------------|------------|---------|
| `crates/soldier_core/` | Core Rust execution lib | `Cargo.toml` workspace | **KEEP** |
| `crates/soldier_infra/` | Infrastructure lib | `Cargo.toml` workspace | **KEEP** |
| `scripts/contract_kernel_lib.py` | Kernel Python lib | `check_contract_kernel.py`, `build_contract_kernel.py` | **KEEP** |
| `scripts/utils/*.py` | Utility modules | `scripts/*.py` imports | **KEEP** |

---

## F) TOOLING (dev utilities)

| Path | What it does | Wired from | Verdict |
|------|--------------|------------|---------|
| `scripts/check_arch_flows.py` | Arch flow validation | `verify.sh` | **KEEP** |
| `scripts/check_state_machines.py` | State machine validation | `verify.sh` | **KEEP** |
| `scripts/check_global_invariants.py` | Invariant validation | `verify.sh` | **KEEP** |
| `scripts/check_time_freshness.py` | Time freshness validation | `verify.sh` | **KEEP** |
| `scripts/check_crash_matrix.py` | Crash matrix validation | `verify.sh` | **KEEP** |
| `scripts/check_crash_replay_idempotency.py` | Crash replay validation | `verify.sh` | **KEEP** |
| `scripts/check_reconciliation_matrix.py` | Reconciliation validation | `verify.sh` | **KEEP** |
| `scripts/check_vq_evidence.py` | VQ evidence validation | `verify.sh` (16 refs) | **KEEP** |
| `scripts/check_csp_trace.py` | CSP trace validation | CI `ci.yml:43-45`, `verify.sh` | **KEEP** |
| `scripts/check_contract_crossrefs.py` | Contract cross-refs | `verify.sh` | **KEEP** |
| `scripts/check_contract_kernel.py` | Kernel validation | `verify.sh` | **KEEP** |
| `scripts/build_contract_kernel.py` | Kernel builder | `build_contract_digest.sh` | **KEEP** |
| `scripts/extract_contract_excerpts.py` | Contract excerpts | `verify.sh` | **KEEP** |
| `scripts/generate_impact_report.py` | Impact report | CI `ci.yml:51-52` | **KEEP** |
| `scripts/setup_hooks.sh` | Git hooks setup | Human use | **KEEP** |
| `scripts/push_main.sh` | Push to main | Human use | **KEEP** |
| `tools/ci/check_contract_profiles.py` | Profile tag check | CI `ci.yml:36` | **KEEP** |
| `tools/vendor_docs_lint_rust.py` | Vendor docs linting | `verify.sh` | **KEEP** |

---

## G) DOCS (non-normative guidance)

| Path | What it does | Wired from | Verdict |
|------|--------------|------------|---------|
| `AGENTS.md` | Agent guide | Human reading, `workflow_acceptance.sh` | **KEEP** |
| `README.md` | Repo readme | Human reading | **KEEP** |
| `WORKFLOW_FRICTION.md` | Friction log | `AGENTS.md` ref | **KEEP** |
| `docs/schemas/*.json` | JSON schemas | `contract_review_validate.sh`, `artifacts_validate.sh` | **KEEP** |
| `docs/skills/workflow.md` | Workflow skill doc | `AGENTS.md` ref | **KEEP** |
| `docs/roadmap/*.md` | Roadmap docs | Human reading | **KEEP** |
| `docs/contract_anchors.md` | Contract anchors | `build_contract_kernel.py` | **KEEP** |
| `docs/validation_rules.md` | Validation rules | `build_contract_kernel.py` | **KEEP** |
| `docs/contract_coverage.md` | Coverage tracking | `contract_coverage_matrix.py` | **KEEP** |
| `docs/contract_kernel.json` | Derived kernel | `check_contract_kernel.py` | **KEEP** |
| `prompts/auditor.md` | PRD auditor prompt | `run_prd_auditor.sh`, `workflow_acceptance.sh` | **KEEP** |
| `reviews/REVIEW_CHECKLIST.md` | PR review checklist | `AGENTS.md` ref | **KEEP** |
| `reviews/postmortems/*.md` | PR postmortems | `postmortem_check.sh` | **KEEP** |
| `reviews/postmortems/PR_POSTMORTEM_TEMPLATE.md` | Template | `AGENTS.md` ref | **KEEP** |

---

## H) QUARANTINE CANDIDATES (uncertain value)

| Path | What it does | Issue | Verdict |
|------|--------------|-------|---------|
| `plans/cut_prd.sh` | PRD cutting | **0 inbound refs** | **QUARANTINE** |
| `scripts/suggest_downstream_patches.py` | Patch suggestions | **0 inbound refs** | **QUARANTINE** |
| `scripts/verify_local.sh` | Local verify | **0 inbound refs** (new file?) | **QUARANTINE** |
| `prompts/architect_advisor.md` | Architect prompt | **0 inbound refs** | **QUARANTINE** |
| `prompts/contact_arbiter.md` | Arbiter prompt | **0 inbound refs** | **QUARANTINE** |
| `prompts/workflow_121.md` | Workflow prompt | **0 inbound refs** | **QUARANTINE** |
| `prompts/Workflow_Auditor.md` | Auditor prompt | **0 inbound refs** (duplicate of auditor.md?) | **QUARANTINE** |
| `docs/architecture/*.md` | Architecture docs | **orphan** (no inbound links except system_map.md) | **QUARANTINE** (merge into docs/codebase/) |
| `docs/codebase/*.md` | Codebase docs | **orphan** (no inbound links) | **QUARANTINE** (referenced by AGENTS.md conceptually) |

---

## I) DELETE CANDIDATES

| Path | What it does | Evidence unused | Safe delete proof | Verdict |
|------|--------------|-----------------|-------------------|---------|
| `patches/*.patch` | CSP patches | No script references; manual apply only | Remove + verify CI passes | **DELETE** (archive first) |
| `to-do/*.diff`, `to-do/*.md` | WIP contract patches | Superseded by `specs/CONTRACT.md` edits | Remove + verify CI passes | **DELETE** (archive first) |
| `docs/bundle_CONTRACT_PHASE1.md` | Phase 1 excerpt | 688 lines; no refs; specs/CONTRACT.md is canonical | Remove + verify CI passes | **DELETE** |
| `docs/audit_fixes.md` | Audit fixes log | No refs | Remove + verify CI passes | **QUARANTINE** |
| `docs/dispatch_map_discovery.md` | Discovery doc | No refs | Check if needed | **QUARANTINE** |
| `docs/order_size_discovery.md` | Discovery doc | No refs | Check if needed | **QUARANTINE** |
| `docs/flows.md` | Flow notes | Superseded by `specs/flows/` | Remove + verify CI passes | **DELETE** |
| `docs/verify_runs.md` | Verify run log | No refs | Remove + verify CI passes | **QUARANTINE** |
| `docs/PLAN_PHASE1_EXCERPT.md` | Phase 1 excerpt | Superseded by `specs/IMPLEMENTATION_PLAN.md` | Remove + verify CI passes | **DELETE** |
| `plans/ideas.md` | Ideas log | Non-essential | Keep for now | **KEEP** (optional) |
| `plans/pause.md` | Pause notes | Non-essential | Keep for now | **KEEP** (optional) |
| `plans/story_cutter_report.md` | Cutter report | Artifact from `cut_prd.sh` | Remove if cut_prd.sh removed | **QUARANTINE** |
| `plans/cutter_rules.md` | Cutter rules | Used by `cut_prd.sh` only | Remove if cut_prd.sh removed | **QUARANTINE** |
| `plans/prd_audit.json` | Audit output | Generated artifact | Should be in .gitignore | **QUARANTINE** |
| `plans/prd_audit.md` | Audit markdown | Generated artifact | Should be in .gitignore | **QUARANTINE** |

---

## J) GENERATED/ARTIFACT (should be gitignored)

| Path | Status | Action |
|------|--------|--------|
| `.ralph/` | Gitignored | OK |
| `artifacts/` | Partially tracked | Review what should be committed |
| `target/` | Gitignored | OK |
| `plans/logs/` | Tracked | Should be gitignored |
| `plans/prd_audit.json` | Tracked | Should be gitignored |
| `plans/prd_audit.md` | Tracked | Should be gitignored |

---

## Summary Statistics

| Category | Count | Action |
|----------|-------|--------|
| **KEEP** | ~80 files | No action |
| **KEEP (stub)** | 2 files | Ensure stub-only |
| **CREATE** | 1 file | `IMPLEMENTATION_PLAN.md` stub at root |
| **QUARANTINE** | ~15 files | Move to `attic/` with README |
| **DELETE** | ~20 files | Archive + remove |
