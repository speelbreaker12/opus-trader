# Claude Code Instructions

> This file is read automatically by Claude Code. It defines code quality standards and codebase patterns.

## Model Selection

| Task Type | Model | Why |
|-----------|-------|-----|
| Quick fixes, typos, simple edits | `sonnet` (default) | Fast, sufficient |
| Contract changes (specs/CONTRACT.md) | `opus` | Safety-critical, needs deep reasoning |
| Architecture decisions | `opus` | Complex tradeoffs |
| State machine changes | `opus` | Correctness-critical |
| Debugging complex issues | `opus` | Needs careful analysis |
| PRD implementation | `sonnet` | Balanced speed/quality |

**Switch models:**
```bash
claude --model opus   # For critical work
claude --model sonnet # Default
```

## Code Quality Standards

### Rust Code

**Error Handling (Non-Negotiable)**
```rust
// NEVER use unwrap() in production code
let value = map.get(&key).unwrap();           // BAD
let value = map.get(&key)?;                    // GOOD
let value = map.get(&key).ok_or(MyError)?;    // GOOD

// NEVER use expect() without a reason that helps debugging
let x = foo.expect("failed");                  // BAD
let x = foo.expect("config missing: DB_URL"); // GOOD (but still prefer ?)

// NEVER silently ignore errors
let _ = dangerous_operation();                 // BAD
dangerous_operation().ok();                    // BAD
if let Err(e) = dangerous_operation() {        // GOOD
    tracing::warn!(?e, "operation failed");
}
```

**Fail-Closed Pattern (Required for Safety-Critical Code)**
```rust
// Default to the SAFE state when uncertain
fn resolve_trading_mode(&self) -> TradingMode {
    // If ANY check fails or is uncertain, restrict trading
    if self.policy_stale() || self.watchdog_stale() || self.f1_cert_invalid() {
        return TradingMode::ReduceOnly;
    }
    // Only return Active when ALL checks pass
    TradingMode::Active
}
```

**Type Safety**
- Use newtypes for domain concepts: `struct InstrumentId(String);`
- Prefer enums over strings for fixed sets: `enum Side { Buy, Sell }`
- Use `NonZeroU64` when zero is invalid
- Mark fields `#[serde(deny_unknown_fields)]` on config structs

**Logging**
```rust
// Use structured logging with tracing
tracing::info!(instrument_id = %id, side = ?side, "submitting order");

// Include context that helps debugging
tracing::error!(
    error = ?e,
    intent_id = %intent.id,
    trading_mode = ?mode,
    "dispatch rejected"
);
```

### Python Code

**Type Hints (Required)**
```python
# Always annotate function signatures
def validate_status(data: dict[str, Any], schema_path: Path) -> list[str]:
    ...

# Use Optional explicitly, not implicit None
def get_value(key: str) -> Optional[str]:  # GOOD
def get_value(key: str) -> str:            # BAD if can return None
```

**Error Handling**
```python
# Never bare except
try:
    result = risky_operation()
except:  # BAD
    pass

# Catch specific exceptions
try:
    result = risky_operation()
except ValueError as e:  # GOOD
    logger.warning(f"Invalid value: {e}")
    return None
```

### Testing

**Every New Function Needs Tests**
- Unit test the happy path
- Unit test at least one error path
- For safety-critical code: test the fail-closed behavior
- **Fail-closed test naming**: tests for safety gates must include pattern keywords (nan, missing, stale, fail_closed, invalid, expired, forbidden, degraded) for automated coverage checks via `plans/fail_closed_coverage.sh`

**Table-Driven Tests (Preferred)**
```rust
#[test]
fn test_trading_mode_resolution() {
    let cases = vec![
        // (policy_stale, watchdog_stale, expected_mode)
        (false, false, TradingMode::Active),
        (true, false, TradingMode::ReduceOnly),
        (false, true, TradingMode::ReduceOnly),
        (true, true, TradingMode::ReduceOnly),
    ];
    for (policy_stale, watchdog_stale, expected) in cases {
        // ...
    }
}
```

**Acceptance Tests Must Prove Causality**
From CONTRACT.md: Tests must prove the guard is the *sole* reason for the outcome via:
- Dispatch count (0 vs 1)
- Specific reject reason code
- Specific latch reason code

## This Codebase

### Architecture
- **Rust** (`crates/soldier_core/`, `crates/soldier_infra/`): Execution and risk
- **Python** (`python/`): Policy, schemas, validation tools
- **Specs** (`specs/`): Contract, state machines, flows
- **Plans** (`plans/`): Ralph harness, PRD, verification

### Key Concepts
- **TradingMode**: `Active | ReduceOnly | Kill` - resolved by PolicyGuard each tick
- **RiskState**: `Healthy | Degraded | Maintenance | Kill` - health layer
- **Fail-closed**: If uncertain, choose the safe/restrictive option
- **Contract alignment**: Code must implement what CONTRACT.md specifies

### Files You Must Read Before Editing
| If editing... | Read first... |
|---------------|---------------|
| PolicyGuard / TradingMode logic | `specs/CONTRACT.md` §2.2 |
| State machines | `specs/state_machines/` |
| /status endpoint | `specs/status/README.md`, schemas in `python/schemas/` |
| Verification gates | `plans/verify.sh`, `specs/WORKFLOW_CONTRACT.md` |

### Patterns to Follow
```rust
// Intent classification: if uncertain, treat as OPEN (most restrictive)
fn classify_intent(intent: &Intent) -> IntentClass {
    if intent.reduce_only == Some(true) {
        IntentClass::Close  // Risk-reducing
    } else {
        IntentClass::Open   // Fail-closed: unknown = OPEN
    }
}

// Latch pattern: set on bad event, clear only on explicit reconciliation
fn handle_ws_gap(&mut self) {
    self.open_permission_latch = true;
    self.latch_reason = LatchReason::WsBookGap;
    // Latch stays set until reconcile() is called
}
```

### Anti-Patterns to Avoid
```rust
// DON'T: Optimistic defaults
let mode = config.trading_mode.unwrap_or(TradingMode::Active);  // BAD

// DO: Pessimistic defaults
let mode = config.trading_mode.unwrap_or(TradingMode::ReduceOnly);  // GOOD
```

```python
# DON'T: Swallow errors
try:
    validate(data)
except Exception:
    pass  # BAD - hides contract violations

# DO: Fail loudly
try:
    validate(data)
except ValidationError as e:
    raise ContractViolation(f"Status validation failed: {e}") from e
```

## Recommended Workflows

### Mandatory Skill Lookup (BEFORE Starting Tasks)

**CRITICAL: Before performing these tasks, check SKILLS/ for relevant skills and USE them.**

| Task | Required Skill | Why |
|------|----------------|-----|
| Review a plan | `/plan-review` | Ad-hoc reviews miss failure modes |
| Review a PR | `/pr-review` | Systematic checklist prevents omissions |
| Review risky code | `/failure-mode-review` | Traces implementation failure paths, not just happy paths |
| Review architecture/ops | `/strategic-failure-review` | Systemic risks, hidden assumptions, operational/human factors |
| Pre-implementation risk analysis | premortem | Forces failure modes, wrong impls, decisions before coding |
| Implement PRD story | premortem → `/slice-execute` → `/post-impl-audit` | Premortem gate, fail-closed implementation, breaker audit |
| Implement single story | `/slice-execute` | Premortem gate → preflight → implement → golden vectors |
| Audit after implementation | `/post-impl-audit` | Breaker audit: AT proof, fail-closed, wrong-impl, paper compliance |
| Write acceptance test | `/acceptance-test` | Contract alignment |
| Check contracts (fast) | `/contract-review` | Fail-open hazard filter on code diffs |
| Check contracts (full) | `/contract-audit-full` | Exhaustive Contract-vs-PRD coverage audit |
| Git workflow (branches, merges, worktrees) | `/git` | Never commit on main, per-file diff before --theirs, worktree isolation, safety-biased conflict resolution |

**Process:**
```
1. User requests: "review this plan"
2. FIRST: Check if SKILLS/*review*.md or similar exists
3. Read the skill file
4. Follow the skill's checklist systematically
5. Do NOT do ad-hoc work that the skill covers
```

**Why this matters:**
- Skills encode lessons learned from past failures
- Ad-hoc reviews have happy-path bias
- Checklists catch what intuition misses
- Skipping skills = repeating past mistakes

**Anti-pattern:**
```
User: "review this plan"
Agent: [reads plan, gives opinions]  # WRONG - skipped skill lookup
```

**Correct pattern:**
```
User: "review this plan"
Agent: [checks SKILLS/, finds plan-review.md, reads it, follows checklist]  # RIGHT
```

### PRD Story Implementation (MANDATORY: Premortem → Execute → Audit)

**CRITICAL: Pending PRD stories (`passes=false`) in `plans/prd.json` MUST follow this workflow:**

1. **Premortem** — `./plans/scaffold_premortem.sh <ID>` → fill all sections (§0-§10) → STOPLIGHT must be GREEN/YELLOW
2. **Implement** — `/slice-execute` (reads premortem + prior postmortems, implements enforcement + tests + golden vectors)
3. **Audit** — `/post-impl-audit` (breaker role: AT proof, fail-closed, wrong-impl, paper compliance)
4. **Verify** — `./plans/verify.sh quick` then `./plans/verify.sh full`
5. **Gate** — `./plans/prd_set_pass.sh <ID> true`
6. **Postmortem** — fill `artifacts/story/<ID>/postmortem.md` using TOC template (`plans/postmortem_template.md`), validate with `plans/postmortem_gate.sh <ID>`

Do NOT skip the premortem. Do NOT mark `passes=true` without proving tests.

**Exceptions:**
- Post-implementation fixes: Stories with `passes=true` can be manually corrected/improved
- Read-only operations: Review, status checks, scope analysis
- Non-PRD work: Workflow maintenance, bug fixes, documentation

### Interview-Driven Specs (for new features)
Before implementing complex features, build detailed specs through Q&A:

```
Read this feature idea and interview me in detail using AskUserQuestionTool:
- Technical implementation details
- Edge cases and error handling
- Contract alignment (which sections apply?)
- Tradeoffs and alternatives

Continue until complete, then write to specs/features/FEATURE_NAME.md
```

This creates **auditable, versioned context** instead of relying on model memory.

See: `SKILLS/interview.md`

## MCP Tools

### Context7 (Documentation Lookup)
Add "use context7" to fetch up-to-date library documentation:
```
use context7 to look up tokio::sync::mpsc channel API
use context7 for serde_json error handling patterns
```

Use before implementing with any external crate to avoid hallucinated APIs.

### Contract Validation Tools (Auto-Use)
The `ralph` MCP server provides contract validation tools. **Use automatically** during PRD work:

| When | Use This Tool |
|------|---------------|
| Before editing CONTRACT.md | `contract_lookup("section")` to read current state |
| After editing CONTRACT.md | `check_contract_crossrefs()` to validate |
| Checking acceptance tests | `list_acceptance_tests()` |
| Verifying flows | `check_arch_flows()` |
| Before committing | `run_all_checks()` |
| Starting a PRD task | `get_prd_tasks("pending")` then `get_prd_task("T-xxx")` |

### GitHub Tools (Auto-Use for PR Work)
The `github` MCP server provides authenticated GitHub access. **Use automatically** for:

- Fetching PR details and comments
- Reading issue context
- Checking CI/workflow status
- Creating/updating PRs and issues

Prefer MCP tools over `gh` CLI when available for richer context.

## Contract Traceability

Principles for mapping CONTRACT.md clauses to implementation:

- **Stable IDs + anchors**: Contract clauses need CSP-### IDs with 2-5 search anchors (grep-able terms)
- **Chain, not star**: Map Contract → Plan → PRD → code/tests (TRACE.yaml tracks links)
- **AT-ID joins**: Referencing ATs in plans is the highest-leverage traceability signal
- **CI enforcement**: Changed CSP clause requires TRACE entry (prevents unmapped drift)
- **LLMs for candidates, not truth**: Use AI to suggest mappings, human confirms
- **One good link per clause**: Don't block progress on full mapping; iterate over time

## Commit Messages

Format: `<area>: <what changed>`

```
PolicyGuard: add F1 cert staleness check
status: validate fixtures against exact schema
verify: add --strict flag to status validation
```

Keep the first line under 72 characters. Reference CONTRACT.md sections when implementing contract requirements.

## PR Review Checklist

Before approving implementation PRs, verify each claimed change:

**1. Assertions validate what they claim (not just existence)**
```bash
# BAD: Checks if string exists anywhere (could be in comment/allowlist)
grep -q "my_function" file.sh

# GOOD: Checks actual invocation pattern
grep -Eq 'call_site[[:space:]]+"my_function"' file.sh
```
Ask: "Does this check prove integration, or just existence?"

**2. Ordering and sequencing**
```bash
# Extract IDs and verify monotonic order
grep -n "test_start.*0k\." file.sh | cut -d'"' -f2 | sort -V | diff - <(grep -o '0k\.[0-9]*' file.sh | head -20)
```
Ask: "Are numbered items in logical order? Any gaps or out-of-sequence?"

**3. Trace callsites, not just definitions**
- Function defined? Check if it's actually *called*
- File in allowlist? Check if it's actually *invoked*
- For each new function: find at least one callsite

**4. Question why tests pass**
- "This passes, but *why* does it pass?"
- A check that passes for the wrong reason is worse than no check
- Run the test, then break the thing it claims to test — does it fail?

**5. Implementation plan checklist**
For each claimed change in the PR:
- [ ] Code exists (definition)
- [ ] Code is invoked (callsite)
- [ ] Test validates invocation (not just existence)
- [ ] Ordering/sequencing is correct
- [ ] Error paths handled

**6. Failure mode analysis (for risky code)**

Use `/failure-mode-review` skill when PR touches:
- Caching or persistence logic
- Cross-script/cross-module integrations (env vars, file paths)
- State machines or lifecycle management
- Code handling external inputs (files, JSON, env vars)

Key questions:
- For each env var: did you verify the consumer reads that exact name?
- For each cache: what happens when source disappears but cache remains?
- For each error return: what does the caller do with it?
- For each `|| true` or silent catch: is silent failure safe here?

## PRD Audit Patterns

- Clear `.context/prd_slice.json` and `.context/prd_audit_cache.json` before re-running slice audits after modifying prd.json
- Valid `enforcement_point` values: `PolicyGuard|EvidenceGuard|DispatcherChokepoint|WAL|AtomicGroupExecutor|StatusEndpoint`
- Valid `failure_mode` values: `stall|hang|backpressure|missing|stale|parse_error`
- Valid `loss_mode` subfields: `worst_case` (economic worst case), `fail_closed_cap` (how fail-closed limits damage), `drift_metric` (runtime metric to monitor for drift). All three required non-empty for `passes=true` (exempt: policy/certification)
- `enforcing_contract_ats` must reference existing AT-XXX anchors in CONTRACT.md (not placeholder AT-000)
- PRD `scope.touch` should stay within a single subsystem (crate) to keep stories bite-sized
