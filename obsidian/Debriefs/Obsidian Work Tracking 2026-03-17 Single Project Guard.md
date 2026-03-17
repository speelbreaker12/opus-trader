---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — single-project staged Obsidian guard batch

## 0) What shipped
- Feature/behavior: Tightened the shared Obsidian commit guard so a commit may stage exactly one project note, and every staged Obsidian debrief must declare that same project in frontmatter.
- Value (what problem it solves): Prevents accidental carryover of unrelated staged Obsidian files into the wrong commit, which is exactly how the earlier Execution Facade tracking commit picked up an Autoresearch debrief.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): An unrelated Obsidian debrief could stay staged across sessions; the existing guard still passed if one correct project note and one correct linked debrief were present; commit scope errors were only caught after the commit landed.
- Time/token drain it caused: Follow-up inspection, extra cleanup decisions, and lower trust in the Obsidian tracking workflow whenever the worktree was already dirty.
- Workaround I used this session (exploit): Added single-project validation to the shared guard and pinned it with fixture tests for mismatched staged debriefs and multi-project note staging.
- Next-agent default behavior (subordinate): Before commit, assume staged Obsidian files must belong to one project only and let the shared guard fail closed if the index is mixed.
- Permanent fix proposal (elevate): Keep all Obsidian commit-scope enforcement in the shared guard so both repo git hooks and Claude-side hooks share the same single-project rule.
- Smallest increment: Add mismatch detection using debrief frontmatter and reject commits that stage more than one project note.
- Validation (proof it got better): The shared guard test now fails on mismatched staged debriefs and multi-project note staging, and the Claude-side precommit hook test proves the same mismatch blocks tool-time commits too.

## 2) Best follow-up
- Single best next step: Add an optional guard for the project note `## Commits` section if you want the hook to require commit-history maintenance, not just project/debrief presence and scope.
- 1-3 upgrades worth considering:
- Validate that the staged project note's `## Commits` section exists and is non-empty before commit.
- Add a helper command that unstages unrelated Obsidian files automatically after showing the blocking list.
- Extend the debrief validation to require a matching `project: [[...]]` plus at least one commit entry that is either `pending` or a short hash.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Stage Obsidian project/debrief files for exactly one project per commit.
- Every staged Obsidian debrief must declare the same project as the staged project note in frontmatter.
- Shared Obsidian scope checks belong in `plans/obsidian_commit_guard.sh`, not in tool-specific wrapper hooks.
