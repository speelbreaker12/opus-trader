---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## 0) What shipped
- Feature/behavior: Fixed 4 findings in PR #205 facade lint scripts — restored parser safety guards (nested-brace, nested-module, wildcard rejection), removed wrong routing-boundary exclusion, resolved smoke/gate-test fixture conflict.
- Value (what problem it solves): Facade lint scripts can now catch complex re-export violations instead of silently misparsing them. Fixture profile test no longer fails.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The simplified regex parser silently produced garbage symbol names for nested use trees. The base_gates.rs exclusion was placed in the routing-boundary check instead of a pub-item check. Facade lint tests were double-listed in smoke AND parallel_gate_tests.
- Time/token drain it caused: Required reading all 3 lint scripts, 3 test files, preflight.sh, verify_fork.sh, and test_preflight_fixture_profiles.sh to trace the conflicts.
- Workaround I used this session (exploit): Added cheap pre-parse guards (4 lines each) instead of restoring the full 200-line recursive-descent parser.
- Next-agent default behavior (subordinate): When simplifying parsers, check that all rejection paths from the old parser are preserved or have equivalent guards.
- Permanent fix proposal (elevate): Factor the pub-use parser into a shared Python module imported by all facade lint scripts — single source of truth.
- Smallest increment: The guards added in this commit.
- Validation (proof it got better): All 6 affected test suites pass (execution, risk, venue, infra facade lints + preflight fixture profiles + workflow allowlist coverage).

## 2) Best follow-up
- Single best next step: Factor shared facade lint Python logic into `plans/lib/facade_lint_parser.py`.
- 1-3 upgrades worth considering:
  - Add a compile-time assertion linking OPEN_GATE_ORDER to the GateStep enum
  - Consider making base_gates.rs/intent_assembly.rs items `pub(crate)` instead of `pub`

## 3) Enforceable rules
- When replacing a parser/validator with a simpler version, enumerate every rejection path from the old version and verify the new version rejects the same inputs (or add explicit guards).
- Test arrays in fixture profile tests must be disjoint — never add a test to both smoke and parallel_gate_tests.
