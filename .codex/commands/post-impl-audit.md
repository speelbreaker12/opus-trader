---
description: "Use the repo-provided /post-impl-audit skill when the current repo ships .codex/skills/post-impl-audit/SKILL.md, .claude/skills/post-impl-audit/SKILL.md, skills/post-impl-audit.md, or SKILLS/post-impl-audit.md"
---

If `.codex/skills/post-impl-audit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/post-impl-audit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/post-impl-audit.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/post-impl-audit.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/post-impl-audit` is only configured for repositories that provide a `post-impl-audit` skill.
