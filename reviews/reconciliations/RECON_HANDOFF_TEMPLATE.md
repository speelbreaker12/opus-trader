# Reconciliation Handoff — {{SLICE_ID}}

---

## Role

You are a reconciliation operator auditing already-passing stories for contract-proof integrity.

Operational rule:
- If a story cannot pass the same gates required today, it must not remain `passes=true`.

---

## Source Of Truth

| Document | Use |
|---|---|
| `reviews/reconciliations/PROTOCOL.md` | Required. Execution order, gates, handoff cadence. |
| `reviews/reconciliations/REFERENCE.md` | Anti-patterns, escalation, troubleshooting. |
| `plans/step_prompts/recon/<step>.md` | Step-specific prompt details. |
| `specs/WORKFLOW_CONTRACT.md` | Workflow contract authority when in doubt. |
| `plans/wf_step.sh` | Canonical step order and receipt enforcement. |
| `plans/verify.sh` | Canonical verify entrypoint. |
| `plans/prd_set_pass.sh` | Canonical pass-flip gate. |

---

## Quick Orientation

- Stories: `plans/prd.json` via `.items[] | select(.id=="<STORY_ID>")`
- Premortems: `reviews/premortems/<STORY_ID>_premortem.md`
- Slice artifacts: `reviews/reconciliations/{{SLICE_ID}}/`
- Story artifacts: `artifacts/story/<STORY_ID>/`
- Receipts: `.wf/receipts/<STORY_ID>/`

---

## Slice Context

| Field | Value |
|---|---|
| Slice ID | {{SLICE_ID}} |
| Integration branch | {{BASE_BRANCH}} |
| Stories in scope | {{STORY_LIST}} |
| Started | {{YYYY-MM-DD}} |
| Last updated | {{YYYY-MM-DD}} |

---

## Story Status Matrix

Update from `plans/recon_scoreboard.sh {{SLICE_ID}}` after each step attempt.

Symbols: `·` not started · `→` in progress · `✓` done · `✗` blocked

All stories use the same full 9-step pipeline:
`preflight -> implement -> self_review -> cycle1 -> fix -> cycle2 -> resolution -> verify_full -> pass`

| Story | Step 1 preflight | Step 2 implement | Step 3 self_review | Step 4 cycle1 | Step 5 fix | Step 6 cycle2 | Step 7 resolution | Step 8 verify_full | Step 9 pass | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| {{S1}} | · | · | · | · | · | · | · | · | · | — |
| {{S2}} | · | · | · | · | · | · | · | · | · | — |
| {{S3}} | · | · | · | · | · | · | · | · | · | — |

---

## Per-Story Work Log

Repeat this block for each story.

### {{STORY_ID}}

#### Hard Evidence Summary

| Gate | Status | Artifact |
|---|---|---|
| Preflight | {{PASS/FAIL}} | `reviews/reconciliations/{{SLICE_ID}}/{{STORY_ID}}_reconciliation.md` |
| Self-review | {{PASS/FAIL}} | `reviews/reconciliations/{{SLICE_ID}}/R5B_SELF_REVIEW_GATE.json` |
| External C1 | {{PASS/FAIL}} | `reviews/reconciliations/{{SLICE_ID}}/external/cycle1/{{STORY_ID}}/R3_EXTERNAL_MANIFEST.json` |
| External C2 | {{PASS/FAIL}} | `reviews/reconciliations/{{SLICE_ID}}/external/cycle2/{{STORY_ID}}/R7_EXTERNAL_MANIFEST.json` |
| Verify full | {{PASS/FAIL}} | `artifacts/verify/{{run_id}}/` |

#### Step Log

Add one block per attempted step.

```text
Step N · <wf_step_name>
Status: COMPLETE / IN_PROGRESS / BLOCKED
Receipt: .wf/receipts/<STORY_ID>/<receipt>.json
Gate: PASS / FAIL — <reason if fail>
Artifacts: <key paths>
Notes: <one line, or empty>
Friction: <what broke · root cause · fix needed — only if something broke>
```

Example:

```text
Step 1 · preflight
Status: COMPLETE
Receipt: .wf/receipts/{{STORY_ID}}/00_preflight.json
Gate: PASS
Artifacts: reviews/reconciliations/{{SLICE_ID}}/{{STORY_ID}}_reconciliation.md
Notes: Preflight passed with ready evidence ledger.
Friction:
```

---

## Process Backlog

Promote recurring structural issues here.

| # | Step | Rule | Severity | Fix target | Owner | Status |
|---|---|---|---|---|---|---|
| 1 | {{step}} | `rule: … · trigger: … · prevents: … · enforce: …` | {{P0/P1/P2}} | {{target}} | {{owner}} | {{open/applied}} |

---

## HANDOFF (Required)

Next agent starts here first.

### Stopped At

- Story: `{{STORY_ID}}`
- Step: `{{wf_step_name}}`
- Status: `{{what is done / what is mid-flight}}`
- HEAD at stop: `{{git_sha}}`

### What Happened (2-5 bullets)

- {{key decision/finding}}
- {{key decision/finding}}
- {{blocker/open question or "none"}}

### Must Read First (ordered)

1. `{{path}}` — {{why}}
2. `{{path}}` — {{why}}
3. `{{path}}` — {{why}}

### Next Steps (exact commands/actions)

1. {{exact command/action}}
2. {{exact command/action}}
3. {{exact command/action}}

### Open Decisions / Blockers

- {{decision or blocker, or "none"}}

### Resume Command

```bash
/reconcil
plans/wf_step.sh {{STORY_ID}} --status
```

---

## Mandatory Cadence

After **every** `wf_step.sh` attempt (pass or fail), update:
1. Matrix symbol for that step.
2. Step block `Status / Receipt / Gate / Artifacts`.
3. Blocker details (command + exit + first failing line) if blocked.
4. HANDOFF footer (`Stopped At`, `What Happened`, `Must Read`, `Next Steps`, `Resume`).

No story is exempt from handoff updates.
