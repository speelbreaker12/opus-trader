---
description: "Use the repo-provided /plan-review skill when the current repo ships .codex/skills/plan-review/SKILL.md, .claude/skills/plan-review/SKILL.md, skills/plan-review.md, or SKILLS/plan-review.md"
---

If `.codex/skills/plan-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/plan-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/plan-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/plan-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/plan-review` is only configured for repositories that provide a `plan-review` skill.
