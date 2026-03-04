---
phase: 01-foundation
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - crates/soldier_core/src/execution/dispatch_map.rs
  - crates/soldier_core/src/execution/preflight.rs
autonomous: true
requirements:
  - REQ-1
must_haves:
  truths:
    - "All exchange dispatch goes through the single chokepoint"
    - "Illegal orders are rejected before calling exchange APIs"
  artifacts:
    - path: "crates/soldier_core/src/execution/dispatch_map.rs"
      provides: "Central dispatch chokepoint"
    - path: "crates/soldier_core/src/execution/preflight.rs"
      provides: "Pre-dispatch validation"
  key_links:
    - from: "crates/soldier_core/src/execution/preflight.rs"
      to: "crates/soldier_core/src/execution/dispatch_map.rs"
      via: "validation before dispatch"
---

<objective>
Implement and verify the central dispatch chokepoint and pre-flight rejections.

Purpose: Ensure no orders bypass risk checks and illegal orders never hit the exchange.
Output: Working dispatch map and preflight rejection logic.
</objective>

<context>
@.planning/ROADMAP.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Enforce Dispatch Chokepoint</name>
  <files>crates/soldier_core/src/execution/dispatch_map.rs</files>
  <action>Ensure all dispatch routes explicitly go through the central chokepoint defined in dispatch_map.rs. Add explicit wiring so that dispatch_map calls preflight validation before routing. Add test coverage if missing to enforce this architectural constraint.</action>
  <verify>
    <automated>cargo test --package soldier_core test_dispatch_map</automated>
  </verify>
  <done>All execution goes through a single tested chokepoint.</done>
</task>

<task type="auto">
  <name>Task 2: Implement Preflight Rejections</name>
  <files>crates/soldier_core/src/execution/preflight.rs</files>
  <action>Add logic in preflight.rs to catch and reject illegal orders before they are sent to the exchange APIs. Update validation to enforce strict formatting and valid combinations.</action>
  <verify>
    <automated>cargo test --package soldier_core test_preflight_invalid</automated>
  </verify>
  <done>Preflight tests pass showing illegal orders fail before dispatch.</done>
</task>

</tasks>

<verification>
Ensure cargo tests for dispatch and preflight pass without regressions.
</verification>

<success_criteria>
All dispatch is centralized and illegal orders are caught early.
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-foundation-01-SUMMARY.md`
</output>