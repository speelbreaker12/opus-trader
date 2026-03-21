---
description: "Use the repo-provided /pre-commit skill when the current repo ships .codex/skills/pre-commit/SKILL.md, .claude/skills/pre-commit/SKILL.md, skills/pre-commit.md, or SKILLS/pre-commit.md"
---

If `.codex/skills/pre-commit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/pre-commit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/pre-commit.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/pre-commit.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/pre-commit` is only configured for repositories that provide a `pre-commit` skill.
