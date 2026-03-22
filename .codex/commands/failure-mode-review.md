---
description: "Use the repo-provided /failure-mode-review skill when the current repo ships .codex/skills/failure-mode-review/SKILL.md, .claude/skills/failure-mode-review/SKILL.md, skills/failure-mode-review.md, or SKILLS/failure-mode-review.md"
---

If `.codex/skills/failure-mode-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/failure-mode-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/failure-mode-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/failure-mode-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/failure-mode-review` is only configured for repositories that provide a `failure-mode-review` skill.
