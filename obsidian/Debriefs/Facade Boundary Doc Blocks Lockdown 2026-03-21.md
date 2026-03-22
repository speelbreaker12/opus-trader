---
project: "[[Facade Boundary Doc Blocks Lockdown]]"
date: "2026-03-21"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Moved `infra_bootstrapped()` behind the `soldier_infra` facade, added a structure proof that `src/lib.rs` stays a pure facade root, and normalized the remaining routed facade-root doc blocks.
- Value (what problem it solves): Closes the last direct crate-root facade leak in `soldier_infra`, aligns the routed facade roots to the repo’s current doc-block standard, and leaves the boundary mechanically checked instead of review-only.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): the first quick-verify run failed because `plans/lint_soldier_infra_facade.sh` correctly saw `infra_bootstrapped` in `api.rs` but the checked allowlist did not include it; the workflow branch handoff had routed only source/doc cleanup so the allowlist was initially outside scope; after fixing that, `./plans/verify.sh quick` still failed on `plans/tests/test_pr_review_gate_hook.sh`, and the same test failed unchanged on clean `main`.
- Time/token drain it caused: one red-green cycle was spent chasing the live facade lint instead of just the Rust move, and the final repo quick gate could not go fully green because of a baseline workflow failure unrelated to this diff.
- Workaround I used this session (exploit): updated the active Obsidian owner note before touching the allowlist, fixed the allowlist in the same atomic lane, and validated the baseline workflow failure separately on clean `main` so the branch-local result is defensible.
- Next-agent default behavior (subordinate): treat the facade/doc-block hotfix itself as implemented and verified at the Rust/facade level; do not reopen the code change unless the unrelated `test_pr_review_gate_hook.sh` baseline is being worked in its own workflow lane.
- Permanent fix proposal (elevate): repair the `pr_review_gate_hook` workflow expectation on `main`, then rerun `./plans/verify.sh quick` (and full verify when needed) on this branch or its rebased successor.
- Smallest increment: land this hotfix commit, then create or resume a dedicated workflow lane for `plans/tests/test_pr_review_gate_hook.sh`.
- Validation (proof it got better): `cargo test -p soldier_infra --test test_soldier_infra_facade_public --locked`; `cargo test -p soldier_infra --lib --locked`; `cargo test -p soldier_core --lib --locked`; `cargo fmt --all -- --check`; `bash plans/lint_soldier_infra_facade.sh`; `./plans/verify.sh quick` now reaches the unrelated baseline failure only; `bash plans/tests/test_pr_review_gate_hook.sh` fails the same way on clean `main`.

## 2) Best follow-up
- Single best next step: commit this hotfix and leave the remaining quick-verify failure to a separate workflow owner because it reproduces on clean `main`.
- 1-3 upgrades worth considering:
  - add a dedicated workflow owner note for the `pr_review_gate_hook` regression and repair it on fresh `main`;
  - after that baseline fix lands, rerun `./plans/verify.sh quick` on this branch and then decide whether a full verify is warranted before merge.

## 3) Enforceable rules
- if a new public facade symbol is added, update its checked allowlist in the same commit / trigger: facade lint adds a new export / prevents: quick verify failure after otherwise-correct Rust changes / enforce: `plans/lint_*_facade.sh` + owner `scope_paths`
- keep `soldier_infra/src/lib.rs` as a pure facade root / trigger: new infra public helper needed / prevents: crate-root escape hatches bypassing `api.rs` / enforce: `soldier_infra_root_stays_a_pure_facade` test
- separate unrelated workflow-gate repairs from source-facade hotfixes / trigger: repo quick verify fails in untouched workflow tests / prevents: mixed-purpose branches and owner-scope churn / enforce: Obsidian owner notes + fresh branch/worktree routing
