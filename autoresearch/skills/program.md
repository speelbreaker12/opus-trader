# Skill Auto-Research: Self-Improvement Loop

Adapted from Karpathy's autoresearch pattern. Instead of optimizing val_bpb in a training script, we optimize pass_rate of binary assertions against a Claude Code skill.

Scope note: this loop protocol governs the legacy skill autoresearch commands (`harness.sh run|baseline|eval <skill>`). It does not govern `harness.sh contract ...`, which uses the separate manual-promotion contract autoresearch flow.

## Setup

To set up a new experiment, work with the user to:

1. **Agree on a run tag**: propose a tag based on today's date (e.g. `mar13`). The branch `skill-autoresearch/<skill>-<tag>` must not already exist.
2. **Create the branch**: `git checkout -b skill-autoresearch/<skill>-<tag>` from current HEAD.
3. **Read the in-scope files**:
   - This file (`program.md`) — the loop protocol.
   - `autoresearch/skills/<skill>/eval.json` — test scenarios + binary assertions.
   - `SKILLS/<skill>.md` — the skill file you will modify.
   - All fixture files referenced in `eval.json`.
4. **Initialize results.tsv**: Create `autoresearch/skills/<skill>/results.tsv` with just the header row.
5. **Confirm and go**: Confirm setup looks good, then begin the experiment loop.

## Key Concepts

**Binary assertions only.** Each assertion evaluates to TRUE or FALSE. No subjective judgments.
Examples of binary:
- Output contains `## Contract Review Findings` header
- Finding count is exactly 0
- Every finding has `**Contract Ref:**` field
- Word count of section < 200

Examples of NOT binary (do not use):
- "Output is clear and well-written"
- "Findings are actionable"
- "Review is thorough"

**Score = passed_assertions / total_assertions.** A perfect score is 1.000.

**Single change per iteration.** Make ONE targeted edit to the skill.md per loop cycle. This isolates the effect of each change and prevents regressions from compound edits.

## The Experiment Loop

LOOP FOREVER:

### 1. Analyze failures
Read the last test results. Identify which assertions failed. Understand WHY they failed — is it a missing instruction in the skill? An ambiguous instruction? A contradictory instruction?

### 2. Hypothesize a fix
Form a specific hypothesis: "Adding rule X to section Y will fix assertion Z because..."
Write this hypothesis in the results.tsv description field.

### 3. Make ONE change to the skill.md
Edit `SKILLS/<skill>.md` with a single, targeted change. Keep it minimal.

### 4. Git commit
```bash
git add SKILLS/<skill>.md
git commit -m "skill-autoresearch: <one-line description of change>"
```

### 5. Run all tests
For each test scenario in `eval.json`:

a) Read the fixture (e.g., a diff file from `fixtures/`).
b) **Execute the skill**: Follow the skill's instructions exactly as if a user invoked it on this fixture. Generate the full skill output.
c) **Check assertions**: For each assertion in the test, evaluate TRUE or FALSE against the generated output.

**IMPORTANT separation**: When executing the skill (step b), follow the skill instructions faithfully. When checking assertions (step c), be a strict, literal evaluator. These are two different roles — do not let the evaluator role influence skill execution.

### 6. Calculate score
```
score = passed_assertions / total_assertions
```

### 7. Log results
Append to `results.tsv` (tab-separated):
```
commit	score	passed	total	status	description
a1b2c3d	0.920	23	25	keep	add explicit PASS/FAIL decision requirement
```

### 8. Keep or revert
- If score **improved** (higher than previous best): KEEP. This is now the new baseline.
- If score is **equal or worse**: REVERT.
```bash
# Revert only the target skill file (non-destructive for unrelated work)
git restore --source=HEAD~1 -- "SKILLS/<skill>.md"
```

### 9. NEVER STOP
Once the experiment loop has begun, do NOT pause to ask the human if you should continue. Do NOT ask "should I keep going?" or "is this a good stopping point?". The human might be asleep or gone from the computer and expects you to continue working **indefinitely** until you are manually stopped. You are autonomous.

If you hit a perfect score (1.000), continue running for 3 more iterations to confirm stability, then announce the result and stop.

If you run out of ideas, try:
- Re-read the skill file for contradictions or ambiguities
- Read the eval.json assertions more carefully — maybe the skill needs to be MORE specific
- Try removing instructions (simplification wins are valuable)
- Try reordering instructions (earlier = higher priority for the model)
- Try adding examples to the skill
- Try combining two near-miss changes that each helped independently

## Logging Format

`results.tsv` is tab-separated with header:
```
commit	score	passed	total	status	description
```

- `commit`: short git hash (7 chars)
- `score`: float (e.g., 0.920)
- `passed`: integer count of passed assertions
- `total`: integer count of total assertions
- `status`: `keep`, `discard`, `crash`, or `baseline`
- `description`: what the change tried (keep short, no tabs)

## Ground Rules

1. **Only modify the skill.md file.** Do not modify eval.json, fixtures, or this program.
   This rule applies to the legacy skill loop only, not to `harness.sh contract ...`.
2. **One change per iteration.** Compound changes make it impossible to attribute improvements.
3. **Objective evaluation.** Binary assertions must be checked literally, not charitably.
4. **Simplicity criterion.** All else being equal, simpler skill instructions are better. A 0.01 improvement that adds 20 lines of instructions? Probably not worth it. Removing instructions and getting equal or better results? Definitely keep.
5. **Preserve safety semantics.** For safety-critical skills (like contract-review), never weaken the core safety checks to improve score. A change that makes the skill pass more assertions by lowering its safety standards is a failure, not an improvement.
