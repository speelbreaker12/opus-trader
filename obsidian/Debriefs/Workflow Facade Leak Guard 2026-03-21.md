---
project: "[[Workflow Facade Leak Guard]]"
date: "2026-03-21"
---

## Commits
- address PR #225 review comments

## 0) What shipped
- Feature/behavior: Addressed 5 unresolved PR #225 review comments covering stderr capture, allowlist deduplication, python3 availability check, ASCII output, and string-literal false-positive documentation.
- Value (what problem it solves): Brings the PR to reviewer-accepted quality by fixing reviewer-identified issues around robustness, maintainability, and correctness.

## 1) Constraint (ONE)
- How it manifested: Duplicated allowlist between bash array and hardcoded awk filter meant adding a new facade required edits in two places.
- Workaround I used this session (exploit): Derived the awk filter dynamically from the bash array using paste and awk split.
- Next-agent default behavior (subordinate): When defining allowlists, always derive secondary uses from the primary definition.
- Permanent fix proposal (elevate): The fix is itself the permanent solution -- single source of truth for the allowlist.
- Validation: Code review of the diff confirms the awk filter now reads from `required_core_facades`.

## 2) Best follow-up
- Single best next step: Get PR #225 approved and merged.

## 3) Enforceable rules
- When a shell script defines an allowlist array, all downstream consumers (awk, grep, etc.) must derive from that array, not duplicate it.
- Test output capture should always include stderr (2>&1) to avoid losing diagnostic information.
- Use ASCII-only characters in script output for portability.
