---
description: "Use the repo-provided /commit skill when the current repo ships .codex/skills/commit/SKILL.md, .claude/skills/commit/SKILL.md, skills/commit.md, or SKILLS/commit.md"
---

Use the `/commit` skill from `SKILLS/commit.md` to create a clean local commit in the current worktree.

If `.codex/skills/commit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/commit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/commit.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/commit.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/commit` is only configured for repositories that provide a `commit` skill.
