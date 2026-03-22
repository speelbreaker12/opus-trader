---
description: "Use the repo-provided /git skill when the current repo ships .codex/skills/git/SKILL.md, .claude/skills/git/SKILL.md, skills/git.md, or SKILLS/git.md"
---

If `.codex/skills/git/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/git/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/git.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/git.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/git` is only configured for repositories that provide a `git` skill.
