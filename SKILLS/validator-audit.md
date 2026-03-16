# SKILL: /validator-audit (Validator Completeness Audit)

Purpose
- Find **missing validations** in rule-based validators, not just bugs in existing rules
- Answer "what SHOULD be validated but isn't?" rather than "does this rule work?"
- Detect paper compliance: data that passes all rules but doesn't prove what it claims
- Complements `/failure-mode-review` (which checks how existing code fails) and `/contract-review` (which checks contract alignment of production code)

When to use
- Reviewing validation rule sets (proof graph rules, schema validators, gate checks)
- Reviewing merge/aggregate functions that combine multiple sources
- After adding new fields/enums to a data model — are they validated?
- When a validator is the quality gate for a pipeline (CI, workflow, deploy)
- **Any new Python module or shell script that reads structured input and produces a gating verdict** — e.g., proposal evaluators, harness scoring scripts, autoresearch render tools, contract patch renderers. "Tooling" is not a reason to skip.
- When an external reviewer finds gaps your skills missed (retrospective)

**The domain-agnostic test:** Does this code (1) accept structured input, (2) apply correctness checks, and (3) gate or score downstream output? If yes → apply this skill, regardless of whether it touches the trading engine.

When NOT to use
- Simple single-rule fixes (use `/pr-review`)
- Production enforcement code (use `/contract-review`)
- Implementation failure modes (use `/failure-mode-review`)

---

## Before You Start (MANDATORY)

### 1. Identify the validator boundary

Map the three layers:
```
DATA MODEL (schema/types)  →  RULES (validation functions)  →  CONSUMERS (what trusts the output)
```

Read all three before starting. The audit compares MODEL against RULES to find gaps, then checks whether CONSUMERS would be harmed by those gaps.

### 2. Inventory the data model

Enumerate every field, enum, and type in the schema:
```bash
# For Python dataclasses/Pydantic
rg "class.*:" schema.py enums.py --type py

# For Rust structs
rg "pub struct|pub enum" --type rust

# For JSON schemas
rg '"properties"|"enum"' --type json
```

### 3. Inventory the rules

List every validation rule and what it checks:
```bash
# For function-per-rule patterns
rg "^def r_|^fn r_" --type py --type rust

# For rule registration
rg "ALL_RULES|RULES|validators" --type py --type rust
```

### 4. Triage: which sections apply?

| If the validator involves... | Apply sections... |
|------------------------------|-------------------|
| Enum types in conditions | **Always** §1 Enum Exhaustiveness |
| Schema fields | **Always** §2 Field Coverage |
| Imports/types not in rules | **Always** §3 Dead Import Detection |
| Merge/aggregate of multiple sources | §4 Merge Invariants |
| Threshold comparisons (>, <, in) | §5 Threshold Boundary |
| "Proven" / "passed" / "valid" verdicts | **Always** §6 Paper Compliance |
| Counts, totals, summaries | §7 Derived Value Consistency |
| Multiple schema versions | §8 Version Gate Coverage |
| Iterative calibration / self-improving pipelines | §9 Benchmark and Promotion Integrity |

**Always apply**: §1, §2, §3, §6 — these catch the most gaps.

---

## Review Process

### 1. Enum Exhaustiveness (HIGHEST SIGNAL)

For each enum used in a rule condition, check whether ALL relevant members are covered.

```python
# BAD: Rule fires on MED/HIGH but not CRITICAL
if level in (LossModeLevel.MED, LossModeLevel.HIGH):  # CRITICAL slips through

# GOOD: Explicit about what's included
if level in (LossModeLevel.MED, LossModeLevel.HIGH, LossModeLevel.CRITICAL):
```

Checklist:
- [ ] For each `in (EnumA, EnumB)` check: list ALL enum members. Which are excluded? Is exclusion intentional?
- [ ] For each `== EnumValue` check: what happens for every OTHER member? Is the implicit else safe?
- [ ] For enums with a severity/risk ordering: does the rule cover the ENTIRE dangerous range, not just the middle?
- [ ] Document each exclusion with rationale (e.g., "NONE/LOW excluded because non-safety-critical")

**Anti-pattern**: Rules that check `MED/HIGH` but forget `CRITICAL` — the most dangerous level falls through silently.

### 2. Field Coverage Matrix

Build a matrix: every schema field vs. every rule that touches it. Look for uncovered fields.

```
| Field                  | Checked by | Missing check?                    |
|------------------------|------------|-----------------------------------|
| at_verdict.verdict     | R-001..015 | OK                                |
| at_verdict.severity    | R-009,010  | OK                                |
| test.pass_result       | ???        | NO RULE CHECKS THIS               |
| test.causal_proof.*    | R-024,024b | mechanism validated, but assertions not required |
| premortem.section2_*   | ???        | AssumptionStatus imported but unused |
```

Checklist:
- [ ] Every required field in the schema has at least one rule that rejects invalid values
- [ ] Every field that affects a verdict/decision is validated, not just present
- [ ] Boolean fields: is `false` when `true` is required caught by a rule?
- [ ] String fields: is empty string caught? (not just missing/null)
- [ ] Numeric fields: are out-of-range values caught?

### 3. Dead Import Detection

Grep for types/enums imported into the rules module but never used in any rule condition.

```bash
# Find imports
rg "^from.*import|^use " rules.py validator.rs

# For each imported type, check if it's used in a rule body
rg "AssumptionStatus" rules.py  # If only in import line → dead import → missing rule
```

Checklist:
- [ ] Every imported enum/type appears in at least one rule condition (not just the import line)
- [ ] Every imported enum/type that ISN'T used: is it a missing rule or a cleanup candidate?
- [ ] For each dead import: would the validator be unsafe without a rule for this type?

**Signal**: An imported-but-unused type almost always means someone intended to write a rule but didn't.

### 4. Merge Invariants

For aggregate/merge functions that combine multiple inputs:

```python
# BAD: Severity only updated when verdict changes
if strictest != base_verdict:
    base_at["severity"] = reviewer_severity  # Same verdict, stricter severity → MISSED

# GOOD: Severity tightened independently
merged_severity = max(all_severities, key=severity_rank)
```

Checklist:
- [ ] **Order independence**: does swapping input order change the output? Test with `[A, B]` vs `[B, A]`
- [ ] **Severity independence**: is severity updated even when the verdict doesn't change?
- [ ] **Tie-breaking**: when two inputs have equal rank, is the winner deterministic or order-dependent?
- [ ] **Metadata lifecycle**: are temporary/conflict fields cleaned up when no longer applicable?
- [ ] **Empty input**: what happens with zero inputs? One input? Does it degrade gracefully?

### 5. Threshold Boundary Analysis

For every comparison against a threshold or set membership:

```python
# Rule fires at MED/HIGH. What about values ABOVE HIGH?
# Rule fires at > 0. What about exactly 0? What about negative?
# Rule fires at < 1. What about NaN? What about infinity?
```

Checklist:
- [ ] For each `in (A, B)` — what values are ABOVE B? Are they intentionally excluded or forgotten?
- [ ] For each `> threshold` — what about exactly `threshold`? Off-by-one?
- [ ] For each numeric comparison — what about NaN, infinity, negative, zero, MAX?
- [ ] For "trading halt" vs "validation failure" thresholds — document which is tighter and why

### 6. Paper Compliance Detection (CRITICAL)

Can data pass ALL rules while being substantively wrong? This is the hardest class of bug.

```python
# Can a graph with pass_result=false tests get PROVEN_INTEGRATED verdict?
# → YES if no rule checks pass_result. Paper compliance!

# Can a graph claim "PROVEN" with zero tests?
# → R-012 catches enforcement FOUND + zero tests, but only as HARDENING (not BLOCKING)

# Can mechanism="dispatch_count" pass without dispatch_count_assert being set?
# → YES if no rule requires mechanism-specific assertions
```

Checklist:
- [ ] Can the most permissive verdict (`PROVEN_INTEGRATED`) coexist with failing tests? If yes → missing rule
- [ ] Can a proof claim be made with no supporting evidence? (tests=[], evidence=[])
- [ ] For each "mechanism" type: does the validator require mechanism-specific data? Or just the string?
- [ ] Can `reconciliation_status=RECONCILED` coexist with unproven ATs? (not just BLOCKING ones)
- [ ] Construct a **minimal adversarial input** that passes all rules but is clearly wrong. If you can build one, there's a gap.

**Path-derived metadata**: When `run_id` and `fixture_id` are encoded in the directory structure rather than JSON fields, the schema cannot validate them. Check whether required identifiers live in the file or only in the path — path-only means per-fixture attribution depends entirely on naming conventions with no machine-enforceable contract.

**Technique**: Build the most dishonest input that could pass validation. If it passes, you've found a gap.

### 7. Derived Value Consistency

For fields computed from other fields (counts, booleans, summaries):

Checklist:
- [ ] Is the derived value recomputed after mutations, or could it be stale?
- [ ] Does the recomputation use the same logic as the original computation?
- [ ] Are there rules that detect recomputation drift (e.g., R-025 for trading_halt)?
- [ ] For count fields: trace every increment/decrement. Can the count go negative? Exceed array length?

### 8. Version Gate Coverage

For validators that support multiple schema versions:

Checklist:
- [ ] V2 rules properly gated by `_is_v2()` or equivalent?
- [ ] V1 data doesn't accidentally trigger V2 rules?
- [ ] V2-only fields have V2-specific validation (not just V1 rules applied to V2)?
- [ ] Schema version itself validated (unknown version → reject, not ignore)?

### 9. Benchmark and Promotion Integrity

For validators embedded in iterative self-improvement loops (calibration harnesses, auto-patching pipelines, scored feedback loops). Skip for single-pass validators.

Checklist:
- [ ] **Monotonic benchmark**: Can `refresh_fixtures.sh` or equivalent rewrite the pass threshold from the candidate's own current output? A reviewed, human-authored inventory artifact must floor the threshold; it may only increase unless a human explicitly modifies the inventory file.
- [ ] **Authoritative-source vs declared-metadata**: For every proposal-declared field used in routing or gating, is the value resolved from an authoritative sibling artifact, not merely required and present?
- [ ] **Coordinate bridge**: If evaluation uses local coordinates (fixture line numbers) and promotion uses global coordinates (live file), is the fixture-local -> live-file resolve step explicitly specified?
- [ ] **Single-writer ownership**: For each mutable promotion-state artifact (for example `proposals_index.json`, status transitions such as `verifying -> applied`), is there exactly one code path that writes each state?
- [ ] **Canonical review artifact**: Does human approval produce a dedicated, machine-readable record with `run_id`, `proposal_id`, `decision`, `reviewer`, `timestamp`, `base_contract_hash`, and `reason_code`?

Evidence checks (deterministic):
- [ ] Trace every write to threshold/count fields in eval configs (for example `rg -n "expected_gate_input_count|threshold|target_count"`).
- [ ] For each gating field, show both declaration/read site and authoritative cross-check site.
- [ ] Trace every writer to promotion-state artifacts (for example `rg -n "proposals_index|verifying|applied"`).

**Anti-pattern**: A spec that says "human reviews and marks accepted/rejected in proposals.json" has no canonical machine-readable proof of what the human decided.

---

## Reviewer Anti-Patterns (Mistakes to Avoid)

1. **Checking rules work, not checking rules exist**: Verifying R-009 counts correctly is `/failure-mode-review` territory. This skill asks "is there an R-027 that should exist but doesn't?"

2. **Assuming imports mean coverage**: `from .enums import AssumptionStatus` doesn't mean assumptions are validated. Trace from import to rule condition to assertion.

3. **Trusting the rule count**: "29 rules" sounds comprehensive. But if the schema has 40 validatable fields and only 20 are checked, coverage is 50%. Count fields, not rules.

4. **Ignoring the "obvious" fields**: `pass_result` seems so obvious that reviewers assume it's checked. It's exactly the fields everyone assumes are validated that aren't.

5. **Threshold confirmation bias**: Seeing `MED/HIGH` in a rule and thinking "that covers the dangerous range" — without checking whether `CRITICAL` (the MOST dangerous) is included.

6. **Testing the validator, not adversarial inputs**: Unit tests that pass valid/invalid data through rules prove the rules work. They don't prove the rules are sufficient. Construct adversarial inputs that SHOULD fail but don't.

---

## Output Format

```markdown
## Validator Audit: <component>

### Data Model Inventory
- Schema: <path> — <N fields, M enums>
- Rules: <path> — <N rules>
- Consumers: <what trusts this validator's output>

### Coverage Matrix
| Field / Type | Checked by | Gap? | Severity |
|---|---|---|---|
| field_a | R-001, R-008 | OK | — |
| field_b | — | MISSING | HIGH |
| EnumType.VARIANT | R-002 excludes | PARTIAL | MEDIUM |

### Findings

#### CRITICAL
- **<title>** — `file:line`
  - Gap: <what's not validated>
  - Adversarial input: <construct one>
  - Impact: <what consumers would trust incorrectly>
  - Fix: <new rule or rule modification>

#### HIGH
- ...

#### MEDIUM
- ...

### Enum Exhaustiveness
- [ ] `LossModeLevel` in R-002: covers MED/HIGH — missing CRITICAL?
- [ ] `Verdict` in R-015: covers FAIL_OPEN_RISK — what about WRONG_IMPL_UNBLOCKED?

### Merge Invariants (if applicable)
- [ ] Order independence: tested?
- [ ] Severity independence: tested?
- [ ] Tie-breaking: deterministic?
- [ ] Metadata cleanup: on re-aggregation?

### Benchmark and Promotion Integrity (if applicable)
- [ ] Monotonic benchmark: threshold cannot drop without human inventory change?
- [ ] Authoritative-source: all gating fields resolved from ground truth, not just present?
- [ ] Coordinate bridge: fixture-local -> live-file promotion address explicitly defined?
- [ ] Single-writer: each promotion state has exactly one writer?
- [ ] Review artifact: canonical machine-readable record of human decisions exists?

### Paper Compliance Test
Adversarial input that passes all rules but is substantively wrong:
```json
{ "description": "...", "why_it_passes": "...", "why_its_wrong": "..." }
```

### Dead Imports
- `AssumptionStatus` — imported, unused in any rule → missing §2 assumption validation

### Recommendations (prioritized)
1. <highest-impact new rule>
2. <threshold fix>
3. <merge invariant fix>
```

---

## Common Gap Patterns

| Pattern | Gap | Detection |
|---------|-----|-----------|
| Enum subset in condition | Highest/most dangerous member excluded | List all members, check which are in the condition |
| Imported but unused type | Rule was intended but never written | Grep imports vs. rule bodies |
| Boolean field unchecked | `false` when `true` required passes silently | Field coverage matrix |
| String field presence-only | Empty string passes, placeholder passes | Check for `.strip()` / `PLACEHOLDER_RE` coverage |
| Mechanism string validated, data not | "dispatch_count" accepted, but `dispatch_count_assert` not required | Trace mechanism → required subfields |
| Count recomputed, boolean not | `blocking_count` recalculated, `trading_halt` stale | Check which derived fields have consistency rules |
| Merge ignores same-value severity | Verdict matches → severity update skipped | Test same-verdict-different-severity inputs |
| Tie-break by input order | First reviewer wins on equal rank | Test with reversed input order |
| Metadata not cleaned up | Old conflicts persist after resolution | Test re-aggregation after disagreement resolved |
| Version gate missing | V2 rule runs on V1 data or V1 rule misses V2 field | Check `_is_v2()` guards |
| Threshold gap at boundary | MED/HIGH checked, CRITICAL forgotten | Enumerate full range above threshold |
| Self-lowering threshold | Refresh script recomputes threshold from current state; regression silently drops the bar | Trace every write to threshold/count fields in eval configs |
| Declared-metadata gating | Gating field required by schema but not cross-checked against authoritative source | For each gating field, find where it is declared and where it is verified against ground truth |
| Missing coordinate bridge | Fixture-local line spans reused as live-file write coordinates | Trace applicator use of `start_line`/`end_line` and confirm explicit live-coordinate resolution |

---

## Integration with Other Skills

- Run `/pr-review` first for general code correctness
- Run `/failure-mode-review` for how existing rules fail (error paths, state, concurrency)
- Use **this skill** (`/validator-audit`) to find missing rules and coverage gaps
- Use `/contract-review` to check whether the rules align with CONTRACT.md requirements
- Use `/strategic-failure-review` for architectural concerns about the validation pipeline itself

**Sequencing**: `/pr-review` → `/validator-audit` → `/failure-mode-review` → `/contract-review`

The first two catch "is anything missing?" before the latter two check "does what exists work correctly?"
