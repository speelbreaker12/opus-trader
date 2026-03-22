---
project: "[[Verify Harness Acceleration]]"
date: "2026-03-21"
---

## Commits
- (this commit)

## 0) What shipped
- Feature/behavior: documented the parallel gate wait_rc index alignment invariant in `plans/verify_fork.sh`. Investigated the P1 concern that `PARALLEL_WAIT_NEXT_INDEX` could drift from the gate iteration index when `VERIFY_PARALLEL_JOBS` is smaller than the parallel group size.
- Value (what problem it solves): confirms there is no bug — the FIFO discipline on `PARALLEL_ACTIVE_PIDS` guarantees `WAIT_RCS[i]` always corresponds to `NAMES[i]`. The comment block prevents future contributors from re-investigating the same concern.

## 1) Constraint (ONE)
- How it manifested: PR review flagged a potential P1 index misalignment between gate names and wait return codes in the parallel gate machinery.
- Time/token drain it caused: required careful trace of the FIFO pop order, insertion order, and wait-index increment logic across three functions.
- Workaround I used this session (exploit): traced the logic manually through a 4-gate, 2-job example to prove alignment holds, then documented the invariant.
- Next-agent default behavior (subordinate): read the invariant comment before modifying parallel gate functions.
- Permanent fix proposal (elevate): the comment is the permanent fix — no code change needed.
- Smallest increment: the comment itself.
- Validation (proof it got better): manual trace proves alignment for any `VERIFY_PARALLEL_JOBS >= 1`.

## 2) Best follow-up
- Single best next step: push to origin/verify and let CI confirm.

## 3) Enforceable rules
- When modifying `parallel_wait_oldest`, `start_parallel_gate`, or `finish_parallel_group_or_exit`: preserve the FIFO pop discipline on `PARALLEL_ACTIVE_PIDS` — any reordering breaks the name-to-RC index correspondence.
