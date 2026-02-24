# Codebase Concerns

**Analysis Date:** 2026-02-23

## Tech Debt

**Large modules requiring refactoring:**
- Issue: Several core modules exceed 800+ lines, increasing cognitive load and maintenance risk
- Files:
  - `crates/soldier_infra/src/store/ledger.rs` (1120 lines)
  - `crates/soldier_core/src/execution/group.rs` (886 lines)
  - `crates/soldier_core/src/risk/pending_exposure.rs` (850 lines)
  - `crates/soldier_infra/src/bootstrap.rs` (712 lines)
  - `crates/soldier_core/src/execution/gate.rs` (693 lines)
- Impact: Higher cognitive load, increased bug risk, harder to test individual concerns
- Fix approach: Break into smaller modules by concern (e.g., state machine + persistence separation in ledger.rs)

**Repository structure drift from single-source-of-truth:**
- Issue: Documented in DRIFT_RISKS.md with multiple outstanding issues
- Files:
  - Missing `IMPLEMENTATION_PLAN.md` stub at root (required by ssot_lint.sh)
  - `docs/bundle_CONTRACT_PHASE1.md` (688 lines, manual drift risk)
  - `docs/PLAN_PHASE1_EXCERPT.md` (excerpt-based, unsynchronized)
  - Old `to-do/CONTRACT_patched_*.md` and `.diff` files (stale)
  - `patches/*.patch` files (already applied, not archived)
- Impact: Documentation divergence, confusing canonical sources, potential incorrect references
- Fix approach: Implement all DRIFT_RISKS.md recommendations (§ Recommended Single-Source-of-Truth Fixes)

**Python test helpers with broad exception handling:**
- Issue: Multiple Python tools catch `Exception` broadly without logging context
- Files:
  - `tools/phase0_meta_test.py` (2 instances of bare `except Exception`)
  - `tools/phase1_compare.py` (bare `except Exception` returns silent defaults)
  - `plans/validators/validate_external_manifest.py` (5 instances with traceback logging)
- Impact: Hard to debug test failures, silent failures mask real problems
- Fix approach: Replace with specific exception types, add structured logging for all failure paths

---

## Known Bugs

**WAL write queue backpressure not fully observable:**
- Symptoms: System can hit WAL queue capacity but visibility is limited to `wal_queue_enqueue_failures` counter
- Files: `crates/soldier_infra/src/store/ledger.rs` (queue-based append model)
- Trigger: High concurrency with slow disk I/O; queue fills faster than async writer drains
- Workaround: Monitor `/status` endpoint `wal_queue_depth` and `wal_queue_capacity` with alerts; consider pre-allocating queue larger than peak concurrency

**State transition validation in TlsState may diverge from core TLSM:**
- Symptoms: WAL allows illegal transitions that core TLSM forbids
- Files: `crates/soldier_infra/src/store/ledger.rs:67-80` (is_valid_successor); `crates/soldier_core/src/execution/tlsm.rs` (core state machine)
- Trigger: If core TLSM adds new transitions without updating WAL validator, ledger will accept states core rejects
- Workaround: Use state machine tests that exercise both ledger and core paths
- Notes: Comment at line 67 says "keep in sync" but no automation enforces this

**Bootstrap expect() statements lack error context:**
- Symptoms: Panics on filesystem issues provide minimal debugging info
- Files: `crates/soldier_infra/src/bootstrap.rs:309, 342, 374, 395, 402, 446, 494, 515, 522, 547, 567, 589, 617, 632, 663, 685, 695` (17 expect() calls)
- Trigger: Disk full, permission denied, mount unmounted
- Workaround: Grep for "bootstrap should" in logs to find which expect failed
- Notes: Function is test-only, so low production risk, but poor DX for developers

---

## Security Considerations

**forbid(unsafe_code) properly enforced:**
- Risk: Memory corruption via unsafe Rust blocks
- Files: Both crate roots have `#![forbid(unsafe_code)]`
  - `crates/soldier_infra/src/lib.rs:1`
  - `crates/soldier_core/src/lib.rs:1`
- Current mitigation: Compile-time ban on all unsafe blocks
- Recommendations: Continue enforcing; audit any future crate additions

**Configuration validation with deny_unknown_fields:**
- Risk: Typos or deprecated config fields silently ignored, leading to unsafe defaults
- Files: `crates/soldier_infra/src/config.rs:31` (StorageConfig uses `#[serde(deny_unknown_fields)]`)
- Current mitigation: Serde validation rejects unknown fields
- Recommendations: Audit all config structs; ensure fail-closed defaults for all safety-critical parameters (already done in ConfigParam enum)

**Trade ID registry idempotency without secrets:**
- Risk: If trade ID registry is world-readable, attacker can learn order IDs
- Files: `crates/soldier_infra/src/store/trade_id_registry.rs` (file-based registry)
- Current mitigation: Stored in local data_dir with OS file permissions
- Recommendations: Ensure data_dir permissions are 0700; audit at deployment; consider encrypted storage for future phases

---

## Performance Bottlenecks

**Atomic global counters for all metrics:**
- Problem: 50+ static AtomicU64 counters (group lock timeout, persist fail, pending exposure reject, etc.)
- Files: Scattered across `crates/soldier_core/src/execution/` and `crates/soldier_infra/src/` modules
- Cause: Each counter uses Relaxed ordering (no lock), but per-metric emit still calls string formatting
- Improvement path: Aggregate metrics into fewer atomic fields; batch metric line emission (§2.5 performance gates)

**Python tools with large file scans:**
- Problem: phase0_meta_test.py (885 lines), phase1_compare.py (2300 lines) scan artifact directories on every run
- Files: `tools/phase0_meta_test.py`, `tools/phase1_compare.py`, `plans/validate_external_manifest.py` (851 lines)
- Cause: No caching; regex scanning full files
- Improvement path: Add incremental artifact cache; use file mtime as invalidation signal

**Floating-point epsilon comparisons in exposure calculation:**
- Problem: `pending_exposure.rs` uses hardcoded FP_EPSILON = 1e-12 for snap-to-zero
- Files: `crates/soldier_core/src/risk/pending_exposure.rs:45`
- Cause: Fixed epsilon may not match market notional scales (e.g., micro-cap vs mega-cap instruments)
- Improvement path: Make epsilon configurable per instrument or tier; audit FP comparison logic

---

## Fragile Areas

**Trade Lifecycle State Machine (TLSM) state explosion:**
- Files: `crates/soldier_infra/src/store/ledger.rs` (TlsState enum: 8 states), `crates/soldier_core/src/execution/tlsm.rs` (core logic)
- Why fragile:
  - 8 states × multiple transition rules = 40+ combinations to test
  - Manual sync between ledger validator and core TLSM
  - TlsState::Rejected exists only in WAL, not core (comment notes this)
- Safe modification:
  - Add table-driven tests for all valid state transitions
  - Generate validator from core TLSM (code generation or macro)
  - Add integration tests that exercise both ledger replay and core dispatch
- Test coverage: Core has `test_tlsm.rs` but ledger state validator lacks dedicated tests

**Group atomic execution with lock timeout:**
- Files: `crates/soldier_core/src/execution/group.rs` (886 lines, 6 states)
- Why fragile:
  - Lock acquisition bounded by `group_lock_max_wait_ms` (configurable)
  - Timeout forces ReduceOnly, but timeout is global (not per-group or market condition aware)
  - FirstFail atomicity invariant (first leg failure seeds MixedFailed, cannot be overwritten) is enforced by code comment only
- Safe modification:
  - Add explicit FirstFail invariant assertion in transition logic
  - Make lock timeout adaptive based on system load
  - Add tests for timeout → ReduceOnly escalation
- Test coverage: `test_group_*.rs` exists but timeout scenario lacks explicit test

**Intent classification default to OPEN (fail-closed):**
- Files: `crates/soldier_core/src/execution/intent_assembly.rs` (277 lines)
- Why fragile:
  - Intent classification (OPEN vs CLOSE) determines downstream risk gates
  - Uncertain/missing reduce_only field defaults to OPEN (most restrictive)
  - If reduce_only field is null/missing in schema, behavior is implicit
- Safe modification:
  - Add explicit schema validation before classification
  - Add unit test: null reduce_only → OPEN (with assertion name "fail_closed_unknown_intent_type")
  - Document contract requirement in code comment
- Test coverage: Basic tests exist but no explicit fail-closed test for unknown intent types

**WAL writer async queue with bounded capacity:**
- Files: `crates/soldier_infra/src/store/ledger.rs` (queue-based append)
- Why fragile:
  - Bounded in-memory queue per CONTRACT.md §2.4.1
  - If queue fills, writes are rejected and counter incremented
  - No automatic backpressure to hot loop (dispatch loop must check wal_queue_enqueue_failures)
  - Slow disk I/O or background writer thread stall can fill queue quickly
- Safe modification:
  - Add pre-startup smoke test that verifies disk I/O latency
  - Add monitoring alert on wal_queue_enqueue_failures > 0
  - Add test: fill queue intentionally and verify reject behavior
- Test coverage: `test_async_wal_writer.rs` exists but queue-full scenario may not be exercised

**Reconciliation epsilon hardcoded in config:**
- Files: `crates/soldier_infra/src/config.rs:78-80` (PositionReconcileEpsilon)
- Why fragile:
  - Epsilon is `max(config_value, instrument.min_amount)` per CONTRACT.md §2.2.4
  - If instrument metadata is stale or missing, min_amount is unknown
  - Hard-coded default could be too large for small-notional instruments, too small for large
- Safe modification:
  - Add per-instrument epsilon validation at bootstrap
  - Add test matrix: [tiny_notional, normal_notional, huge_notional] × [tight_epsilon, loose_epsilon]
  - Document why max() is necessary
- Test coverage: `test_config_defaults.rs` covers defaults but not per-instrument interaction

---

## Scaling Limits

**WAL ledger file size without compaction (Phase 1):**
- Current capacity: Configurable via StorageConfig.wal_capacity (minimum 10 records)
- Limit: Phase 1 has NO compaction; file grows indefinitely with append-only writes
- Scaling path: Implement compaction for Phase 2; snapshots + delta format; or move to log rotation

**Trade ID registry without eviction:**
- Current capacity: Configurable via StorageConfig.trade_id_capacity (minimum 10)
- Limit: No eviction policy; fills up, then rejects new trades
- Scaling path: Implement time-based eviction (e.g., drop trades >24h old); or move to database backend

**Python artifact scanning (meta_test tools):**
- Current capacity: Scans entire artifact/ directory on each run
- Limit: 200+ nested test cases × multiple JSON deserialization passes = slow CI feedback
- Scaling path: Incremental caching; only scan modified artifacts

**Atomic counter memory footprint:**
- Current capacity: 50+ AtomicU64 counters in crates/soldier_core/src/
- Limit: Each counter is 8 bytes; negligible, but metric emission creates temporary String allocations
- Scaling path: Aggregate into fewer counters; use histogram bucket for latency metrics

---

## Dependencies at Risk

**Rust edition = 2024 (potentially unstable):**
- Risk: Cargo.toml specifies `edition = "2024"`, which may not be stable Rust
- Impact: Build failures if 2024 edition is removed or changed
- Migration plan: Verify with `rustc --version` what edition is available; fallback to 2021 if 2024 is nightly-only

**Missing dev-dependency pinning in soldier_infra:**
- Risk: soldier_infra has NO dev-dependencies; test-helpers feature in soldier_core used only by other crates
- Impact: Tests are hard to run in isolation; no cargo test --test <name> convenience
- Migration plan: Add serde_json, tracing-test to soldier_infra dev-dependencies for local testing

**serde deny_unknown_fields audit incomplete:**
- Risk: Only StorageConfig verified; other config structs may accept unknown fields silently
- Impact: Typos in config files (e.g., "gate_confg" instead of "gate_config") go undetected
- Migration plan: Audit all config struct definitions; add cfg macro to enforce deny_unknown_fields at compile time

**Tracing library log output unconfigured:**
- Risk: tracing crate wired but no subscriber configured at startup; logs may be lost
- Impact: Debug logs silently discarded in production
- Migration plan: Add RUST_LOG environment variable parsing; configure tracing-appender for file output

---

## Missing Critical Features

**No compaction or archival strategy for durable storage:**
- Problem: WAL ledger grows unbounded; no snapshots or rotation
- Blocks: Long-running processes will exhaust disk; multi-month deployments impossible
- PRD mapping: Phase 2 feature; currently tracked as known limit

**No metric export format (Prometheus, statsd, etc.):**
- Problem: Metrics emitted as unstructured text lines; no standard format for scraping
- Blocks: Integration with monitoring systems
- PRD mapping: Phase 2+ feature

**No explicit intent versioning or schema migration:**
- Problem: If intent JSON schema changes, old replays may fail
- Blocks: Deploying schema changes safely in production
- PRD mapping: Not tracked; would be Phase 2

---

## Test Coverage Gaps

**Fail-closed behavior for missing configuration:**
- What's not tested: Config parameter missing + no default → behavior (should reject gracefully)
- Files: `crates/soldier_infra/src/config.rs` (ConfigParam enum has defaults, but code may not use them)
- Risk: If default is skipped, system could crash or use unsafe value
- Priority: HIGH (contract AT-930 requires fail-closed config)

**WAL write queue exhaustion scenarios:**
- What's not tested: Hot loop behavior when wal_queue_enqueue_failures > 0 (should throttle or block)
- Files: `crates/soldier_infra/src/store/ledger.rs` (queue-based append)
- Risk: Unknown how system behaves under sustained disk backpressure
- Priority: HIGH (production reliability)

**State machine recovery after crashed state writes:**
- What's not tested: Restart with partial/corrupted state files (should be fail-closed)
- Files: `crates/soldier_infra/tests/test_ledger_replay.rs` (partial; test_crash_mid_intent exists)
- Risk: Corrupted ledger could cause double-fill or missed close
- Priority: MEDIUM (covered by test_crash_mid_intent, but additional scenarios needed)

**Intent assembly with null/missing fields:**
- What's not tested: Schema validation for intent JSON with missing required fields
- Files: `crates/soldier_core/src/execution/intent_assembly.rs` (277 lines)
- Risk: Null-pointer or silent default behavior
- Priority: MEDIUM (schema should enforce, but validation tests needed)

**Group timeout escalation to ReduceOnly:**
- What's not tested: Lock acquisition timeout → ReduceOnly transition (explicit test missing)
- Files: `crates/soldier_core/src/execution/group.rs` (group_lock_timeout_total counter incremented)
- Risk: Timeout behavior untested; actual behavior in production unknown
- Priority: MEDIUM (safety-critical but tested implicitly)

**Inventory skew gate edge cases:**
- What's not tested: k-value boundary conditions, tick penalty saturation, rescue spread activation
- Files: `crates/soldier_core/src/execution/inventory_skew.rs` (248 lines)
- Risk: Off-by-one errors in skew calculation
- Priority: MEDIUM (P&L impact if skew wrong)

---

## Untracked Technical Risks

**Hidden test state pollution:**
- Issue: Multiple `.state.json.lock` files in `artifacts/phase0/runtime_state_tests/` (215 lock files)
- Files: `artifacts/phase0/runtime_state_tests/.phase0_*.state.json.lock`
- Impact: Tests may be reading stale or partially-written state
- Action: Verify lock files are cleaned up between test runs; add CI step to ensure clean state

**Edition mismatch warning in Cargo.toml:**
- Issue: `edition = "2024"` may not exist in stable Rust
- Files: `crates/soldier_core/Cargo.toml:4`, `crates/soldier_infra/Cargo.toml:4`
- Impact: Build failures on standard toolchains
- Action: Verify with CI logs; change to `edition = "2021"` if needed

---

*Concerns audit: 2026-02-23*
