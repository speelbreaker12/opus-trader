---
project: "[[chairman-synthesis]]"
date: "2026-03-19"
---

## Commits
- pending — 2026-03-19 — plans: harden chairman synthesis script

## 0) What shipped
- Feature/behavior: Robustness improvements to `chairman_synthesis.sh` — consolidated temp file cleanup, early model ID resolution, tee exit code check, broader citation regex, richer sidecar JSON fields (description, suggested_fix), and post-generation JSON validation.
- Value (what problem it solves): Previous version had duplicated model ID resolution, fragile trap handlers that overwrote each other, no detection of transcript capture failure, citation regex that missed extensionless files like `Makefile:42`, and sidecar JSON lacked finding descriptions. "Kimi-only" section name was vendor-specific.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Multiple `trap` statements overwrote each other, leaving stale temp files; tee failure was silently ignored so truncated transcripts could become artifacts; sidecar JSON had no downstream validation and lacked description/fix fields needed by consumers.
- Time/token drain it caused: Debugging chairman artifacts that were silently truncated or missing expected fields.
- Workaround I used this session (exploit): Refactored to CLEANUP_FILES array with single trap; added tee exit code check; expanded sidecar extractor; added json.tool validation gate.
- Next-agent default behavior (subordinate): Use `add_cleanup` for any new temp files instead of rewriting the trap line.
- Permanent fix proposal (elevate): Add a fixture-based test that runs dry-run mode and validates the sidecar schema.
- Smallest increment: The single-file change as committed.
- Validation (proof it got better): Manual code review. No automated tests for this script exist yet.

## 2) Best follow-up
- Single best next step: Run a real chairman synthesis (dry-run or live) to confirm end-to-end correctness of the sidecar output with the new fields.
- 1-3 upgrades worth considering:
  - Add a dry-run smoke test that validates sidecar schema against expected keys
  - Consider extracting the Python sidecar parser into a standalone script for testability

## 3) Enforceable rules
- Always use `add_cleanup` to register temp files; never overwrite the trap directly.
- The sidecar JSON validation gate must remain — malformed sidecar is a hard error.
