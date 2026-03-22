---
description: "Use the repo-provided /codebase-health skill when the current repo ships .codex/skills/codebase-health/SKILL.md, .claude/skills/codebase-health/SKILL.md, skills/codebase-health.md, or SKILLS/codebase-health.md"
---

If `.codex/skills/codebase-health/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/codebase-health/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/codebase-health.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/codebase-health.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/codebase-health` is only configured for repositories that provide a `codebase-health` skill.
