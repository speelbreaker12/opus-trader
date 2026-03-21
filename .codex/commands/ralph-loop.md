---
description: "Use the repo-provided /ralph-loop skill when the current repo ships .codex/skills/ralph-loop/SKILL.md, .claude/skills/ralph-loop/SKILL.md, skills/ralph-loop.md, or SKILLS/ralph-loop.md"
---

If `.codex/skills/ralph-loop/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/ralph-loop/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/ralph-loop.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/ralph-loop.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/ralph-loop` is only configured for repositories that provide a `ralph-loop` skill.
