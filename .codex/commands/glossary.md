---
description: "Use the repo-provided /glossary skill when the current repo ships .codex/skills/glossary/SKILL.md, .claude/skills/glossary/SKILL.md, skills/glossary.md, or SKILLS/glossary.md"
---

If `.codex/skills/glossary/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/glossary/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/glossary.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/glossary.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/glossary` is only configured for repositories that provide a `glossary` skill.
