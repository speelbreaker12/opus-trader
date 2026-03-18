# Story Premortem: S2-004

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S2-004 -- S2.5 RejectReasonCode registry (intent-level rejections)
- Contract clause(s): §2.2.6 RejectReasonCode Registry (Intent-Level Rejections), Definitions (fail-closed intent classification)
- Acceptance tests: AT-201
- Touch scope: `crates/soldier_core/src/execution/reject_reason.rs`, `crates/soldier_core/src/execution/mod.rs`, `crates/soldier_core/tests/test_reject_reason.rs`
- **Risk rating**: MED
  - This story defines the exhaustive enum of all pre-dispatch rejection reasons. An incomplete or incorrectly-wired registry means rejections happen without auditable reason codes, making debugging impossible and contract compliance unverifiable. The AT-201 (fail-closed intent classification) component is safety-critical: if unknown actions bypass OPEN gates, risk-increasing intents could dispatch without PolicyGuard or latch checks.
  - The risk is elevated because this is a foundational type definition that every other rejection site in the codebase must use. A wrong shape here propagates to all consumers.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-201 | Definitions (fail-closed intent classification) | Given: OrderIntent with unknown action (not Place/Cancel/Close/Hedge) OR missing classification fields. When: intent classification computed. Then: classification MUST be OPEN, and OPEN gates (PolicyGuard mode + CP-001 latch) MUST apply. | MUST (Non-Negotiable) | Yes -- classification = OPEN, blocked when OPEN gate blocks |

Additional contract context referenced by this story but not in `enforcing_contract_ats`:

| AT | Contract § | Clause text (abbreviated) | Type | Relevance |
|----|-----------|---------------------------|------|-----------|
| AT-930 | §2.2.6 | Test harness triggers at least one rejection in each category; response includes reject_reason_code in registry. | MUST | Not claimed by S2-004 but the registry enum this story defines is what AT-930 validates. |
| AT-1101 | §2.2.6 | Full set of Rejected(...) tokens in contract MUST have corresponding variant in RejectReasonCode enum. | MUST | Completeness check. This story must ensure the enum is complete w.r.t. the contract. |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

**Note on AT scope**: This story only claims AT-201, but the registry completeness (AT-1101) and usage coverage (AT-930) are implicitly required for the registry to be meaningful. The story should implement the registry enum that satisfies AT-1101 even if it does not formally claim that AT.

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The `RejectReasonCode` enum variants must be a 1:1 superset of the CONTRACT.md §2.2.6 allowed values list (verified 30 values in-contract). | If the enum has fewer variants than the contract list, AT-1101 fails. If it has extra variants not in the contract, the completeness rule is violated in the other direction (code has tokens the contract does not reference). | `test_registry_contains_contract_minimum_set()` -- enumerate all 30 contract values and assert each has a corresponding enum variant. | MUST TEST |
| 2 | The PRD-defined reason codes `UnknownActionClassifiedOpen` and `RejectReasonRegistryMissing` are NOT in the CONTRACT.md §2.2.6 allowed values list. | If these are added to the Rust enum but not to the contract registry, AT-1101's "1:1 correspondence" is violated. Alternatively, these may be PRD-internal identifiers, not RejectReasonCode values. | Clarify: are `UnknownActionClassifiedOpen` and `RejectReasonRegistryMissing` actual enum variants or internal diagnostic identifiers? The contract lists neither. | MUST RESOLVE -- this is a potential paper-compliance violation |
| 3 | S2-004’s PRD dependency on S2-003 is sequencing-only; classifier behavior is independent of S2-003 label matching and can be implemented against contract definitions alone. | If implementation is blocked on label-matching from S2-003, scope can expand and PRD ordering gets incorrectly treated as a technical blocker. | Verify: `classify_intent()` is based on action/reduce_only in `execution/mod.rs` and has no dependency on S2-003 label-matching helpers or types. | MUST VERIFY before coding |
| 4 | "Any intent rejected before dispatch MUST include reject_reason_code" means the rejection type/struct carries the code, not just that a metric is incremented or a log line is emitted. | If the rejection path returns a bare error without a RejectReasonCode field, the rejection technically "happens" but the code is not machine-accessible for diagnostics or AT-930 validation. | Test: trigger a rejection, inspect the returned struct, assert `.reject_reason_code` field exists and is a valid variant. | MUST TEST |
| 5 | `GateCascadeSkip` is described as "internal diagnostic -- never emitted as primary reject code." This means it can appear in the enum but must never be the `reject_reason_code` of a rejection. | If GateCascadeSkip is used as a primary rejection reason, it violates the contract note. But if it is excluded from the enum, downstream diagnostic use is impossible. | Test: `GateCascadeSkip` variant exists in enum but is never returned as a primary rejection from any gate. This is a negative test: no code path produces `GateCascadeSkip` as the sole/primary reason. | Should test, but full verification requires integration-level checks across all gates |
| 6 | The fail-closed intent classification (AT-201) must classify unknown actions as OPEN even if the unknown action string/enum value is superficially "safe-looking" (e.g., "Reduce", "Exit", "Liquidate"). | If the classifier has a match arm like `"Close" | "Exit" | "Liquidate" => CLOSE`, it silently treats non-canonical action names as safe. Only explicitly known canonical values (Place, Cancel, Close, Hedge) should map to their respective classes. Everything else is OPEN. | Test: action="Reduce" -> classified as OPEN. action="Liquidate" -> OPEN. action="" -> OPEN. action="PLACE" (wrong case) -> OPEN (if case-sensitive matching). | MUST TEST -- this is the core of AT-201 |
| 7 | The `reject_reason_code` must be serializable to a string that matches the contract's token names exactly (e.g., `"TooSmallAfterQuantization"`, not `"too_small_after_quantization"` or `"TOO_SMALL"`). | If the Rust enum uses `#[serde(rename_all = "snake_case")]` or similar, the serialized names do not match the contract tokens. AT-930 checks that the value "is a member of RejectReasonCode" which implies string identity with the contract list. | Test: serialize each enum variant, compare against the exact contract string. Or use `#[serde(rename = "ExactContractName")]` on each variant. | MUST TEST |
| 8 | The PRD step "Wire reason codes, state transitions, and observability fields" may imply this story should add `/status` endpoint fields or metrics. But the PRD `observability.metrics` list is empty, and `status_fields` only lists `trading_mode` and `risk_state` (which already exist). | If the story tries to wire status endpoint changes, it expands scope into the status module. If it does not, the observability step is a no-op. | Verify: the observability wiring for S2-004 is limited to ensuring existing status fields (`trading_mode`, `risk_state`) reflect the effects of AT-201 enforcement. No new status fields are needed. | Validated -- empty metrics list confirms no new metrics |

## 3) Top 7 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **Enum is incomplete: missing a contract-required variant.** If a rejection site tries to use a variant that does not exist in the enum, Rust compilation fails. But if the rejection site uses a catch-all (e.g., `RejectReason::Other(String)`) instead, the variant gap is silently papered over. The rejection "works" but the reason code is not in the registry. | AT-1101 (completeness check). Compile-time enforcement if the enum has no `Other` variant. | Do NOT add an `Other(String)` or `Unknown` catch-all variant. Force compilation errors when a new rejection reason is needed, which forces the registry to be updated. This is principle 0.4: harder to misuse > easier to audit. | AT-1101 (not claimed by S2-004 but critical). `test_registry_contains_contract_minimum_set()` |
| 2 | **Fail-closed classification does not actually trigger OPEN gates.** The classifier returns OPEN for unknown actions, but the dispatch pipeline does not check the classification before gating. The intent bypasses PolicyGuard and CP-001 latch because those gates are wired to check `action == Place` rather than `classification == OPEN`. | AT-201 TRIP test: unknown action + OPEN gate blocks (e.g., ReduceOnly mode) -> intent must be rejected. If it dispatches, the gate is not wired. | The classifier must return a classification value that the dispatch pipeline consumes. The dispatch pipeline must gate on classification, not on raw action values. | AT-201 |
| 3 | **PRD reason codes (`UnknownActionClassifiedOpen`, `RejectReasonRegistryMissing`) conflict with contract registry.** The PRD lists these as `reason_codes.values` but the contract §2.2.6 does not include them. If added to the Rust enum, they are code-only variants without contract backing. If omitted, the PRD traceability is broken. | Compare enum variants against contract §2.2.6 list. Any variant not in the contract list is suspicious. | Treat `UnknownActionClassifiedOpen` as an internal diagnostic code (similar to `GateCascadeSkip`), not a primary RejectReasonCode. Or add it to the contract in the same patch (per the completeness rule). `RejectReasonRegistryMissing` is a meta-error (the registry itself is absent) which should be a compile-time guarantee, not a runtime reason code. | No AT covers this. Need explicit design decision. |
| 4 | **Case sensitivity or naming mismatch in serialization.** Rust enum variant `TooSmallAfterQuantization` serializes as `"TooSmallAfterQuantization"` by default with serde. But if `#[serde(rename_all = "snake_case")]` is applied at the enum level, it becomes `"too_small_after_quantization"`. Downstream consumers (AT-930, /status, logs) that check for the contract token by string would fail silently. | `test_reject_reason_serialization_matches_contract()` -- serialize each variant and compare against known contract strings. | Use `#[derive(Serialize, Deserialize)]` without rename, or apply explicit `#[serde(rename = "...")]` on each variant to match the contract exactly. | AT-930 (not claimed but implicitly required for registry usability) |
| 5 | **Intent classifier treats `None`/missing action as CLOSE/HEDGE instead of OPEN.** If the action field is `Option<Action>` and the classifier maps `None` to a default like `Cancel` (assuming "do nothing" is safe), it bypasses OPEN gates. The contract says "missing required classification fields" -> MUST be OPEN. | AT-201 TRIP test: intent with action=None + ReduceOnly mode -> must be blocked (classified as OPEN). | The classifier's default/fallback arm must map to OPEN. This is the classic fail-closed pattern. The match must be: `Some(Place) | Some(Close) | ... => classified, _ => OPEN`. | AT-201 |
| 6 | **The reject_reason.rs module defines the enum but does not export it or wire it into the rejection return type.** The enum exists, tests pass by constructing values directly, but no actual rejection site in the codebase uses it. The registry is "paper compliance" -- it exists in code but is not enforced. | `test_reject_reason_present_on_pre_dispatch_reject()` -- trigger an actual rejection via the dispatch pipeline and verify the returned struct includes a `RejectReasonCode` field. This requires integration, not just unit testing. | The rejection return type (e.g., `DispatchResult::Rejected { reason: RejectReasonCode, ... }`) must use the enum. Verify via compilation: if the dispatch pipeline returns a rejection without a RejectReasonCode, the compiler complains. | AT-930 (integration). `test_reject_reason_present_on_pre_dispatch_reject()` |
| 7 | **Classifier correctly returns OPEN but the specific OPEN gate (PolicyGuard mode check or CP-001 latch check) is not applied because the pipeline checks classification AFTER those gates have already run.** Order of operations: if gates run first and then classification happens, the gates see the raw action (e.g., unknown) and may not know to apply OPEN rules. | AT-201 TRIP test: unknown action + gate that should block OPEN -> verify gate fires. This test must force exactly one gate to block (e.g., ReduceOnly mode) and verify the unknown-action intent is rejected by THAT gate, not by a later classifier-based rejection. | Classification must happen BEFORE gate evaluation, not after. The dispatch pipeline order must be: classify intent -> evaluate gates based on classification -> dispatch or reject. | AT-201 |

## 4) Open decisions (resolve before coding)

### Decision: Treatment of PRD-specific reason codes (`UnknownActionClassifiedOpen`, `RejectReasonRegistryMissing`)
- **What is ambiguous / missing**: The PRD lists `reason_codes.values: [UnknownActionClassifiedOpen, RejectReasonRegistryMissing]` but these are not in the CONTRACT.md §2.2.6 allowed values list. The contract's completeness rule says "the registry MUST be complete w.r.t. this contract" -- implying the enum should match the contract, not exceed it.
- **Evidence**: CONTRACT.md §2.2.6 allowed values list (30 items). Neither `UnknownActionClassifiedOpen` nor `RejectReasonRegistryMissing` appears. PRD prd.json S2-004 `reason_codes.values`.
- **Options**:
  1. Option A -- Add both to the Rust enum AND to CONTRACT.md in the same patch (per the completeness rule: "if a new rejection token is added anywhere, the registry MUST be updated in the same patch").
  2. Option B -- Treat them as internal diagnostic annotations (like `GateCascadeSkip`), not primary reject reason codes. They exist in the enum but are never emitted as `reject_reason_code` on a rejection response.
  3. Option C -- Do not add them to the enum. They are PRD metadata, not runtime values. The PRD `reason_codes` field tracks contract traceability, not Rust enum membership.
- **Chosen**: B -- Internal diagnostic annotations. `UnknownActionClassifiedOpen` is a classification diagnostic ("we classified this as OPEN because the action was unknown"), not a rejection reason. The rejection reason when an OPEN is blocked is the gate-specific reason (e.g., `PolicyGuardReduceOnly` or the latch code). `RejectReasonRegistryMissing` is a meta-error that should be prevented by compilation (no catch-all variant), not a runtime code.
- **Why not others**: Option A adds non-standard tokens to the contract, which sets a precedent for PRD-driven contract changes outside the normal amendment process. Option C ignores the PRD's signal entirely.
- **Scope control**:
  - What we're NOT doing yet: wiring `UnknownActionClassifiedOpen` into the /status or metrics pipeline. It is purely a classification outcome, not a rejection reason.
  - What unblocks us if this choice is wrong: upgrading from diagnostic to primary reject code requires adding it to the contract and changing one match arm. No structural change.

### Decision: Where does the intent classifier live?
- **What is ambiguous / missing**: AT-201 requires fail-closed intent classification. The PRD touch scope is `reject_reason.rs` and `execution/mod.rs`. But intent classification is a concept that belongs to the dispatch pipeline (Definitions section), not specifically to the rejection registry. The classifier could live in `reject_reason.rs`, `mod.rs`, or a separate `classify.rs`.
- **Evidence**: CONTRACT.md Definitions: "Fail-closed intent classification: if an intent cannot be classified, it MUST be treated as OPEN." The touch scope does not include a `classify.rs` file. The scope.avoid list excludes `plans/**` but not other execution module files.
- **Options**:
  1. Option A -- Implement the classifier as a function in `reject_reason.rs` alongside the enum. Rationale: the classifier produces information used to determine rejection behavior.
  2. Option B -- Implement the classifier in `execution/mod.rs` as a standalone function. Rationale: classification is a pipeline concern, not a rejection-specific concern.
  3. Option C -- Create `execution/classify.rs`. Rationale: cleanest separation of concerns.
- **Chosen**: B -- `execution/mod.rs`. The classifier is a one-function utility that maps action to classification. It does not warrant its own file (§0.3: smallest surface area). It is not specific to rejection (rejection is one consequence of classification). `mod.rs` is already in the touch scope.
- **Why not others**: Option A conflates classification with rejection. Option C creates a new file for a single function, adding scope.
- **Scope control**:
  - What we're NOT doing yet: wiring the classifier into the full dispatch pipeline. This story defines the function; the dispatch pipeline integration happens when the pipeline is built.
  - What unblocks us if this choice is wrong: moving a function from `mod.rs` to `classify.rs` is a trivial refactor with no behavioral change.

### Decision: Enum representation (C-like discriminants vs. plain enum)
- **What is ambiguous / missing**: The contract lists reason codes as string tokens. The Rust enum could use plain variants (no discriminant) or C-like discriminants (`TooSmallAfterQuantization = 1`). Discriminants enable stable wire-format IDs but add maintenance burden.
- **Evidence**: CONTRACT.md §2.2.6: "the value MUST be in this registry" (string identity). No numeric code requirement.
- **Options**:
  1. Option A -- Plain enum variants with `#[derive(Serialize, Deserialize)]`. Serializes to string by default.
  2. Option B -- C-like enum with integer discriminants. Requires explicit serde impl or `#[serde(rename)]`.
- **Chosen**: A -- Plain enum. The contract uses string tokens, not numeric codes. Adding discriminants is scope creep and creates a maintenance burden (keeping discriminants stable across versions).
- **Why not others**: Option B adds complexity with no contract requirement. The string serialization of variant names already provides the stable identity the contract needs.
- **Scope control**:
  - What we're NOT doing yet: defining a numeric wire format for reject codes.
  - What unblocks us if this choice is wrong: adding `#[repr(u16)]` and discriminants later is backward-compatible if serde continues to use string names.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-201 | Classifier maps `Action::Unknown` to OPEN but the `Action` enum has a catch-all `Other(String)` variant. An intent with `action = Other("close")` is classified as OPEN because it does not match `Action::Close`. But an intent with `action = Action::Close` is correctly classified as CLOSE. The test only checks `Action::Unknown` (which maps to OPEN) and `Action::Place` (which maps to OPEN). It never tests `Other("close")` or `Other("hedge")`. | The catch-all variant hides the fact that non-canonical action names bypass classification. An attacker (or buggy upstream) could send `action = Other("hedge")` and get OPEN classification, which is correct per contract but the test does not verify this. More importantly, if someone later adds a match arm `Other("close") => CLOSE`, it silently weakens the fail-closed gate. | Property test: for ALL non-canonical action values (including strings resembling canonical names), classification MUST be OPEN. Test with: "close" (lowercase), "PLACE" (uppercase), "Hedge" (title case), "", "reduce", "liquidate", "exit". |
| AT-201 | Classifier correctly returns OPEN for unknown actions, but the test verifies classification only, not that OPEN gates actually apply. The test asserts `classify(intent) == OPEN` but does not verify that PolicyGuard blocks the intent in ReduceOnly mode. A future refactor could remove the gate check without breaking this test. | AT-201 says "OPEN gates MUST apply." Testing classification alone is necessary but not sufficient. The gate application is the enforcement; classification is just the input. | TRIP test: unknown action + TradingMode::ReduceOnly -> intent rejected, dispatch_count = 0, reject_reason is a PolicyGuard-level code. This test proves that the classifier's output is consumed by the gate. |
| AT-201 | Classifier is implemented but placed AFTER the gate evaluation in the dispatch pipeline. Gates check `action == Place` (raw action) instead of `classification == OPEN`. For known actions this is equivalent. For unknown actions, the gate does not recognize the action and falls through (no match), allowing dispatch. The classifier runs after dispatch and logs "classified as OPEN" but the order is already sent. | Order of operations matters. Classification must precede gate evaluation. The test passes because it calls `classify()` directly, not through the pipeline. | Integration test: construct a full dispatch pipeline, inject an unknown-action intent, verify the gate blocks it. This tests pipeline wiring, not just the classifier function. |
| AT-201 | Classifier handles unknown `action` but not missing classification fields (the second condition in AT-201: "OR missing required classification fields"). If `reduce_only` is `None` and `action` is `Place`, the intent should be classified as OPEN (because `reduce_only != true` means OPEN per Definitions). The wrong impl classifies it as OPEN correctly, but a test only checks the `action` branch and not the `reduce_only = None` branch. | The test covers unknown action but not missing fields. A future change that breaks the missing-fields path would not be caught. | Explicit test: `action = Place`, `reduce_only = None` -> classified as OPEN. `action = Place`, `reduce_only = Some(false)` -> OPEN. `action = Place`, `reduce_only = Some(true)` -> CLOSE. This covers the full classification matrix. |
| AT-201 (registry) | The RejectReasonCode enum has all 30 contract variants, but `test_registry_contains_contract_minimum_set()` checks by variant count (assert enum has >= 30 variants) rather than by name. Adding 30 arbitrary variants like `Dummy1..Dummy30` passes the test. | Count-based checks do not prove name identity. The test must check that specific named variants exist. | The test must iterate over a hardcoded list of contract token strings, deserialize each into the enum, and verify deserialization succeeds. If any contract token fails deserialization, the enum is incomplete. |
| AT-201 (registry) | The enum includes an `Other(String)` or `#[serde(other)]` catch-all that deserializes any unknown string to a default variant. `test_registry_contains_contract_minimum_set()` deserializes all 30 contract tokens successfully, but they all map to the catch-all, not to distinct variants. | The catch-all masks missing variants. Every contract token must deserialize to its own distinct variant. | Test: deserialize each contract token, then serialize it back. The round-trip must produce the original token string. This proves each token has a dedicated variant, not a catch-all. Also: attempt to deserialize a non-contract token (e.g., "NotARealReason") and assert it FAILS. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-201 (classification) | DispatcherChokepoint (intent classifier in execution/mod.rs) | `test_unknown_action_classified_as_open` | Yes (unknown action -> OPEN classification) | Yes (known action Place -> OPEN; known action Close -> CLOSE; known action with reduce_only=true -> CLOSE) | Classification result == OPEN for unknown | Yes -- only AT-201 tests fail-closed classification |
| AT-201 (gate enforcement) | DispatcherChokepoint (PolicyGuard mode check + CP-001 latch) | `test_unknown_action_blocked_by_open_gate` | Yes (unknown action + ReduceOnly -> rejected, dispatch_count = 0) | Yes (unknown action + Active mode + no latch -> dispatched, dispatch_count = 1) | dispatch_count = 0, reject_reason = PolicyGuard-level code | Yes -- proves the classifier output is consumed by the gate |
| AT-201 (missing fields) | DispatcherChokepoint (intent classifier) | `test_missing_reduce_only_classified_as_open` | Yes (action=Place, reduce_only=None -> OPEN) | Yes (action=Place, reduce_only=Some(true) -> CLOSE) | Classification result == OPEN | Yes -- tests the "missing required fields" branch of AT-201 |
| Registry completeness (AT-1101 support) | Compile-time (enum definition) | `test_registry_contains_contract_minimum_set` | Yes (all 30 contract tokens deserialize to distinct variants) | Yes (non-contract token fails deserialization) | Deserialization success/failure per token | Yes -- tests enum completeness |
| Rejection struct wiring | DispatcherChokepoint (rejection return type) | `test_reject_reason_present_on_pre_dispatch_reject` | Yes (trigger a rejection, verify .reject_reason_code field is populated) | Yes (trigger a successful dispatch, verify no rejection struct) | .reject_reason_code field exists and is a valid variant | Yes -- tests structural wiring |

Causality proof must be one of: `dispatch_count`, `reject_reason`, `latch_reason`, `cortex_override`.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix -- YELLOW: gate enforcement test requires pipeline wiring which may not exist yet; deferred to integration

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Two distinct failure modes with different economic profiles:
  1. **Registry incomplete/unwired**: A rejection occurs without a `reject_reason_code`. No financial impact (the rejection still prevents dispatch). The harm is operational: debugging is impossible, AT-930 compliance fails, and the operator cannot distinguish between rejection categories in logs/metrics. Financial loss: $0 directly, but degraded observability increases mean-time-to-diagnose for real issues.
  2. **Fail-closed classification broken (AT-201)**: An unknown action is classified as CLOSE/HEDGE/CANCEL instead of OPEN. The intent bypasses PolicyGuard mode check and CP-001 latch. If the system is in ReduceOnly mode (e.g., after a WS gap), this intent dispatches an order that should have been blocked. Worst case: a risk-increasing order dispatches during a period when the system has explicitly decided to restrict trading. Financial exposure: bounded by the single-order size, but the ReduceOnly invariant is violated.
- **Fail-closed cap on loss**: DispatcherChokepoint rejects the intent. For scenario 1, the rejection happens but reason is missing (operational debt, not financial). For scenario 2, the fail-closed cap is the classifier itself -- if it defaults to OPEN, all downstream gates apply. The cap fails only if the classifier defaults to non-OPEN.
- **Drift metric**: No drift metric defined (PRD `observability.metrics` is empty). The registry completeness is a compile-time property, not a runtime metric. For AT-201, the closest drift signal is monitoring for intents with unknown actions that successfully dispatch -- this should be zero.
- **Loss boundary**: PolicyGuard's ReduceOnly/Kill mode blocks OPEN intents. If classification is correct, PolicyGuard is the ultimate gate. The loss boundary is: one incorrectly classified intent = one order that should have been blocked, bounded by per-order size limits (max_order_usd) and position limits.
- **Rollback plan**: Revert reject_reason.rs and classifier changes. This removes the enum and classifier, meaning: (a) rejections have no reason code (AT-930 violation), and (b) intent classification is undefined (AT-201 violation). Rollback must be paired with TradingMode::Kill or ReduceOnly to prevent unclassified intents from dispatching.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**:
  - Intent classification affects every gate that distinguishes OPEN from CLOSE/HEDGE/CANCEL: PolicyGuard mode check, CP-001 latch, EvidenceGuard (GOP only), quantization rejection gates (AT-926/AT-908 scope to OPEN), LiquidityGate, Margin Headroom Gate.
  - The RejectReasonCode enum is consumed by every rejection site in the codebase. Adding or removing a variant is a global change.
- **If conflict with CONTRACT.md**: No conflict. §2.2.6 is the authoritative source for the registry. AT-201 is the authoritative source for fail-closed classification. This story implements both.
- Files with recent churn or shared ownership: `crates/soldier_core/src/execution/mod.rs` is shared across all S2 stories. S2-000 adds quantization exports, S2-001 adds hashing exports, S2-002 adds label exports, S2-003 adds label match exports. S2-004 adds reject reason and classifier exports. Coordinate mod.rs changes.
- Struct fields I'm assuming exist (verify before coding):
  - `OrderIntent` struct with an `action` field (enum or Option) and a `reduce_only` field (Option<bool>).
  - `DispatchResult` or equivalent rejection return type that can carry a `reject_reason_code: RejectReasonCode` field.
  - `IntentClassification` enum: `Open | Close | Hedge | Cancel` (may need to be created by this story).
- State machine transitions affected: None directly. The classifier and registry are stateless. But the classifier output feeds into PolicyGuard's gate evaluation, which determines TradingMode transitions. A wrong classification could cause PolicyGuard to allow an OPEN in ReduceOnly mode, which is a state machine violation (ReduceOnly -> Active transition is not supposed to happen implicitly).
- **Cross-story dependencies**:
  - S2-000 (quantization) uses `RejectReason::TooSmallAfterQuantization` and `RejectReason::InstrumentMetadataMissing`. If S2-004 defines the enum, S2-000 depends on S2-004 for these variants. But S2-000 has no dependency on S2-004 in the PRD dependency graph (S2-004 depends on S2-003, not the other way). This means S2-000 must define these variants itself or they must already exist. Verify: are these variants defined by an earlier story?
  - S2-003 (label match): S2-004 depends on S2-003. Verify S2-003 is complete before starting S2-004.
  - All future rejection sites: any story that adds a new rejection must import and use `RejectReasonCode`. The enum is foundational infrastructure.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (no S2-004 postmortem exists; S2-003 postmortem not available)
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A -- no prior Slice 2 postmortem reviewed. If S2-003's postmortem exists, check for notes about execution/mod.rs coordination or intent struct shape.
- What will slow me down: The dual nature of this story -- it is both a type definition (enum) and a behavioral contract (AT-201 classifier). The type definition is straightforward (enumerate 30 variants). The behavioral contract requires understanding the dispatch pipeline well enough to place the classifier correctly and wire its output into gate checks. If the pipeline does not exist yet (it may not, since this is Slice 2), the behavioral tests become design-level integration tests that define the pipeline's interface before the pipeline exists.
- Exploit: Define the enum and classifier as free-standing functions with clear input/output types. Write the unit tests against these functions directly. Defer pipeline integration testing to the story that builds the dispatch pipeline. This keeps S2-004 focused on its touch scope (reject_reason.rs, mod.rs, test_reject_reason.rs) without expanding into pipeline wiring.
- Smallest fix that prevents it next time: Add a compile-time test that attempts to deserialize every CONTRACT.md §2.2.6 token into the enum. If the contract is updated and the enum is not, the test fails. This is a "living documentation" test that keeps the enum in sync with the contract automatically.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: The registry definition is clean and well-scoped. The AT-201 classifier is well-understood. The gaps are: (1) PRD reason codes (`UnknownActionClassifiedOpen`, `RejectReasonRegistryMissing`) are not in the contract registry and their treatment needs a design decision (resolved as "internal diagnostic" in §4), (2) the gate enforcement test for AT-201 requires pipeline wiring that may not exist yet, (3) the dependency on S2-003 needs verification. All gaps have explicit owners and target slices.

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| AT-201 gate enforcement integration test (unknown action + ReduceOnly -> blocked) | Med | Requires dispatch pipeline wiring; pipeline may not exist in S2 scope | S2-004 implementer | Dispatch pipeline story (S3+) | `test_unknown_action_blocked_in_reduceonly_mode()` with full pipeline |
| Verify S2-003 completion before starting S2-004 | Low | Dependency chain check; PRD says S2-004 depends on S2-003 | S2-004 implementer | S2-004 implementation start | Verify `passes=true` for S2-003 |
| AT-1101 completeness check (enum vs. contract) | Med | AT-1101 is not claimed by S2-004 but the enum must satisfy it | S2-004 implementer | S2-004 implementation | `test_registry_contract_completeness_roundtrip()` with all 30 contract tokens |
| `GateCascadeSkip` never-emitted-as-primary invariant test | Low | Requires cross-gate integration; not possible in unit tests | Full integration story | S3+ (gate wiring) | Integration test: no gate ever returns GateCascadeSkip as sole reject_reason |
| Serialization format test (variant name == contract token) | Med | Must be done at implementation time when serde attributes are chosen | S2-004 implementer | S2-004 implementation | `test_reject_reason_serde_roundtrip_matches_contract()` |
| Cross-story coordination: S2-000 RejectReason variants vs S2-004 enum definition | Med | S2-000 uses TooSmallAfterQuantization and InstrumentMetadataMissing. If S2-004 defines the canonical enum, variants must exist before S2-000 can compile. But S2-000 has no PRD dependency on S2-004. | S2-000 and S2-004 implementers | S2-000 / S2-004 coordination | Verify variant availability at compile time; possibly define variants in S2-000 and re-export from S2-004 |

YELLOW with all debt tracked and assigned to target slices. No RED blockers.

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause -- AT-201 traced to Definitions (fail-closed classification); AT-1101/AT-930 noted as implicitly required
- [x] §2 all assumptions validated or killed -- 8 assumptions documented; 2 require resolution before coding (PRD reason codes, classifier location); 1 requires cross-story verification (S2-003 dependency)
- [x] §3 all failure modes have detection + mitigation -- 7 modes identified, all have detection and mitigation paths
- [x] §4 all decisions resolved, grounded in evidence -- 3 decisions resolved with CONTRACT.md references
- [x] §5 wrong impl gate: every AT tightened -- 6 wrong impls identified for AT-201 and registry, each with specific tightening tests
- [ ] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs -- YELLOW: unit-level TRIP/NON-TRIP designed; integration-level gate enforcement deferred to pipeline wiring
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan -- two failure scenarios documented with economic profiles and rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts) -- clean; cross-story dependency on S2-000 and S2-003 noted
- [x] No new debt without owner + target slice -- 6 debt items tracked in register with owners and target slices
