---
description: "Use the repo-provided /reconcil skill when the current repo ships .codex/skills/reconcil/SKILL.md, .claude/skills/reconcil/SKILL.md, skills/reconcil.md, or SKILLS/reconcil.md"
---

If `.codex/skills/reconcil/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/reconcil/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/reconcil.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/reconcil.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/reconcil` is only configured for repositories that provide a `reconcil` skill.
