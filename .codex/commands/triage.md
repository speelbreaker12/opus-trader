---
description: "Use the repo-provided /triage skill when the current repo ships .codex/skills/triage/SKILL.md, .claude/skills/triage/SKILL.md, skills/triage.md, or SKILLS/triage.md"
---

If `.codex/skills/triage/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/triage/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/triage.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/triage.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/triage` is only configured for repositories that provide a `triage` skill.
