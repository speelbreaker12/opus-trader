---
description: "Use the repo-provided /toc skill when the current repo ships .codex/skills/toc/SKILL.md, .claude/skills/toc/SKILL.md, skills/toc.md, or SKILLS/toc.md"
---

If `.codex/skills/toc/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/toc/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/toc.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/toc.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/toc` is only configured for repositories that provide a `toc` skill.
