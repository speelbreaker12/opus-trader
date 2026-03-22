---
description: "Use the repo-provided /pr-check skill when the current repo ships .codex/skills/pr-check/SKILL.md, .claude/skills/pr-check/SKILL.md, skills/pr-check.md, or SKILLS/pr-check.md"
---

If `.codex/skills/pr-check/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/pr-check/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/pr-check.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/pr-check.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/pr-check` is only configured for repositories that provide a `pr-check` skill.
