---
description: "Use the repo-provided /merge-cleanup skill when the current repo ships .codex/skills/merge-cleanup/SKILL.md, .claude/skills/merge-cleanup/SKILL.md, skills/merge-cleanup.md, or SKILLS/merge-cleanup.md"
---

If `.codex/skills/merge-cleanup/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/merge-cleanup/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/merge-cleanup.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/merge-cleanup.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/merge-cleanup` is only configured for repositories that provide a `merge-cleanup` skill.
