---
description: "Use the repo-provided /contract-audit-full skill when the current repo ships .codex/skills/contract-audit-full/SKILL.md, .claude/skills/contract-audit-full/SKILL.md, skills/contract-audit-full.md, or SKILLS/contract-audit-full.md"
---

If `.codex/skills/contract-audit-full/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/contract-audit-full/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/contract-audit-full.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/contract-audit-full.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/contract-audit-full` is only configured for repositories that provide a `contract-audit-full` skill.
