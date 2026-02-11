# Phase 1 Acceptance — Foundation Hardening

Canonical checklist source: `docs/PHASE1_CHECKLIST_BLOCK.md`.
If this document and the canonical checklist differ, the canonical checklist wins.

## Purpose

Phase 1 exists to prove mechanical correctness of intent construction and dispatch gating before advanced runtime policy controls.

This phase does not prove strategy quality.
It proves that the execution core is deterministic, fail-closed, and restart-safe.

## What Phase 1 Must Prove

By Phase 1 completion, it must be mechanically impossible to:
- bypass the dispatch chokepoint,
- create duplicate dispatches across restart/reconnect,
- create OPEN risk when foundational safety inputs fail,
- leak persistent side effects on rejected intents,
- continue trading when critical config required for safety is missing.

## Required Artifacts (minimum)

- `docs/dispatch_chokepoint.md`
- `docs/intent_gate_invariants.md`
- `docs/critical_config_keys.md`
- `evidence/phase1/README.md`
- `evidence/phase1/ci_links.md`
- `evidence/phase1/restart_loop/restart_100_cycles.log`
- `evidence/phase1/determinism/intent_hashes.txt`
- `evidence/phase1/no_side_effects/rejection_cases.md`
- `evidence/phase1/traceability/sample_rejection_log.txt`
- `evidence/phase1/config_fail_closed/missing_keys_matrix.json`
- `evidence/phase1/crash_mid_intent/auto_test_passed.txt` or `evidence/phase1/crash_mid_intent/drill.md`

## Required Gate Set (P1-A .. P1-G)

- P1-A: chokepoint no-bypass enforcement
- P1-B: determinism snapshot (same inputs => same hash/bytes)
- P1-C: rejected intent has no persistent side effects
- P1-D: `intent_id` / `run_id` propagation to logs/metrics
- P1-E: gate ordering invariants enforced
- P1-F: missing critical config fails closed with deterministic reasons
- P1-G: crash-mid-intent proof (AUTO preferred)

See exact test names and unblock conditions in `docs/PHASE1_CHECKLIST_BLOCK.md`.

## Owner Sign-Off Criteria

Owner must answer YES to all checklist sign-off questions with links into `evidence/phase1/`.
Any uncertain answer ("I think so") is a fail.

## Explicit Non-Goals

Phase 1 must NOT be expanded to include:
- full `/status` schema completion,
- PolicyGuard/TradingMode precedence rollout,
- full replay governance/certification loop,
- dashboard/UI work.

Those are later-phase deliverables.

## Final Rule

If Phase 1 is weakened or treated as partial, later safety claims are invalid.
