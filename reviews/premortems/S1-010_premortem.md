# Story Premortem: S1-010

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-010 — Appendix A config defaults
- Contract clause(s): Appendix A: Configuration Defaults (Safety-Critical Thresholds), §0.X Repository Layout
- Acceptance tests: AT-341, AT-040, AT-424, AT-970, AT-971
- Touch scope: `crates/soldier_infra/src/lib.rs`, `crates/soldier_infra/tests/`, `crates/soldier_infra/config/` (new)
- **Risk rating**: MED
  - Applies safety-critical config defaults. Wrong defaults or missing fail-closed behavior on non-Appendix-A parameters could silently weaken safety gates downstream.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-341 | Appendix A.CSP | "Given: config missing instrument_cache_ttl_s and mm_util_kill at runtime. When: safety-critical defaults applied. Then: defaults used (instrument_cache_ttl_s=3600, mm_util_kill=0.95) and enforcement uses those defaults (no implicit zero/none)." | MUST | Yes — unit test with missing config values |
| AT-040 | Appendix A.GOP | "Given: a safety-critical gate references a required parameter that has no Appendix A default (e.g., dd_limit). When: that parameter is missing or unparseable. Then: the gate MUST fail-closed (block policy application / rollout) and surface a deterministic reason." | MUST | Yes — unit test with missing non-Appendix-A parameter |
| AT-424 | Appendix A.CSP | "Given: each CSP safety-critical config value listed in Appendix A.CSP is omitted at runtime (one-at-a-time). When: the associated gate computes its decision. Then: the Appendix A default is used for that parameter." | MUST | Yes — parameterized test per CSP config key |
| AT-970 | Appendix A.GOP | "Given: config missing evidenceguard_global_cooldown and replay_window_hours at runtime. When: GOP defaults applied. Then: defaults used (evidenceguard_global_cooldown=120, replay_window_hours=48)." | MUST | Yes — unit test with missing GOP config values |
| AT-971 | Appendix A.GOP | "Given: each GOP safety-critical config value listed in Appendix A.GOP is omitted at runtime (one-at-a-time). When: the associated gate computes its decision. Then: the Appendix A default is used for that parameter." | MUST | Yes — parameterized test per GOP config key |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The workspace scaffolding (S1-001) is complete and `crates/soldier_infra` exists | Cannot create config module without the crate | AT-905 (S1-001 dependency) | Dependency |
| 2 | Appendix A defaults table in CONTRACT.md is the single source of truth for default values | If defaults are hardcoded from memory rather than from Appendix A, they may drift | Config loader must reference Appendix A values exactly; test golden vectors use contract values | Code review |
| 3 | "Fail-closed" for missing non-Appendix-A params means returning an error, not panicking | Panic in config loading would crash the process rather than fail-closed gracefully | AT-040: gate MUST "block policy application and surface a deterministic reason" — error return, not panic | AT-040 |
| 4 | The config loader is a standalone module in soldier_infra, not coupled to runtime gates yet | Gates consume config values later; this story only defines the loader + defaults | Scope: `crates/soldier_infra/config/` and tests only | Scope guard |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing non-Appendix-A parameter silently defaults to zero/none instead of failing closed | Gate operates with wrong threshold; e.g., dd_limit=0 allows unlimited drawdown | AT-040: gate MUST fail-closed and surface deterministic reason; test asserts error return for missing non-Appendix-A key | AT-040 |
| 2 | Appendix A default value hardcoded incorrectly (e.g., mm_util_kill=0.90 instead of 0.95) | Gate trips at wrong threshold; incorrect risk boundary | AT-341, AT-424: test golden vectors use exact contract values (3600, 0.95, 120, 48) | AT-341, AT-424, AT-970 |
| 3 | Config loader applies defaults but downstream gate reads from a different source (bypassing loader) | Defaults exist but are never used; gate reads raw config and gets None | Integration test verifies the gate's input comes through the config loader path | AT-424, AT-971 (gate behavior test) |
| 4 | `unwrap()` on config parse causes panic instead of fail-closed error | Process crashes on bad config instead of degrading gracefully | AT-040: "surface a deterministic reason" — must return Result, not panic | AT-040 |
| 5 | Appendix A table grows but config loader is not updated — new parameters silently missing | Future safety gates operate without defaults | AT-424/AT-971 are parameterized per config key — adding a new Appendix A param without a loader entry fails the test | AT-424, AT-971 |

## 4) Open decisions (resolve before coding)

### Decision: Config representation — struct vs. map
- **What is ambiguous / missing**: Should the config defaults be a typed Rust struct with named fields, or a `HashMap<String, ConfigValue>`?
- **Evidence**: CONTRACT.md Appendix A lists ~20+ parameters across CSP and GOP profiles. PRD scope says `crates/soldier_infra/config/`.
- **Options**:
  1. Option A — Typed struct with `Option<T>` fields + `Default` impl that fills Appendix A values. Compile-time safety, IDE support, but requires struct changes when new params are added.
  2. Option B — HashMap-based with typed accessors. More flexible but less compile-time safety.
- **Chosen**: A — Typed struct. Safety-critical parameters deserve compile-time guarantees. The Appendix A table is finite and stable.
- **Why not others**: Option B trades compile-time safety for flexibility we don't need — the parameter set is contract-defined and changes infrequently.
- **Scope control**:
  - What we're NOT doing yet: Wiring the config into runtime gates (PolicyGuard, EvidenceGuard). This story only creates the loader + defaults.
  - What unblocks us if this choice is wrong: Refactoring a struct to a map (or vice versa) is a contained change within soldier_infra.

### Decision: Fail-closed mechanism for missing non-Appendix-A params
- **What is ambiguous / missing**: AT-040 says "block policy application / rollout and surface a deterministic reason." What does "block" look like in code?
- **Evidence**: CONTRACT.md AT-040: "the system blocks the associated capability until the parameter is provided."
- **Options**:
  1. Option A — Return `Err(ConfigError::MissingRequired { key, reason })` from config validation. Caller decides how to block.
  2. Option B — Set a latch/flag that forces ReduceOnly until the parameter is provided.
- **Chosen**: A — Return an error with a deterministic reason. The config loader's job is validation; the caller (PolicyGuard) decides the enforcement action.
- **Why not others**: Option B couples config loading with runtime enforcement, violating separation of concerns. The latch belongs in PolicyGuard (future story).
- **Scope control**:
  - What we're NOT doing yet: PolicyGuard integration, latch setting, or ReduceOnly forcing.
  - What unblocks us if this choice is wrong: The error type can be extended to carry more context.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-341 | Hardcode `instrument_cache_ttl_s = 3600` and `mm_util_kill = 0.95` as constants, ignoring config file entirely | Defaults are correct but config overrides are impossible; system is locked to defaults forever | Test must verify that an explicit config value overrides the default (golden vector: set ttl=1800, assert 1800 used) |
| AT-040 | Return `Ok(default_value)` for ALL missing params, including non-Appendix-A ones | Silently invents defaults for params that should fail-closed | AT-040 explicitly tests a param with no Appendix A default — must get an error, not a value |
| AT-424 | Test only one CSP param instead of all | Partial coverage hides missing defaults for other params | AT-424 says "each CSP safety-critical config value... one-at-a-time" — parameterized test required |
| AT-970 | Hardcode evidenceguard_global_cooldown=120 but don't handle replay_window_hours | Partial implementation — one GOP param defaults correctly, another doesn't | AT-970 tests both params together; both must default correctly |
| AT-971 | Test only one GOP param instead of all | Same as AT-424 issue for GOP profile | AT-971 says "each GOP safety-critical config value... one-at-a-time" — parameterized test required |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-341 | ConfigLoader (soldier_infra::config) | `test_missing_instrument_cache_ttl_s_uses_3600_default` + `test_missing_mm_util_kill_uses_095_default` | Yes (missing → default applied) | Yes (present → override used) | Config value assertion (exact default vs exact override) | Yes |
| AT-040 | ConfigLoader (soldier_infra::config) | `test_missing_non_appendix_a_param_fails_closed` | Yes (missing → error) | Yes (present → no error) | Error type assertion (`ConfigError::MissingRequired`) | Yes |
| AT-424 | ConfigLoader (soldier_infra::config) | `test_each_csp_param_defaults_when_omitted` (parameterized) | Yes (omitted → default) | Yes (provided → override) | Per-param value assertion | Yes |
| AT-970 | ConfigLoader (soldier_infra::config) | `test_missing_evidenceguard_global_cooldown_uses_120_default` + `test_missing_replay_window_hours_uses_48_default` | Yes (missing → default) | Yes (present → override) | Config value assertion | Yes |
| AT-971 | ConfigLoader (soldier_infra::config) | `test_each_gop_param_defaults_when_omitted` (parameterized) | Yes (omitted → default) | Yes (provided → override) | Per-param value assertion | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: A wrong default value could cause a safety gate to trip at the wrong threshold. For example, if `mm_util_kill` defaults to 0.99 instead of 0.95, the system allows 4% more margin utilization before Kill mode — potentially leading to larger losses in a margin crisis. Conversely, if a non-Appendix-A param silently defaults to zero, a gate could be permanently tripped or permanently open.
- **Fail-closed cap on loss**: AT-040 ensures missing non-Appendix-A params block the associated capability. Worst case is limited to the delta between correct and incorrect Appendix A defaults (e.g., mm_util_kill off by a few percent).
- **Drift metric**: `config_defaults_applied_total` counter (from PRD observability). If this counter increases unexpectedly in prod, it means config values are missing and defaults are being applied — worth investigating.
- **Loss boundary**: ReduceOnly (downstream PolicyGuard enforcement). Config errors in isolation don't dispatch orders; they only set thresholds that gates use.
- **Rollback plan**: Revert the config module commit. Fall back to pre-Appendix-A behavior (which may be less safe — document the delta).

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: This story defines the config values that PolicyGuard, EvidenceGuard, and margin gates will consume. Incorrect values here propagate to all downstream safety checks.
- **If conflict with CONTRACT.md**: No conflict — this story implements what Appendix A specifies. Values must match exactly.
- Files with recent churn or shared ownership: `crates/soldier_infra/src/lib.rs` (may be modified by S1-001 and S1-011).
- Struct fields I'm assuming exist: None yet — this story creates the config structs.
- State machine transitions affected: None directly — config values feed into state machine guards implemented in later stories.

## 9) Constraint I expect to hit
- What will slow me down: Enumerating all Appendix A parameters and their exact default values. The table is spread across CONTRACT.md §A.CSP and §A.GOP with ~20+ parameters.
- Exploit: Parse the Appendix A summary table in CONTRACT.md §A which lists all params, defaults, units, and sections in one place.
- Smallest fix that prevents it next time: Add a machine-readable Appendix A defaults file (e.g., `specs/appendix_a_defaults.toml`) that both code and tests can reference as single source of truth.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Config loader not wired into PolicyGuard/EvidenceGuard runtime | Medium | Wiring requires PolicyGuard implementation (S2+) | PolicyGuard story owner | Slice 2+ | Integration AT proving gate reads config through loader |
| Parameterized tests for ALL Appendix A params (AT-424, AT-971) may be incomplete if new params are added to contract | Low | Contract is stable for Slice 1; new params added in future slices | Config story owner | Ongoing | CI check: count of test params == count of Appendix A params |

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice
