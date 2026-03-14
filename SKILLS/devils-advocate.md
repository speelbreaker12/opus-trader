# SKILL: /devils-advocate (Test-the-Tests)

Purpose
- Stress-test an AT suite by iteratively writing wrong implementations that pass
- Catch insufficient tests before they reach review
- Gate: if a simpler-than-correct implementation passes, the story is blocked

When to use
- After writing or modifying safety-critical ATs (any AT in `crates/soldier_core/` or `crates/soldier_infra/`)
- During ralph loop implementation, between "tests written" and "self-review"
- When `/contract-review` Phase 3 flags weak causality
- When a reviewer asks "what wrong implementation would also pass?"

When NOT to use
- Documentation-only changes
- Non-safety code (Python tooling, scripts, CI)
- ATs that are purely observability/format (no safety gate)

---

## Process

### Phase 1 — Identify Target ATs

List the ATs under test. For each, note:

| AT | Gate/Guard | What it proves | TRIP or NON-TRIP |
|----|-----------|----------------|------------------|
| AT-XXXX | e.g. PolicyGuard | e.g. clock uncertainty → ReduceOnly not Kill | TRIP |

### Phase 2 — Mutation Loop (repeat until phase transition)

For each AT, iterate:

1. **Mutate**: Write a deliberately wrong implementation that you believe will pass all current tests. Target the simplest wrong impl first:
   - Always-reject (ignores conditions)
   - Always-allow (ignores guards)
   - Hard-coded return value
   - Off-by-one / boundary flip (`<` vs `<=`)
   - Ignore one input field entirely
   - Swap two enum variants
   - **Enum variant sweep**: For each enum variant the function accepts, feed it through the full function with hostile/garbage inputs for all other parameters. Example: `evaluate_assembled_pipeline(CancelOnly, NaN_metadata)` — does CancelOnly still get approved? Tests that only exercise one variant (e.g., always Open) leave every other variant's path untested.
   - **Identity/no-op mutation**: new implementation == old implementation (passthrough, no change). For any loop-style optimization or score-based exit criterion, check whether the scoring fixtures already satisfy the structural assertions *before any patcher runs*. If they do, the null patcher scores 100% — the exit criterion is vacuous. Fix: add a post-apply hash check asserting `hash(output) != hash(input)` before accepting a patch as "applied".

2. **Run tests**: `cargo test` on the relevant module. Does the wrong impl pass?

3. **If it passes** → the test suite has a gap:
   - Identify which AT *should* have caught this
   - Add a test case (or tighten an existing one) that fails against the wrong impl
   - Record the mutation and the fix in the output log
   - Return to step 1 with the tightened suite

4. **If it fails** → the test suite caught it. Try the next mutation from the list above.

5. **Phase transition**: Stop when every remaining wrong implementation you can think of either:
   - Requires logic *more complex* than the correct implementation, OR
   - Is so contrived it would never occur naturally (e.g., `if input == 42 { wrong_path }`)

### Phase 3 — Simpler-Than-Correct Gate (blocking)

After the mutation loop, answer this question explicitly:

> **Is there any implementation SIMPLER than the correct one that passes all ATs?**

- "Simpler" = fewer branches, fewer field accesses, shorter code, trivial constant
- If YES → **BLOCKED**. The AT suite is insufficient. Add tests until the answer is NO.
- If NO → **PASS**. Record the gate result.

Common simpler-than-correct patterns:
- Gate that always rejects → passes all TRIP tests but has no NON-TRIP test
- Gate that always allows → passes all NON-TRIP tests but has no TRIP test
- Gate that ignores one input → passes because no test varies that input
- Gate that uses `>` instead of `>=` → passes because no test hits the boundary

### Phase 4 — Record Results

Document in the output:

```markdown
## Devils Advocate: <AT list>

### Mutations Attempted
| # | Mutation | Passed? | Test Added |
|---|---------|---------|------------|
| 1 | Always-reject (ignore conditions) | YES → gap | Added NON-TRIP case: valid input → must allow |
| 2 | Ignore `clock_uncertainty` field | YES → gap | Added case: clock_uncertain=true, all else healthy → ReduceOnly |
| 3 | Hard-code ReduceOnly | NO | — (TRIP test caught it) |
| 4 | Off-by-one on threshold | NO | — (boundary test caught it) |

### Simpler-Than-Correct Gate
**Result: PASS / BLOCKED**
<If BLOCKED: which simpler impl still passes, and what test is needed>

### Phase Transition
Remaining possible mutations all require logic more complex than the correct implementation.
Weakest surviving test: <which test would be first to break if you relaxed it>

### Tests Added
- `test_xxx_non_trip_valid_input` — catches always-reject mutation
- `test_xxx_clock_field_required` — catches ignore-field mutation
```

---

## Integration

| Workflow step | How this skill fits |
|---------------|-------------------|
| Ralph loop | Run after writing tests, before self-review |
| `/contract-review` Phase 3 | If causality is weak, reviewer says "run `/devils-advocate`" |
| `/pr-review` P2 | Reviewer can request this for any AT where "what wrong impl would pass?" is unclear |
| Preflight | The preflight question "what wrong impl would also pass?" is the *first* iteration of this loop |

## Exit Criteria

The skill is complete when:
1. All mutations from the standard list have been attempted (including the identity/no-op mutation)
2. Every gap found has been closed with a new test case
3. The simpler-than-correct gate returns PASS
4. The phase transition has been reached and documented

## Contract Alignment

This skill enforces:
- CLAUDE.md: "What wrong implementation would also pass this AT? If one exists, tighten the AT."
- QUALITY_GATES.md: AT-BEHAVIOR proves correctness (not just AT-SCOPE proves ownership)
- QUALITY_GATES.md: TRIP + NON-TRIP isolation requirement
