---
description: "Use the repo-provided /premortem skill when the current repo ships .codex/skills/premortem/SKILL.md, .claude/skills/premortem/SKILL.md, skills/premortem.md, or SKILLS/premortem.md"
---

If `.codex/skills/premortem/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/premortem/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/premortem.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/premortem.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/premortem` is only configured for repositories that provide a `premortem` skill.
