---
project: "[[chairman-synthesis]]"
date: "2026-03-21"
---

## Commits
- pending — 2026-03-21 — plans: make chairman failures explicit

## 0) What shipped
- Feature/behavior: Two fail-explicit fixes for chairman synthesis pipeline.
- P1: `parallel_review.sh` now exits non-zero when `--chairman` was requested but the run directory is missing (was silently exiting 0 with a WARN).
- P2: `chairman_synthesis.sh` redirects claude CLI stderr to `$OUTDIR/chairman_stderr.log` instead of `/dev/null`, preserving diagnostic output for debugging.
- Value: Eliminates false-green results and preserves stderr diagnostics.

## 1) Constraint (ONE)
- How it manifested: PR #221 review found that missing run directory silently succeeded, giving false confidence.
- Workaround I used this session: Set `chairman_rc=1` in the missing-directory branch so the existing exit-code check (exit 4) fires.
- Permanent fix proposal (elevate): This is the permanent fix.
- Validation: `chairman_rc` is already checked at the exit section (line 365) and causes `exit 4` on non-zero.
