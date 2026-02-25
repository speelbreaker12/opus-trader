# Codebase Concerns

**Analysis Date:** 2026-02-25

## Tech Debt

**Execution path still marked as test-only assumptions:**
- Issue: `crates/soldier_core/src/venue/types.rs` (`derive_instrument_kind`), `crates/soldier_core/src/venue/cache.rs` (`opens_blocked`), and `crates/soldier_core/src/execution/order_size.rs` (`build_order_size`) still carry comments indicating they are only called from unit tests.
- Why: The comments likely outlived refactors and may no longer match actual callsites in production flow.
- Impact: Misleading assumptions can hide missing production validation and reduce confidence when modifying sizing/cache/order intent behavior.
- Fix approach: Verify true callsites, add production-level tests, and either remove the comments or split test-only and production logic explicitly.

**WAL gate migration is partially implemented:**
- Issue: `crates/soldier_core/src/execution/open_runtime.rs` uses a precomputed-WAL path with `TODO` in `assemble_order`, while `crates/soldier_core/src/execution/build_order_intent.rs` and `crates/soldier_core/src/execution/pipeline.rs` document migration work for gate outcome converters.
- Why: Legacy and new paths coexist during transition.
- Impact: Increases cognitive load and risks divergence between durable WAL behavior and intent construction logic.
- Fix approach: Complete migration to the new gate pipeline, remove transition shims, and assert behavior parity with targeted regression tests.

## Known Bugs

**Not detected.**

## Security Considerations

**API auth handling is not robustly hardened:**
- Risk: `dashboard/convex/http.ts` performs direct bearer-token style checks via environment-provided secret in handler path, with no timing-hardening or structured authorization abstraction.
- Current mitigation: Straightforward equality checks and explicit failure paths in handler.
- Recommendations: Use a constant-time comparison helper and centralized auth middleware; add rotation/rotation-failure monitoring and rotate secrets periodically.

**Potential SQL edge-case in retention cleanup path:**
- Risk: `dashboard/publisher/spool.py` builds a retention query with variable-length placeholders from `keep_ids` for `DELETE` filtering.
- Current mitigation: Standard parameterized placeholder construction is used.
- Recommendations: Add explicit guard + deterministic test for the empty-list case and add bound checks around statement shape generation.

## Performance Bottlenecks

**Open-address and instrument map hot path allocation pressure:**
- Problem: `crates/soldier_core/src/risk/pending_exposure.rs` notes `TODO(PX-3)` about interning `instrument_id` to reduce allocation pressure.
- Measurement: Not detected (no benchmarks provided).
- Cause: Hash lookups and map churn around instrument identifiers can add avoidable overhead in high-frequency path.
- Improvement path: Implement interning in that hot path and add a benchmark/profiler baseline before/after.

**Not detected additional bottlenecks with quantified measurements.**

## Fragile Areas

**Panic-on-variant assumptions in liquidity gate logic:**
- Why fragile: `crates/soldier_core/src/execution/gate.rs` uses `unreachable!` for `CancelOnly` branches and relies on variant assumptions across variants.
- Common failures: Unexpected variants or future expansion can crash process paths that were assumed impossible.
- Safe modification: Replace hard assumptions with explicit fallbacks or clear guarded error returns.
- Test coverage: Minimal if path is difficult to execute in normal tests.

**Invariant-heavy panic paths in production:**
- Why fragile: `crates/soldier_core/src/risk/pending_exposure.rs` has multiple `debug_assert` plus `expect` on production state transitions (instrument/position lookups).
- Common failures: State drift or malformed runtime updates can produce panics instead of recoverable errors.
- Safe modification: Convert to typed state-machine states or structured validation errors before unwrap/expect.
- Test coverage: Missing tests for recovery/error paths and malformed-state resilience.

**Migration shim complexity in order-intent assembly:**
- Why fragile: `crates/soldier_core/src/execution/build_order_intent.rs` and `crates/soldier_core/src/execution/pipeline.rs` keep shim logic and TODO-driven deprecations.
- Common failures: Gate outcome semantics can diverge between legacy and migrated paths.
- Safe modification: Delete legacy branch after full parity checks and keep one canonical path.
- Test coverage: Add golden tests comparing both outputs until parity is formally proven and remove transition code.

## Scaling Limits

**Not detected.**

## Dependencies at Risk

**Not detected.**

## Missing Critical Features

**Formalize WAL persistence contract for order submission:**
- Problem: `crates/soldier_core/src/execution/open_runtime.rs` TODO indicates production wiring remains pending for order submission entrypoints.
- Current workaround: Existing migration/deprecated code paths are used.
- Blocks: Full confidence in durable, production-consistent WAL-backed order routing.
- Implementation complexity: Medium; requires finishing gate/intent wiring and adding integration assertions.

**Not detected additional feature gaps.**

## Test Coverage Gaps

**Potentially stale "unit tests only" assumptions unverified in production paths:**
- What's not tested: Real production callpaths for `derive_instrument_kind`, `opens_blocked`, `build_order_size`, and related gate outcome conversions.
- Risk: Changes may pass unit tests while breaking live execution logic.
- Priority: High
- Difficulty to test: Requires end-to-end fixtures for venue/open-runtime/execution pipelines.

**WAL migration and panic paths lack dedicated regression coverage:**
- What's not tested: Behavior parity between legacy and migrated gate handling, plus malformed-state/edge-case paths in `crates/soldier_core/src/risk/pending_exposure.rs`.
- Risk: Undetected correctness regressions and runtime panics under rare states.
- Priority: High
- Difficulty to test: Requires synthetic malformed-state generators and property-style checks.

*Concerns audit: 2026-02-25*
*Update as issues are fixed or new ones discovered*
