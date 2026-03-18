# Codebase Concerns Map

**Analysis Date:** 2026-03-04  
**Focus:** concerns/risk  
**Scope:** `/Users/admin/Desktop/opus-trader`

## Priority Risk Queue (Planning-First)

| Priority | Concern | Why it matters | Evidence |
|---|---|---|---|
| P0 | WAL gate still has bypass-prone migration path | Dispatch safety depends on recorded-before-dispatch; shimmed precomputed booleans can drift from real append behavior | `crates/soldier_core/src/execution/build_order_intent.rs` (`PrecomputedWalGate` TODO), `crates/soldier_core/src/execution/pipeline.rs` (migration TODO), `crates/soldier_core/src/execution/open_runtime.rs` |
| P0 | Production order assembly path appears not fully wired | Critical sizing/dispatch consistency code is marked as not yet production-wired; behavior may differ between tests and live flow | `crates/soldier_core/src/execution/open_runtime.rs` (`build_open_intent_with_assembly` TODO), `crates/soldier_core/src/venue/types.rs`, `crates/soldier_core/src/execution/order_size.rs`, `crates/soldier_core/src/venue/cache.rs` |
| P1 | Workflow gate in CI is explicitly disabled | One of the intended PR enforcement gates is not running in CI, reducing prevention of process regressions | `.github/workflows/ci.yml` (`prd-story-gate` job has `if: false && ...`) |
| P1 | Security boundary on status endpoint is basic and leak-prone | Auth check and error handling are functional but can expose internals and lack hardened comparison | `dashboard/convex/http.ts` |
| P1 | Local verification tolerates dirty trees by default | Creates false confidence risk where local pass does not represent clean-checkout behavior | `plans/verify_fork.sh` (dirty tree warns only), `plans/progress.txt` (repeated dirty-tree notes) |
| P2 | High script/gate surface area increases maintenance fragility | Many coupled shell gates increase chance of accidental breakage and slower feedback loops | `plans/verify_fork.sh`, `plans/preflight.sh`, `plans/verify_gate_contract_check.sh`, `plans/workflow_contract_gate.sh` |

## Technical Debt

1. Transitional execution wiring remains in-place instead of a single canonical path.
- Evidence: `crates/soldier_core/src/execution/build_order_intent.rs`, `crates/soldier_core/src/execution/pipeline.rs`, `crates/soldier_core/src/execution/open_runtime.rs`.
- Risk: behavior drift across call paths and harder reasoning during incidents.

2. Test-only annotations remain on logic that should be core runtime behavior.
- Evidence: `crates/soldier_core/src/venue/types.rs`, `crates/soldier_core/src/venue/cache.rs`, `crates/soldier_core/src/execution/order_size.rs`.
- Risk: production path may not exercise contract-critical transformations.

3. Risk book internals rely on interior mutability with panic-based invariant assumptions.
- Evidence: `crates/soldier_core/src/risk/pending_exposure.rs` (`RefCell`, multiple `expect(...)` in runtime methods).
- Risk: rare state drift turns into runtime panic instead of recoverable rejection.

## Likely Bug Candidates

1. `CancelOnly` assumptions can panic on future path expansion.
- Evidence: `crates/soldier_core/src/execution/gate.rs` uses `unreachable!("handled above")` in live gate logic.
- Risk: enum flow changes can convert logic mistakes into process crash.

2. Reservation settle mismatch paths can leak accounting signal and only log.
- Evidence: `crates/soldier_core/src/execution/open_runtime.rs` settle failure logs TLSM/book desync; `crates/soldier_core/src/risk/pending_exposure.rs` contains mismatch and reverse-map error branches.
- Risk: hard-to-debug latent exposure accounting discrepancies.

3. Caller-side downgrade semantics for dispatch mismatch are partly documented in tests.
- Evidence: `crates/soldier_core/src/execution/dispatch_map_tests.rs` contains TODO for production wiring assertion.
- Risk: production caller may regress without direct guard.

## Security Concerns

1. Bearer token compare is plain string equality.
- Evidence: `dashboard/convex/http.ts` (`provided !== expected`).
- Risk: lacks constant-time compare hardening.

2. Error payloads include raw exception messages.
- Evidence: `dashboard/convex/http.ts` returns `${message}` in 422/500 branches.
- Risk: internal details may leak to clients/log consumers.

3. Static analysis coverage is uneven by language.
- Evidence: `.github/workflows/codeql.yml` scans `python` only.
- Risk: Rust/TypeScript security smells rely on other gates and human review.

## Performance Risks

1. Durable WAL path can become throughput bottleneck under fsync or writer pressure.
- Evidence: `crates/soldier_infra/src/store/ledger.rs` (bounded channel + barrier timeout), `crates/soldier_infra/src/wal.rs` (append waits barrier timing).
- Risk: queue saturation produces write failures/fail-closed rejects during bursts.

2. Pending exposure map uses cloned string keys in hot paths.
- Evidence: `crates/soldier_core/src/risk/pending_exposure.rs` TODO(PX-3).
- Risk: avoidable allocation pressure in high-frequency reserve/settle loops.

3. Spool retention creates dynamic `NOT IN (...)` deletion sets.
- Evidence: `dashboard/publisher/spool.py` (`apply_retention`, dynamic placeholder generation from `keep_ids`).
- Risk: large outbox history can increase SQL/CPU/memory churn.

## Fragile Workflow Areas

1. Critical process gate is present but off in CI.
- Evidence: `.github/workflows/ci.yml` (`prd-story-gate`).

2. Dirty-tree behavior is warning-only despite policy emphasis on clean verification.
- Evidence: `plans/verify_fork.sh`, policy text in `AGENTS.md`, many dirty-tree notes in `plans/progress.txt`.

3. Pattern scanning is diff-based, not repository-global.
- Evidence: `plans/pattern_guard.sh` uses `git diff "$BASE_REF"...HEAD`.
- Risk: pre-existing or non-diff surfaces can bypass guard.

4. Workflow contract gate depends on token/text presence heuristics.
- Evidence: `plans/verify_gate_contract_check.sh`, `plans/workflow_contract_gate.sh`.
- Risk: semantic drift can pass if token checks still match.

## Missing Guardrails

1. No enforced gate proving production path uses `build_open_intent_with_assembly`.
- Evidence: `crates/soldier_core/src/execution/open_runtime.rs` TODO; no obvious verify gate asserting this wiring.

2. No explicit guard failing when test-only TODO markers remain in core dispatch path.
- Evidence: TODO markers in `crates/soldier_core/src/venue/types.rs`, `crates/soldier_core/src/venue/cache.rs`, `crates/soldier_core/src/execution/order_size.rs`.

3. No mandatory constant-time secret compare helper for API auth.
- Evidence: `dashboard/convex/http.ts`.

4. No CI parity gate requiring PRD story-gate job to be enabled.
- Evidence: `.github/workflows/ci.yml`.

## Suggested Planning Buckets

- **Bucket A (Safety First):** remove precomputed WAL shim path and enforce real gate adapter usage everywhere (`crates/soldier_core/src/execution/*`, `crates/soldier_infra/src/wal.rs`).
- **Bucket B (Production Wiring):** complete assembly-path wiring and add contract test proving runtime use (`crates/soldier_core/src/execution/open_runtime.rs`, `crates/soldier_core/src/execution/dispatch_map_tests.rs`).
- **Bucket C (Workflow Integrity):** re-enable CI PRD story gate and add self-check that it cannot be disabled silently (`.github/workflows/ci.yml`, `plans/verify_gate_contract_check.sh`).
- **Bucket D (Security Hardening):** constant-time auth compare + response message sanitization (`dashboard/convex/http.ts`).

*Update this map after each safety/workflow merge that changes risk posture.*
