---
project: "[[Contract Phase2 Accepted Patch Batch]]"
date: "2026-03-20"
---

## Commits
- `17404bca` — contract: apply accepted hardened phase2 patch batch

## 0) What shipped
- Feature/behavior: Applied the accepted LG, EG, TMC, and EC contract deltas from the hardened Phase 2 autoresearch review batch, renumbered the placeholder ATs to `AT-1283` and `AT-1284`, and refreshed the derived contract/autoresearch artifacts.
- Value (what problem it solves): Moves reviewed contract fixes into `specs/CONTRACT.md` on a contract-scoped branch without widening PR `#224`, while keeping the kernel/context/fixture stack aligned to the edited contract.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The accepted contract deltas lived only as rendered review patches on the autoresearch branch; two proposals still carried placeholder AT ids; that branch's open PR and Obsidian scope did not permit `specs/CONTRACT.md` edits.
- Time/token drain it caused: Each follow-up had to rediscover scope boundaries, AT collisions, and ledger requirements before any contract edit could be made safely.
- Workaround I used this session (exploit): Cut a stacked contract-scoped branch and project note, then applied only the accepted LG/EG/TMC/EC deltas there with permanent AT ids and a matching ledger row.
- Next-agent default behavior (subordinate): Treat accepted contract patch application as its own contract-scoped branch whenever the source review branch owns a narrower autoresearch-only scope.
- Permanent fix proposal (elevate): Teach the autoresearch review flow to emit a ready-to-apply contract batch with reserved AT ids and branch-routing metadata when proposals are accepted.
- Smallest increment: Keep the accepted review artifacts, contract edits, kernel/context refresh, and Obsidian contract note linked on one stacked branch.
- Validation (proof it got better): `python3 scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --check-at --strict --include-bare-section-refs`, `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`, `./plans/check_contract_change_ledger.sh`, and `git diff --check` all passed. `./plans/verify.sh quick` run `20260320_171755` completed but failed outside this slice in `wf_test_review_command_wrappers`, which expected `Use the Skill tool with skill name "review-stack"` in `.claude/commands/review-stack.md`.

## 2) Best follow-up
- Single best next step: Commit this contract-scoped batch, then fix or route the unrelated `wf_test_review_command_wrappers` failure on a workflow-scoped branch before using quick/full as merge evidence.
- 1-3 upgrades worth considering:
  - Reserve permanent AT ids during review rendering so accepted patch files never ship placeholders.
  - Add a helper that promotes accepted contract review packages into a dedicated contract worktree automatically.
  - Emit the contract ledger row draft directly from the accepted-only render step.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Accepted contract deltas from an autoresearch review branch must land on a contract-scoped branch if the source branch or Obsidian note does not own `specs/CONTRACT.md`.
- Accepted patch files must not be applied with placeholder AT ids; renumber them before touching `specs/CONTRACT.md`.
- Any `specs/CONTRACT.md` edit on a diverged branch must append exactly one new `CONTRACT_CHANGE_LEDGER` row in the same patch batch.
