---
description: "Use the repo-provided /contract-review skill when the current repo ships .codex/skills/contract-review/SKILL.md, .claude/skills/contract-review/SKILL.md, skills/contract-review.md, or SKILLS/contract-review.md"
---

If `.codex/skills/contract-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/contract-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/contract-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/contract-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/contract-review` is only configured for repositories that provide a `contract-review` skill.
