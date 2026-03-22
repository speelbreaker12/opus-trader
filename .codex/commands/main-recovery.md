---
description: "Use the repo-provided /main-recovery skill when the current repo ships .codex/skills/main-recovery/SKILL.md, .claude/skills/main-recovery/SKILL.md, skills/main-recovery.md, or SKILLS/main-recovery.md"
---

If `.codex/skills/main-recovery/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/main-recovery/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/main-recovery.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/main-recovery.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/main-recovery` is only configured for repositories that provide a `main-recovery` skill.
