# REPO_MAP

Generated: 2026-02-08

## Source of truth

- `specs/CONTRACT.md` — runtime/trading contract.
- `specs/WORKFLOW_CONTRACT.md` — coding workflow contract.
- `specs/IMPLEMENTATION_PLAN.md` — implementation plan.
- `plans/prd.json` — story backlog.

## Verification surface

- `plans/verify.sh` — stable verify entrypoint.
- `plans/verify_fork.sh` — canonical verify implementation.
- `plans/preflight.sh` — cheap preflight gate.
- `plans/lib/verify_utils.sh` — artifact/logging helpers.
- `plans/lib/rust_gates.sh` — rust gates.
- `plans/lib/python_gates.sh` — python gates.
- `plans/lib/node_gates.sh` — node gates.

## Workflow controls

- `plans/prd_set_pass.sh` — guarded pass flips.
- `plans/workflow_contract_gate.sh` — workflow contract/map consistency checks.
- `plans/workflow_verify.sh` — workflow maintenance runner.
- `plans/workflow_files_allowlist.txt` — workflow-sensitive file inventory.

## PRD + review tooling

- `plans/prd_gate.sh`
- `plans/prd_schema_check.sh`
- `plans/prd_audit_check.sh`
- `plans/codex_review_let_pass.sh`
- `reviews/REVIEW_CHECKLIST.md`

## Root wrappers

- `verify.sh` — wrapper to `plans/verify.sh`.
- `sync` — `git fetch` + `git pull --ff-only`.
