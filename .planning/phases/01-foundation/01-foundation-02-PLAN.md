---
phase: 01-foundation
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - crates/soldier_infra/src/wal.rs
  - crates/soldier_core/src/idempotency/hash.rs
autonomous: true
requirements:
  - REQ-2
must_haves:
  truths:
    - "WAL ledger prevents duplicate orders on restart"
    - "Determinism is guaranteed for hashes, labels, and quantizations"
  artifacts:
    - path: "crates/soldier_infra/src/wal.rs"
      provides: "Durable WAL storage"
    - path: "crates/soldier_core/src/idempotency/hash.rs"
      provides: "Determinism implementations"
  key_links:
    - from: "crates/soldier_infra/src/wal.rs"
      to: "crates/soldier_core/src/idempotency/hash.rs"
      via: "Idempotency checks during replay"
---

<objective>
Implement WAL ledger protections against duplicates and finalize determinism testing.

Purpose: Ensure crash/restart doesn't cause double-execution and system behavior is deterministic.
Output: Crash-safe WAL and deterministic hashing logic.
</objective>

<context>
@.planning/ROADMAP.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Harden WAL Durability</name>
  <files>crates/soldier_infra/src/wal.rs</files>
  <action>Enhance wal.rs to ensure the ledger safely prevents duplicate intents across crash, restart, and reconnect events. Add explicit wiring so that WAL replay invokes hash determinism checks (from hash.rs) for idempotency validation. Implement fsync barriers if missing.</action>
  <verify>
    <automated>cargo test --package soldier_infra test_dispatch_durability</automated>
  </verify>
  <done>WAL tests prove duplicates are prevented on restart.</done>
</task>

<task type="auto">
  <name>Task 2: Finalize Determinism Tests</name>
  <files>crates/soldier_core/src/idempotency/hash.rs</files>
  <action>Review and enforce determinism across hashing, quantization, and label matching. Ensure there is no non-deterministic state that could break idempotency.</action>
  <verify>
    <automated>cargo test --package soldier_core test_idempotency</automated>
  </verify>
  <done>Determinism tests pass for hashing, labels, and quantization.</done>
</task>

</tasks>

<verification>
Ensure infrastructure WAL tests and core idempotency tests pass.
</verification>

<success_criteria>
System handles crashes gracefully and is fully deterministic.
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-foundation-02-SUMMARY.md`
</output>