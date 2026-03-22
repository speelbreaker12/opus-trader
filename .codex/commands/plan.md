---
description: "Use the repo-provided /plan skill when the current repo ships .codex/skills/plan/SKILL.md, .claude/skills/plan/SKILL.md, skills/plan.md, or SKILLS/plan.md"
---

If `.codex/skills/plan/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/plan/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/plan.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/plan.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/plan` is only configured for repositories that provide a `plan` skill.
