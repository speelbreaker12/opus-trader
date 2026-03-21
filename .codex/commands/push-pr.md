---
description: "Use the repo-provided /push-pr skill when the current repo ships .codex/skills/push-pr/SKILL.md, .claude/skills/push-pr/SKILL.md, skills/push-pr.md, or SKILLS/push-pr.md"
---

Use the `/push-pr` skill from `SKILLS/push-pr.md` to refresh the branch, push, and create or update a PR.

If `.codex/skills/push-pr/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/push-pr/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/push-pr.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/push-pr.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/push-pr` is only configured for repositories that provide a `push-pr` skill.
