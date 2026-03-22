---
description: "Use the repo-provided /pr-review skill when the current repo ships .codex/skills/pr-review/SKILL.md, .claude/skills/pr-review/SKILL.md, skills/pr-review.md, or SKILLS/pr-review.md"
---

If `.codex/skills/pr-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/pr-review/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/pr-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/pr-review.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/pr-review` is only configured for repositories that provide a `pr-review` skill.
