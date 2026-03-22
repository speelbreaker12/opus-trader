---
description: "Use the repo-provided /external-review-generic skill when the current repo ships .codex/skills/external-review-generic/SKILL.md, .claude/skills/external-review-generic/SKILL.md, skills/external-review-generic.md, or SKILLS/external-review-generic.md"
---

If `.codex/skills/external-review-generic/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/external-review-generic/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/external-review-generic.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/external-review-generic.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/external-review-generic` is only configured for repositories that provide a `external-review-generic` skill.
