# SKILL: /grill (Adversarial Plan Interview)

Relentlessly interview the user about a plan, design, or decision until every branch of the decision tree is resolved. This is NOT a checklist review — it's a conversational stress-test.

## When to use

- Before approving an implementation plan (complements `/plan-review`)
- When a design has ambiguous tradeoffs
- When someone says "grill me" or "stress-test this"
- Before committing to an architectural decision
- When a plan "feels right" but hasn't been challenged

## How it differs from /plan-review

| `/plan-review` | `/grill` |
|---|---|
| Checklist-based | Conversational |
| Catches omissions | Catches wrong assumptions |
| Verifies compliance | Challenges reasoning |
| Static analysis | Dynamic probing |
| One pass | Iterative until resolved |

Use both. `/plan-review` catches structural gaps. `/grill` catches reasoning gaps.

## Workflow

### 1. Read the Plan

Read the plan, design doc, or decision in full. If the codebase can answer a question, explore the codebase first instead of asking the user.

### 2. Interview Relentlessly

Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one. Use the AskUserQuestion tool for each question.

**Interview axes** (work through ALL of these):

**Failure modes**
- "What happens when [X] fails?"
- "What's the worst-case outcome if this assumption is wrong?"
- "If [dependency] is stale/missing/corrupt, what does the system do?"
- "Walk me through the error path for [specific scenario]"

**Alternatives rejected**
- "Why this approach over [alternative]?"
- "What did you consider and reject? Why?"
- "Is there a simpler way to achieve the same goal?"

**Boundary conditions**
- "What happens at zero? At maximum? At exactly the threshold?"
- "What if this runs twice? Concurrently? After a crash?"
- "What state is left behind if this is interrupted mid-way?"

**Hidden assumptions**
- "You're assuming [X] — is that always true?"
- "This works when [condition] — what changes when it doesn't?"
- "Who else touches this state? Could they invalidate your invariant?"

**Contract alignment** (specific to this codebase)
- "Which CONTRACT.md section governs this behavior?"
- "Is the fail-closed default correct here?"
- "What does the acceptance test prove about this?"

**Blast radius**
- "What else breaks if this is wrong?"
- "Who downstream depends on this output?"
- "If we have to revert this, what's the cost?"

### 3. Resolve Each Branch

For each question:
- If the user gives a clear answer → note it and move to the next branch
- If the user is uncertain → probe deeper, suggest options, help them decide
- If the codebase can resolve it → read the code and state what you found

Don't move on until the current branch is resolved. Don't accept hand-waving.

### 4. Summary

After all branches are resolved, output:

```markdown
## Grill Summary: <plan/design name>

### Decisions Made
- [Decision 1]: [resolution]
- [Decision 2]: [resolution]

### Assumptions Validated
- [Assumption]: [evidence or user confirmation]

### Risks Accepted
- [Risk]: [user's reasoning for accepting it]

### Open Items (if any)
- [Item]: needs [investigation/prototype/external input]
```

## Rules

- Be adversarial but constructive — the goal is to make the plan stronger, not to prove it wrong
- One question at a time — don't dump a list of 10 questions
- Explore the codebase before asking — don't ask what you can read
- Don't stop early — cover ALL axes, not just the first one that yields findings
- Don't accept "it should be fine" — push for specifics
- If a plan has a safety-critical path (trading, risk, state machines), be extra aggressive on failure modes

## Anti-Patterns

- **Softball questions**: "This looks good, any concerns?" — always probe specifics
- **Accepting vague answers**: "We'll handle that later" needs "How? When? What's the cost of not handling it now?"
- **Skipping axes**: Don't stop after finding one issue — cover all axes systematically
- **Checklist mode**: This is a conversation, not a form to fill out
- **Asking what you can read**: If the codebase has the answer, read it first
