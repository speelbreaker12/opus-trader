---
description: "Use the repo-provided /devils-advocate skill when the current repo ships .codex/skills/devils-advocate/SKILL.md, .claude/skills/devils-advocate/SKILL.md, skills/devils-advocate.md, or SKILLS/devils-advocate.md"
---

If `.codex/skills/devils-advocate/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/devils-advocate/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/devils-advocate.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/devils-advocate.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/devils-advocate` is only configured for repositories that provide a `devils-advocate` skill.
