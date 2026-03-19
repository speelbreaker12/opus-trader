#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): DISABLED.
#
# This hook previously duplicated the obsidian commit guard logic, but it runs
# from the bare repo root — wrong staging area, wrong script version, can't see
# worktree env vars. The git pre-commit hook (.githooks/pre-commit) already runs
# obsidian_commit_guard.sh in the correct worktree context.
#
# Kept as a no-op so the settings.json reference doesn't break.

exit 0
