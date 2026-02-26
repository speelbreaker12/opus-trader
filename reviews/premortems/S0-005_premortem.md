# Story Premortem: S0-005

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-005 — P0-F Machine Policy Loader Baseline
- Contract clause(s): Phase 0 §P0-F ("Bind a machine-readable policy path + strict loader so runtime checks are not doc-only"), §2.2 PolicyGuard (consumes `python_policy`), §2.2.1.1 (missing/stale inputs -> fail-closed), Appendix A (`max_policy_age_sec`)
- Acceptance tests: AT-NONE (no formal AT-XXX IDs in `enforcing_contract_ats` (empty). Story-level acceptance criteria are the three GIVEN/WHEN/THEN clauses in prd.json.
- Touch scope: `config/policy.json`, `tools/policy_loader.py`, `tools/phase0_meta_test.py`, `tests/phase0/test_machine_policy_loader_and_config.md`
- **Risk rating**: LOW
  - Infrastructure/tooling story. No trading logic, no order dispatch, no state machines. However, the fail-closed property of this loader is safety-foundational: if the loader silently accepts invalid policy, downstream PolicyGuard may operate on garbage inputs. The risk is indirect but the correctness bar is high.

## 1) Clause audit (contract → AT traceability)

The `enforcing_contract_ats` array is empty. This story has no formal AT-XXX coverage in CONTRACT.md. The contract evidence is a single quote:

> "Policy JSON loaded and validated before first tick" -- specs/CONTRACT.md:131, anchor P0-F Machine Policy Loader Baseline

The normative clause from the Phase 0 table (CONTRACT.md line 131):

| AT | Contract section | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| (none -- no AT-XXX) | Phase 0, P0-F | "Bind a machine-readable policy path + strict loader so runtime checks are not doc-only" | MUST (Non-Negotiable -- Phase 0 items are marked "MUST be completed and evidenced") | Yes -- loader exit code + policy parse result |
| (none -- no AT-XXX) | S2.2.1.1 | "PolicyGuard MUST NOT return TradingMode::Active if any critical safety input required for Kill/ReduceOnly decisions is missing or stale" | MUST (Non-Negotiable) | Yes -- but this is downstream of P0-F; the loader story establishes the foundation |

- [x] Every claimed AT traced to a normative clause -- N/A (no ATs claimed)
- [x] No informational-only ATs counted as enforcement -- N/A

**Note:** The absence of formal AT-XXX IDs is a gap. P0-F is described as Non-Negotiable but has no formal acceptance test anchor in CONTRACT.md. The implementation tests (`test_machine_policy_loader_and_config`, `test_policy_is_required_and_bound_runtime`) serve as the de facto proof, but there is no traceability chain from CONTRACT.md AT to code. This is flagged as debt in S10.

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `config/policy.json` has a defined schema with required fields that the strict loader validates against | If the schema is too loose (e.g., accepts `{}`), the loader provides no safety guarantee | `test_machine_policy_loader_and_config` must reject empty/minimal JSON | Needs AT |
| 2 | The policy path is bound at runtime (i.e., the Rust runtime actually reads from the same path the Python loader validates) | If the Rust binary reads from a hardcoded different path or env var, the Python loader's validation is irrelevant -- a "paper-only" check | `test_policy_is_required_and_bound_runtime` must prove the Rust side reads the same path | Needs AT |
| 3 | "Strict" means the loader rejects unknown fields, not just missing fields | If `deny_unknown_fields` is absent, extra keys sneak in without error; not fail-closed for schema drift | A test with an extra unknown field must fail validation | Needs AT |
| 4 | The loader exits non-zero on ANY validation failure, not just some | If certain validation paths log a warning but return exit code 0, malformed policy silently passes | `test_machine_policy_loader_and_config` malformed case must assert non-zero exit | Needs AT |
| 5 | The Rust runtime refuses to start (or enters ReduceOnly) if policy is absent at startup -- not just "logs a warning and continues with defaults" | If the runtime has a fallback default policy, the loader is cosmetic and the P0-F guarantee is doc-only | `test_policy_is_required_and_bound_runtime` must prove startup fails or ReduceOnly when policy file is missing | Needs AT |
| 6 | **[CR-A]** The policy schema is forward-compatible: when future stories (S2.2 PolicyGuard, etc.) add new required fields to `config/policy.json`, the strict loader (`deny_unknown_fields` / `additionalProperties: false`) will reject policy files written for a newer schema version. Conversely, a newer loader will reject old policy files missing newly-required fields. Schema evolution must be managed by updating the loader and policy file in lockstep. | If the loader and policy file are deployed out of sync (e.g., new loader, old policy file), the strict loader rejects the valid-but-old policy and the runtime cannot start. This is fail-closed (good) but could cause a deployment outage if the update is not atomic. Conversely, if `deny_unknown_fields` is enforced, a policy file containing fields from a future story will be rejected by the current loader, blocking forward deployment. | Test that documents the current schema version and asserts that adding an unknown field is rejected (proving strictness) AND that all currently-required fields are present (proving completeness). Schema migration path must be documented when fields are added in future stories. | Needs AT |
| 7 | **[CR-A]** The policy file validated by the Python loader is the same content consumed by the Rust runtime (no TOCTOU race). The Python loader validates `config/policy.json` at CI/build time, then the Rust runtime reads the same file at startup. If the file is modified, replaced, or is a symlink that changes between validation and runtime consumption, the runtime loads unvalidated content. | If an attacker or misconfiguration changes the file between Python validation and Rust consumption, the runtime operates on a policy that was never validated. Symlinks are particularly dangerous: `config/policy.json` could be a symlink to `/tmp/attacker_policy.json` that changes after validation passes. | For Phase 0, this is an accepted risk: the loader and runtime run in the same CI/test context with no intervening mutation. For production, the mitigation is: (1) the Rust runtime should re-validate or checksum the policy at load time, or (2) the policy file should be read-only with restricted permissions. Track as future hardening, not a Phase 0 blocker. | Deferred (Phase 1+ hardening) |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **Loader accepts empty JSON `{}`** -- passes validation because no required fields are enforced; runtime operates on an empty policy, which downstream code interprets as "no restrictions" | The system trades with no policy constraints; no error surfaced until a real incident | Loader MUST validate required fields exist and are non-empty; schema MUST have required field list; test MUST supply `{}` and assert non-zero exit | `test_machine_policy_loader_and_config` (malformed case) |
| 2 | **Policy path not actually bound at runtime** -- the Python loader validates `config/policy.json` but the Rust binary reads policy from a different source (e.g., Commander push, env var, or embedded default); the loader is "paper-only" | Everything looks green in CI but the runtime never reads the validated file; PolicyGuard consumes stale/default policy | Runtime test MUST prove that the same file path validated by the loader is the path consumed by the Rust binary; removing the file MUST cause runtime failure | `test_policy_is_required_and_bound_runtime` |
| 3 | **Loader has a `--lenient` or `--allow-empty` flag** that becomes the default in CI or is passed in the meta-test invocation -- strict mode exists but is never actually exercised | The "strict" validation is dead code; all CI runs use lenient mode; malformed policy passes | Meta-test MUST invoke the loader in its strictest mode (no flags that weaken validation); test MUST assert that the invocation uses strict mode explicitly | `test_machine_policy_loader_and_config` (meta-test path) |
| 4 | **Malformed policy causes a Python exception that is caught and swallowed** -- the loader has a `try/except Exception: pass` or returns exit code 0 in a finally block, masking the validation failure | Exit code is always 0 regardless of validation outcome; malformed policy appears to validate successfully | Every exception path MUST propagate to a non-zero exit code; no bare `except` without re-raise; test MUST supply multiple malformed variants (truncated JSON, wrong types, missing required keys) and assert non-zero for each | `test_machine_policy_loader_and_config` (malformed case) |
| 5 | **Runtime Rust test mocks the policy instead of loading from disk** -- the test constructs a valid policy struct in memory and never exercises the actual file-to-parse-to-validate pipeline, so it passes even if the real loader is broken | The test proves the struct is valid, not that the file loading works; a broken loader path is invisible | Runtime test MUST exercise the actual file I/O path: read from a real file on disk, parse, validate; mock-only tests MUST NOT count as proof of P0-F | `test_policy_is_required_and_bound_runtime` |
| 6 | **[CR-B] Loader validates schema but not value ranges** -- policy file has all required fields with correct types but semantically dangerous values (e.g., `max_position_usd: 999999999`, `max_order_rate_per_sec: 0`, `max_policy_age_sec: -1`). Structural validation passes; the runtime operates on a policy that is technically valid but effectively removes all safety limits or makes the system inoperable | No error surfaced by the loader; PolicyGuard consumes a policy with absurd values. A zero rate limit halts trading entirely; an unbounded position limit removes risk protection | For Phase 0: Document explicitly that value-range validation is OUT OF SCOPE for the baseline loader. The loader validates structure and types only. Range validation is deferred to PolicyGuard (S2.2) which applies domain-specific checks at runtime. Add a debt item tracking the gap. For implementation: consider adding optional range checks for obviously dangerous values (negative numbers, zero where positive is required) as a defense-in-depth measure, but do not block the story on full domain validation. | Deferred to S2.2 PolicyGuard (debt item added to S10) |
| 7 | **[CR-A] TOCTOU: policy file changes between Python validation and Rust consumption** -- the Python loader validates `config/policy.json` at CI/build time, the file is modified (or symlink target changes) before the Rust runtime reads it at startup. The runtime loads content that was never validated. | Runtime operates on unvalidated policy; all loader guarantees are void. Particularly dangerous with symlinks or shared filesystems where the file can be swapped atomically. | For Phase 0: accepted risk (CI/test context, no intervening mutation). For production: Rust runtime should either re-validate the policy content at load time or verify a checksum/hash produced by the Python loader. Track as hardening debt for Phase 1+. | Deferred (Phase 1+ hardening) |

## 4) Open decisions (resolve before coding)

### Decision: Schema strictness level for `config/policy.json`
- **What is ambiguous / missing**: CONTRACT.md P0-F says "strict loader" but does not define what fields the policy schema must contain, nor whether unknown fields are rejected. The `python_policy` input in S2.2 references a "latest policy payload" but the schema of that payload is not specified in the P0-F clause.
- **Evidence**: CONTRACT.md line 131: "Bind a machine-readable policy path + strict loader so runtime checks are not doc-only". S2.2 lists `python_policy` as an input but does not specify its schema for Phase 0.
- **Options**:
  1. Option A -- Define a minimal required schema (e.g., at least one required field like `version` or `trading_mode`) and reject unknown fields (`deny_unknown_fields` equivalent). Blast radius: minimal; blocks only truly invalid files. Verification: test with empty JSON, missing required fields, extra fields.
  2. Option B -- Accept any valid JSON that parses without error. Blast radius: very loose; `{}` passes. Verification: only test JSON parse, not semantic validity.
- **Chosen**: A -- "strict loader" in the contract implies semantic validation, not just syntactic JSON parsing. A loader that accepts `{}` is not "strict" in any meaningful sense.
- **Why not others**: Option B makes the loader a JSON syntax checker, not a policy validator. The entire purpose of P0-F is to prevent doc-only checks. A loader that accepts empty JSON is effectively doc-only.
- **Scope control**:
  - What we're NOT doing yet: Full runtime PolicyGuard integration, policy staleness checks (`max_policy_age_sec`), live policy hot-reload.
  - What unblocks us if this choice is wrong: Schema can be relaxed later; strictness only fails safe.

### Decision: What constitutes "malformed" in the acceptance criteria
- **What is ambiguous / missing**: The acceptance criterion says "GIVEN a malformed policy file WHEN strict loader runs THEN validation fails closed with non-zero exit code" but does not enumerate malformation types.
- **Evidence**: PRD acceptance criteria item 2.
- **Options**:
  1. Option A -- Test a single malformation (e.g., invalid JSON syntax only).
  2. Option B -- Test multiple categories: (a) not valid JSON, (b) valid JSON but missing required fields, (c) valid JSON but wrong types, (d) empty file, (e) empty JSON object `{}`.
- **Chosen**: B -- A single malformation test is trivially gameable. Wrong-impl gate (S5) shows that accepting `{}` is the most dangerous failure mode.
- **Why not others**: Option A leaves the most critical failure mode (structurally valid but semantically empty JSON) untested.
- **Scope control**:
  - What we're NOT doing yet: Fuzzing, property-based testing of arbitrary JSON.
  - What unblocks us if this choice is wrong: Adding more malformation cases is additive, not breaking.

### Decision: Python loader vs Rust loader ownership
- **What is ambiguous / missing**: Touch scope includes both `tools/policy_loader.py` (Python) and a Rust test (`test_policy_is_required_and_bound_runtime`). It is unclear whether the "strict loader" is the Python tool, the Rust code, or both.
- **Evidence**: CONTRACT.md P0-F evidence required: "`config/policy.json`, `tools/policy_loader.py`, passing tests". Touch scope: `tools/policy_loader.py`, `tools/phase0_meta_test.py`, plus a Rust integration test.
- **Options**:
  1. Option A -- Python loader is the canonical strict validator; Rust test just confirms the path is bound (file exists and is readable at runtime).
  2. Option B -- Both Python and Rust perform full schema validation independently.
- **Chosen**: A -- P0-F is a baseline story. The Python loader is the "strict loader" per the contract evidence list. The Rust test proves runtime path binding (the policy file is actually consumed, not ignored). Dual validation is a later concern.
- **Why not others**: Option B is over-scoped for a Phase 0 baseline; schema duplication across languages is a maintenance hazard.
- **Scope control**:
  - What we're NOT doing yet: Rust-side schema validation (that is PolicyGuard's job in later stories).
  - What unblocks us if this choice is wrong: Adding Rust-side validation is additive.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

Since there are no formal AT-XXX IDs, the wrong-impl analysis is against the three story-level acceptance criteria (AC-1, AC-2, AC-3):

| AC | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AC-1 (valid policy exits 0) | Loader ignores the file entirely, always exits 0 (`sys.exit(0)` unconditionally) | "Validation" is a no-op; any file (including malformed) passes; no actual loading occurs | AC-2 tightens: malformed file MUST exit non-zero. But: also need a test that verifies the loader actually reads and parses the file content (e.g., assert parsed fields match expected values from a known-good fixture) |
| AC-1 (valid policy exits 0) | Loader parses JSON but does not validate schema -- just checks `json.loads()` succeeds | `{}` passes, missing required fields pass; no semantic validation | Add golden vector: supply `{}` as input, assert non-zero exit. Supply file with wrong types for required fields, assert non-zero exit |
| AC-2 (malformed exits non-zero) | Loader only rejects syntactically invalid JSON (truncated, bad encoding) but accepts any valid JSON object regardless of content | `{}`, `{"foo": "bar"}`, and any structurally-valid-but-semantically-wrong policy all pass | Add test cases: (1) empty object `{}`, (2) object with required keys but wrong types, (3) object with all keys but values out of range. All must exit non-zero |
| AC-2 (malformed exits non-zero) | Loader catches the validation error but prints a warning and exits 0 (error swallowed in except block) | CI shows "WARN: validation failed" but exit code is 0; caller sees success | Test MUST assert exit code, not just log output. Add: verify no `except Exception: pass` pattern in loader source |
| AC-3 (meta-test passes) | Meta-test passes because it tests a mock/stub instead of the real loader invocation | The real loader could be broken but the meta-test never exercises it | Meta-test MUST invoke the actual `policy_loader.py` as a subprocess (or equivalent); MUST NOT construct a mock policy in-memory and validate that |
| AC-3 (meta-test passes) | Meta-test calls the loader but with a `--lenient` flag, so "strict validation" is never exercised | Strict mode is dead code; only lenient mode is tested | Meta-test MUST assert the invocation uses strict mode; add a test that verifies `--lenient` (if it exists) is NOT passed |
| (cross-cutting) | Python loader validates correctly, but Rust runtime ignores the policy file entirely -- reads policy from Commander push or has a hardcoded default | The loader is a CI-only check with no runtime effect; P0-F's purpose ("not doc-only") is violated | `test_policy_is_required_and_bound_runtime` MUST prove: (1) removing the policy file causes the Rust runtime to fail/ReduceOnly, (2) the path used at runtime matches the path validated by the loader |
| AC-3 (meta-test passes) **[CR-B]** | Meta-test validates a test fixture file (e.g., `tests/fixtures/policy.json` or an inline JSON blob) instead of the canonical `config/policy.json` checked into the repo | The meta-test proves the loader works against a known-good fixture, but the actual `config/policy.json` in the repo could be malformed or missing required fields. CI is green while the real policy file is broken. | Meta-test MUST validate the canonical `config/policy.json` path (not a test fixture). If the meta-test also tests malformed cases, those can use fixtures, but at least one valid-case assertion MUST target the real policy file. Add assertion: the path passed to the loader in the meta-test's valid case is literally `config/policy.json` (or the canonical path constant). |
| AC-2 (malformed exits non-zero) **[CR-B]** | Loader validates schema structure and types but accepts semantically dangerous values (e.g., `max_position_usd: 999999999` or `max_order_rate_per_sec: 0`) | Policy is structurally valid but operationally dangerous; the loader gives a false sense of safety. No range check catches values that effectively disable safety limits or make the system inoperable. | For Phase 0: explicitly document that range validation is out of scope and add to debt register. For tightening: add at least one golden vector with an obviously dangerous value (e.g., negative `max_policy_age_sec`) and assert non-zero exit IF range checks are in scope, or assert exit 0 with a logged warning IF range checks are deferred. The key is making the scope decision explicit, not silent. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

> **Proof graph (v1.7)**: This section's data feeds `proof_graph.json`. After implementation, run
> `python3 python/proof_graph/scaffold.py <STORY_ID>` to generate the skeleton, then fill in
> verdicts, test names, and wiring status. The validator (`validate.py --strict`) enforces
> consistency at pass-flip time. See `python/proof_graph/` for schema details.

Since there are no formal AT-XXX IDs, the proof plan maps the three acceptance criteria and two implementation tests:

| AC / Test | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AC-1 (valid -> exit 0) | PolicyLoader (Python tool) | `test_machine_policy_loader_and_config` | N/A (tooling, not runtime gate) | N/A | Exit code == 0 when valid policy supplied | Yes |
| AC-2 (malformed -> non-zero) | PolicyLoader (Python tool) | `test_machine_policy_loader_and_config` | N/A | N/A | Exit code != 0 when malformed policy supplied | Yes |
| AC-3 (meta-test passes) | Phase0MetaTest (orchestrator) | `test_machine_policy_loader_and_config` (in phase0_meta_test.py) | N/A | N/A | Meta-test invokes loader and asserts pass | Yes |
| Runtime binding | RuntimePolicyBinding (Rust startup) | `test_policy_is_required_and_bound_runtime` | YES (policy absent -> runtime fails/ReduceOnly) | YES (policy present -> runtime starts normally) | TRIP: missing file -> non-zero exit or ReduceOnly. NON-TRIP: valid file -> successful startup | Yes |

Note: The runtime binding test (`test_policy_is_required_and_bound_runtime`) is the only test with TRIP/NON-TRIP semantics because it tests a runtime enforcement point. The Python loader tests are structural (tool invocation).

**Causality for runtime binding:**
- TRIP: Remove `config/policy.json` -> Rust runtime MUST fail to start OR enter ReduceOnly. This proves the runtime actually reads the file.
- NON-TRIP: Provide valid `config/policy.json` -> Rust runtime starts successfully. This proves the file path is correct and the valid case works.
- The causality proof is: the ONLY difference between TRIP and NON-TRIP is the presence/absence of the policy file. If both fail or both pass, the test is broken.

Causality proof for this story uses `exit_code` (not `dispatch_count`/`reject_reason`/`latch_reason`/`cortex_override`), which is appropriate for a Phase 0 infrastructure story that does not yet have a runtime dispatch loop.

- [x] Every safety-critical AT has TRIP + NON-TRIP -- Yes (runtime binding test)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: N/A -- this is a Phase 0 infrastructure story. No trading logic exists at this stage. However, a broken policy loader in a future state would mean PolicyGuard operates on invalid/empty policy, potentially allowing unrestricted trading. The indirect risk is high but is gated by later stories (S2.2 PolicyGuard).
- **Fail-closed cap on loss**: N/A -- no trading capability exists at P0-F time. In the future, the fail-closed cap is PolicyGuard's `REDUCEONLY_INPUT_MISSING_OR_STALE` (S2.2.1.1) which would catch a missing policy at runtime even if the loader fails.
- **Drift metric**: N/A -- structural artifact. In a future state, `policy_age_sec > max_policy_age_sec` (Appendix A: 300s) would be the drift metric for stale policy.
- **Loss boundary**: N/A.
- **Rollback plan**: `git revert` the implementation commit. The policy loader is a standalone Python tool; removing it has no cascading effect on existing functionality.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None directly. P0-F establishes the policy file that will later feed PolicyGuard (S2.2). The loader itself is not a runtime gate -- it is a build-time/CI-time validation tool.
- **If conflict with CONTRACT.md**: No conflict. P0-F is explicitly listed as a Non-Negotiable Phase 0 prerequisite. The implementation aligns with "bind a machine-readable policy path + strict loader."
- Files with recent churn or shared ownership:
  - `config/policy.json` -- may be edited by other stories that add policy fields.
  - `tools/phase0_meta_test.py` -- shared across multiple Phase 0 stories; adding a new test function should not conflict.
- **[CR-B, CR-A] S0-004 alignment dependency**: If `config/policy.json` includes a `trading_mode_default` field (or similar), the string values in the policy schema MUST match the `TradingMode` enum variant names defined by S0-004 (P0-E Health + Owner Status Scaffolding). For example, if S0-004 defines `TradingMode::Active` and the status endpoint serializes it as `"Active"`, then the policy schema must accept `"Active"` (not `"active"`, not `"ACTIVE"`). A mismatch causes deserialization failure at runtime -- which is fail-closed (safe) but creates a confusing deployment error. The policy schema's enum values should be validated against S0-004's `TradingMode` enum definition before implementation. This is a cross-story constraint that neither premortem originally tracked.
- Struct fields I'm assuming exist: None -- this is Python tooling + a Rust integration test. No struct dependencies. However, see S0-004 alignment note above: if the policy references `TradingMode` values, the enum must exist and its serialized form must match.
- State machine transitions affected: None.

## 9) Constraint I expect to hit

> The supervisor injects the prior postmortem path. Read section 8 (Next-Story Startup Note).

Prior Postmortem: NONE
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A (no prior postmortem for this story).
- What will slow me down: Defining the "right" schema for `config/policy.json` at this early stage. The policy schema will evolve as S2.2 PolicyGuard is implemented. Over-specifying now creates maintenance burden; under-specifying defeats the purpose of "strict loader."
- Exploit: Define a minimal schema with only the fields absolutely required at Phase 0 (e.g., `version`, `trading_mode_default` or equivalent baseline fields). Use `additionalProperties: false` / `deny_unknown_fields` equivalent to prevent drift. Schema can be extended in later stories.
- Smallest fix that prevents it next time: Document the policy schema in a JSON Schema file (or equivalent) alongside `config/policy.json` so the schema is machine-readable, not just embedded in loader code.

**[CR-A] Schema evolution constraint**: When `deny_unknown_fields` is active, every future story that adds a policy field must update both the schema definition and all existing policy files atomically. This is by design (strict lockstep prevents drift), but it means S0-005's loader will be a friction point for every schema change. The exploit above (minimal schema + JSON Schema file) mitigates this: the schema file is the single source of truth, and future stories extend it rather than fighting embedded validation logic.

**[CR-B] Debt sink warning**: S0-005 is receiving deferred items from at least three other stories:
- S0-000 defers "machine-readable policy format" to P0-F
- S0-002 defers "policy path binding proof" concerns to P0-F
- S0-003 defers "policy-absent runtime behavior" questions to P0-F

This makes S0-005 a debt sink. The story's scope must remain disciplined: it owns the loader baseline (schema validation + runtime path binding), NOT the full policy domain model, NOT value-range enforcement, NOT cross-story integration testing. Items deferred from other stories that fall outside this scope should be redirected to S2.2 (PolicyGuard) or tracked as standalone follow-up items, not silently absorbed into S0-005. If implementation reveals that absorbed debt pushes the story beyond its touch scope, STOP and re-scope rather than expanding silently.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: Five gaps explicitly deferred (2 original + 3 from cross-review findings):

**Debt Register** (required if YELLOW, DEFERRED items tracked):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| No formal AT-XXX in CONTRACT.md for P0-F | Medium | P0-F is in the Phase 0 table but has no formal acceptance test anchors (AT-XXX) in CONTRACT.md. The story relies on implementation tests only. | Story implementor | S0-005 or follow-up contract patch | Add AT-XXX anchors to CONTRACT.md for P0-F: (1) valid policy loads with exit 0, (2) malformed policy rejects with non-zero exit, (3) runtime path binding proven |
| `enforcing_contract_ats` is empty in prd.json | Low | Cannot trace story to contract acceptance tests because none exist yet. Traceability chain is broken at the AT link. | Story implementor | S0-005 or follow-up PRD patch | Populate `enforcing_contract_ats` after AT-XXX anchors are added to CONTRACT.md |
| **[CR-B]** Value-range validation not enforced by loader | Medium | The strict loader validates structure and types but does not check that numeric values are within safe/sane ranges (e.g., rejects negative `max_policy_age_sec`, zero `max_order_rate_per_sec`, absurdly large `max_position_usd`). Structurally valid but semantically dangerous policy passes silently. | S2.2 PolicyGuard implementor | S2.2 (PolicyGuard) | Add range-check tests: negative values, zero-where-positive-required, values exceeding sane upper bounds. PolicyGuard MUST validate ranges at runtime even if the loader does not. |
| **[CR-A]** TOCTOU gap between Python validation and Rust consumption | Low | DEFERRED: Policy file could change between CI-time Python validation and runtime Rust consumption. Accepted for Phase 0 (same CI context, no mutation window). Requires hardening for production. | Phase 1+ implementor | Phase 1 production hardening | Rust runtime re-validates or checksums policy at load time; or policy file is read-only with restricted permissions. |
| **[CR-B]** Meta-test may validate fixture instead of canonical policy | Medium | If the meta-test uses a test fixture file rather than the real `config/policy.json`, the canonical policy file is never validated in CI. | Story implementor | S0-005 | Meta-test valid-case assertion MUST target the canonical `config/policy.json` path, not a test fixture. |

YELLOW with untracked debt (no target slice) = RED. All items above have target slices (resolved check).

**Exit criteria (definition of done, before I start):**
- [x] S1 clause audit: every AT traced to normative clause -- N/A (no ATs; DEFERRED gap tracked in debt register)
- [x] S2 all assumptions validated or killed -- 7 assumptions identified (5 original + 2 from cross-review: schema evolution, TOCTOU), each has a corresponding test requirement or explicit deferral (resolved via explicit deferral)
- [x] S3 all failure modes have detection + mitigation -- 7 failure modes with mitigations (5 original + 2 from cross-review: value-range validation, TOCTOU race)
- [x] S4 all decisions resolved, grounded in evidence -- 3 decisions resolved
- [x] S5 wrong impl gate: every AT tightened, no easy wrong impl survives -- 9 wrong impls identified with tightenings (7 original + 2 from cross-review: meta-test fixture risk, value-range passthrough), mitigated
- [x] S6 proof plan: TRIP + NON-TRIP for runtime binding test; structural tests for Python loader
- [x] S7 loss_mode documented with fail-closed boundary + rollback plan
- [x] S8 conflict scan clean (no CONTRACT.md conflicts); S0-004 TradingMode alignment dependency documented
- [x] No new debt without owner + target slice -- 5 debt items total (2 original + 3 from cross-review), all with owners and target slices (resolved)
