---
description: "Use the repo-provided /design-interface skill when the current repo ships .codex/skills/design-interface/SKILL.md, .claude/skills/design-interface/SKILL.md, skills/design-interface.md, or SKILLS/design-interface.md"
---

If `.codex/skills/design-interface/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/design-interface/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/design-interface.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/design-interface.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/design-interface` is only configured for repositories that provide a `design-interface` skill.
