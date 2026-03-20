# Commit Skill

Create a clean local commit in the assigned worktree. No push, no PR, no merge.

## Never
- commit on `main` or from bare repo root
- push, open/update PR, merge, or rebase
- include unrelated files
- call `code_review_expert_attest.sh` without actually running code-review-expert

## Fast path (tier 1: docs, obsidian, scripts, formatting)

```
1. Confirm worktree + branch (not main)
2. Stage files: git add <paths>
3. Commit: git commit -m "<area>: <what changed>"
```

That's it. The pre-commit hook handles classification and defers heavy gates to push.

## Full path (tier 2: crates/ — trading system code)

Same three steps, plus the pre-commit hook runs scope guard, SSOT lint, contract checks, and unwrap detection. Expect 30-60 seconds.

## Staging rules
- Stage by explicit path, not `git add -A`
- Verify with `git diff --cached --stat`
- If scope guard rejects: check project note `scope_paths`

## Obsidian tracking
- **Debrief note:** append one log line per commit (hash + what changed). Do not rewrite on every commit.
- **Project page:** update once per session or at PR boundary (`/push-pr`). Not on every commit.
- **First commit in review window:** create debrief, link from project note `## Debriefs`.
- **Follow-up commit:** `OBSIDIAN_REVIEW_FIX=1` skips debrief requirement.
- **Amend:** auto-detected.
- **docs_only / obsidian_only / formatting_only:** obsidian gate skipped at commit (enforced at push).

## Commit message
Format: `<area>: <what changed>` — under 72 chars.

## Result
```
Commit Result
- Folder:
- Branch:
- Commit hash:
- Files included:
- Next step:
```
