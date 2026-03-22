---
description: "Use the repo-provided /hotfix skill when the current repo ships .codex/skills/hotfix/SKILL.md, .claude/skills/hotfix/SKILL.md, skills/hotfix.md, or SKILLS/hotfix.md"
---

If `.codex/skills/hotfix/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/hotfix/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/hotfix.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/hotfix.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/hotfix` is only configured for repositories that provide a `hotfix` skill.
