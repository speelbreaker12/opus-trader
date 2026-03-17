---
status: in_progress
priority: medium
branch: codex/sonnet-switch-main-pr
pr:
started: 2026-03-16
---

# Sonnet Switch Review Lane

## 2026-03-16
- Switched the default Claude review lane from Opus to Sonnet 4.6 across workflow scripts, validators, prompts, and regression tests.
- Rebased the change onto `origin/main` in `codex/sonnet-switch-main-pr` to keep the eventual PR diff scoped to the Sonnet migration.
