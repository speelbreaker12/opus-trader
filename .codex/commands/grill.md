---
description: "Use the repo-provided /grill skill when the current repo ships .codex/skills/grill/SKILL.md, .claude/skills/grill/SKILL.md, skills/grill.md, or SKILLS/grill.md"
---

If `.codex/skills/grill/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/grill/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/grill.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/grill.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/grill` is only configured for repositories that provide a `grill` skill.
