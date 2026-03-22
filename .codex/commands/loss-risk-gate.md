---
description: "Use the repo-provided /loss-risk-gate skill when the current repo ships .codex/skills/loss-risk-gate/SKILL.md, .claude/skills/loss-risk-gate/SKILL.md, skills/loss-risk-gate.md, or SKILLS/loss-risk-gate.md"
---

If `.codex/skills/loss-risk-gate/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `.claude/skills/loss-risk-gate/SKILL.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `skills/loss-risk-gate.md` exists in the current repository, read it and follow it as the instruction source for this command.

Otherwise, if `SKILLS/loss-risk-gate.md` exists in the current repository, read it and follow it as the instruction source for this command.

If none of those files exist, tell the user that `/loss-risk-gate` is only configured for repositories that provide a `loss-risk-gate` skill.
