# Skills 2.0: `/review-stack` and `/premortem` Migration & Evaluation

**Date:** 2026-03-14
**Status:** Approved (v2 — post spec-review fixes)
**Scope:** Wrapper-only format migration + autoresearch evaluation for `/review-stack`; wrapper-only migration for `/premortem` (eval already exists)

---

## 1. Goals

1. Expose `/review-stack` and `/premortem` as formal Claude Code Skills 2.0 skills (YAML frontmatter, dynamic context injection, `context: fork` subagent isolation)
2. Add autoresearch evaluation for `/review-stack` — orchestration fidelity (T1/T2) + end-to-end catch rate (T3/T5)
3. Zero disruption to existing autoresearch loop, SKILLS/ source files, and the 11 skills already under calibration

---

## 2. Approach: Wrapper-Only

The `SKILLS/*.md` files remain the authoritative source of truth and the autoresearch loop continues targeting them. Thin `.claude/skills/*/SKILL.md` wrappers use `!cat` dynamic injection to pull the content at invocation time — any edit to `SKILLS/review-stack.md` is automatically reflected on the next invocation. The wrapper command resolves the repo root with `git rev-parse --show-toplevel`, so it works from any repo subdirectory and fails closed if the source file cannot be loaded.

**Why not replace/mirror/parallel?**
- Autoresearch loop hardcodes `SKILLS/` paths in `eval.json` and `program.md`
- `/premortem` autoresearch is actively running on this branch — no path changes mid-calibration
- Wrapper is reversible: delete `.claude/skills/` entries, nothing else changes
- If the pattern proves valuable, migrating the rest of SKILLS/ is mechanical

---

## 3. File Structure

### New files — wrapper migration

```
.claude/skills/
├── review-stack/
│   └── SKILL.md
└── premortem/
    └── SKILL.md
```

### New files — review-stack evaluation

```
autoresearch/skills/review-stack/
├── eval.json
├── results.tsv
├── outputs/              ← auto-created by harness, listed for clarity
└── fixtures/
    ├── safe_refactor.diff
    ├── single_planted_p1.diff
    ├── fail_open_dispatch.diff
    ├── wrong_impl_passes_tests.diff
    └── multi_issue_cross_skill.diff
```

### Unchanged

```
SKILLS/review-stack.md              ← wrappers !cat this
SKILLS/premortem.md                 ← wrappers !cat this
autoresearch/skills/premortem/      ← already complete, no changes
autoresearch/skills/program.md      ← no changes needed
```

---

## 4. Wrapper Format

### `.claude/skills/premortem/SKILL.md`

```yaml
---
name: premortem
description: Pre-implementation safety analysis — 25 binary assertions, STOPLIGHT gate (GREEN/YELLOW/RED), Hard Gate table. Blocks implementation if RED.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash"]
---

!`cat "$(git rev-parse --show-toplevel)/SKILLS/premortem.md"`
```

### `.claude/skills/review-stack/SKILL.md`

```yaml
---
name: review-stack
description: Full 7-skill review stack — pr-review → failure-mode → strategic → contract → validator-audit → devils-advocate → loss-risk-gate. Produces P0/P1/P2 verdict.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat "$(git rev-parse --show-toplevel)/SKILLS/review-stack.md"`
```

**Key decisions:**
- `context: fork` on both — isolated subagent context per invocation, no bleed between sequential skill runs
- `Agent` in allowed-tools for review-stack only — orchestrator needs to spawn sub-reviewers; premortem does not
- Wrapper command resolves from the git toplevel — portable across repo subdirectories and fail-closed on missing source
- `allowed-tools` uses JSON array format — consistent with all existing `.claude/skills/` modules

---

## 5. `/review-stack` Evaluation Design

### Autoresearch Loop Scope Note

**Important:** The autoresearch loop for `/review-stack` targets `SKILLS/review-stack.md` — the orchestrator file. Useful edits to this file can improve **orchestration fidelity** (T1/T2): sequencing, skip-condition logic, synthesis format, artifact structure.

**Catch rate (T3/T5) is determined by the sub-skills**, not the orchestrator. If T3/T4/T5 fail, the correct response is NOT to edit `review-stack.md` but to open a new autoresearch run on the specific sub-skill that missed the issue (e.g., `contract-review`, `devils-advocate`). The T3/T5 scores in `results.tsv` are diagnostic — they reveal which sub-skill needs calibration, not where to edit.

### Eval Harness: Git Dependency Handling

`/review-stack` normally reads git state (diff, base branch). In eval context, fixtures supply the diff directly. Each test's `prompt` field instructs the model to:
- Treat the fixture content as the complete git diff output
- Skip all git commands (`git diff`, `git rev-parse`, etc.)
- Use `STORY_ID=TEST-01` and `BASE_BRANCH=main` as literals

### Format

5 tests × 5 assertions = 25 binary checks. Same `eval.json` schema, same `results.tsv` columns, same scoring logic in `program.md`.

---

### Test Specifications

#### T1 — `orchestration_all_skills`

**Fixture:** `safe_refactor.diff` — a pure rename + doc update, no risks.
**Domain:** Orchestration fidelity
**Purpose:** Proves all 7 reviewers are invoked and synthesis is produced without false positives.

**Prompt:**
```
You are running /review-stack. Story ID: TEST-01, Base branch: main.
The diff for this story is provided below — treat this as the complete git diff output.
Skip all git commands and run all 7 review skills (pr-review, failure-mode-review,
strategic-failure-review, contract-review, validator-audit, devils-advocate,
loss-risk-gate) on this diff. Produce the full review-stack output including synthesis.

<diff>
[fixture content]
</diff>
```

**Assertions:**

| ID | Check | Rule |
|----|-------|------|
| T1-A1 | Output references all 7 skill names | `{"type": "count_min", "pattern": "(?i)(pr.review\|failure.mode\|strategic\|contract.review\|validator.audit\|devils?.advocate\|loss.risk)", "min": 7}` |
| T1-A2 | Synthesis/verdict section present | `{"type": "regex", "pattern": "(?i)synthesis\|verdict\|overall"}` |
| T1-A3 | Verdict is PASS | `{"type": "regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS\|PASS\\s*verdict"}` |
| T1-A4 | No P0 findings (false positive check) | `{"type": "not_regex", "pattern": "(?i)\\bP0\\b.{0,40}(finding\|issue\|blocker\|risk\|critical)"}` |
| T1-A5 | Findings summary section present | `{"type": "regex", "pattern": "(?i)P0\\s*[:\\-]?\\s*0\|no P0\|zero P0"}` |

---

#### T2 — `orchestration_synthesis`

**Fixture:** `single_planted_p1.diff` — one `unwrap()` call in a non-critical logging path.
**Domain:** Orchestration fidelity
**Purpose:** Proves synthesis correctly counts a P1 finding and assigns CONDITIONAL verdict.

**Anchor string in fixture:** `tracing_ctx.unwrap()` in a non-dispatch path.

**Prompt:** Same template as T1, substituting fixture content.

**Assertions:**

| ID | Check | Rule |
|----|-------|------|
| T2-A1 | At least one P1 finding in output | `{"type": "count_min", "pattern": "(?i)\\bP1\\b", "min": 1}` |
| T2-A2 | Verdict is CONDITIONAL | `{"type": "regex", "pattern": "(?i)CONDITIONAL"}` |
| T2-A3 | Finding has explicit severity label | `{"type": "regex", "pattern": "(?i)\\bP1\\b.*unwrap\|unwrap.*\\bP1\\b"}` |
| T2-A4 | Summary section present | `{"type": "regex", "pattern": "(?i)summary\|synthesis"}` |
| T2-A5 | No P0 claim (summary count line ok) | `{"type": "not_regex", "pattern": "(?i)\\bP0\\b.{0,40}(finding\|issue\|blocker\|risk\|critical)"}` |

---

#### T3 — `catch_fail_open`

**Fixture:** `fail_open_dispatch.diff`
**Domain:** Catch rate
**Purpose:** Proves contract-review or failure-mode-review catches a fail-open gate.

**Planted issue:** `check_dispatch_allowed()` returns `true` on `Err(_)` instead of `false`.

**Anchor strings in fixture:**
```rust
fn check_dispatch_allowed(&self, intent: &Intent) -> bool {
    match self.policy.get_mode() {
        Ok(mode) => mode == TradingMode::Active,
-       Err(_) => false,
+       Err(_) => true,   // fail-open on policy error
    }
}
```

**Prompt:** Same template as T1, substituting fixture content.

**Assertions:**

| ID | Check | Rule |
|----|-------|------|
| T3-A1 | Fail-open finding present | `{"type": "regex", "pattern": "(?i)fail.open\|returns true on error\|Err.*true\|fail open"}` |
| T3-A2 | Attributed to contract-review or failure-mode | `{"type": "regex", "pattern": "(?i)contract.review\|failure.mode"}` |
| T3-A3 | Severity is P0 or P1 | `{"type": "regex", "pattern": "(?i)\\bP0\\b\|\\bP1\\b"}` |
| T3-A4 | Verdict is not PASS | `{"type": "not_regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS\\b"}` |
| T3-A5 | Economic/loss risk flagged | `{"type": "regex", "pattern": "(?i)economic\|capital\|loss\|financial risk"}` |

---

#### T4 — `catch_wrong_impl`

**Fixture:** `wrong_impl_passes_tests.diff`
**Domain:** Catch rate
**Purpose:** Proves devils-advocate catches a gate that checks the wrong field.

**Planted issue:** `is_reduce_only()` checks `instrument_id` instead of `reduce_only`. Tests assert on `instrument_id` too, so they pass.

**Anchor strings in fixture:**
```rust
fn is_reduce_only(&self, intent: &Intent) -> bool {
-   intent.reduce_only == Some(true)
+   intent.instrument_id.ends_with("-PERP")  // wrong field — tests also use instrument_id
}
```

**Prompt:** Same template as T1, substituting fixture content.

**Assertions:**

| ID | Check | Rule |
|----|-------|------|
| T4-A1 | Wrong-impl or wrong-field finding present | `{"type": "regex", "pattern": "(?i)wrong.impl\|wrong.field\|instrument_id\|reduce_only.*instead\|incorrect.*field"}` |
| T4-A2 | Devils-advocate attribution | `{"type": "regex", "pattern": "(?i)devil.?s?.advocate"}` |
| T4-A3 | Test sufficiency questioned | `{"type": "regex", "pattern": "(?i)test.*sufficiency\|tests.*insufficient\|wrong.*reason\|pass.*wrong\|mutation"}` |
| T4-A4 | Verdict is not PASS | `{"type": "not_regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS\\b"}` |
| T4-A5 | Mutation or wrong-field described | `{"type": "regex", "pattern": "(?i)mutant\|mutation\|instrument_id.*reduce_only\|reduce_only.*instrument_id"}` |

---

#### T5 — `catch_multi_issue`

**Fixture:** `multi_issue_cross_skill.diff`
**Domain:** Catch rate
**Purpose:** Proves the stack catches issues requiring 3 different sub-skills.

**Planted issues (3 separate hunks):**
1. **failure-mode-review domain:** `l2_snapshot_age_ms` staleness check removed — stale L2 snapshot allowed through
2. **contract-review domain:** `unwrap_or(TradingMode::Active)` — optimistic trading mode default
3. **loss-risk-gate domain:** `check_spread_cross()` threshold guard removed — uncapped loss on spread cross

**Anchor strings in fixture:**
- `l2_snapshot_age_ms` (removed check)
- `unwrap_or(TradingMode::Active)` (optimistic default)
- `check_spread_cross` / `SPREAD_GATE_THRESHOLD` (removed guard)

**Prompt:** Same template as T1, substituting fixture content.

**Assertions:**

| ID | Check | Rule |
|----|-------|------|
| T5-A1 | At least 3 distinct severity-labeled findings | `{"type": "count_min", "pattern": "(?i)\\b(P0\|P1\|P2)\\b", "min": 3}` |
| T5-A2 | Findings reference at least 2 of the 3 planted anchors | `{"type": "count_min", "pattern": "(?i)(l2_snapshot_age_ms\|unwrap_or.*Active\|check_spread_cross\|SPREAD_GATE_THRESHOLD)", "min": 2}` |
| T5-A3 | At least one P0 finding | `{"type": "regex", "pattern": "(?i)\\bP0\\b"}` |
| T5-A4 | Verdict is FAIL | `{"type": "regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*FAIL\|FAIL\\s*verdict"}` |
| T5-A5 | Loss path or spread risk mentioned | `{"type": "regex", "pattern": "(?i)loss\|spread.*cross\|uncapped\|capital impact"}` |

---

### results.tsv Headers

```
commit	score	passed	total	status	description
```

Starts with one `pending` baseline row. Example format (matches `autoresearch/skills/premortem/results.tsv`):

```
commit	score	passed	total	status	description
pending	—	—	25	pending	initial baseline — no run yet
```

---

## 6. `/premortem` Evaluation

Already complete. `autoresearch/skills/premortem/eval.json` has 25 binary assertions across 5 tests. Active calibration is ongoing on branch `skill-autoresearch/premortem-mar14`. No new evaluation work required — wrapper only.

---

## 7. What Is Out of Scope

- Migrating any other SKILLS/ files to .claude/skills/ format
- Changes to `autoresearch/skills/program.md`
- Changes to `autoresearch/skills/premortem/eval.json` or fixtures
- Per-domain catch rate breakdown (Approach 2) — deferred to iteration 2 if baseline scores indicate it's needed
- Editing sub-skill files to improve T3/T5 catch rate — those belong in separate autoresearch runs per sub-skill

---

## 8. Implementation Order

1. Create `.claude/skills/premortem/SKILL.md` wrapper
2. Create `.claude/skills/review-stack/SKILL.md` wrapper
3. Create `autoresearch/skills/review-stack/fixtures/` (5 diff files, with anchor strings as specified in §5)
4. Create `autoresearch/skills/review-stack/eval.json` (25 assertions, using rule objects from §5)
5. Create `autoresearch/skills/review-stack/results.tsv` (headers + pending baseline row)
