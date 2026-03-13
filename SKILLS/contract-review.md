# SKILL: /contract-review (Fast Safety Filter)

## Purpose
Identify **HIGH-CONFIDENCE** contract violations in **code changes** that could cause **fail-open** behavior (unintended trades / capital loss).
This is a *surgical* review: minimal false positives, only actionable findings.

## Related skills
- Use **/contract-audit-full** when you need exhaustive coverage analysis:
  - "Does PRD cover the contract for CSP/GOP/FULL?"
  - "Are there conflicts/ambiguities between PRD and contract?"

## What this skill does NOT do
- Does **not** prove full contract compliance.
- Does **not** build a full AT-* coverage matrix.
- Does **not** validate docs/tooling/roadmap synchronization.
- Does **not** flag purely theoretical issues without an exploitation path.

Use **/contract-audit-full** when you need completeness/coverage.

## When to use
- Before merging PRs touching `crates/soldier_core/` or `crates/soldier_infra/`
- When any change touches: PolicyGuard, TradingMode, intent classification, WAL/RecordedBeforeDispatch, reconciliation, order dispatch, or owner endpoints
- Before changing workflow/harness files or flipping `passes` (subsumes former `/audit` skill)
- Before approving a PR that touches contract or workflow alignment

## Inputs
- `git diff main...HEAD` (or PR diff)
- `CONTRACT.md` (canonical)
- Optional: PRD story for the change (if it exists)

## Confidence rule (hard)
Only report a finding if **all** are true:
1) You cite a specific Contract section or Acceptance Test (AT-*).
2) There is a concrete path to unsafe behavior.
3) The fix is precise and implementable.

## Categories (safety-critical only)

### 1) Fail-open patterns
Flag when in production paths:
- `unwrap()` / `expect()`
- silent error swallowing: `let _ = ...`, `.ok()`, `unwrap_or_default()` on safety-critical values
- fallbacks that default to permissive behavior (e.g., `TradingMode::Active` on error)

### 2) TradingMode / PolicyGuard enforcement violations
Flag when:
- Any dispatch authorization bypasses PolicyGuard
- Mode is computed in multiple places ("split brain")
- Staleness/freshness checks required by contract are missing or use wall-clock incorrectly
- Open Permission Latch semantics are not enforced where required
- /status omits mode reasons / latch fields in a change that touches them

### 3) Intent classification errors
Flag when:
- UNKNOWN intent is treated as CLOSE/HEDGE/CANCEL
- `reduce_only` is not used correctly to classify OPEN vs CLOSE/HEDGE
- "Replace" is not treated as cancel + new order placement (OPEN gates apply)

### 4) Execution layer violations
Flag when:
- Any OPEN dispatch can occur without explicit "OPEN allowed" check
- Reject reason codes are missing / non-deterministic
- A new guard is added without TRIP + NON-TRIP acceptance coverage that proves causality

### 5) Owner endpoint hazards (read-only contract)
Flag when:
- Any endpoint allows risk mutation or "set Active"
- `/health` or `/status` payloads regress required keys/semantics in the touched code

## Exclusions (do NOT flag)
- Test files (`*_test.rs`, `tests/`) unless the test itself creates a fail-open illusion (e.g., asserting success while bypassing gating)
- Documentation and comments
- Python tooling scripts unless they are part of a safety gate used by CI/verify
- Style preferences not codified in CLAUDE.md / contract

## Method (4 phases)

### Phase 0 — Workflow alignment (quick)
If the change touches workflow/harness files, verify:
- Read `specs/WORKFLOW_CONTRACT.md` and identify affected clauses
- Confirm enforcement paths (script, contract, test) exist for each clause
- Confirm `verify.sh` / preflight / gate coverage where required
- Record evidence (commands + outputs)

Skip this phase if the change is pure Rust/application code with no workflow surface.

### Phase 1 — Context research
```bash
git diff main...HEAD --name-only
git log --oneline main...HEAD

# Pull the exact contract anchors touched by the change (search by keywords or AT ids)
rg -n "PolicyGuard|TradingMode|Open Permission|RecordedBeforeDispatch|WAL|reconcile|/api/v1/status|/api/v1/health|AT-" CONTRACT.md
```

### Phase 2 — Pattern scan
```bash
git diff main...HEAD -- '*.rs' | rg -n "\.unwrap\(|\.expect\(|let _ =|\.ok\(\)|unwrap_or_default"
```
Then inspect touched files for:
- Where is dispatch authorization enforced?
- Where is intent classified?
- Where is reduce_only injected?
- Where are latches / staleness checks applied?
- **For each NEW function that takes `ChokeIntentClass` or `IntentClass`**: trace CancelOnly through it. CancelOnly must never be blocked by non-dispatch failures (metadata, sizing, consistency). If the function runs sizing/validation before checking intent class, CancelOnly can be falsely rejected — this is a P1 cancel-blocking hazard.

### Phase 2.5 — Callsite trace

For each enforcement point in the story, verify it's called in the production dispatch path (not just tested):
```bash
# For each guard function, find production callers (excluding tests/)
rg "guard_function_name" crates/ --glob '*.rs' | grep -v '/tests/' | grep -v '_test.rs'
```
Zero production callers = dead enforcement = P1 finding.

### Phase 2.7 — Test-validates-unsafe check

When a diff modifies BOTH production code AND test code:
- Check whether any test change asserts or validates the unsafe production behavior introduced in the same diff
- A test that asserts a wrong safety classification (e.g., `assert_eq!(class, Close)` for unknown intents) is itself a finding — it enshrines the violation and makes it harder to catch later
- Report the test change as part of the production finding's evidence, not as a separate finding

### Phase 3 — Causality check
For each NEW or MODIFIED guard/latch/gate:
- Must have TRIP + NON-TRIP coverage
- Must prove causality via dispatch count OR reason code OR latch reason OR override field

## Output format (strict)

### When findings exist
```markdown
## Contract Review Findings

### [CRITICAL|HIGH|MEDIUM|LOW] <title>
**File:** path/to/file.rs:123
**Contract Ref:** §X.Y.Z or AT-###
**Category:** Fail-Open | PolicyGuard | Intent | Execution | Endpoint

**What changed:**
<one sentence>

**Violation:**
<exact contract rule being violated>

**Exploit scenario:**
<how this can cause unintended trades / unsafe behavior>

**Fix (actionable):**
<exact remediation steps>

**Evidence:**
<diff hunk or function name>

---

**Decision: FAIL** — N finding(s) require remediation before merge.
```

### When no findings exist
```markdown
## Contract Review Findings

No contract violations found.

**Scope reviewed:** <list files touched and why they are safe — e.g., "test-only change, no production code affected" or "documentation change, excluded per skill rules">

**Decision: PASS**
```

**Decision rules:**
- Any CRITICAL or HIGH finding -> **FAIL**
- Only MEDIUM or LOW findings -> **FAIL** (still requires remediation)
- Zero findings -> **PASS**

## Severity
- **CRITICAL**: Could cause unintended trades / exposure increase / capital loss
- **HIGH**: Bypasses safety gates, can fail-open under error or staleness
- **MEDIUM**: Observability or test causality gaps that can mask unsafe behavior
- **LOW**: Minor contract drift that is safe but will cause future failures
