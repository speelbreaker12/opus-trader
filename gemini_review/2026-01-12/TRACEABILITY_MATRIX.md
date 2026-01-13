# Traceability Matrix

| Rule ID | Requirement | Implementation | Verification (Acceptance Test) | Status |
| :--- | :--- | :--- | :--- | :--- |
| **WF-2.1** | Contract alignment mandatory | `ralph.sh`: `ensure_contract_review` | `workflow_acceptance.sh`: Test 6, 7, 8 | ✅ Covered |
| **WF-2.2** | Verification mandatory | `ralph.sh`: `run_verify` (pre/post) | `workflow_acceptance.sh`: Test 2 | ✅ Covered |
| **WF-2.3** | WIP = 1 | `ralph.sh`: Agent Prompt | Indirect (Agent Logic) | ⚠️ inferred |
| **WF-2.4** | Slices executed in order | `ralph.sh`: `active_slice` logic | `workflow_acceptance.sh`: Test 4 (Partial) | ✅ Covered |
| **WF-2.5** | No cheating | `ralph.sh`: `detect_cheating` | `workflow_acceptance.sh`: Test 11 | ✅ Covered (Patched) |
| **WF-2.6** | Observable gate | `ralph.sh`: `write_blocked_*` | `workflow_acceptance.sh`: All Tests | ✅ Covered |
| **WF-3.1** | Schema gating | `ralph.sh`: `prd_schema_check.sh` | `workflow_acceptance.sh`: Test 1 | ✅ Covered |
| **WF-5.1** | Preflight invariants | `ralph.sh`: `preflight` block | `workflow_acceptance.sh`: Test 1, 5 | ✅ Covered |
| **WF-5.2** | Active slice gating | `ralph.sh`: `ACTIVE_SLICE` calc | `workflow_acceptance.sh`: Test 4 | ✅ Covered |
| **WF-5.3** | Selection modes | `ralph.sh`: `RPH_SELECTION_MODE` | `workflow_acceptance.sh`: Test 4 | ✅ Covered |
| **WF-5.4** | Hard stop on human decision | `ralph.sh`: `NEXT_NEEDS_HUMAN` | `workflow_acceptance.sh`: Test 10 | ✅ Covered (New) |
| **WF-5.5** | Verify gates (pre/post) | `ralph.sh`: `run_verify` | `workflow_acceptance.sh`: Test 2 | ✅ Covered |
| **WF-5.6** | Story verify requirement | `ralph.sh`: `missing_verify_sh_in_story` | **MISSING** (Implicit in schema?) | ⚠️ Partial |
| **WF-5.7** | Optional self-heal | `ralph.sh`: `RPH_SELF_HEAL` | `workflow_acceptance.sh`: Test 13 | ✅ Covered (New) |
| **WF-5.8** | Completion | `ralph.sh`: `completion_requirements_met` | `workflow_acceptance.sh`: Test 3, 9 | ✅ Covered |
| **WF-5.9** | Anti-spin | `ralph.sh`: `MAX_ITERS` | `workflow_acceptance.sh`: Test 12 | ✅ Covered (New) |
| **WF-6.1** | Iteration Artifacts | `ralph.sh`: `save_iter_artifacts` | `workflow_acceptance.sh`: Test 9 | ✅ Covered |
| **WF-6.2** | Blocked Artifacts | `ralph.sh`: `write_blocked_*` | `workflow_acceptance.sh`: All blocked tests | ✅ Covered |
| **WF-7.1** | Contract Alignment Gate | `ralph.sh`: `ensure_contract_review` | `workflow_acceptance.sh`: Test 6, 8 | ✅ Covered |
| **WF-7.2** | Enforcement (fail closed) | `ralph.sh`: `ensure_contract_review` | `workflow_acceptance.sh`: Test 8 | ✅ Covered |
| **WF-8.1** | CI executes verify | `plans/verify.sh` | N/A (CI Config) | ⚠️ CI-dependent |
| **WF-8.2** | Drift observability | `ralph.sh`: `verify_log_has_sha` | `workflow_acceptance.sh`: Test 4 | ✅ Covered |
| **WF-9.1** | Progress Log | `ralph.sh`: `progress_gate` | `workflow_acceptance.sh`: Test 9, 12 | ✅ Covered |