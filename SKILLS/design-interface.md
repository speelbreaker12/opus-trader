# SKILL: /design-interface ("Design It Twice")

Based on "Design It Twice" from John Ousterhout's *A Philosophy of Software Design*: your first idea is unlikely to be the best. Generate multiple radically different designs, then compare.

## When to use

- Designing a new module, trait, or public API
- Refactoring an existing interface (gates, execution pipeline, etc.)
- Any time there's a non-obvious design tradeoff
- When someone says "design it twice" or "explore interface options"

## Workflow

### 1. Gather Requirements

Before designing, understand:

- [ ] What problem does this module solve?
- [ ] Who are the callers? (other modules, integration tests, external users)
- [ ] What are the key operations?
- [ ] Any constraints? (fail-closed, performance, contract alignment)
- [ ] What should be hidden inside vs exposed?

Ask: "What does this module need to do? Who will use it?"

For this codebase, also check:
- [ ] Which CONTRACT.md sections apply?
- [ ] Does the interface sit on a safety-critical path?
- [ ] Must it support the fail-closed pattern?

### 2. Generate Designs (Parallel Sub-Agents)

Spawn 3+ sub-agents simultaneously using the Agent tool. Each must produce a **radically different** approach — not minor variations.

```
Prompt template for each sub-agent:

Design an interface for: [module description]

Requirements: [gathered requirements]
Contract constraints: [relevant CONTRACT.md sections]

Your design constraint: [UNIQUE per agent]
- Agent 1: "Minimize method count — aim for 1-3 methods max"
- Agent 2: "Maximize flexibility — support many use cases and extension"
- Agent 3: "Optimize for the most common caller — make the default case trivial"
- Agent 4: "Design around the fail-closed pattern — safety is the primary axis"

Output format:
1. Interface signature (types, methods, params)
2. Usage example (how caller uses it)
3. What this design hides internally
4. Trade-offs of this approach
5. How fail-closed behavior works in this design
```

### 3. Present Designs

Show each design with:

1. **Interface signature** — types, methods, params
2. **Usage examples** — how callers actually use it in practice
3. **What it hides** — complexity kept internal
4. **Fail-closed behavior** — what happens when inputs are uncertain

Present designs sequentially so the user can absorb each approach before comparison.

### 4. Compare Designs

After showing all designs, compare them on:

- **Interface simplicity**: fewer methods, simpler params = easier to use correctly
- **Module depth**: small interface hiding significant complexity (good) vs large interface with thin implementation (bad)
- **Fail-closed safety**: which design makes the safe default easiest?
- **Testability**: which design is easiest to test at the boundary?
- **Contract alignment**: which design maps most naturally to CONTRACT.md requirements?

Discuss trade-offs in prose, not tables. Highlight where designs diverge most.

Give your **own recommendation**: which design is strongest and why. If elements from different designs would combine well, propose a hybrid. Be opinionated — the user wants a strong read, not just a menu.

### 5. Synthesize

Ask:
- "Which design best fits your primary use case?"
- "Any elements from other designs worth incorporating?"

## Evaluation Criteria (from Ousterhout)

**Interface simplicity**: Fewer methods, simpler params = easier to learn and use correctly.

**General-purpose**: Can handle future use cases without changes. But beware over-generalization.

**Implementation efficiency**: Does interface shape allow efficient implementation? Or force awkward internals?

**Depth**: Small interface hiding significant complexity = deep module (good). Large interface with thin implementation = shallow module (avoid).

## Anti-Patterns

- Don't let sub-agents produce similar designs — enforce radical difference
- Don't skip comparison — the value is in contrast
- Don't implement — this is purely about interface shape
- Don't evaluate based on implementation effort
- Don't forget fail-closed — every design must answer "what happens when uncertain?"
