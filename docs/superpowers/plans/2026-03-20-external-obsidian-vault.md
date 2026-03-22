## Goal

Move Obsidian workflow state out of the repo tree into a shared external vault while keeping publish-boundary enforcement fail-closed.

## Guardrails

- `push` and `PR` creation must still hard-fail when project metadata is missing, unreadable, or out of scope.
- Session-start routing may warn and continue when the external vault is absent.
- Tests must never read a real home-directory vault by accident.
- Commit-time project/debrief staging requirements are removed; publish-boundary validation remains.

## Task 1: Shared Vault Resolver

Files:
- `plans/lib/obsidian_vault.sh`
- `plans/tests/test_obsidian_context_hook.sh`
- `plans/tests/test_project_scope_guard.sh`

Work:
- Add a shell helper that resolves the vault path from `OBSIDIAN_VAULT_PATH` or the default `$HOME/Obsidian/opus-trader`.
- Support `advisory` and `required` modes with deterministic stderr messages.
- Prove the resolver through hook/guard tests by pointing them at temp external vault fixtures.

Verify:
- `bash plans/tests/test_obsidian_context_hook.sh`
- `bash plans/tests/test_project_scope_guard.sh`

## Task 2: Migrate External-Vault Readers

Files:
- `.claude/hooks/obsidian-context-hook.sh`
- `plans/project_scope_guard.sh`
- `plans/post_rebase_frontmatter_check.sh`
- `.claude/hooks/pr-review-gate-hook.sh`
- `plans/open_project_pr.sh`
- `plans/tests/test_obsidian_context_hook_branch_guard.sh`
- `plans/tests/test_open_project_pr.sh`
- `plans/tests/test_pr_review_gate_hook_scope.sh`

Work:
- Replace repo-local `obsidian/Projects` lookups with the shared resolver.
- Keep context routing advisory when the vault is missing.
- Keep scope, post-rebase, PR wrapper, and raw `gh pr create` gating fail-closed when the vault is missing.

Verify:
- `bash plans/tests/test_obsidian_context_hook_branch_guard.sh`
- `bash plans/tests/test_open_project_pr.sh`
- `bash plans/tests/test_pr_review_gate_hook_scope.sh`

## Task 3: Bootstrap and Migration Helpers

Files:
- `scripts/setup_hooks.sh`
- Optional new helper if needed under `plans/lib/`

Work:
- Create the external vault directory skeleton during hook setup.
- Keep setup idempotent and avoid touching user notes beyond directory creation.

Verify:
- `bash -n scripts/setup_hooks.sh`

## Task 4: Remove Commit-Time Obsidian Enforcement

Files:
- `.githooks/pre-commit`
- `.githooks/post-commit`
- `.claude/hooks/obsidian-precommit-hook.sh`
- `plans/obsidian_commit_guard.sh`
- `plans/tests/test_obsidian_commit_guard.sh`
- `plans/tests/test_obsidian_precommit_hook.sh`
- `plans/workflow_files_allowlist.txt`
- `plans/verify_fork.sh`
- `plans/tests/test_preflight_fixture_profiles.sh`
- `plans/tests/test_workflow_allowlist_coverage.sh`
- `plans/worktree_commit_push.sh`

Work:
- Remove `OBSIDIAN_CHANGE_CLASS`, `OBSIDIAN_REVIEW_FIX`, and `OBSIDIAN_AMEND`.
- Drop `obsidian_only` and `formatting_only` classifications tied only to the commit guard.
- Delete the commit guard and no-op precommit hook, and clean up tests/allowlists.
- Remove obsolete post-commit references to in-repo Obsidian dashboards.

Verify:
- `bash plans/tests/test_workflow_allowlist_coverage.sh`
- `bash plans/tests/test_preflight_fixture_profiles.sh`

## Task 5: Docs and Skill Updates

Files:
- `AGENTS.md`
- `SKILLS/obsidian-workflow.md`
- `SKILLS/commit.md`
- `SKILLS/push-pr.md`
- `SKILLS/merge-cleanup.md`
- Any other skill or command doc still referencing `obsidian/`

Work:
- Update policy text from commit-time note staging to external-vault update expectations at push/PR and end-of-session.
- Replace repo-local `obsidian/` references with `$OBSIDIAN_VAULT_PATH` or “external vault”.

Verify:
- `rg -n "obsidian/|OBSIDIAN_CHANGE_CLASS|OBSIDIAN_REVIEW_FIX|OBSIDIAN_AMEND" AGENTS.md SKILLS .claude .githooks plans scripts`

## Task 6: Repo Cleanup and Final Verification

Files:
- `obsidian/`
- `.gitignore`

Work:
- Delete the tracked `obsidian/` tree from the repo.
- Add `obsidian/` to `.gitignore`.
- Confirm remaining code and tests no longer depend on repo-local notes.

Verify:
- `./plans/workflow_verify.sh`
- `./plans/verify.sh quick`

## Expected Outcome

- Worktrees no longer carry repo-committed Obsidian notes.
- Session routing can continue without a vault, but publish boundaries fail closed.
- Tests stay hermetic by using temp external vault fixtures.
