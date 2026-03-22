---
description: "Use the repo-provided /obsidian-workflow skill when the current repo ships .codex/skills/obsidian-workflow/SKILL.md, .claude/skills/obsidian-workflow/SKILL.md, skills/obsidian-workflow.md, or SKILLS/obsidian-workflow.md"
---

If `.codex/skills/obsidian-workflow/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/obsidian-workflow/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/obsidian-workflow.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/obsidian-workflow.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/obsidian-workflow` is only configured for repositories that provide a `obsidian-workflow` skill.
