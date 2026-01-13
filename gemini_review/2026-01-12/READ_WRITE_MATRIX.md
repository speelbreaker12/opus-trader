# Read/Write Matrix

| Step | Artifact | Access | Notes |
|------|----------|--------|-------|
| **Init** | `.ralph/lock` | **Create** | Directory lock. |
| **Init** | `plans/logs/ralph.log` | **Append** | Execution log. |
| **Preflight** | `plans/prd.json` | Read | Schema validation. |
| **Preflight** | `plans/prd_schema_check.sh` | Execute | |
| **Preflight** | `.ralph/state.json` | R/W | Init state if missing. |
| **Preflight** | `plans/progress.txt` | Check | Existence check. |
| **Loop Start** | `plans/progress.txt` | Read/Write | Rotation (via `rotate_progress.py`). |
| **Loop Start** | `.ralph/iter_*/` | **Create** | New iteration dir. |
| **Select** | `plans/prd.json` | Read | Filter active slice, pick story. |
| **Select** | `.ralph/iter_*/selected.json` | **Create** | Snapshot of selection. |
| **Verify Pre** | `plans/verify.sh` | Execute | Baseline check. |
| **Verify Pre** | `.ralph/iter_*/verify_pre.log` | **Create** | Output capture. |
| **Prompt** | `plans/prd.json` | Read | Context for agent. |
| **Prompt** | `plans/progress.txt` | Read | Context for agent. |
| **Prompt** | `AGENTS.md` | Read | Context for agent. |
| **Prompt** | `.ralph/iter_*/prompt.txt` | **Create** | Prompt text. |
| **Run Agent** | `plans/progress.txt` | **Append** | Agent adds entry. |
| **Run Agent** | `docs/codebase/*` | **Write** | Agent updates docs (optional). |
| **Run Agent** | `plans/ideas.md` | **Append** | Agent adds ideas (optional). |
| **Run Agent** | `plans/pause.md` | **Write** | Agent adds pause note (optional). |
| **Run Agent** | *Source Code* | **Write** | Agent implements story. |
| **Run Agent** | `.ralph/iter_*/agent.out` | **Create** | Agent stdout capture. |
| **Post-Agent** | `.ralph/iter_*/diff.patch` | **Create** | Snapshot of changes. |
| **Verify Post** | `plans/verify.sh` | Execute | Validation check. |
| **Verify Post** | `.ralph/iter_*/verify_post.log` | **Create** | Output capture. |
| **Review** | `plans/contract_check.sh` | Execute | Contract alignment check. |
| **Review** | `CONTRACT.md` | Read | Checked against refs. |
| **Review** | `.ralph/iter_*/contract_review.json` | **Create** | Review artifact. |
| **Update** | `plans/update_task.sh` | Execute | Flips passes=true. |
| **Update** | `plans/prd.json` | **Write** | Updated status. |
| **Commit** | `.git` | **Write** | `git commit`. |
| **Completion** | `plans/prd.json` | Read | Check all passed. |
| **Block** | `.ralph/blocked_*/` | **Create** | Snapshot on failure. |
