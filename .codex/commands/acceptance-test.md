---
description: "Use the repo-provided /acceptance-test skill when the current repo ships .codex/skills/acceptance-test/SKILL.md, .claude/skills/acceptance-test/SKILL.md, skills/acceptance-test.md, or SKILLS/acceptance-test.md"
---

If `.codex/skills/acceptance-test/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/acceptance-test/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/acceptance-test.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/acceptance-test.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/acceptance-test` is only configured for repositories that provide a `acceptance-test` skill.
