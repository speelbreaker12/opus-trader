# Workflow Skills & Hooks Index

How the workflow system fits together. Skills define agent behavior at each boundary. Hooks enforce it mechanically.

## Lifecycle

```
  session start
       │
       ├─ hook: obsidian-context-hook.sh ── inject project context
       │
       ▼
  /obsidian-workflow ─── classify task, route to project + worktree
       │
       ▼
  workspace-policy ──── preflight, lane rules, worktree cap, sync rules
       │
       ▼
  (implement)
       │
       ├─ hook: dangerous-command-blocker.py ── block catastrophic commands
       │
       ▼
  /commit ───────────── stage, review gate, obsidian tracking, local commit
       │
       ├─ hook: obsidian-precommit-hook.sh ── delegate to obsidian_commit_guard.sh
       ├─ hook: pre-commit ──────────────── change-class, scope guard, SSOT, code-review gate
       ├─ hook: post-commit ─────────────── post-commit review reminder
       │
       ▼
  /push-pr ──────────── refresh branch, push, create/update PR
       │
       ├─ hook: pre-push ─── scope guard, frontmatter check, verify cache
       ├─ hook: pre-rebase ── speed bump (confirm before rebase)
       │
       ▼
  /pr-check ─────────── surface comments, resolve conflicts, merge queue
       │
       ├─ hook: pr-review-gate-hook.sh ── scope guard at PR creation
       │
       ▼
  /merge-cleanup ────── merge single PR, sync main, remove worktree, update obsidian
       │
       ▼
  session end
```

## Skills

| Skill | File | Invokable | Purpose |
|-------|------|-----------|---------|
| `/obsidian-workflow` | `SKILLS/obsidian-workflow.md` | yes | Session classification, project routing, worktree assignment |
| `workspace-policy` | `SKILLS/workspace-policy.md` | no | Lane rules, preflight, worktree lifecycle, sync policy, active cap |
| `/commit` | `SKILLS/commit.md` | yes | Stage, code-review gate, obsidian tracking, local commit |
| `/push-pr` | `SKILLS/push-pr.md` | yes | Refresh branch, push, create/update PR |
| `/pr-check` | `SKILLS/pr-check.md` | yes | Review comments, conflict resolution, merge queue (multi-PR) |
| `/merge-cleanup` | `SKILLS/merge-cleanup.md` | yes | Merge single PR, sync main, worktree + branch removal, obsidian update |
| `/git` | `SKILLS/git.md` | yes | Branch discipline, conflict resolution patterns, worktree inventory |
| `/hotfix` | `SKILLS/hotfix.md` | yes | Shared baseline bug — dedicated branch from main |
| `/main-recovery` | `SKILLS/main-recovery.md` | yes | Recover diverged/dirty/stuck main (preserve → reset → replay) |

## Claude Code hooks (`.claude/hooks/`)

| Hook | Trigger | Gate | What it does |
|------|---------|------|--------------|
| `obsidian-context-hook.sh` | UserPromptSubmit | soft | First-message project routing via branch ownership |
| `obsidian-precommit-hook.sh` | PreToolUse (Bash) | disabled | No-op — git pre-commit hook handles obsidian enforcement |
| `post-commit-review-hook.sh` | PreToolUse (Bash) | advisory | Reminds agent to run code-review-expert after commit |
| `pr-review-gate-hook.sh` | PreToolUse (Bash) | hard | Runs scope guard at PR creation |
| `pre-verify-fmt.sh` | PreToolUse (Bash) | soft | Pre-verify formatting check |

## Claude Code scripts (`.claude/scripts/`)

| Script | Trigger | Gate | What it does |
|--------|---------|------|--------------|
| `dangerous-command-blocker.py` | PreToolUse (Bash) | hard | Blocks rm -rf, force-push, reset --hard, push to main |
| `secret-scanner.py` | PreToolUse (Bash) | hard | Blocks commits containing secrets |

## Git hooks (`.githooks/`)

| Hook | Gate | What it does |
|------|------|--------------|
| `pre-commit` | hard | Main guard, change-class tier, obsidian guard (all tiers), scope guard + SSOT + contract + unwrap (Tier 2 only) |
| `pre-push` | hard | Main guard, scope guard (push mode), frontmatter integrity check, code-review-expert attestation, verify cache |
| `pre-rebase` | hard | Main guard, confirmation speed bump |
| `post-commit` | soft | Dashboard sync notification |

## Guard scripts (`plans/`)

| Script | Called by | Purpose |
|--------|----------|---------|
| `obsidian_commit_guard.sh` | pre-commit | Project note + debrief enforcement (change-class aware, amend-aware, review-fix mode) |
| `project_scope_guard.sh` | pre-commit, pre-push, pr-review-gate-hook | Staged/branch files vs scope_paths (commit warn, push/PR hard fail, `--dry-run` mode) |
| `code_review_expert_guard.sh` | pre-push (publish mode) | Attestation marker check (skipped for branches with no significant changes) |
| `code_review_expert_attest.sh` | agent (manual) | Writes attestation marker — only after running code-review-expert |
| `post_rebase_frontmatter_check.sh` | pre-push | Verifies branch/base/scope_paths not clobbered by rebase |
| `write_review_gate_marker.sh` | agent (manual) | One-liner to write/check review attestation |
| `worktree_commit_push.sh` | agent (manual) | CWD-resilient atomic stage+commit+push from worktree path |
| `ssot_lint.sh` | pre-commit | Single source of truth lint |

## Shared libraries (`plans/lib/`)

| File | Used by | Purpose |
|------|---------|---------|
| `obsidian_frontmatter.py` | obsidian-context-hook, project_scope_guard (both blocks) | Single frontmatter parser implementation |

## Change-class tiers

Classified by `pre-commit` based on staged file types, passed via `OBSIDIAN_CHANGE_CLASS` env:

| Class | Obsidian gate | Code-review gate | Examples |
|-------|---------------|-------------------|---------|
| `docs_only` | skip (enforced at push) | skip | `*.md`, `docs/`, `reviews/` |
| `obsidian_only` | skip (enforced at push) | skip | `obsidian/**` |
| `formatting_only` | skip (enforced at push) | skip | whitespace-only diffs |
| `non_critical` | full | full | `plans/*.sh`, `scripts/`, `.githooks/` |
| `critical` | full | full | `crates/`, `python/` |

## Environment variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `OBSIDIAN_REVIEW_FIX=1` | obsidian_commit_guard | Skip debrief if one exists on branch since divergence |
| `OBSIDIAN_AMEND=1` | obsidian_commit_guard | Signal amend (auto-detected from `GIT_REFLOG_ACTION`) |
| `OBSIDIAN_CHANGE_CLASS` | obsidian_commit_guard | Change-class from pre-commit (docs_only/obsidian_only/etc.) |
| `SKIP_CODE_REVIEW_EXPERT_HOOK=1` | code_review_expert_guard | Emergency bypass for code-review attestation |
| `SKIP_CODE_REVIEW_REASON=<reason>` | code_review_expert_guard | Named skip reason (e.g., `fmt_only`) |
| `SKIP_PRE_PUSH_VERIFY=1` | pre-push | Skip verify.sh on push |
| `SCOPE_DRY_RUN=1` | project_scope_guard | Report scope violations without blocking |
