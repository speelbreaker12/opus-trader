# Premortem Cross-Review: Agent A
**Reviewing**: S0-002, S0-003, S0-004, S0-005
**Date**: 2026-02-23

---

## S0-002 Review
**Story**: P0-C Keys & Secrets Baseline

### Strengths
- Excellent identification of the "probe provenance" problem (FM-1): a hand-crafted `key_scope_probe.json` is the single most dangerous failure mode for this story, and the premortem correctly flags it as the top risk.
- The traceability vacuum (no formal AT-XXX) is called out repeatedly and honestly. The premortem does not paper over this gap.
- The wrong-implementation gate (section 5) is thorough for a documentation story. The `scopes: ["all"]` example is a sharp, realistic wrong implementation that would pass a naive field-presence check.
- Decision 1 (Option A: strict least-privilege definition) is well-justified and correctly infers from the test name `test_api_keys_transfer_privilege_rejected_runtime` that the stricter interpretation is intended.

### Gaps Found
1. **Assumption 2 is insufficiently alarming.** The premortem says "A hand-crafted JSON file can claim any scopes; it proves nothing about actual key configuration" but then accepts Decision 2 choosing Option B (static JSON validation, not live API). This creates an internal contradiction: if the probe's provenance is unverifiable (FM-1), and the tests only validate the JSON artifact (Decision 2, Option B), then the entire story's security claim rests on trusting a single JSON file that anyone can forge. The premortem identifies this tension but resolves it with a shrug ("accepted gap") rather than escalating it.

2. **Missing assumption: key scope APIs differ across exchanges.** The premortem assumes `withdraw_enabled` is a universal field exposed by all exchange APIs. If the exchange returns scopes in a different schema (e.g., a bitmask, or nested permission objects), the probe JSON format may not faithfully represent the actual permissions. This is not addressed.

3. **Decision 2 (Option B) contradicts the story's purpose.** The contract says "least-privilege proof" -- not "least-privilege assertion." Option B produces a JSON artifact that asserts least-privilege without proving it against a live API. The premortem predicts this is the implementation, but does not sufficiently flag that this makes P0-C fundamentally "doc-only" (exactly what P0-F is trying to prevent in a different context). If the tests only parse a static JSON file, then `test_api_keys_are_least_privilege_runtime` is misnamed -- the `_runtime` suffix implies live execution, but the premortem predicts it is a fixture test.

### Missing Failure Modes
1. **Key rotation invalidates the probe.** The probe is a point-in-time snapshot. If the key is rotated (as the rotation plan recommends), the new key may have different scopes. The probe becomes stale evidence. No re-validation mechanism is proposed.

2. **Sub-account or IP whitelist scopes not captured.** A key could be least-privilege on scopes but unrestricted on IP whitelist, allowing access from any host. The probe schema does not capture this, and the premortem's Assumption 3 kills this concern ("accepted scope") without adequately justifying why IP restrictions are out of scope for a security baseline.

3. **The `operator` field is self-reported.** Nothing prevents the probe from claiming `operator: "human"` when it was machine-generated. This is a provenance problem at the meta level.

### Missing Wrong Implementations
1. **Test that only checks `withdraw_enabled` but ignores `scopes` array.** The probe could have `withdraw_enabled: false` but `scopes: ["withdraw"]` -- contradictory fields. A wrong implementation checks only one field.

2. **Rotation plan says "rotate quarterly" but no mechanism to detect stale probes.** The key_scope_probe.json could be 6 months old and still pass all checks because `timestamp_utc` is not validated against a freshness window.

### Stoplight Assessment
YELLOW is appropriate. The debt register is well-structured with owners and targets. However, the "Probe provenance not machine-verifiable" item should be **Medium severity**, not Low. A probe that cannot be verified against reality is the central weakness of the entire story, and it directly undermines the contract's "least-privilege proof" requirement.

### Verdict: ACCEPT (with provenance severity escalation)
The premortem is thorough for a LOW-risk documentation story. The identified gaps are real but not blocking. The one concern is that the premortem accepts a fundamentally unverifiable probe as an "accepted gap" when it is the story's core deliverable. Escalate probe provenance debt to Medium.

---

## S0-003 Review
**Story**: P0-D Break-Glass Runbook + Drill

### Strengths
- The risk rating override from LOW to HIGH is exactly correct and well-justified. This is the last-resort safety mechanism; a paper drill is safety theater. The premortem author clearly understands the stakes.
- Failure mode 2 ("drill is paper-only") is the sharpest observation across all four premortems. The specific evidence requirements (monotonic timestamps, intent IDs, Kill-mode transition) transform a vague "drill happened" into a falsifiable claim.
- Failure mode 3 ("missing cancel outstanding OPENs step") catches a real gap in the Kill semantics: Kill blocks NEW dispatches but does not cancel in-flight orders. The reference to Non-Active OPEN Cancellation (section 2.2.3.4.1) shows the author has deeply read the contract.
- The wrong-implementation gate is comprehensive. Eight acceptance criteria, each with a sharp wrong implementation. The "drill has time to halt" tightening (wall-clock measurement) is particularly good.
- Assumption 6 (inflight/queued orders) is a subtle and important catch. The runbook's "verify no further OPEN risk" step must address already-dispatched orders, not just TradingMode state.

### Gaps Found
1. **Decision 2 (trigger mechanism) is left unresolved.** The premortem says "Cannot decide blindly" and defers to implementation. This is honest, but the debt item severity is only MED. For the last-resort safety mechanism, not knowing HOW it triggers is arguably a RED flag, not YELLOW. If the trigger mechanism turns out to be fragile (e.g., requires the process to be healthy to receive an API call, but the emergency is that the process is hung), the entire runbook is worthless.

2. **Missing assumption: the operator can actually reach the system during an emergency.** The premortem assumes SSH or API access is available during a crisis. Network partitions, cloud provider outages, or credential expiry could prevent the operator from executing the runbook. The fallback ("kill the process") assumes the operator has OS-level access, which may not be true if the system runs in a managed container or serverless environment.

3. **No time-bound on drill execution.** The contract says "execute recorded drill proving halt capability" but the premortem does not specify how quickly Kill must take effect. If Kill takes 30 seconds to propagate, is that acceptable? The wrong-implementation gate asks for "time to halt" but there is no acceptance threshold (e.g., "Kill must be effective within 1 tick / 500ms").

### Missing Failure Modes
1. **Kill command races with in-flight dispatch.** The operator triggers Kill, but between the trigger and the mode transition, the hot loop dispatches one more OPEN. The premortem covers "Kill does not block OPENs" (code bug) but not the race window between trigger and enforcement. If the tick loop is long (e.g., 1 second), one more order could dispatch before Kill takes effect.

2. **Runbook steps are correct but executed out of order by a panicked operator.** The operator verifies risk reduction BEFORE triggering Kill (skipping step 1). Now they believe CLOSEs are possible, trigger Kill, but the system was already in Kill (no change), and the CLOSEs were already dispatched. A panicked operator does not follow sequential steps reliably.

3. **Log excerpt proves drill but from a different system version.** The drill was run against v0.1 but the current system is v0.8 with different Kill semantics. The log excerpt is valid evidence for a system that no longer exists. No version binding between drill evidence and current code.

### Missing Wrong Implementations
1. **Runbook says "trigger Kill" but the example command is wrong or outdated.** The runbook documents `touch /tmp/kill_switch` but the implementation actually reads `/var/soldier/kill`. The runbook passes review (it has a command) but the command is wrong.

2. **Drill log excerpt is real but from a non-Kill scenario.** The logs show the system in ReduceOnly (not Kill), which also blocks OPENs. The reviewer sees "OPEN rejected" and assumes Kill was tested, but it was actually ReduceOnly being tested. The log excerpt does not distinguish between Kill-rejection and ReduceOnly-rejection.

### Stoplight Assessment
YELLOW is borderline. I would argue this should be RED due to the unresolved trigger mechanism decision. The premortem itself acknowledges this is a safety-critical escape hatch, then leaves the most fundamental question ("how do you trigger it?") unresolved. The debt register correctly tracks this, but a debt item of MED severity for "we don't know how the kill switch works" undervalues the risk.

Counter-argument for YELLOW: the implementation tests provide a mechanical backstop regardless of the runbook quality. If `test_break_glass_kill_blocks_open_allows_reduce_runtime` is correct, Kill works mechanically even if the runbook is wrong. The premortem is betting on the tests, not the runbook, for safety assurance.

### Verdict: REVISE (escalate trigger mechanism to HIGH severity; add time-bound on Kill latency; address drill version binding)
The premortem is the strongest of the four in terms of adversarial thinking, but it leaves a critical decision unresolved and rates it MED severity. For the last-resort safety mechanism, every open question should be HIGH or the stoplight should be RED.

---

## S0-004 Review
**Story**: P0-E Health + Owner Status Scaffolding

### Strengths
- The tension between AT-022 (requires HTTP) and PRD scope (no HTTP) is identified immediately and handled correctly. The premortem does not pretend the scaffolding satisfies AT-022; it explicitly marks it as CLAIMED-NOT-PROVEN with a clear completion path via S8-008.
- Assumption 1 (`contract_version` must be exactly `"5.2"`) is sharp. The cross-reference to F1_CERT binding (section 2.2.1) explains why a wrong format (`"v5.2"`) would cause perpetual ReduceOnly downstream. This is not an obvious consequence for a scaffolding story.
- Failure mode 3 (dead code: structs exist but are private/unexported) is a subtle and realistic catch. Many scaffolding stories produce code that compiles but is never importable by the consuming story.
- Decision 3 (`build_id` via constructor injection) is the correct choice for testability. The reasoning about deferring CI pipeline concerns to later stories is sound.
- The wrong-implementation for `is_trading_allowed` (wildcard `_ => false` that "happens to work") demonstrates understanding that tests must assert the mapping explicitly for each variant, not rely on coincidental correctness.

### Gaps Found
1. **Missing assumption: `serde` serialization format.** The premortem assumes the structs will serialize to JSON with expected field names (e.g., `ok`, `build_id`, `contract_version`). But Rust's default serde behavior for enums and bools may not match the expected JSON schema. If `TradingMode::Active` serializes as `"Active"` but the contract expects `"active"` (lowercase), schema compatibility breaks silently. No test for serde round-trip with expected JSON keys is mentioned.

2. **No discussion of `#[serde(rename_all = "snake_case")]` or field renaming.** The struct field `is_trading_allowed` must appear exactly as `is_trading_allowed` in JSON output. If the Rust field is named `isTradingAllowed` (camelCase) or mapped differently by serde attributes, the contract alignment breaks. The premortem does not flag serde attribute correctness as an assumption.

3. **`OwnerStatus` struct relationship to `HealthResponse` is unspecified.** The premortem discusses `HealthResponse` (for AT-022: `ok`, `build_id`, `contract_version`) and `OwnerStatus` (for P0-E: `trading_mode`, `is_trading_allowed`) as separate concerns. But it does not clarify whether these are the same struct, nested structs, or completely independent. This structural decision affects S8-008's wiring and is not tracked.

### Missing Failure Modes
1. **`contract_version` const defined in wrong crate causes circular dependency.** The premortem's section 9 mentions this risk but does not elevate it to a failure mode. If `CONTRACT_VERSION` is defined in `soldier_infra` but `soldier_core` needs it for F1_CERT binding, a circular crate dependency results. This is a compile-time failure that blocks the entire build, not just this story.

2. **`ok` field is always `true` in scaffolding, creating false confidence.** The premortem mentions this in the wrong-implementation gate (section 5) but does not list it as a failure mode (section 3). If S8-008 inherits the scaffolding assumption that `ok = true` always, the health endpoint never reports unhealthy state. This should be a failure mode: "scaffolding hard-codes `ok=true`, S8-008 copies pattern without adding real health checks."

### Missing Wrong Implementations
1. **`OwnerStatus` serializes `trading_mode` as the enum's Debug representation.** Instead of `"Active"`, the JSON contains `"TradingMode::Active"` or `"Active { reasons: [] }"`. Passes a "field exists" check but breaks any downstream consumer expecting a clean enum string.

2. **Structs use `Option<T>` for required fields.** `HealthResponse { ok: Option<bool>, ... }` allows `null` in JSON output. AT-022 requires keys to "exist" -- does `"ok": null` count? A lazy implementation uses `Option<bool>` for flexibility, but this weakens the schema guarantee.

### Stoplight Assessment
YELLOW is appropriate and honest. The two debt items (AT-022 HTTP proof deferred, `is_trading_allowed` formal AT anchor missing) are correctly categorized with owners and targets. No items need escalation.

### Verdict: ACCEPT
This is the most straightforward premortem of the four. The scope is genuinely LOW risk, the tensions are correctly identified, and the debt is well-tracked. The missing serde assumptions are a minor gap that should be noted but do not warrant REVISE.

---

## S0-005 Review
**Story**: P0-F Machine Policy Loader Baseline

### Strengths
- Failure mode 2 ("policy path not actually bound at runtime") is the deepest insight in this premortem. It identifies the exact scenario where the entire P0-F guarantee is doc-only: the Python loader validates one path, the Rust runtime reads from another. The TRIP/NON-TRIP proof plan for runtime binding (remove file = fail, provide file = succeed) is the correct way to prove this.
- The wrong-implementation gate is the most comprehensive of all four premortems: 7 wrong implementations covering both the Python loader and the Rust runtime binding, with cross-cutting concerns.
- Decision 1 (schema strictness: Option A) is correctly justified. A loader that accepts `{}` is not "strict" in any meaningful sense.
- Decision 3 (Python loader as canonical validator, Rust test for path binding) correctly decomposes the responsibilities and avoids schema duplication across languages.
- Assumption 5 (Rust runtime refuses to start or enters ReduceOnly if policy is absent) is the single most important assumption in the story. If the runtime has a fallback default, the entire loader is cosmetic.

### Gaps Found
1. **Missing assumption: policy file format stability.** The premortem correctly worries about over-specifying the schema (section 9), but does not address the inverse: what happens when a later story adds a required field to `config/policy.json`? If the strict loader enforces `deny_unknown_fields` today, but a new story adds `max_position_size` tomorrow, the old loader (if not updated) will reject the new valid policy. Schema evolution under strict validation is a known tension that is not addressed.

2. **The meta-test relationship is underspecified.** AC-3 says "meta-test passes" and the proof plan says `test_machine_policy_loader_and_config` in `phase0_meta_test.py`. But the premortem does not clarify what the meta-test actually does beyond "invokes loader and asserts pass." Does it test both valid and malformed cases? Does it test the Rust runtime binding? The wrong-implementation gate flags the mock-vs-real concern but the proof plan does not resolve it.

3. **No discussion of policy file permissions or read-only enforcement.** The loader reads `config/policy.json`, but what if the file is world-writable? A strict loader that validates content but ignores file permissions leaves a privilege escalation vector. This may be out of scope for Phase 0, but it is an unstated assumption worth killing.

4. **Failure mode 3 (lenient flag) is speculative but important.** The premortem raises the possibility of a `--lenient` flag that bypasses strict validation. This is a realistic concern (many tools grow convenience flags over time), but the proposed mitigation ("assert the invocation uses strict mode") is weak. A stronger mitigation: the loader should have NO lenient mode at all. If `--lenient` exists, it should be rejected or removed, not merely not-passed in CI.

### Missing Failure Modes
1. **Policy file exists but is not readable (permission denied).** The loader crashes with an OS error, not a validation error. The exit code may be non-zero (satisfying AC-2) but the error message is misleading ("permission denied" vs. "validation failed"). This is a UX issue that could confuse an operator.

2. **Policy file is a symlink to a different file.** The loader validates `config/policy.json` which is a symlink to `/tmp/attacker_policy.json`. The validated path and the actual content may diverge if the symlink is changed between validation and runtime consumption. This is a TOCTOU (time-of-check-time-of-use) issue.

3. **The Rust runtime reads policy once at startup but the file changes afterward.** The loader validates the file at build/CI time, but the file is modified between validation and runtime startup. The runtime loads a different (potentially invalid) version than what was validated. The premortem's TRIP/NON-TRIP test (remove file = fail) does not catch content modification.

### Missing Wrong Implementations
1. **Loader validates schema but ignores value ranges.** `config/policy.json` has `{"max_policy_age_sec": -1}`. The field exists, has the correct type (number), but the value is nonsensical. A strict loader that checks types but not ranges passes a negative value.

2. **The Rust runtime test loads policy from a test fixture, not from `config/policy.json`.** The test proves that the Rust policy-loading code works, but uses `tests/fixtures/policy.json` instead of the canonical path. Path binding is unproven.

### Stoplight Assessment
YELLOW is appropriate. The two debt items (no formal AT-XXX, empty `enforcing_contract_ats`) are correctly tracked with targets. The severity ratings (Medium and Low) are reasonable given that P0-F is infrastructure/tooling.

### Verdict: ACCEPT (with schema evolution and TOCTOU notes)
The premortem is thorough and demonstrates strong adversarial thinking, particularly around the paper-only risk. The schema evolution gap and TOCTOU concern should be noted as future considerations but do not block the story.

---

## Cross-Story Findings

### 1. Shared Blind Spot: No Formal AT-XXX Anchors
S0-002, S0-003, and S0-005 all have empty `enforcing_contract_ats`. S0-004 claims AT-022 but can only partially satisfy it. This means **four out of four reviewed stories have broken or absent traceability chains from CONTRACT.md to implementation tests.** Each premortem independently flags this gap, but the systemic implication is larger: if all Phase 0 stories lack formal ATs, then the entire Phase 0 gate has no automated contract enforcement. A regression in any Phase 0 story would not trigger a contract violation alert.

**Recommendation**: Before Phase 0 is considered complete, add formal AT anchors to CONTRACT.md for P0-C, P0-D, P0-E (owner status fields), and P0-F. Otherwise Phase 0 is a "trust the reviewer" gate with no automated backstop.

### 2. Shared Blind Spot: Document-Review Acceptance Criteria
S0-002 (4 of 5 criteria) and S0-003 (8 of 8 criteria) rely on "WHEN reviewed THEN has X" acceptance. These are subjective, non-automated checks. Both premortems acknowledge this but neither proposes a concrete cross-story solution. A shared JSON/YAML schema for documentation artifacts (runbook steps, probe fields, rotation plan structure) could convert some subjective checks into automated assertions across both stories.

### 3. S0-003 Depends on S0-004 and S0-005 (Implicit)
S0-003's break-glass drill tests Kill mode enforcement. Kill mode's behavior depends on `TradingMode` enum semantics. S0-004 scaffolds the `TradingMode` data model. If S0-004 defines `TradingMode` with different variant names or missing variants, S0-003's implementation tests may not compile. This cross-story dependency is not documented in either premortem.

Similarly, S0-003's runbook must document the operator's ability to verify system state after Kill. If S0-004's health/status scaffolding does not include `trading_mode` in its output, the operator has no way to verify Kill took effect. The "verify no further OPEN risk" step in the runbook implicitly depends on the status scaffolding being complete.

### 4. S0-005 and S0-004 Share `TradingMode` Dependency
S0-004 assumes `TradingMode` enum exists (Assumption 3). S0-005 assumes the Rust runtime can enter ReduceOnly when policy is absent (Assumption 5). Both assumptions depend on the same `TradingMode` implementation in `soldier_core`, but neither story claims to create it. If neither story defines the enum, both stories fail at compile time. If a prior story (S0-000 or S0-001) defines it, that dependency should be explicit.

### 5. S0-002 and S0-005: "Doc-Only" Risk in Opposite Directions
S0-002 produces evidence (key_scope_probe.json) that may be doc-only (hand-crafted, never verified against live API). S0-005 explicitly exists to prevent doc-only checks ("so runtime checks are not doc-only"). This creates a philosophical tension: S0-005 builds the infrastructure to prevent doc-only policy validation, while S0-002 (which runs concurrently) accepts a potentially doc-only security probe. If the project takes S0-005's "not doc-only" principle seriously, S0-002's probe provenance gap (FM-1) should be escalated.

### 6. S0-003 and S0-005: Kill Mode vs. Policy Absence
S0-003 tests Kill mode enforcement. S0-005 tests what happens when policy is absent (runtime should fail or ReduceOnly). What happens if the policy file is absent AND the operator triggers Kill? Does the system honor Kill (from break-glass) or ReduceOnly (from missing policy)? The contract says TradingMode is resolved as "worst-of" across axes (section 2.2.3). Kill is worse than ReduceOnly, so Kill should win. But this interaction is not tested by either story.

### 7. Shared Test File Contention
S0-002, S0-003 (and likely S0-004/S0-005) all add tests to `crates/soldier_infra/tests/test_phase0_runtime.rs`. Multiple premortems note this as a merge conflict risk, but none proposes a mitigation (e.g., separate test files per story, or a test-file naming convention). This is a practical execution risk that could slow down parallel story implementation.

### 8. No Premortem References Prior Postmortems
All four premortems state "Prior Postmortem: NONE." This is expected for early Phase 0 stories. However, it means none of the premortems can learn from prior implementation mistakes. Once the first S0 story is implemented and its postmortem written, subsequent premortems should reference it. The premortems should note this explicitly: "First story implemented should establish postmortem patterns for remaining S0 stories."
