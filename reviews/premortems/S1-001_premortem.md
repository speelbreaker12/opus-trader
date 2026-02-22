# Story Premortem: S1-001

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-001 — Workspace scaffolding
- Contract clause(s): §0.X Repository Layout & Canonical Module Mapping (Non-Negotiable)
- Acceptance tests: AT-905, AT-901
- Touch scope: `Cargo.toml`, `.gitignore`, `crates/soldier_core/Cargo.toml`, `crates/soldier_core/src/lib.rs`, `crates/soldier_infra/Cargo.toml`, `crates/soldier_infra/src/lib.rs`
- **Risk rating**: LOW
  - Pure scaffolding — no trading logic, no safety gates, no data handling.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-905 | §0.X Repository Layout | "Given: repo at root with Cargo.toml present. When: repo layout is verified. Then: crates/soldier_core and crates/soldier_infra exist and are listed in workspace members." | MUST (Non-Negotiable) | Yes — directory existence + workspace member check |
| AT-901 | §0.X Repository Layout | "Given: repo at root with plans/verify.sh present. When: plans/verify.sh is executed. Then: it runs cargo test --workspace and exits 0 when tests pass." | MUST (Non-Negotiable) | Yes — script execution + exit code check |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Rust toolchain is installed and `cargo` is on PATH | Build fails entirely | AT-901 (`cargo test --workspace` exits 0) | Pre-req |
| 2 | `plans/verify.sh` already exists or will be created as part of this story | AT-901 cannot pass without it | AT-901 (script must exist and run) | Verify scope |
| 3 | Empty lib.rs files are sufficient for initial scaffolding | Compilation fails if lib.rs has syntax errors | AT-901 (workspace builds and tests pass) | Trivial |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Crate directories created but not added to workspace members | `cargo test --workspace` ignores them | AT-905 checks workspace member list explicitly | AT-905 |
| 2 | Typo in crate path (e.g., `crate/soldier_core` vs `crates/soldier_core`) | Cargo workspace resolution fails | `cargo test --workspace` exits non-zero | AT-901 |
| 3 | `verify.sh` exists but does not actually run `cargo test --workspace` | AT-901 passes vacuously | AT-901 fail criteria: "exits 0 when tests fail OR does not run workspace tests" | AT-901 |
| 4 | Root `Cargo.toml` uses `[package]` instead of `[workspace]` | Cargo treats it as single package, not workspace | `cargo test --workspace` fails or ignores crates | AT-905, AT-901 |
| 5 | `.gitignore` missing `target/` — bloats repo but not a safety issue | Large commits, slow clones | Code review / CI check | None (cosmetic) |

## 4) Open decisions (resolve before coding)

### Decision: verify.sh scope
- **What is ambiguous / missing**: Does S1-001 own creating `plans/verify.sh`, or is it assumed to exist?
- **Evidence**: PRD `verify` field lists `./plans/verify.sh` and `cargo test --workspace`. AT-901 requires `plans/verify.sh` to exist.
- **Options**:
  1. Option A — S1-001 creates `plans/verify.sh` as a minimal script that runs `cargo test --workspace` — self-contained story.
  2. Option B — Assume `plans/verify.sh` already exists — depends on external setup.
- **Chosen**: A — S1-001 should ensure the script exists so AT-901 is self-contained.
- **Why not others**: Option B creates a hidden dependency; AT-901 would fail if the script is missing.
- **Scope control**:
  - What we're NOT doing yet: adding linting, formatting, or advanced CI steps to verify.sh.
  - What unblocks us if this choice is wrong: verify.sh can be extended in later stories.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-905 | Create the directories but put an empty `Cargo.toml` in each (no `[package]` or `[lib]` section) | Directories exist but crates are not valid Rust packages; future stories fail | AT-901 tightens: `cargo test --workspace` must exit 0, which requires valid crate manifests |
| AT-901 | `verify.sh` contains `exit 0` with no actual test execution | Script passes vacuously regardless of test state | AT-901 fail criteria explicitly states "does not run workspace tests" — verify.sh must invoke `cargo test` |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-905 | WorkspaceScaffold (structural) | Directory existence + workspace member assertion | N/A (structural) | N/A (structural) | Directory listing + Cargo.toml parse | Yes |
| AT-901 | VerifyHarness (repo structure) | `plans/verify.sh` execution | N/A (structural) | N/A (structural) | Exit code 0 + cargo test output | Yes |

Note: These are structural/scaffolding ATs, not safety-critical runtime gates. TRIP/NON-TRIP is not applicable — there is no runtime enforcement point to trip or not trip. The proof is structural: the artifacts exist and function.

- [x] Every safety-critical AT has TRIP + NON-TRIP — N/A (no safety-critical ATs)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: None. This is repo scaffolding with no runtime behavior. A broken workspace blocks all downstream development but causes zero financial loss.
- **Fail-closed cap on loss**: N/A — no trading logic exists at this stage.
- **Drift metric**: N/A — structural artifact, does not drift at runtime.
- **Loss boundary**: N/A.
- **Rollback plan**: `git revert` the scaffolding commit; workspace returns to pre-scaffold state.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None — this creates the workspace structure that gates will later inhabit.
- **If conflict with CONTRACT.md**: No conflict. §0.X explicitly requires this layout.
- Files with recent churn or shared ownership: Root `Cargo.toml` (may be edited by other stories adding dependencies).
- Struct fields I'm assuming exist: None.
- State machine transitions affected: None.

## 9) Constraint I expect to hit
- What will slow me down: Ensuring `plans/verify.sh` is correctly scoped (not too much, not too little).
- Exploit: Keep verify.sh to a single `cargo test --workspace` invocation with `set -euo pipefail`.
- Smallest fix that prevents it next time: Document the verify.sh contract in a comment header.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- **GREEN**: All gates pass, proof plan complete, no unresolved ambiguities.

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
