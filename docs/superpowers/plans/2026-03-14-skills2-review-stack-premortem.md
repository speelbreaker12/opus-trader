# Skills 2.0: review-stack and premortem Migration & Evaluation

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `/review-stack` and `/premortem` as Claude Code Skills 2.0 skills (SKILL.md wrappers with `context: fork`) and add a 25-assertion autoresearch eval for `/review-stack`.

> **All commands assume cwd = repo root** (`/Users/admin/Desktop/opus-trader`). Run `pwd` to verify before starting.

**Architecture:** Thin `.claude/skills/*/SKILL.md` wrappers use `!cat` dynamic injection — the `SKILLS/` source files remain untouched and the autoresearch loop keeps targeting them. The `/review-stack` eval follows the exact same schema as the 11 existing skill evals (eval.json + fixtures/ + results.tsv).

**Tech Stack:** YAML frontmatter (Claude Code SKILL.md format), JSON (eval.json), unified diff format (fixtures), TSV (results.tsv)

**Spec:** `docs/superpowers/specs/2026-03-14-skills2-review-stack-premortem-design.md`

---

## Chunk 1: Wrapper Files

### Task 1: Create `.claude/skills/premortem/SKILL.md`

**Files:**
- Create: `.claude/skills/premortem/SKILL.md`

- [ ] **Step 1: Create the wrapper file**

```bash
mkdir -p .claude/skills/premortem
```

Then create `.claude/skills/premortem/SKILL.md` with this exact content:

```
---
name: premortem
description: Pre-implementation safety analysis — 25 binary assertions, STOPLIGHT gate (GREEN/YELLOW/RED), Hard Gate table. Blocks implementation if RED.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash"]
---

!`cat /Users/admin/Desktop/opus-trader/SKILLS/premortem.md`
```

- [ ] **Step 2: Verify the wrapper was written correctly and the `!cat` source exists**

```bash
# Confirm wrapper file exists at the expected path
ls .claude/skills/premortem/SKILL.md

# Confirm wrapper contains required frontmatter fields
grep -c "context: fork\|allowed-tools\|!.cat" .claude/skills/premortem/SKILL.md
```

Expected: `ls` prints the file path; `grep -c` prints `3`.

```bash
# Confirm the !cat source path resolves (absolute path, works from any cwd)
cat /Users/admin/Desktop/opus-trader/SKILLS/premortem.md | head -5
```

Expected: First 5 lines of the premortem skill content (not an error).

Note: The `!cat` path in the wrapper is intentionally absolute. Claude Code evaluates `!cmd` at invocation time regardless of cwd — a relative path would silently inject empty content.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/premortem/SKILL.md
git commit -m "skills2: add premortem SKILL.md wrapper (context: fork, !cat injection)"
```

---

### Task 2: Create `.claude/skills/review-stack/SKILL.md`

**Files:**
- Create: `.claude/skills/review-stack/SKILL.md`

- [ ] **Step 1: Create the wrapper file**

```bash
mkdir -p .claude/skills/review-stack
```

Then create `.claude/skills/review-stack/SKILL.md` with this exact content:

```
---
name: review-stack
description: Full 7-skill review stack — pr-review → failure-mode → strategic → contract → validator-audit → devils-advocate → loss-risk-gate. Produces P0/P1/P2 verdict.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat /Users/admin/Desktop/opus-trader/SKILLS/review-stack.md`
```

- [ ] **Step 2: Verify the wrapper was written correctly and the `!cat` source exists**

```bash
# Confirm wrapper file exists
ls .claude/skills/review-stack/SKILL.md

# Confirm wrapper contains required frontmatter fields including Agent tool
grep -c "context: fork\|allowed-tools\|Agent\|!.cat" .claude/skills/review-stack/SKILL.md
```

Expected: `ls` prints the file path; `grep -c` prints `4`.

```bash
# Confirm the !cat source path resolves
cat /Users/admin/Desktop/opus-trader/SKILLS/review-stack.md | head -5
```

Expected: First 5 lines of the review-stack skill content.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/review-stack/SKILL.md
git commit -m "skills2: add review-stack SKILL.md wrapper (context: fork, Agent tools)"
```

---

## Chunk 2: Fixtures

All fixtures go in `autoresearch/skills/review-stack/fixtures/`. Create the directory first:

```bash
mkdir -p autoresearch/skills/review-stack/fixtures autoresearch/skills/review-stack/outputs
```

---

### Task 3: `safe_refactor.diff` — No-risk rename (T1 fixture)

**Files:**
- Create: `autoresearch/skills/review-stack/fixtures/safe_refactor.diff`

This fixture is a pure function rename in reconciliation code. No logic change. Used by T1 to verify the stack produces no false positives.

- [ ] **Step 1: Create the fixture**

Create `autoresearch/skills/review-stack/fixtures/safe_refactor.diff`:

```diff
diff --git a/crates/soldier_infra/src/wal/reconcile.rs b/crates/soldier_infra/src/wal/reconcile.rs
index a1b2c3d..d4e5f6a 100644
--- a/crates/soldier_infra/src/wal/reconcile.rs
+++ b/crates/soldier_infra/src/wal/reconcile.rs
@@ -18,7 +18,7 @@ impl WalReconciler {
     /// Check whether the WAL entry is fully settled.
-    pub fn is_settled(&self, entry: &WalEntry) -> bool {
+    pub fn is_entry_settled(&self, entry: &WalEntry) -> bool {
         entry.fill_qty >= entry.intended_qty
     }

@@ -31,7 +31,7 @@ impl WalReconciler {
     /// Drain all settled entries from the pending list.
     pub fn drain_settled(&mut self, entries: &mut Vec<WalEntry>) {
-        entries.retain(|e| !self.is_settled(e));
+        entries.retain(|e| !self.is_entry_settled(e));
     }
 }

diff --git a/crates/soldier_infra/src/wal/reconcile.rs b/crates/soldier_infra/src/wal/reconcile.rs
@@ -4,1 +4,1 @@
-/// Settles WAL entries against fills.
+/// Settles WAL entries against fills. Renamed is_settled → is_entry_settled for clarity.
```

- [ ] **Step 2: Verify the file is valid diff format**

```bash
head -3 autoresearch/skills/review-stack/fixtures/safe_refactor.diff
```

Expected: `diff --git a/...` on line 1.

---

### Task 4: `single_planted_p1.diff` — One unwrap() in logging path (T2 fixture)

**Files:**
- Create: `autoresearch/skills/review-stack/fixtures/single_planted_p1.diff`

Planted bug: `tracing_ctx.unwrap()` in a non-dispatch logging path. Expected catch: pr-review flags it as P1.

- [ ] **Step 1: Create the fixture**

Create `autoresearch/skills/review-stack/fixtures/single_planted_p1.diff`:

```diff
diff --git a/crates/soldier_core/src/execution/logger.rs b/crates/soldier_core/src/execution/logger.rs
index b2c3d4e..e5f6a7b 100644
--- a/crates/soldier_core/src/execution/logger.rs
+++ b/crates/soldier_core/src/execution/logger.rs
@@ -24,6 +24,14 @@ impl ExecutionLogger {
     pub fn log_intent(&self, intent: &Intent) {
+        let tracing_ctx = self.context_map.get(&intent.id);
+        // Log enriched context when available
+        let ctx_label = tracing_ctx.unwrap().label.as_deref().unwrap_or("none");
+        tracing::info!(
+            intent_id = %intent.id,
+            ctx_label = %ctx_label,
+            "intent received"
+        );
     }
 }
```

- [ ] **Step 2: Verify**

```bash
grep "unwrap()" autoresearch/skills/review-stack/fixtures/single_planted_p1.diff
```

Expected: one line containing `tracing_ctx.unwrap()`.

---

### Task 5: `fail_open_dispatch.diff` — Fail-open gate (T3 fixture)

**Files:**
- Create: `autoresearch/skills/review-stack/fixtures/fail_open_dispatch.diff`

Planted bug: `check_dispatch_allowed()` returns `true` on `Err(_)` — fail-open on policy error. Anchor strings: `check_dispatch_allowed`, `Err(_) => true`.

- [ ] **Step 1: Create the fixture**

Create `autoresearch/skills/review-stack/fixtures/fail_open_dispatch.diff`:

```diff
diff --git a/crates/soldier_core/src/execution/dispatch_gate.rs b/crates/soldier_core/src/execution/dispatch_gate.rs
index c3d4e5f..f6a7b8c 100644
--- a/crates/soldier_core/src/execution/dispatch_gate.rs
+++ b/crates/soldier_core/src/execution/dispatch_gate.rs
@@ -31,10 +31,10 @@ impl DispatchGate {
     /// Returns true only when dispatch is permitted.
     /// Fail-closed: any uncertainty must block dispatch.
     pub fn check_dispatch_allowed(&self, intent: &Intent) -> bool {
         match self.policy.get_mode() {
             Ok(mode) => mode == TradingMode::Active,
-            Err(_) => false,  // fail-closed: block on policy error
+            Err(_) => true,   // fail-open on policy error
         }
     }
 }
```

- [ ] **Step 2: Verify anchor strings are present**

```bash
grep -c "Err.*true\|fail-open" autoresearch/skills/review-stack/fixtures/fail_open_dispatch.diff
```

Expected: `2` (both anchor lines present).

---

### Task 6: `wrong_impl_passes_tests.diff` — Wrong field, tests pass (T4 fixture)

**Files:**
- Create: `autoresearch/skills/review-stack/fixtures/wrong_impl_passes_tests.diff`

Planted bug: `is_reduce_only()` checks `instrument_id.ends_with("-PERP")` instead of `reduce_only == Some(true)`. The test is also updated to assert on `instrument_id`, so it passes. Anchor strings: `reduce_only`, `instrument_id`, `is_reduce_only`.

- [ ] **Step 1: Create the fixture**

Create `autoresearch/skills/review-stack/fixtures/wrong_impl_passes_tests.diff`:

```diff
diff --git a/crates/soldier_core/src/execution/intent_classifier.rs b/crates/soldier_core/src/execution/intent_classifier.rs
index d4e5f6a..a7b8c9d 100644
--- a/crates/soldier_core/src/execution/intent_classifier.rs
+++ b/crates/soldier_core/src/execution/intent_classifier.rs
@@ -15,7 +15,7 @@ impl IntentClassifier {
     /// Returns true if the intent is reduce-only (risk-reducing).
     pub fn is_reduce_only(&self, intent: &Intent) -> bool {
-        intent.reduce_only == Some(true)
+        intent.instrument_id.ends_with("-PERP")  // wrong field — checks instrument name not reduce_only flag
     }
 }

diff --git a/crates/soldier_core/src/execution/tests/intent_classifier_tests.rs b/crates/soldier_core/src/execution/tests/intent_classifier_tests.rs
index e5f6a7b..b8c9d0e 100644
--- a/crates/soldier_core/src/execution/tests/intent_classifier_tests.rs
+++ b/crates/soldier_core/src/execution/tests/intent_classifier_tests.rs
@@ -12,14 +12,14 @@ fn test_is_reduce_only_true() {
     let intent = Intent {
-        reduce_only: Some(true),
-        instrument_id: "BTC-USD".to_string(),
+        reduce_only: None,
+        instrument_id: "BTC-PERP".to_string(),
         ..Default::default()
     };
     assert!(classifier.is_reduce_only(&intent));
 }

 fn test_is_reduce_only_false() {
     let intent = Intent {
-        reduce_only: Some(false),
-        instrument_id: "BTC-PERP".to_string(),
+        reduce_only: None,
+        instrument_id: "BTC-USD".to_string(),
         ..Default::default()
     };
     assert!(!classifier.is_reduce_only(&intent));
 }
```

- [ ] **Step 2: Verify anchor strings**

```bash
grep -c "instrument_id\|reduce_only\|is_reduce_only" autoresearch/skills/review-stack/fixtures/wrong_impl_passes_tests.diff
```

Expected: at least `6` lines (all three anchor strings appear multiple times).

---

### Task 7: `multi_issue_cross_skill.diff` — Three planted issues (T5 fixture)

**Files:**
- Create: `autoresearch/skills/review-stack/fixtures/multi_issue_cross_skill.diff`

Three separate hunks with bugs from three different sub-skill domains:
1. **failure-mode-review**: `l2_snapshot_age_ms` staleness check removed
2. **contract-review**: `unwrap_or(TradingMode::Active)` optimistic default
3. **loss-risk-gate**: `SPREAD_GATE_THRESHOLD` guard removed from `check_spread_cross()`

- [ ] **Step 1: Create the fixture**

Create `autoresearch/skills/review-stack/fixtures/multi_issue_cross_skill.diff`:

```diff
diff --git a/crates/soldier_core/src/execution/liquidity_gate.rs b/crates/soldier_core/src/execution/liquidity_gate.rs
index a1b2c3d..c4d5e6f 100644
--- a/crates/soldier_core/src/execution/liquidity_gate.rs
+++ b/crates/soldier_core/src/execution/liquidity_gate.rs
@@ -44,11 +44,7 @@ impl LiquidityGate {
     pub fn check(&self, input: &LiquidityGateInput) -> Result<(), GateError> {
-        let l2_snapshot_age_ms = input.l2_snapshot.age_ms();
-        if l2_snapshot_age_ms > input.l2_book_snapshot_max_age_ms {
-            return Err(GateError::StaleSnapshot { age_ms: l2_snapshot_age_ms });
-        }
+        // staleness check removed — always use whatever snapshot is present
         self.check_depth(input)
     }
 }

diff --git a/crates/soldier_core/src/execution/policy_guard.rs b/crates/soldier_core/src/execution/policy_guard.rs
index b2c3d4e..d5e6f7a 100644
--- a/crates/soldier_core/src/execution/policy_guard.rs
+++ b/crates/soldier_core/src/execution/policy_guard.rs
@@ -22,7 +22,7 @@ impl PolicyGuard {
     pub fn resolve_trading_mode(&self) -> TradingMode {
-        self.cached_mode.ok_or(PolicyError::NotInitialized)
-            .map_err(|_| TradingMode::ReduceOnly)
-            .unwrap_or(TradingMode::ReduceOnly)
+        self.cached_mode.unwrap_or(TradingMode::Active)
     }
 }

diff --git a/crates/soldier_core/src/execution/spread_gate.rs b/crates/soldier_core/src/execution/spread_gate.rs
index c3d4e5f..e6f7a8b 100644
--- a/crates/soldier_core/src/execution/spread_gate.rs
+++ b/crates/soldier_core/src/execution/spread_gate.rs
@@ -18,10 +18,6 @@ const SPREAD_GATE_THRESHOLD: f64 = 0.002;
 impl SpreadGate {
     pub fn check_spread_cross(&self, best_bid: f64, best_ask: f64) -> Result<(), GateError> {
         let spread = (best_ask - best_bid) / best_bid;
-        if spread > SPREAD_GATE_THRESHOLD {
-            return Err(GateError::SpreadTooWide {
-                spread,
-                threshold: SPREAD_GATE_THRESHOLD,
-            });
-        }
+        // threshold check removed — allow any spread
         Ok(())
     }
 }
```

- [ ] **Step 2: Verify all three anchor strings are present**

```bash
grep -c "l2_snapshot_age_ms\|unwrap_or(TradingMode::Active)\|SPREAD_GATE_THRESHOLD\|check_spread_cross" autoresearch/skills/review-stack/fixtures/multi_issue_cross_skill.diff
```

Expected: at least `4` (each anchor appears at least once).

- [ ] **Step 3: Commit all fixtures**

```bash
git add autoresearch/skills/review-stack/
git commit -m "skills2: add review-stack autoresearch fixtures (5 diffs, T1-T5)"
```

---

## Chunk 3: eval.json and results.tsv

### Task 8: Create `autoresearch/skills/review-stack/eval.json`

**Files:**
- Create: `autoresearch/skills/review-stack/eval.json`

The eval.json must match the exact schema used by the autoresearch harness. Reference: `autoresearch/skills/premortem/eval.json` and `autoresearch/skills/contract-review/eval.json`.

**Important:** The `prompt` field for each test tells the harness how to invoke the skill with the fixture. Since `/review-stack` normally reads git state, each prompt instructs the model to treat the fixture as the complete git diff and skip git commands.

- [ ] **Step 1: Create eval.json**

Create `autoresearch/skills/review-stack/eval.json`:

```json
{
  "skill": "SKILLS/review-stack.md",
  "description": "Binary assertion tests for /review-stack skill output quality — orchestration fidelity (T1-T2) and end-to-end catch rate (T3-T5)",
  "total_assertions": 25,
  "tests": [
    {
      "id": "T1",
      "name": "orchestration_all_skills",
      "description": "Safe rename diff with no planted issues. Stack must invoke all 7 reviewers, produce synthesis, return PASS verdict, and generate zero P0 findings.",
      "fixture": "fixtures/safe_refactor.diff",
      "prompt": "You are running /review-stack. Story ID: TEST-01, Base branch: main. The diff for this story is provided below — treat this as the complete git diff output. Skip all git commands and run all 7 review skills (pr-review, failure-mode-review, strategic-failure-review, contract-review, validator-audit, devils-advocate, loss-risk-gate) on this diff. Produce the full review-stack output including synthesis.",
      "assertions": [
        {
          "id": "T1-A1",
          "check": "Output references all 7 skill names",
          "rule": {"type": "count_min", "pattern": "(?i)(pr.review|failure.mode|strategic|contract.review|validator.audit|devils?.advocate|loss.risk)", "min": 7},
          "expected": true
        },
        {
          "id": "T1-A2",
          "check": "Synthesis or verdict section present",
          "rule": {"type": "regex", "pattern": "(?i)synthesis|verdict|overall"},
          "expected": true
        },
        {
          "id": "T1-A3",
          "check": "Verdict is PASS",
          "rule": {"type": "regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS|PASS\\s*verdict"},
          "expected": true
        },
        {
          "id": "T1-A4",
          "check": "No P0 findings (P0 in summary count line is ok)",
          "rule": {"type": "not_regex", "pattern": "(?i)\\bP0\\b.{0,40}(finding|issue|blocker|risk|critical)"},
          "expected": true
        },
        {
          "id": "T1-A5",
          "check": "Summary confirms zero P0 findings",
          "rule": {"type": "regex", "pattern": "(?i)P0\\s*[:\\-]?\\s*0|no P0|zero P0"},
          "expected": true
        }
      ]
    },
    {
      "id": "T2",
      "name": "orchestration_synthesis",
      "description": "Diff with one unwrap() in a non-critical logging path. Stack must catch it as P1, assign CONDITIONAL verdict, and produce no P0 claims.",
      "fixture": "fixtures/single_planted_p1.diff",
      "prompt": "You are running /review-stack. Story ID: TEST-02, Base branch: main. The diff for this story is provided below — treat this as the complete git diff output. Skip all git commands and run all 7 review skills on this diff. Produce the full review-stack output including synthesis.",
      "assertions": [
        {
          "id": "T2-A1",
          "check": "At least one P1 finding in output",
          "rule": {"type": "count_min", "pattern": "(?i)\\bP1\\b", "min": 1},
          "expected": true
        },
        {
          "id": "T2-A2",
          "check": "Verdict is CONDITIONAL",
          "rule": {"type": "regex", "pattern": "(?i)CONDITIONAL"},
          "expected": true
        },
        {
          "id": "T2-A3",
          "check": "Finding explicitly labels the unwrap as P1",
          "rule": {"type": "regex", "pattern": "(?i)\\bP1\\b.*unwrap|unwrap.*\\bP1\\b"},
          "expected": true
        },
        {
          "id": "T2-A4",
          "check": "Summary or synthesis section present",
          "rule": {"type": "regex", "pattern": "(?i)summary|synthesis"},
          "expected": true
        },
        {
          "id": "T2-A5",
          "check": "No P0 finding claimed (summary count line ok)",
          "rule": {"type": "not_regex", "pattern": "(?i)\\bP0\\b.{0,40}(finding|issue|blocker|risk|critical)"},
          "expected": true
        }
      ]
    },
    {
      "id": "T3",
      "name": "catch_fail_open",
      "description": "Diff with check_dispatch_allowed() returning true on Err — fail-open on policy error. contract-review or failure-mode-review must catch it as P0/P1 with economic risk flagged.",
      "fixture": "fixtures/fail_open_dispatch.diff",
      "prompt": "You are running /review-stack. Story ID: TEST-03, Base branch: main. The diff for this story is provided below — treat this as the complete git diff output. Skip all git commands and run all 7 review skills on this diff. Produce the full review-stack output including synthesis.",
      "assertions": [
        {
          "id": "T3-A1",
          "check": "Fail-open finding is present",
          "rule": {"type": "regex", "pattern": "(?i)fail.open|returns true on error|Err.*true|fail open"},
          "expected": true
        },
        {
          "id": "T3-A2",
          "check": "Finding attributed to contract-review or failure-mode-review",
          "rule": {"type": "regex", "pattern": "(?i)contract.review|failure.mode"},
          "expected": true
        },
        {
          "id": "T3-A3",
          "check": "Severity is P0 or P1",
          "rule": {"type": "regex", "pattern": "(?i)\\bP0\\b|\\bP1\\b"},
          "expected": true
        },
        {
          "id": "T3-A4",
          "check": "Verdict is not PASS",
          "rule": {"type": "not_regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS\\b"},
          "expected": true
        },
        {
          "id": "T3-A5",
          "check": "Economic or loss risk is flagged",
          "rule": {"type": "regex", "pattern": "(?i)economic|capital|loss|financial risk"},
          "expected": true
        }
      ]
    },
    {
      "id": "T4",
      "name": "catch_wrong_impl",
      "description": "Diff where is_reduce_only() checks instrument_id instead of reduce_only flag; tests also updated to use instrument_id so they pass. devils-advocate must catch this as a wrong-impl mutation.",
      "fixture": "fixtures/wrong_impl_passes_tests.diff",
      "prompt": "You are running /review-stack. Story ID: TEST-04, Base branch: main. The diff for this story is provided below — treat this as the complete git diff output. Skip all git commands and run all 7 review skills on this diff. Produce the full review-stack output including synthesis.",
      "assertions": [
        {
          "id": "T4-A1",
          "check": "Wrong-impl or wrong-field finding present",
          "rule": {"type": "regex", "pattern": "(?i)wrong.impl|wrong.field|instrument_id|reduce_only.*instead|incorrect.*field"},
          "expected": true
        },
        {
          "id": "T4-A2",
          "check": "Finding attributed to devils-advocate",
          "rule": {"type": "regex", "pattern": "(?i)devil.?s?.advocate"},
          "expected": true
        },
        {
          "id": "T4-A3",
          "check": "Test sufficiency is questioned",
          "rule": {"type": "regex", "pattern": "(?i)test.*sufficiency|tests.*insufficient|wrong.*reason|pass.*wrong|mutation"},
          "expected": true
        },
        {
          "id": "T4-A4",
          "check": "Verdict is not PASS",
          "rule": {"type": "not_regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*PASS\\b"},
          "expected": true
        },
        {
          "id": "T4-A5",
          "check": "Mutation or wrong field pairing described",
          "rule": {"type": "regex", "pattern": "(?i)mutant|mutation|instrument_id.*reduce_only|reduce_only.*instrument_id"},
          "expected": true
        }
      ]
    },
    {
      "id": "T5",
      "name": "catch_multi_issue",
      "description": "Diff with 3 planted issues across 3 sub-skill domains: stale L2 check removed (failure-mode), optimistic TradingMode::Active default (contract), spread gate threshold removed (loss-risk-gate).",
      "fixture": "fixtures/multi_issue_cross_skill.diff",
      "prompt": "You are running /review-stack. Story ID: TEST-05, Base branch: main. The diff for this story is provided below — treat this as the complete git diff output. Skip all git commands and run all 7 review skills on this diff. Produce the full review-stack output including synthesis.",
      "assertions": [
        {
          "id": "T5-A1",
          "check": "At least 3 distinct severity-labeled findings",
          "rule": {"type": "count_min", "pattern": "(?i)\\b(P0|P1|P2)\\b", "min": 3},
          "expected": true
        },
        {
          "id": "T5-A2",
          "check": "At least 2 of the 3 planted anchor strings are referenced",
          "rule": {"type": "count_min", "pattern": "(?i)(l2_snapshot_age_ms|unwrap_or.*Active|check_spread_cross|SPREAD_GATE_THRESHOLD)", "min": 2},
          "expected": true
        },
        {
          "id": "T5-A3",
          "check": "At least one P0 finding",
          "rule": {"type": "regex", "pattern": "(?i)\\bP0\\b"},
          "expected": true
        },
        {
          "id": "T5-A4",
          "check": "Verdict is FAIL",
          "rule": {"type": "regex", "pattern": "(?i)verdict\\s*[:\\-]?\\s*FAIL|FAIL\\s*verdict"},
          "expected": true
        },
        {
          "id": "T5-A5",
          "check": "Loss path or spread risk mentioned",
          "rule": {"type": "regex", "pattern": "(?i)loss|spread.*cross|uncapped|capital impact"},
          "expected": true
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON parses correctly**

```bash
python3 -c "import json; d = json.load(open('autoresearch/skills/review-stack/eval.json')); print('tests:', len(d['tests'])); print('assertions:', sum(len(t['assertions']) for t in d['tests']))"
```

Expected output:
```
tests: 5
assertions: 25
```

- [ ] **Step 3: Verify total_assertions field matches**

```bash
python3 -c "import json; d = json.load(open('autoresearch/skills/review-stack/eval.json')); actual = sum(len(t['assertions']) for t in d['tests']); claimed = d['total_assertions']; print('MATCH' if actual == claimed else f'MISMATCH: {actual} vs {claimed}')"
```

Expected: `MATCH`

---

### Task 9: Create `autoresearch/skills/review-stack/results.tsv`

**Files:**
- Create: `autoresearch/skills/review-stack/results.tsv`

- [ ] **Step 1: Create the TSV with headers and pending baseline row**

Create `autoresearch/skills/review-stack/results.tsv` with this exact content (tab-separated):

```
commit	score	passed	total	status	description
pending	—	—	25	pending	initial baseline — no run yet
```

Note: the separator between columns must be a literal tab character, not spaces. Reference format: `autoresearch/skills/premortem/results.tsv`.

- [ ] **Step 2: Verify column count**

```bash
awk -F'\t' 'NR==1{print "columns:", NF}' autoresearch/skills/review-stack/results.tsv
```

Expected: `columns: 6`

- [ ] **Step 3: Commit eval.json and results.tsv**

```bash
git add autoresearch/skills/review-stack/eval.json autoresearch/skills/review-stack/results.tsv
git commit -m "skills2: add review-stack eval.json (25 assertions, T1-T5) and results.tsv"
```

---

### Task 10: Smoke test — harness can locate all eval assets

- [ ] **Step 1: Verify all expected files exist**

```bash
ls autoresearch/skills/review-stack/
```

Expected: `eval.json  fixtures  outputs  results.tsv`

```bash
ls autoresearch/skills/review-stack/fixtures/
```

Expected: `fail_open_dispatch.diff  multi_issue_cross_skill.diff  safe_refactor.diff  single_planted_p1.diff  wrong_impl_passes_tests.diff`

- [ ] **Step 2: Verify skill path in eval.json resolves**

```bash
python3 -c "import json, os; d = json.load(open('autoresearch/skills/review-stack/eval.json')); skill = d['skill']; root = '/Users/admin/Desktop/opus-trader'; print('EXISTS' if os.path.exists(os.path.join(root, skill)) else f'MISSING: {skill}')"
```

Expected: `EXISTS`

- [ ] **Step 3: Verify all fixture paths in eval.json resolve**

```bash
python3 -c "
import json, os
d = json.load(open('autoresearch/skills/review-stack/eval.json'))
base = 'autoresearch/skills/review-stack'
for t in d['tests']:
    path = os.path.join(base, t['fixture'])
    status = 'OK' if os.path.exists(path) else 'MISSING'
    print(f\"{t['id']}: {status} — {path}\")
"
```

Expected: all 5 lines show `OK`.

- [ ] **Step 4: Verify wrapper files exist**

```bash
ls .claude/skills/premortem/SKILL.md .claude/skills/review-stack/SKILL.md
```

Expected: both files listed without error.

- [ ] **Step 5: Final commit if anything unstaged**

```bash
git status
```

If any files are untracked or modified, stage and commit them. Otherwise the work is complete.
