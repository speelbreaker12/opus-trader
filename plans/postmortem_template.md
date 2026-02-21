# Postmortem (TOC) — ${STORY_ID}

Story: ${STORY_ID}
Slice: <SLICE_ID>
HEAD: ${HEAD}
Date: <YYYY-MM-DD>
Mode: <implementation|reconciliation>
STOPLIGHT: <GREEN|YELLOW|RED>

## 1) Constraint Summary

**Constraint (single sentence):**
<What bottleneck or weakness actually limited correctness/safety/proof?>

**Constraint Class:** <Spec Gap | Test Gap | Gate Gap | Workflow Gap | Design Gap | Observability Gap>

**Why it matters (loss lens):**
<How this could cause capital loss, missed profit, duplicate dispatch, stale state, fail-open behavior, or hidden drift>

---

## 2) TOC Five Focusing Steps

### Step 1 — Identify the Constraint
- **Primary constraint:** <one clear bottleneck>
- **Symptoms observed:**
  - <symptom 1>
  - <symptom 2>
- **Where it appeared:** <file(s), step(s), gate(s), test(s)>

### Step 2 — Exploit the Constraint (use what exists better)
- **Immediate actions taken (no major redesign):**
  - <tightened AT>
  - <added missing proof>
  - <used existing gate correctly>
- **What we stopped doing:**
  - <paper compliance / broad test / manual shortcut / etc.>

### Step 3 — Subordinate Everything Else
- **What changed so the workflow supports the constraint fix:**
  - <prompt change>
  - <review requirement>
  - <receipt/order rule>
  - <naming requirement>
- **What remains intentionally unchanged (to avoid scope creep):**
  - <list>

### Step 4 — Elevate the Constraint
- **Structural fix (higher leverage):**
  - <new gate / pattern canon / AT addition / config model / integration test>
- **Owner / target slice:** <owner> / <slice or story id>
- **Effort:** <S|M|L>

### Step 5 — Repeat (next likely constraint)
- **Next constraint likely to break us:**
  - <next bottleneck>
- **Early warning signal:**
  - <metric / test gap / review pattern / repeated finding>

---

## 3) Causal Chain (show the failure path)

**Trigger → Propagation → Outcome → Detection**

1. **Trigger:** <what started it>
2. **Propagation:** <how it moved through code/workflow>
3. **Outcome:** <unsafe behavior / missing proof / blocked gate / drift>
4. **Detection:** <which test/review/gate caught it>
5. **Why not caught earlier:** <missing AT / coarse test / no gate / unclear pattern>

---

## 4) Proof and Evidence

### Contract / PRD / Test Proof
- **Contract clauses / ATs affected:** <AT-xxx, section x.y>
- **PRD story refs:** <story refs>
- **Tests proving final behavior:**
  - <test file :: test name>
  - <test file :: test name>

### Artifacts (must be real paths)
- Preflight: <path>
- Reviews: <path(s)>
- Resolution: <path>
- Verify output: <path>

---

## 5) What Was Missing (be explicit)

### Missing Proofs
- <AT / behavior> — <why proof was missing or too weak>

### Wrong-Implementation Risk (critical)
- **A wrong implementation that could have passed before:**
  <describe the bad implementation>
- **What now prevents it:**
  <new AT / gate / prompt rule / pattern>

---

## 6) Rule Updates (what changes permanently)

| Layer | Change | Why | Owner | Target |
|---|---|---|---|---|
| Contract | <change or "none"> | <reason> | <owner> | <target> |
| PRD / AT | <new/updated AT> | <reason> | <owner> | <target> |
| Tests | <new test / rename / split> | <reason> | <owner> | <target> |
| Gate | <new check> | <reason> | <owner> | <target> |
| Prompt / Workflow | <prompt rule> | <reason> | <owner> | <target> |
| Pattern Canon | <pattern added/updated> | <reason> | <owner> | <target> |

---

## 7) Residual Risk (YELLOW debt only)

**Residual risk exists:** <YES|NO>

If YES:
- **Risk:** <what remains>
- **Why deferred:** <scope / dependency / future slice>
- **Safe containment:** <feature flag / non-live path / no-open-risk>
- **Owner / target slice:** <owner> / <target>

---

## 8) Next-Story Startup Note (for Step 0)

> **Carry-forward constraint:** <one line>
>
> Watch for: <specific failure pattern>
>
> Required proof before pass-flip: <AT/test/gate requirement>

---

## 9) Completion Checklist (postmortem quality gate)

- [ ] Constraint named clearly (not vague)
- [ ] Loss/profit impact stated
- [ ] Wrong implementation risk described
- [ ] Permanent rule/gate/test update listed
- [ ] Residual risk either closed or explicitly deferred
- [ ] Next-story startup note written
- [ ] All evidence paths are real
