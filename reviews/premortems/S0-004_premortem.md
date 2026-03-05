# Story Premortem: S0-004

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-004 — P0-E Health + Owner Status Scaffolding
- Contract clause(s): §7.0 Owner Control Plane Endpoints (Read-Only, Owner-Grade), Phase 0 table (P0-E)
- Acceptance tests: AT-022
- Touch scope: `docs/health_endpoint.md`, `crates/soldier_infra/src/lib.rs`
- **Risk rating**: LOW
  - Scaffolding only — data model structs and derivation logic, no HTTP endpoint, no trading logic, no safety gates.
  - PRD explicitly states: "Scaffolding only — provides CLI status data model, not HTTP endpoint. Full AT-022 enforcement in S8-008."

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-022 | §7.0 | "Given: service is running. When: `GET /api/v1/health`. Then: HTTP 200 and keys `ok`, `build_id`, `contract_version` exist with `ok == true`." | MUST (Required) | Yes — HTTP response key/value assertions |

**CRITICAL TENSION identified:** AT-022 as written in CONTRACT.md §7.0 requires an HTTP `GET /api/v1/health` endpoint returning HTTP 200 with JSON payload containing `ok`, `build_id`, `contract_version`. However, the PRD story S0-004 explicitly says "scaffolding only — provides CLI status data model, not HTTP endpoint. Full AT-022 enforcement in S8-008." This means S0-004 claims AT-022 as an enforcing AT but the story scope explicitly excludes the HTTP transport layer that AT-022 specifies. The story can prove the data model produces correct fields but cannot prove the HTTP contract.

Additionally, the P0-E row in the Phase 0 table (CONTRACT.md line ~130) requires `trading_mode` and `is_trading_allowed` in the owner status output. These are NOT part of AT-022 (which covers only `/health` with `ok`, `build_id`, `contract_version`). The owner status fields are tested by story acceptance criteria 2-4 but lack a formal AT anchor in CONTRACT.md §7.0.

- [x] Every claimed AT traced to a normative clause
- [ ] No informational-only ATs counted as enforcement — **FLAG**: AT-022 is normative but S0-004 can only partially satisfy it (HTTP transport deferred to S8-008). This is partial enforcement, tracked in Debt Register (§10).

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | `contract_version` has canonical value `"5.2"` (CONTRACT.md Definitions: "canonical version string `5.2` (numeric only; no codename/tagline)") | If scaffolding hardcodes wrong format (e.g., `"v5.2"`, `"5.2.0"`, `"5_2"`), later F1_CERT binding (§2.2.1) fails with perpetual ReduceOnly | Unit test: `assert_eq!(health.contract_version, "5.2")` — exact string match | Must verify |
| 2 | `build_id` is injected as a non-empty string at construction time | If `build_id` is empty or placeholder, health output is technically compliant (key exists) but operationally useless; F1_CERT binding in later stories will break | Unit test: `assert!(!health.build_id.is_empty())` on constructed struct | Must verify |
| 3 | `TradingMode` enum is available (defined in `soldier_core` or `soldier_infra`) with variants `Active`, `ReduceOnly`, `Kill` | If the enum does not exist yet or has different variant names, owner status cannot derive `is_trading_allowed` | Compilation + type-level test | Depends on prior story ordering; verify before coding |
| 4 | `is_trading_allowed` is strictly derived: `true` iff `TradingMode::Active`; `false` for `ReduceOnly` and `Kill` | If derivation is inverted or `ReduceOnly` maps to `true`, operators get false confidence | Table-driven unit test: `Active->true`, `ReduceOnly->false`, `Kill->false` | Must verify |
| 5 | "CLI status data model" means Rust structs with serde serialization, not a runnable CLI binary | If the story expects an actual CLI subcommand (e.g., `soldier status`), scope is much larger than anticipated | PRD description says "provides CLI status data model" — interpret as struct definition | Scope clarification |
| 6 | Serde serialization produces JSON field names matching CONTRACT.md exactly: `ok`, `build_id`, `contract_version`, `trading_mode`, `is_trading_allowed` (all snake_case) | If serde rename attributes (e.g., `#[serde(rename_all = "camelCase")]`) are applied, or if Rust field names differ from contract-mandated JSON keys (e.g., `buildId` instead of `build_id`, `tradingMode` instead of `trading_mode`), the serialized output silently diverges from CONTRACT.md §7.0 and the P0-E table. S8-008 or external consumers parsing the JSON will fail or misinterpret fields. This is especially insidious because Rust's default serde behavior (use field name as-is) happens to match snake_case for these fields, but a single `#[serde(rename_all = "camelCase")]` at the struct level would break ALL keys at once. | Golden-vector test: serialize struct to JSON string, assert exact key names via `serde_json::to_value()` and check `.as_object().unwrap().contains_key("trading_mode")` etc. No `#[serde(rename)]` attributes unless they produce the exact CONTRACT.md key names. | Must verify |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | `contract_version` hardcoded as wrong string (e.g., `"v5.2"` instead of `"5.2"`) | F1_CERT binding mismatch (§2.2.1) in later stories forces perpetual ReduceOnly | Unit test asserting exact string `"5.2"` matches CONTRACT.md Definitions | AT-022 (partially: checks key exists; does not mandate exact value); golden vector tightens this |
| 2 | `is_trading_allowed` derivation wrong — returns `true` for `ReduceOnly` | Operator trusts system is actively trading when it should be restricted; delayed incident response | Table-driven test covering all three `TradingMode` variants with explicit expected values | Story acceptance criteria 3+4 (no formal AT anchor in §7.0) |
| 3 | Health/status structs exist but are never exported (private visibility) — dead code | S8-008 cannot import/use the structs; AT-022 remains unimplementable at HTTP layer | Test that constructs structs from outside the defining module (validates `pub` visibility) | No AT catches dead-code scaffolding directly |
| 4 | `build_id` returns empty string or constant placeholder `"unknown"` in all environments | Passes key-existence check. Production binary would have wrong `build_id`, breaking F1_CERT binding (§2.2.1) | Unit test: `build_id` must be non-empty; constructor must reject empty string or test asserts non-empty | AT-022 (checks key exists, not value quality) |
| 5 | Owner status struct lacks `trading_mode` field or uses `String` instead of `TradingMode` enum | Downstream consumers (S8-008) must re-derive or cast; type-safety lost; schema drift risk | Type-level assertion: struct field `trading_mode: TradingMode` (not `String`); serde serialization test | No formal AT; only story acceptance criteria |

## 4) Open decisions (resolve before coding)

### Decision: What does "scaffolding" mean concretely?
- **What is ambiguous / missing**: PRD says "CLI status data model, not HTTP endpoint" but AT-022 requires `GET /api/v1/health` returning HTTP 200. Story must decide what artifact it produces.
- **Evidence**: PRD `description` field: "Scaffolding only — provides CLI status data model, not HTTP endpoint. Full AT-022 enforcement in S8-008." CONTRACT.md §7.0 AT-022: "When: `GET /api/v1/health`. Then: HTTP 200..."
- **Options**:
  1. Option A — Produce only the data model structs (`HealthResponse`, `OwnerStatus`) with unit tests proving field presence, types, serialization, and derivation logic. AT-022 is CLAIMED-NOT-PROVEN until S8-008 wires the HTTP endpoint. Tests exercise struct construction only.
  2. Option B — Produce both data model structs AND a minimal HTTP endpoint (e.g., axum handler) that satisfies AT-022 fully. This exceeds PRD scope but closes the AT gap.
- **Chosen**: A — the PRD explicitly scopes out HTTP. AT-022 must be tracked as partially proven (data model only) with S8-008 completing the proof.
- **Why not others**: Option B violates PRD scope boundaries ("not HTTP endpoint") and pulls in HTTP framework dependencies (axum/warp/actix) prematurely into Phase 0.
- **Scope control**:
  - What we're NOT doing yet (subordinate): HTTP server, endpoint routing, integration test with actual HTTP request/response cycle.
  - What unblocks us if this choice is wrong (elevate): S8-008 is the designated completion story for full AT-022 enforcement.

### Decision: Where does `contract_version` come from?
- **What is ambiguous / missing**: CONTRACT.md Definitions says `contract_version` is canonical string `"5.2"`. The scaffolding must decide whether to hardcode, define as const, or read from config.
- **Evidence**: CONTRACT.md Definitions (line ~90): "contract_version: canonical version string `5.2` (numeric only; no codename/tagline)." §2.2.1 (line ~1880): F1_CERT binding requires `F1_CERT.contract_version == runtime.contract_version`. v5.2 WARNING (line ~31): "ALL components that produce or consume `contract_version` MUST be updated to `5.2` in lockstep."
- **Options**:
  1. Option A — Define `pub const CONTRACT_VERSION: &str = "5.2";` in a shared location and reference it everywhere. Compile-time constant ensures lockstep updates.
  2. Option B — Read from a config file at runtime. Allows flexibility but permits config-drift.
- **Chosen**: A — a compile-time constant ensures lockstep per the v5.2 WARNING and prevents config-binary version mismatch.
- **Why not others**: Option B allows config and binary to disagree, which is exactly the failure mode §2.2.1 binding is designed to catch.
- **Scope control**:
  - What we're NOT doing yet: F1_CERT binding validation (§2.2.1 / later stories).
  - What unblocks us if this choice is wrong: the const can be re-exported or relocated later without contract violation.

### Decision: Where does `build_id` come from?
- **What is ambiguous / missing**: `build_id` is defined as "immutable build identifier for the running binary (e.g., git commit SHA)" per §2.2.1 (line ~1878). The scaffolding must decide injection mechanism.
- **Evidence**: CONTRACT.md §2.2.1: "`build_id`: immutable build identifier for the running binary (e.g., git commit SHA)."
- **Options**:
  1. Option A — Inject via `env!("BUILD_ID")` or `option_env!("BUILD_ID")` set by CI pipeline. Compile-time only.
  2. Option B — Use a `build.rs` script that captures `git rev-parse HEAD`. Automatic but adds build-time git dependency.
  3. Option C — Accept `build_id: String` as a constructor parameter (dependency injection). Testable, defers build-time binding to production wiring.
- **Chosen**: C — the data model struct accepts `build_id` as constructor arg. This keeps scaffolding testable with deterministic values. Production injection (A or B) is a later story concern.
- **Why not others**: Options A and B are production concerns; the scaffolding story should focus on the data model and derivation logic. Constructor injection makes unit tests deterministic and isolated.
- **Scope control**:
  - What we're NOT doing yet: actual git SHA injection at build time, CI pipeline integration.
  - What unblocks us if this choice is wrong: the struct accepts any `String`; production wiring is independent of the data model.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-022 | Struct has fields `ok`, `build_id`, `contract_version` but `ok` is a hardcoded `const true` with no way to ever be `false` | For S0-004, `ok=true` when process is up IS correct per AT-022. But if `ok` is a compile-time constant (not a field), it cannot reflect actual health in S8-008 | Golden vector: construct `HealthResponse` with `ok=false` and assert it serializes correctly. This proves the field is mutable, not const. |
| AT-022 | `contract_version` field exists but contains `""` or `"0.0"` or `"v5.2"` | Passes AT-022 "key exists" check but violates Definitions (must be `"5.2"` exactly). Later F1_CERT binding will fail silently until AT-012 is enforced | Golden vector unit test: `assert_eq!(health.contract_version, "5.2")` — exact string, no tolerance for prefix/suffix/format variation |
| AT-022 | `build_id` field exists but is always `"test"` or `""` in production | Passes key-existence check. Production binary would have wrong `build_id`, breaking F1_CERT binding | Unit test: constructor rejects or test asserts `build_id.len() > 0`. In S8-008, add integration test that `build_id` matches actual binary metadata |
| AT-022 | Health struct defined but never exported — `pub(crate)` or private | Struct exists in code, tests in same crate pass, but S8-008 in a different crate cannot import it | Visibility test: construct `HealthResponse` from an integration test (different crate boundary) or explicitly assert `pub` export in lib.rs |
| AT-022 (ACs 2-4) | `is_trading_allowed` derived correctly for `Active` and `Kill` but returns `true` for `ReduceOnly` | Off-by-one in match arm or wrong default; operator trusts ReduceOnly means trading is happening | Table-driven golden vector test: `Active->true`, `ReduceOnly->false`, `Kill->false`. All three variants must be explicitly tested — no wildcard `_ => false` that happens to work |
| AT-022 + P0-E | Struct field names are correct in Rust but serde serialization produces wrong JSON key names (e.g., `tradingMode` instead of `trading_mode`, `buildId` instead of `build_id`) due to `#[serde(rename_all = "camelCase")]` or individual `#[serde(rename = "...")]` attributes | Unit tests that check struct field values in Rust pass correctly, but serialized JSON output has wrong key names. S8-008 wires the struct to HTTP and the endpoint returns JSON that does not match CONTRACT.md §7.0 key names. External consumers and watchdog tooling silently fail to parse. Tests pass because they never check the serialized JSON keys — they only check Rust field values. | Golden-vector serialization test: construct struct, serialize to `serde_json::Value`, assert exact JSON key names match CONTRACT.md: `"ok"`, `"build_id"`, `"contract_version"`, `"trading_mode"`, `"is_trading_allowed"`. This catches both missing keys and renamed keys. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

> **Proof graph (v2)**: This section's data feeds `proof_graph.json`. After implementation, run
> `python3 python/proof_graph/init.py S0-004 --premortem-dir artifacts/story/S0-004/` to generate the skeleton, then fill in
> verdicts, test names, and wiring status. The validator (`validate.py --strict`) enforces
> consistency at pass-flip time. See `python/proof_graph/` for schema details.

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-022 (partial) | StatusEndpoint (data model only; no HTTP) | Unit test: construct `HealthResponse{ok: true, build_id: "abc123", contract_version: "5.2"}`, assert all fields present and correct | N/A (no runtime gate) | N/A (no runtime gate) | Field-value assertion on constructed struct | Yes |
| Story AC-2 | StatusEndpoint (data model) | Unit test: construct `OwnerStatus` from `TradingMode`, assert `trading_mode` and `is_trading_allowed` fields present | N/A | N/A | Field-value assertion | Yes |
| Story AC-3 | StatusEndpoint (data model) | Unit test: `OwnerStatus::from(TradingMode::Active)` yields `is_trading_allowed == true` | N/A | N/A | Direct assertion on derived boolean | Yes |
| Story AC-4 | StatusEndpoint (data model) | Unit test: `OwnerStatus::from(TradingMode::ReduceOnly)` yields `is_trading_allowed == false`; `OwnerStatus::from(TradingMode::Kill)` yields `is_trading_allowed == false` | N/A | N/A | Direct assertion on derived boolean | Yes |

**Note on TRIP/NON-TRIP**: This story is pure scaffolding — there is no runtime enforcement point that "trips" to block trading. The StatusEndpoint enforcement point produces output data; it does not gate dispatch. TRIP/NON-TRIP becomes meaningful in S8-008 when the HTTP endpoint is live and watchdog tooling can query it.

**CLAIMED-NOT-PROVEN**: AT-022 is claimed by this story but cannot be fully proven because the AT requires HTTP `GET /api/v1/health` returning HTTP 200, which is out of scope. The data model tests prove the payload would be correct IF wired to an HTTP handler. Full proof deferred to S8-008.

Causality proof note: the standard proof methods (`dispatch_count`, `reject_reason`, `latch_reason`, `cortex_override`) do not apply to a read-only data model scaffolding story. Proof is structural: field-value assertions on constructed structs.

- [ ] Every safety-critical AT has TRIP + NON-TRIP — N/A (not safety-critical; read-only scaffolding)
- [x] Every test proves causality (not just existence) — field-value assertions, not just key-existence
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix — AT-022 CLAIMED-NOT-PROVEN tracked with S8-008 as completion target in Debt Register

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Health endpoint returns stale/wrong status. Operator trusts bad state and delays incident response. However, this story only produces the data model — no HTTP endpoint serves it yet. The actual economic risk materializes only when S8-008 wires the endpoint. At the scaffolding level, the risk is that a wrong data model (e.g., `is_trading_allowed=true` when `ReduceOnly`) propagates into production via S8-008 uncaught.
- **Fail-closed cap on loss**: StatusEndpoint health check; no direct trading impact. §7.0 states: "This endpoint MUST NOT allow changing risk. No 'set Active' endpoints in this patch." Read-only data model has zero ability to mutate trading state.
- **Drift metric**: `health_endpoint_latency_ms p99 < 100ms` (only meaningful after S8-008 wires HTTP). For scaffolding: compile-time const correctness (`contract_version == "5.2"`) is the drift-prevention mechanism.
- **Loss boundary**: No trading impact. Worst case is operator misinformation leading to delayed manual intervention. No position limit, no ReduceOnly trigger from this code.
- **Rollback plan**: `git revert` the scaffolding commit. No runtime state to clean up since there is no HTTP endpoint, no persistent state, and no trading logic.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None directly. This story creates data model structs that will later be consumed by §7.0 endpoints (S8-008) and §2.2.1 F1_CERT binding. The `contract_version` const will be shared with F1_CERT validation code.
- **If conflict with CONTRACT.md**: No conflict. P0-E explicitly calls for this scaffolding. The tension between AT-022 (requires HTTP) and PRD scope (no HTTP) is a deliberate scope deferral documented in the PRD description, not a contract violation.
- Files with recent churn or shared ownership:
  - `crates/soldier_infra/src/lib.rs` — likely shared with other infra stories; check for existing modules/structs before adding new ones.
  - `crates/soldier_infra/Cargo.toml` — may need `serde`/`serde_json` dependencies for serialization.
- Struct fields I'm assuming exist (verify before coding):
  - `TradingMode` enum in `soldier_core` — must be `Active | ReduceOnly | Kill` per CONTRACT.md Definitions. If not yet defined, this story may need to define it inline or depend on a prior story.
- **TradingMode enum source dependency (cross-review finding, Agent B):** Assumption 3 says "verify before coding" but does not resolve the dependency. Resolution: (a) If `TradingMode` already exists in `soldier_core`, import it via `use soldier_core::TradingMode;` from `soldier_infra`. (b) If `TradingMode` does not exist yet, S0-004 MUST define it in `soldier_core` (not `soldier_infra`) because `soldier_core` is the natural home for trading domain types and avoids circular dependencies when later stories in `soldier_core` need the enum. (c) If another S0 story (e.g., S0-003 break-glass) already defines it, coordinate to avoid duplicate definitions. The implementation must check `soldier_core` for existing `TradingMode` before creating a new one.
- **S0-005 schema alignment dependency (cross-review finding, Agent B):** S0-005 (Machine Policy Loader) may include a `trading_mode` or `trading_mode_default` field in `config/policy.json`. If S0-005 uses string values like `"active"` (lowercase) while S0-004 defines `TradingMode::Active` (PascalCase), deserialization between the two will fail silently or require custom serde logic. The enum variant names and their serde serialization format must be agreed upon across both stories. Mitigation: S0-004's golden-vector serialization test should assert the exact string representation of each `TradingMode` variant (e.g., `"Active"` not `"active"` not `"ACTIVE"`), and S0-005 must consume the same representation. If S0-005 is implemented first, its policy schema choices constrain S0-004's serde attributes.
- State machine transitions affected: None.

## 9) Constraint I expect to hit

> The supervisor injects the prior postmortem path. Read section 8 (Next-Story Startup Note).

Prior Postmortem: NONE
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A (no prior postmortem for this story).
- What will slow me down:
  1. The tension between AT-022 (HTTP endpoint) and PRD scope (CLI data model only). Must resist scope creep into HTTP while still proving the data model is correct and complete.
  2. Uncertainty about whether `TradingMode` is already defined in `soldier_core` or needs to be created/imported as part of this story. Cross-crate dependency ordering matters.
  3. Deciding where to place the `CONTRACT_VERSION` constant so it is importable by both `soldier_core` (for later F1_CERT binding) and `soldier_infra` (for health output). Circular dependency risk if placed wrong.
- Exploit: Define data model structs with `#[derive(Serialize, Debug, Clone)]` and comprehensive unit tests. Accept `build_id` and `TradingMode` as constructor parameters (dependency injection) to keep tests deterministic. Keep `CONTRACT_VERSION` as a `pub const` in whichever crate is lowest in the dependency graph.
- Smallest fix that prevents it next time: Document in the story postmortem which structs were created, their public API surface, and which crate exports `CONTRACT_VERSION`, so S8-008 knows exactly what to wire.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: AT-022 cannot be fully proven in this story because the HTTP transport is out of scope. The gap is explicitly documented by the PRD ("Full AT-022 enforcement in S8-008") and tracked in the Debt Register below. All other sections are complete. (DEFERRED rationale)

**Debt Register** (required if YELLOW, DEFERRED items tracked):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| AT-022 full HTTP proof | Medium | PRD S0-004 explicitly scopes out HTTP endpoint; "Full AT-022 enforcement in S8-008" | S8-008 implementor | S8-008 | Integration test: `GET /api/v1/health` returns HTTP 200 with `ok=true`, `build_id` non-empty, `contract_version=="5.2"`. Must test actual HTTP request/response, not just struct construction. |
| `is_trading_allowed` formal AT anchor | Low | No AT anchor in CONTRACT.md §7.0 for the `trading_mode`/`is_trading_allowed` derivation logic; only P0-E table row and story acceptance criteria cover it | S8-008 implementor or contract editor | S8-008 or contract patch | Add AT for owner status `is_trading_allowed` derivation: `Active->true`, `ReduceOnly->false`, `Kill->false` |

YELLOW with untracked debt (no target slice) = RED. All debt items have target slices assigned. (resolved check)

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed (resolved)
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN — AT-022 is CLAIMED-NOT-PROVEN with explicit S8-008 completion plan
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice (resolved)
