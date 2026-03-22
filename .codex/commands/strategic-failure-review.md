---
description: "Use the repo-provided /strategic-failure-review skill when the current repo ships .codex/skills/strategic-failure-review/SKILL.md, .claude/skills/strategic-failure-review/SKILL.md, skills/strategic-failure-review.md, or SKILLS/strategic-failure-review.md"
---

If `.codex/skills/strategic-failure-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/strategic-failure-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/strategic-failure-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/strategic-failure-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/strategic-failure-review` is only configured for repositories that provide a `strategic-failure-review` skill.
