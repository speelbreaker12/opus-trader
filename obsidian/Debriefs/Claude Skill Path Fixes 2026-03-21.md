---
project: "[[Claude Skill Path Fixes]]"
date: "2026-03-21"
type: debrief
---

## Commits
- pending

## Log
- `pending` — recovered the two `.claude/skills/*` path fixes onto an isolated branch and switched both wrappers to repo-root-resolved `SKILLS/` paths.

## Handoff
- Branch: `recover/claude-skill-path-fixes-20260321`
- Worktree: `/Users/admin/Desktop/opus-trader/Desktop/wt_claude_skill_path_fixes`
- PR:
- Stop point: review, targeted verification, and commit of the isolated two-file recovery slice
- Next step: publish these two path fixes if you want them shared beyond local recovery state
- Constraint: none
- Rule: skill wrapper file loads must resolve from `git rev-parse --show-toplevel`, not the caller's CWD
