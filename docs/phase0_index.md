# Phase 0 Index (Merged Navigation)

This file is a quick navigation map for all Phase 0 material across docs and non-doc paths.

Decision inputs (current):
- `docs/PHASE0_CHECKLIST_BLOCK.md`
- `docs/ROADMAP.md`

Historical reference only:
- Prior merged roadmap text in git history.

## Policy

| Topic | File | Evidence Path |
|---|---|---|
| Canonical gating checklist (P0-A..P0-F, tests, sign-off, non-goals) | `docs/PHASE0_CHECKLIST_BLOCK.md` | `evidence/phase0/` |
| Acceptance narrative and exact minimal tests | `docs/phase0_acceptance.md` | `evidence/phase0/README.md` |
| Phase 0 roadmap status and addendum | `docs/ROADMAP.md` | `evidence/phase0/` |
| Launch policy baseline | `docs/launch_policy.md` | `evidence/phase0/policy/launch_policy_snapshot.md` |
| Environment isolation matrix | `docs/env_matrix.md` | `evidence/phase0/env/env_matrix_snapshot.md` |
| Keys and secrets baseline | `docs/keys_and_secrets.md` | `evidence/phase0/keys/key_scope_probe.json`, `evidence/phase0/keys/rotation_exercise.md` |
| Break-glass runbook | `docs/break_glass_runbook.md` | `evidence/phase0/break_glass/runbook_snapshot.md` |
| Health + owner status contract | `docs/health_endpoint.md` | `evidence/phase0/health/health_endpoint_snapshot.md` |
| Machine-readable policy baseline | `config/policy.json` | `evidence/phase0/policy/policy_config_snapshot.json` |
| Strict policy loader | `tools/policy_loader.py` | `evidence/phase0/policy/policy_config_snapshot.json` |
| Contract references touching Phase 0 | `specs/CONTRACT.md` | `evidence/phase0/` |
| Audit prompt refs for Phase 0 policy/infra | `prompts/auditor.md` | `evidence/phase0/ci_links.md` |

## Evidence

- `evidence/phase0/README.md`
- `evidence/phase0/ci_links.md`
- `evidence/phase0/policy/launch_policy_snapshot.md`
- `evidence/phase0/policy/policy_config_snapshot.json`
- `evidence/phase0/env/env_matrix_snapshot.md`
- `evidence/phase0/keys/key_scope_probe.json`
- `evidence/phase0/keys/rotation_exercise.md`
- `evidence/phase0/keys/rotation_check_all.json`
- `evidence/phase0/keys/rotation_check_live.json`
- `evidence/phase0/keys/rotation_check_staging.json`
- `evidence/phase0/keys/live_cutover_drill.md`
- `evidence/phase0/break_glass/runbook_snapshot.md`
- `evidence/phase0/break_glass/drill.md`
- `evidence/phase0/break_glass/log_excerpt.txt`
- `evidence/phase0/health/health_endpoint_snapshot.md`

## Tests

Definition docs:
- `tests/phase0/README.md`
- `tests/phase0/test_policy_is_required_and_bound.md`
- `tests/phase0/test_machine_policy_loader_and_config.md`
- `tests/phase0/test_health_command_behavior.md`
- `tests/phase0/test_status_command_behavior.md`
- `tests/phase0/test_api_keys_are_least_privilege.md`
- `tests/phase0/test_break_glass_kill_blocks_open_allows_reduce.md`

Runtime integration coverage:
- `crates/soldier_infra/tests/test_phase0_runtime.rs`

## Enforcement

- `tools/phase0_meta_test.py` (Phase 0 doc/evidence/runtime gate checks)
- `stoic-cli` (executable health/status/emergency command surface)
- `plans/verify.sh` (verify entrypoint)
- `plans/verify_fork.sh` (canonical verify gate implementation)
- `plans/test_verify_fork_smoke.sh` (verify smoke coverage)
- `plans/story_verify_allowlist.txt` (workflow allowlist constraints)
- `plans/prd.json` (Phase 0 story state and acceptance mapping)
- `plans/progress.txt` (execution traceability and evidence history)
