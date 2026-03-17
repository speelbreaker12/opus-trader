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

## 2026-03-17
- Fixed 4 Copilot review findings: generic error message for MANIFEST_REQUIRED_COMBO_MISSING, added missing gemini to MANIFEST_UNEXPECTED_TOOL, corrected outdated model-omission comment, POSIX-portable grep pattern in tests.
