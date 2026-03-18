# SKILL: /codebase-health (Architecture Friction Audit)

Explore the codebase like an AI agent would, surface architectural friction, and propose module-deepening refactors. Based on Matt Pocock's `improve-codebase-architecture` skill, adapted for a Rust trading system with facade-enforced deep modules.

A **deep module** (Ousterhout, *A Philosophy of Software Design*) has a small interface hiding a large implementation. Deep modules are more testable, more AI-navigable, and let you test at the boundary instead of inside.

## When to use

- Periodic health check (monthly or after major feature work)
- After adding a new crate or subsystem
- When navigating the codebase feels harder than it should
- Before a major refactor to identify candidates
- When someone says "architecture review", "codebase health", or "find shallow modules"
- When the skill/workflow system itself feels tangled

## Workflow

### 1. Explore for Friction

Use the Agent tool with `subagent_type=Explore` to navigate the codebase **organically**. Do NOT follow a rigid checklist — explore naturally and note where you experience friction.

Friction signals to watch for:

**Module depth**
- Where does understanding one concept require bouncing between many small files?
- Where are modules so shallow that the interface is nearly as complex as the implementation?
- Where have pure functions been extracted "just for testability" but the real bugs hide in how they're called?

**Coupling**
- Where do tightly-coupled modules create integration risk in the seams between them?
- Where does `soldier_infra` reach into `soldier_core` internals (or vice versa)?
- Where do test helpers import internal types that should be `pub(crate)`?

**Facade integrity**
- Does every module with 2+ files have an `api.rs` facade?
- Is `mod.rs` limited to `pub use api::*` (no logic leaking)?
- Are facade completeness contract tests present and passing?

**Testability**
- Which parts of the codebase are untested or hard to test?
- Where are tests coupled to implementation rather than boundary behavior?
- Where are mocks used for internal collaborators instead of system boundaries?

**The friction you encounter IS the signal.** Don't theorize — navigate and report what's hard.

### 2. Present Candidates

Present a numbered list of deepening/improvement opportunities. For each candidate, show:

- **Cluster**: Which modules/concepts are involved
- **Why they're coupled**: Shared types, call patterns, co-ownership of a concept
- **Dependency category**: (see below)
- **Test impact**: What existing tests would be replaced by boundary tests
- **Severity**: How much friction does this actually cause?

Do NOT propose interfaces yet. Ask the user: "Which of these would you like to explore?"

### 3. User Picks a Candidate

### 4. Frame the Problem Space

Before spawning sub-agents, write a user-facing explanation:

- The constraints any new interface would need to satisfy
- The dependencies it would need to rely on
- CONTRACT.md sections that govern this area
- A rough illustrative code sketch to ground the constraints — this is NOT a proposal

Show this to the user, then **immediately proceed to Step 5**. The user reads while sub-agents work in parallel.

### 5. Design Multiple Interfaces

Hand off to `/design-interface` skill for the chosen candidate. This spawns 3+ parallel sub-agents with different design constraints.

### 6. User Picks an Interface

### 7. File as GitHub Issue RFC

Create a refactor RFC as a GitHub issue using `gh issue create`:

```bash
gh issue create --title "RFC: Deepen <module> — <one-line summary>" --body "$(cat <<'EOF'
## Problem

Describe the architectural friction:
- Which modules are shallow and tightly coupled
- What integration risk exists in the seams
- Why this makes the codebase harder to navigate and maintain

## Proposed Interface

The chosen design:
- Interface signature (types, methods, params)
- Usage example showing how callers use it
- What complexity it hides internally
- How fail-closed behavior works

## Dependency Strategy

Which category applies and how dependencies are handled:
- **In-process**: merged directly, no I/O
- **Local-substitutable**: tested with [specific stand-in]
- **Ports & adapters**: port definition + production/test adapters
- **Mock**: mock boundary for external services (exchange APIs)

## Testing Strategy

- **New boundary tests to write**: behaviors to verify at the interface
- **Old tests to delete**: shallow module tests made redundant
- **Facade completeness contract**: add to `*_contract_tests.rs`

## Contract Alignment

- Which CONTRACT.md sections govern this module
- Whether fail-closed behavior is preserved
- AT coverage for the new interface

## Implementation Plan

Durable guidance NOT coupled to current file paths:
- What the module should own (responsibilities)
- What it should hide (implementation details)
- What it should expose (the interface contract)
- How callers migrate to the new interface

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Do NOT ask the user to review before creating — just create it and share the URL.

## Dependency Categories

When assessing a candidate for deepening, classify its dependencies:

### 1. In-process
Pure computation, in-memory state, no I/O. Always deepenable — just merge the modules and test directly.

**Example**: Merging `quantize.rs` + `pricer.rs` + `net_edge.rs` into a single deep "pricing pipeline" module. All pure computation.

### 2. Local-substitutable
Dependencies with local test stand-ins (e.g., in-memory WAL for the real WAL).

**Example**: `store/ledger.rs` — uses file I/O but could use an in-memory journal for tests.

### 3. Remote but owned (Ports & Adapters)
Your own services across a network boundary. Define a port (trait) at the module boundary. Tests use an in-memory adapter.

**Example**: Deribit venue adapter — define a `VenueClient` trait, implement `DeribitClient` for production, `MockVenueClient` for tests.

### 4. True external (Mock)
Third-party services you don't control. Mock at the boundary.

**Example**: Exchange WebSocket feeds — mock the feed, test the consumer.

## Audit Scope Options

When invoked, ask the user which scope to audit:

| Scope | What it covers |
|---|---|
| `core` | `crates/soldier_core/src/` — execution, risk, venue, idempotency, recovery |
| `infra` | `crates/soldier_infra/src/` — WAL, store, config, bootstrap |
| `cross-crate` | Import patterns between soldier_core and soldier_infra |
| `skills` | `SKILLS/` directory — is the skill system itself deep or shallow? |
| `full` | All of the above |

## Anti-Patterns

- **Heuristic-driven exploration**: Don't grep for metrics — navigate and feel the friction
- **Proposing interfaces too early**: Present candidates first, get user buy-in, then design
- **Ignoring "appropriately shallow"**: Single-responsibility modules (idempotency, recovery) don't need deepening
- **Implementation-effort bias**: Evaluate designs on interface quality, not migration cost
- **Forgetting contract alignment**: Every refactor must preserve CONTRACT.md invariants
- **Skipping the RFC issue**: The output is a reviewable artifact, not just a conversation
