# Reconciliation Protocol

> Single source of truth for reconciliation execution.
> Current decision: **one full pipeline for all stories** (no tier routing).
> For anti-patterns and worked examples, see [REFERENCE.md](REFERENCE.md).

---

## 1) Scope And Invariants

This protocol governs reconciliation of already-implemented stories.

Non-negotiables:
- One pipeline for every story: `preflight -> implement -> self_review -> cycle1 -> fix -> cycle2 -> resolution -> verify_full -> pass`.
- `plans/wf_step.sh` is the execution order authority.
- `plans/prd_set_pass.sh` is the pass-flip authority.
- Reconciliation is fail-closed: missing required artifacts or failed gates block progression.
- PRD machine-consumed path fields must not use legacy `reviews/premortems/*` docs; use `reviews/reconciliations/PROTOCOL.md` and `reviews/reconciliations/REFERENCE.md` (enforced by `prd_lint.sh` as `STALE_RECON_DOC_REF`).
- **Handoff is mandatory for all stories and all steps**. After every step attempt (pass or fail), update the active handoff before continuing.

Canonical references:
- Workflow contract: `specs/WORKFLOW_CONTRACT.md`
- Step tracker: `plans/wf_step.sh`
- Verify gate: `plans/verify.sh`
- Pass flip gate: `plans/prd_set_pass.sh`

---

## 2) Required Inputs

For each story `<STORY_ID>`:
- PRD entry in `plans/prd.json` (`.items[]`)
- Premortem: `reviews/premortems/<STORY_ID>_premortem.md`
- Story scope evidence and review artifacts under `reviews/reconciliations/<SLICE_ID>/`
- Story artifacts under `artifacts/story/<STORY_ID>/`

If the premortem is missing, stop and author/fix it before reconciliation.

---

## 3) Full Pipeline (All Stories)

Use `WF_RECON_MODE=1` when running reconciliation receipt steps.

| Step | wf_step name | Purpose | Required Output |
|---|---|---|---|
| 1 | `preflight` | Read-only precheck, evidence readiness, premortem readiness | R1 evidence ledger + preflight receipt |
| 2 | `implement` | Record implementation-phase baseline/eligibility per workflow rules | implement receipt |
| 3 | `self_review` | Verify self-review artifacts exist and are tied to current HEAD | self-review artifacts + receipt |
| 4 | `cycle1` | Cycle 1 external/internal review artifact readiness checks | cycle1 artifacts + receipt |
| 5 | `fix` | Apply fixes for cycle1 findings (or prove no-finding path) | fix artifacts + receipt |
| 6 | `cycle2` | Cycle 2 review gate (mode depends on findings/manifest) | cycle2 artifacts + receipt |
| 7 | `resolution` | Final reconciliation decision artifacts and closure checks | resolution artifact + receipt |
| 8 | `verify_full` | Full verification run for current HEAD | `artifacts/verify/<run_id>/` + receipt |
| 9 | `pass` | Pass flip after all prior gates are green | `passes=true` in PRD |

Preferred command pattern:

```bash
WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> <step>
```

Status and dry-run helpers:

```bash
WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> --status
WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> <step> --dry-run
```

---

## 4) Gate Rules (Operational)

### 4.1 Preflight
- Premortem exists and passes readiness checks.
- Evidence ledger exists for the story.
- Read-only integrity checks must pass for R1 audit steps.

### 4.2 Review Basis
Every review artifact must include one of:
- `Review basis: STORY_SCOPE (Cycle 1)`
- `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`

### 4.3 Cycle 1
- Story-scope review (not diff-only).
- Required artifact/sidecar checks must pass.
- Missing or invalid review artifacts block the step.

### 4.4 Fix
- Must address cycle1 findings, or explicitly satisfy the no-findings path.
- Unrelated changes should be avoided and treated as scope risk.

### 4.5 Cycle 2
- Review mode is findings-driven (dual-combo or recon-clean single when allowed by manifest/rules).
- `R5B_SELF_REVIEW_PROVEN` must hold before cycle2.

### 4.6 Resolution
- Blocking findings must be dispositioned.
- Required closure artifacts must exist and be internally consistent.

### 4.7 Verify Full
- `./plans/verify.sh full` must pass at current HEAD.

### 4.8 Pass Flip
Default preview (no mutation):

```bash
VERIFY_ARTIFACTS_DIR="artifacts/verify/<run_id>" \
  ./plans/prd_set_pass.sh <STORY_ID> true --dry-run
```

Mutation path (only after preview is green):

```bash
VERIFY_ARTIFACTS_DIR="artifacts/verify/<run_id>" \
  ./plans/prd_set_pass.sh <STORY_ID> true
```

`prd_set_pass.sh` must pass all enforced checks, including:
- verify artifacts with matching HEAD
- required review artifacts
- receipt chain requirements
- contract review / proof graph / fail-closed constraints as enforced by script

`plans/prd_set_pass.sh` script output is authoritative for exact check set.

---

## 5) Handoff Is Mandatory (All Stories)

Active handoff path:
- `reviews/reconciliations/<SLICE_ID>/HANDOFF.md`

Required cadence:
- After **every** `wf_step.sh` attempt (pass or fail), update handoff before running the next command.

Minimum required handoff updates each attempt:
1. Status matrix symbol update for the step.
2. Step block update: `Status`, `Receipt`, `Gate`, and key artifact paths.
3. If blocked: include command, exit code, and first failing diagnostic line.
4. Rewrite HANDOFF footer: `Stopped at`, `What happened`, `Must read first`, `Next steps`, `Resume command`.

No story is exempt from handoff updates.

---

## 6) Artifact Layout

Primary paths:
- Slice artifacts: `reviews/reconciliations/<SLICE_ID>/`
- Story artifacts: `artifacts/story/<STORY_ID>/`
- Receipts: `.wf/receipts/<STORY_ID>/`
- Verify artifacts: `artifacts/verify/<run_id>/`

Typical reconciliation artifacts:
- `<STORY_ID>_reconciliation.md` or JSON companion
- `GAP_LIST.*`
- `DEBT_REGISTER.json`
- `R5B_SELF_REVIEW_GATE.json`
- `R7_EXTERNAL_MANIFEST.json` and sidecars
- `R6_VERIFY_SUMMARY.*`

If required artifacts are missing, the affected gate must block.

---

## 7) External Review Command Pattern

Cycle 1/2 command shape:

```bash
plans/review_logged.sh <STORY_ID> --tool <tool> --prompt <enriched|generic> --base <integration_branch>
```

Requirements:
- Capture provenance and sidecars.
- Ensure citations are real and non-vacuous.
- Respect manifest-driven cycle2 mode.

---

## 8) Decision Policy

- Prefer narrowing ambiguity and proving safety over speed shortcuts.
- Do not weaken gates for convenience.
- If documents disagree, follow:
  1) `specs/WORKFLOW_CONTRACT.md`
  2) `plans/wf_step.sh` and `plans/prd_set_pass.sh`
  3) this protocol

---

## 9) Operator Checklist

For each story:
1. Confirm premortem/readiness and scope.
2. Run full 9-step workflow via `wf_step.sh` in order.
3. Update handoff after every step attempt.
4. Run `./plans/verify.sh full` in `verify_full`.
5. Flip pass only via `./plans/prd_set_pass.sh`.

Completion condition:
- Story has completed required receipts, full verify is green, pass flip succeeds, and handoff reflects final state.
