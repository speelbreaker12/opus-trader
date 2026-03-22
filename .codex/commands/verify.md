---
description: "Use the repo-provided /verify skill when the current repo ships .codex/skills/verify/SKILL.md, .claude/skills/verify/SKILL.md, skills/verify.md, or SKILLS/verify.md"
---

If `.codex/skills/verify/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/verify/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/verify.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/verify.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/verify` is only configured for repositories that provide a `verify` skill.
