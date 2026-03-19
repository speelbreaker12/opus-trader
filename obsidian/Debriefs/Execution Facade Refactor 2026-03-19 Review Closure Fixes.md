---
project: "[[Execution Facade Refactor]]"
date: "2026-03-19"
status: complete
---

## Commits
- `pending` — 2026-03-19 — close remaining execution facade review items.

## 0) What shipped
- Feature/behavior: Closed the remaining verified review findings on PR 216 by restoring pricer seam proof, fail-closing invalid fee input, and narrowing liquidity/net-edge graybox events to semantic-only payloads.
- Value (what problem it solves): The PR can now truthfully claim its Upgrade 2A evidence, avoid zero-fee edge distortion on invalid fee input, and satisfy the repo float-policy concern without broad Decimal churn.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Review findings were partly doc-claim drift rather than runtime bugs; a test-only assertion landed in the wrong liquidity test and broke the broad lib sweep; the project note had stale `pending` hashes and stale branch metadata while the active branch had already moved to `project/execution-facade-refactor-v2`.
- Time/token drain it caused: One full lib rerun failed for a non-production reason, and the tracking files required reconciliation before the commit could satisfy repo workflow rules.
- Workaround I used this session (exploit): Narrowed the event enums instead of threading Decimal through telemetry, fixed the misplaced assertion directly, and backfilled the commit hashes already visible in `git log` before adding the new batch.
- Next-agent default behavior (subordinate): When a review item is really about evidence or telemetry shape, preserve the production metric contract at the wrapper boundary and keep graybox events semantic-only unless the contract explicitly requires numeric payloads.
- Permanent fix proposal (elevate): Add a lightweight lint or review check that blocks new `f32`/`f64` fields in event enums under `soldier_core` and another check that flags project-note `pending` entries older than the current HEAD.
- Smallest increment: Add a repo grep gate for `enum .*Event` blocks containing `f32`/`f64`, and a project-note checker that matches `pending` entries against the last few commits on the tracked branch.
- Validation (proof it got better): `cargo test -p soldier_core --lib --locked`, `cargo test -p soldier_core --test test_fee_staleness --locked`, and `cargo fmt --all -- --check` all passed after the patch set.

## 2) Best follow-up
- Single best next step: Finish the remaining Upgrade 2B graybox/chokepoint rollout so the checklist header can move from overall FAIL back to overall PASS without qualification.
- 1-3 upgrades worth considering:
  1. Add a repo guard against float payloads in core event enums. | Increment: a deterministic grep-based verify check for `f32`/`f64` in `Event` enums under `crates/soldier_core/src`. | Validation: the guard fails on a seeded float payload and passes on the current tree.
  2. Make fail-closed fee fallback configurable from the owning policy/config layer instead of only the Rust default. | Increment: wire `fee_rate_fail_closed` through the config bootstrap path. | Validation: an integration test can set a non-default fallback and observe it in `evaluate_fee_staleness`.
  3. Add a checklist consistency test for header vs row state. | Increment: a small doc test or script that rejects `Status: PASS` when any row remains `FAIL`. | Validation: the previous stale header would fail deterministically.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- rule: Keep graybox event payloads semantic-only unless the contract explicitly consumes the numeric fields.
  trigger: Adding or refactoring `*Event` enums in `soldier_core`.
  prevents: Reintroducing float-policy violations or duplicating business data into test-only telemetry seams.
  enforce: `plans/verify_fork.sh` grep gate plus review checklist note.
- rule: Backfill project-note `pending` commit hashes before adding a new pending batch when the hash is already visible in branch history.
  trigger: Updating `obsidian/Projects/*.md` during a follow-on session on an active branch.
  prevents: Project tracking drift that forces extra reconciliation work at commit time.
  enforce: Obsidian pre-commit hook or a small project-note lint.
- rule: After editing tests to relocate assertions, rerun the broad target that contains the surrounding legacy tests, not just the new graybox case.
  trigger: Any test-only refactor in shared execution gate test modules.
  prevents: Shipping a passing targeted test with a broken unrelated neighbor.
  enforce: review checklist plus local verification discipline.
