# SKILL: /toc (Theory of Constraints Commit)

## What this skill does

Creates a git commit for current changes, then produces a structured debrief that answers four
questions through a Theory of Constraints lens: what shipped, what the binding constraint was,
what to build next, and what rules to add so the next agent doesn't repeat the same pain.

## When to use

- After completing any unit of work (story, fix, refactor, tooling change)
- When you're about to hand off to another agent and want to leave institutional knowledge
- As a substitute for `/commit` when you want more than a commit message

---

## Process

### Step 1 — Commit

Run the standard commit flow:

```bash
git status
git diff --stat
git log --oneline -5
```

Stage the relevant files by name (never `git add -A`), write a commit following project
conventions (`<area>: <what changed>`, Co-Author line), and confirm the commit succeeded.

```bash
git commit -m "$(cat <<'EOF'
<area>: <what changed>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Step 2 — Answer the four questions in chat

After the commit, output the debrief below. Fill every field from what actually happened in
this session — no placeholders, no "n/a" unless genuinely not applicable.

---

## 0) What shipped

**Feature / behavior:**
> _One sentence. What does the system do now that it didn't do before?_

**Value (problem it solves / upgrade it provides):**
> _One sentence. Why does this matter to the next agent or to the project?_

---

## 1) Constraint (ONE)

Pick the **single binding constraint** that limited throughput the most this session.
If you can't pick one, you haven't constrained your analysis enough.

**How it manifested — 2–3 concrete symptoms:**
> _Observable, specific. "X happened three times", "gate blocked Y twice", "sidecar parse failed Z"._

**Time / token drain it caused:**
> _Quantify if possible: retries, context consumed, steps repeated._

**Workaround I used this story (exploit — squeezing the constraint now):**
> _What you did to get around it without fixing the root cause._

**Next-agent default behavior (subordinate — everything else bends to this):**
> _What should the next agent do differently to avoid hitting this constraint again before the fix lands?_

**Permanent fix proposal (elevate — break the constraint):**
> _The actual fix. Be specific: which file, which rule, which script._

**Smallest increment to validate the elevation:**
> _The one-line change or single test that proves the fix works._

**Validation (proof the constraint got better):**
> _Metric, observable outcome, or automated check. "Fewer retries", "gate passes on first run",
> "sidecar validates in CI", etc._

---

## 2) Best next story + upgrade candidates

Given what you just built, what is the **single highest-value follow-up story**?
Then list 1–3 upgrades worth considering (not all of them — only the ones worth the investment).

For each item include:
- **What**: one sentence
- **Smallest increment**: the minimal viable version
- **Validation**: how you know it worked

**Best follow-up story:**
> _..._

**Upgrade candidates (1–3):**
1. **What**: … | **Increment**: … | **Validation**: …
2. **What**: … | **Increment**: … | **Validation**: …
3. **What**: … | **Increment**: … | **Validation**: …

---

## 3) Enforceable rules for the next agent

Given the top friction sinks and failure modes you hit this session, what **1–3 rules** should
be added so the next agent doesn't repeat the same pain?

Use the `rule / trigger / prevents / enforce` format from the HANDOFF debrief discipline:

```
rule:     [what the agent must always / never do]
trigger:  [when this rule applies — the specific situation]
prevents: [the exact failure mode it blocks]
enforce:  [where to put it: CLAUDE.md / RUNBOOK / skill file / schema / CI check]
```

**Rule 1:**
```
rule:     …
trigger:  …
prevents: …
enforce:  …
```

**Rule 2 (if applicable):**
```
rule:     …
trigger:  …
prevents: …
enforce:  …
```

**Rule 3 (if applicable):**
```
rule:     …
trigger:  …
prevents: …
enforce:  …
```

---

## Hard constraints

- Commit first, debrief second — never skip the commit even if the debrief is the main goal.
- All four sections are required. Omitting one defeats the point of the skill.
- §1 must name ONE constraint. If you list two, you haven't done the analysis.
- §3 rules must be actionable: each must name a specific `enforce:` target. "Someone should fix this" is not a rule.
- Do not pad with hedging language. Every line should be read by a cold-start agent and acted on.
