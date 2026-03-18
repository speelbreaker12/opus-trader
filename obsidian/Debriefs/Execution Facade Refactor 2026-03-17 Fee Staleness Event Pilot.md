---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## 0) What shipped
- Feature/behavior: Converted `risk/fees.rs` to a crate-private `evaluate_fee_staleness_with_events(...)` path with `FeeEvent` and a parity-preserving production wrapper.
- Value (what problem it solves): Gives the refactor a first true graybox leaf seam so tests can prove fee logic separately from global counters and traced metric lines.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The existing fee evaluator mixed decision logic with global observability writes; the only way to assert hard-stale behavior was through process-lifetime counters and shared metric buffers; repo quick verify was unavailable as final proof because `docs/contract_kernel.json` drifted outside this slice.
- Time/token drain it caused: Required a stricter red-green loop, extra metric-harness checks, and a separate explanation for why repo verify could not be used as the final artifact.
- Workaround I used this session (exploit): Split the evaluator behind a crate-private event sink, kept `bump_fee_staleness_hard_stale()` unchanged, and proved parity with a dedicated wrapper contract test.
- Next-agent default behavior (subordinate): Convert the next leaf with the same `*_with_events` plus `Production*Events` pattern and always pair a graybox logic test with an adapter parity test.
- Permanent fix proposal (elevate): Standardize typed event seams across risk and execution leaves so logic tests stop depending on global telemetry state while wrappers preserve current metric contracts.
- Smallest increment: Apply the same split to the next smallest leaf that has one clear side effect and one public wrapper.
- Validation (proof it got better): `fee_graybox_hard_stale_emits_event_without_global_side_effects` and `fee_wrapper_preserves_hard_stale_metric_contract` both pass, and the existing fee staleness and rejection-counter suites stay green.

## 2) Best follow-up
- Single best next step: Convert the next smallest leaf gate to the same `*_with_events` seam and keep the production adapter metric-exact.
- 1-3 upgrades worth considering:
- Move a second single-side-effect leaf first: choose one routine with a single reject metric and one public entrypoint. | Increment: add crate-private event enum plus one graybox and one wrapper test. | Validation: targeted leaf tests no longer touch global telemetry on the graybox path.
- Extract a tiny local pattern note for leaf eventification. | Increment: document the `EventSink` + `Production*Events` + parity-test template in project notes or workflow docs. | Validation: the next refactor follows the same shape without redesign churn.
- Revisit repo verify blockers separately from leaf refactors. | Increment: regenerate `docs/contract_kernel.json` in a dedicated contract-sync slice. | Validation: `./plans/verify.sh quick` reaches the Rust gates again without unrelated contract-kernel failure.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- rule: Keep typed leaf events crate-private and preserve the public wrapper until parity tests exist.
  trigger: When refactoring a risk or execution leaf from direct metrics into event emission.
  prevents: Public facade churn and accidental contract drift before the new seam is proven.
  enforce: `AGENTS.md` Execution Facade Refactor project workflow and review notes.
- rule: Every `*_with_events` leaf split must add one graybox test and one adapter metric-parity test.
  trigger: When a leaf currently writes counters or metric lines directly.
  prevents: Silent regressions where the internal seam loses observability or the graybox path still mutates global state.
  enforce: `crates/soldier_core/src/*` test modules and code review checklist.
- rule: If repo verify fails for unrelated artifact drift, record the exact blocker in the project log instead of forcing a dirty override.
  trigger: When `./plans/verify.sh quick` or `full` stops on a non-slice artifact mismatch.
  prevents: False completion claims and accidental workflow bypass on unrelated repo state.
  enforce: `obsidian/Projects/*.md` session log entries and final verification summary.
