---
description: "Use the repo-provided /slice-execute skill when the current repo ships .codex/skills/slice-execute/SKILL.md, .claude/skills/slice-execute/SKILL.md, skills/slice-execute.md, or SKILLS/slice-execute.md"
---

If `.codex/skills/slice-execute/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/slice-execute/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/slice-execute.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/slice-execute.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/slice-execute` is only configured for repositories that provide a `slice-execute` skill.
