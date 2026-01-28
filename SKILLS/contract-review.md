# SKILL: /contract-review (Contract Compliance Review)

Purpose
- Identify HIGH-CONFIDENCE contract violations in code changes
- Focus on safety-critical patterns that could cause fail-open behavior
- Minimize false positives by requiring CONTRACT.md citation

When to use
- Before merging PRs that touch `crates/soldier_core/` or `crates/soldier_infra/`
- After implementing CONTRACT.md requirements
- When reviewing code from other contributors

## Vulnerability Categories (Safety-Critical)

### 1. Fail-Open Patterns
- `unwrap()` or `expect()` in production paths
- Default to `TradingMode::Active` when uncertain
- Missing staleness checks on critical inputs
- Silent error swallowing (`let _ =`, `.ok()`)

### 2. TradingMode/PolicyGuard Violations
- Bypassing PolicyGuard for dispatch decisions
- Incorrect mode resolution logic
- Missing mode_reasons in /status
- Latch not set on required events (WS gap, restart, etc.)

### 3. Intent Classification Errors
- OPEN classified as CLOSE (allows risky trades)
- Missing fail-closed default for unknown intents
- reduce_only flag not checked correctly

### 4. Execution Layer Violations
- Dispatch without TradingMode check
- Missing reject reason codes
- Acceptance test not proving causality

### 5. Observability Gaps
- /status missing required fields (§7.0)
- Decision snapshots not retained
- Missing structured logging context

## Exclusions (Do NOT Flag)

- Test files (`*_test.rs`, `tests/`)
- Documentation and comments
- Python tooling scripts (unless safety-critical)
- Theoretical issues without exploitation path
- Style preferences not in CLAUDE.md

## Analysis Methodology

### Phase 1: Context Research
```bash
# Understand what changed
git diff main...HEAD --name-only
git log --oneline main...HEAD

# Read relevant CONTRACT.md sections
contract_lookup("2.2")  # PolicyGuard
contract_lookup("3.0")  # Execution layer
```

### Phase 2: Pattern Matching
For each changed file in `crates/`:
1. Search for `unwrap()`, `expect()`, `let _ =`
2. Check TradingMode handling against §2.2
3. Verify intent classification follows §Definitions
4. Confirm error handling matches contract requirements

### Phase 3: Causality Verification
For new guards/rules:
- [ ] TRIP acceptance test exists
- [ ] NON-TRIP acceptance test exists
- [ ] Tests prove causality (dispatch count OR reason code)

## Output Format

```markdown
## Contract Review Findings

### [SEVERITY] Finding Title
**File:** `path/to/file.rs:123`
**Contract Ref:** §X.Y.Z
**Category:** Fail-Open Pattern | TradingMode Violation | ...

**Description:**
What the code does wrong.

**Violation:**
Specific CONTRACT.md requirement that is violated.

**Exploit Scenario:**
How this could cause unsafe behavior in production.

**Fix:**
Concrete remediation steps.

---
```

## Confidence Threshold

Only report findings where:
- You can cite a specific CONTRACT.md section
- There is a concrete path to unsafe behavior
- The fix is actionable and clear

Do NOT report:
- "This looks suspicious" without contract citation
- Style issues or preferences
- Theoretical concerns without exploitation path

## Severity Levels

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Could cause unintended trades or capital loss |
| **HIGH** | Bypasses safety guards, missing fail-closed |
| **MEDIUM** | Observability gap, missing acceptance test |
| **LOW** | Minor contract drift, documentation mismatch |

## Quick Commands

```bash
# Check for unwrap in changes
git diff main...HEAD -- '*.rs' | grep -n "\.unwrap()"

# Check for silent error ignoring
git diff main...HEAD -- '*.rs' | grep -n "let _ ="

# Validate contract crossrefs
python3 scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --strict

# List touched sections
git diff main...HEAD -- specs/CONTRACT.md | grep "^+.*§"
```
