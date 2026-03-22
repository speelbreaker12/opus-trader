---
description: "Use the repo-provided /commit-push-pr skill when the current repo ships .codex/skills/commit-push-pr/SKILL.md, .claude/skills/commit-push-pr/SKILL.md, skills/commit-push-pr.md, or SKILLS/commit-push-pr.md"
---

If `.codex/skills/commit-push-pr/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/commit-push-pr/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/commit-push-pr.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/commit-push-pr.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/commit-push-pr` is only configured for repositories that provide a `commit-push-pr` skill.
