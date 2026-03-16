# SKILL: /glossary (Domain Terminology)

Extract and maintain a domain glossary from the codebase and conversation. Prevents field-name drift, terminology confusion, and the "I thought it was called X" problem.

## When to use

- Starting work on an unfamiliar part of the codebase
- After discovering a naming inconsistency (e.g., `fee_usd` vs `fee_estimate_usd`)
- When onboarding to a new module or subsystem
- Someone says "glossary", "terminology", "what's this called", or "domain model"
- Before writing tests for a module (to get field names right)

## Workflow

### 1. Identify Scope

Ask: "Which module or subsystem?" or infer from context.

Common scopes for this codebase:
- Execution pipeline (gates, intents, dispatch)
- Risk/policy (TradingMode, RiskState, latches)
- Infrastructure (WAL, TLSM, trade-ID registry)
- Status endpoint (schemas, validation)

### 2. Extract Terms from Code

For the target scope, read actual struct/enum definitions:

```bash
# Find struct definitions in a module
rg "pub struct|pub enum" crates/soldier_core/src/<module>/

# Find field names on key types
rg "pub \w+:" crates/soldier_core/src/<module>/types.rs
```

For each term, capture:
- **Canonical name**: The exact field/type/variant name in code
- **Definition**: What it represents
- **Common mistakes**: Names people guess wrong (from memory or conversation)

### 3. Cross-reference CONTRACT.md

Check if the code terms match contract terminology:

```bash
# Find contract references to the same concept
rg "<concept>" specs/CONTRACT.md
```

Flag any divergence between code names and contract names.

### 4. Write or Update Glossary

Write to `specs/glossary/<scope>.md`. Create the directory if needed.

Format:

```markdown
# Glossary: <Scope>

> Auto-generated from code + CONTRACT.md. Update when struct definitions change.

## Types

| Type | Module | Definition |
|------|--------|------------|
| `TradingMode` | `policy_guard` | Active \| ReduceOnly \| Kill — resolved each tick |
| `RiskState` | `risk` | Healthy \| Degraded \| Maintenance \| Kill |

## Fields (commonly misremembered)

| Struct | Field | NOT this | Actual |
|--------|-------|----------|--------|
| `NetEdgeInput` | `fee_usd` | `fee_estimate_usd` | `fee_usd` |
| `NetEdgeInput` | `expected_slippage_usd` | `slippage_usd` | `expected_slippage_usd` |
| `LiquidityGateInput` | `l2_snapshot` | `book` | `l2_snapshot` |
| `LiquidityGateInput` | `order_qty` | `qty` | `order_qty` |

## Contract ↔ Code Mapping

| Contract Term | Code Term | Notes |
|---------------|-----------|-------|
| "policy staleness" | `policy_stale()` | §2.2.1 |
| "open permission latch" | `open_permission_latch` | §2.2.3 |
```

### 5. Inline Summary

Output a short summary in the conversation so the user has immediate context without opening the file.

## Rules

- **Always read actual code** — never guess field names from memory
- **Flag divergence** — if contract says "X" and code says "Y", that's a finding
- **Keep it current** — update when structs change, don't let it go stale
- **Scope narrowly** — one glossary file per subsystem, not one giant file
- **Include the wrong names** — the "NOT this" column is the most valuable part

## Anti-Patterns

- **Guessing from memory**: Always `rg` the actual struct definition
- **One giant glossary**: Scope to subsystem so each file stays manageable
- **Skipping contract cross-ref**: Terminology drift between contract and code is a bug
- **Writing without reading**: Read the code first, then write the glossary
