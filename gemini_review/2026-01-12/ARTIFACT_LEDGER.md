# Artifact Ledger

| Artifact Path | Type | Producer | Consumer | Lifecycle | Required? |
|---------------|------|----------|----------|-----------|-----------|
| `plans/prd.json` | JSON | **Story Cutter** / `plans/cut_prd.sh` | **Ralph** (Read/Write via helper) | Evolves; main backlog. | **YES** |
| `plans/ralph.sh` | Script | **Dev** / Bootstrap | **User** / CI | Static (executable). | **YES** |
| `plans/verify.sh` | Script | **Dev** / Bootstrap | **Ralph** / CI | Static; single source of truth. | **YES** |
| `plans/progress.txt` | Text | **Agent** (Append) | **Ralph** (Read/Check) | Append-only; audit log. | **YES** |
| `plans/init.sh` | Script | **Dev** / Bootstrap | **Ralph** (Run) | Static; idempotent setup. | Optional |
| `plans/contract_check.sh` | Script | **Dev** | **Ralph** (Run) | Static; contract alignment. | **YES** |
| `plans/prd_schema_check.sh` | Script | **Dev** | **Ralph** (Run) | Static; schema validation. | **YES** |
| `plans/update_task.sh` | Script | **Dev** | **Ralph** (Run) | Static; PRD mutation helper. | **YES** |
| `plans/contract_review_validate.sh` | Script | **Dev** | **Ralph** / `contract_check.sh` | Static; review schema validator. | **YES** |
| `plans/workflow_acceptance.sh` | Script | **Dev** | **Dev** | Static; meta-test for Ralph. | Recommended |
| `plans/bootstrap.sh` | Script | **Dev** | **Dev** | One-off; scaffolding. | No |
| `plans/cut_prd.sh` | Script | **Dev** | **Dev** | Static; Story Cutter entrypoint. | No |
| `plans/prd_lint.sh` | Script | **Dev** | `cut_prd.sh` | Static; PRD linter. | No |
| `plans/prompts/cutter.md` | Markdown | **Dev** | `cut_prd.sh` | Static; prompt template. | No |
| `plans/story_verify_allowlist.txt` | Text | **Dev** | **Ralph** | Static; security config. | **YES** |
| `plans/logs/ralph.*.log` | Log | **Ralph** | **User** | Append/Create per run. | **YES** |
| `.ralph/state.json` | JSON | **Ralph** | **Ralph** | R/W; runtime state persistence. | **YES** |
| `.ralph/lock/` | Dir | **Ralph** | **Ralph** | Ephemeral; concurrency lock. | **YES** |
| `.ralph/iter_*/` | Dir | **Ralph** | **User** (Audit) | Created per iteration. | **YES** |
| `.ralph/iter_*/selected.json` | JSON | **Ralph** | **Agent** / Audit | Iteration snapshot. | **YES** |
| `.ralph/iter_*/prompt.txt` | Text | **Ralph** | **Agent** | Iteration input. | **YES** |
| `.ralph/iter_*/agent.out` | Text | **Agent** | **Ralph** | Iteration output (raw). | **YES** |
| `.ralph/iter_*/verify_pre.log` | Log | **Ralph** (`verify.sh`) | **Ralph** / Audit | Validation log. | **YES** |
| `.ralph/iter_*/verify_post.log` | Log | **Ralph** (`verify.sh`) | **Ralph** / Audit | Validation log. | **YES** |
| `.ralph/iter_*/contract_review.json` | JSON | `contract_check.sh` | **Ralph** | Review decision. | **YES** |
| `.ralph/blocked_*/` | Dir | **Ralph** | **User** | Created on failure/block. | No (Conditional) |
| `CONTRACT.md` | Markdown | **Dev** | **Ralph** / **Agent** | Static; Source of Truth. | **YES** |
| `IMPLEMENTATION_PLAN.md` | Markdown | **Dev** | **Story Cutter** / **Agent** | Static; Source of Truth. | **YES** |
| `docs/codebase/*` | Markdown | **Agent** / **Dev** | **Agent** | Live documentation. | Recommended |
| `plans/ideas.md` | Markdown | **Agent** | **User** | Append-only; scratchpad. | Optional |
| `plans/pause.md` | Markdown | **Agent** | **User** | Ephemeral; handoff note. | Optional |
