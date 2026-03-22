---
description: "Use the repo-provided /validator-audit skill when the current repo ships .codex/skills/validator-audit/SKILL.md, .claude/skills/validator-audit/SKILL.md, skills/validator-audit.md, or SKILLS/validator-audit.md"
---

If `.codex/skills/validator-audit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/validator-audit/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/validator-audit.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/validator-audit.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/validator-audit` is only configured for repositories that provide a `validator-audit` skill.
