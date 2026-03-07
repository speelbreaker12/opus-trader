# Phase 1 Restart Safety Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update the Phase 1 contract boundary so restart safety is explicitly required in Phase 1, while replay/reconciliation alone can never authorize a fresh OPEN.

**Architecture:** Keep this change Phase 1-only and contract-first. `specs/CONTRACT.md` becomes the authoritative source for the conservative restart model: Phase 1 proves restart-safe replay, no duplicate sends, and ACK/fill recovery, but fresh OPEN authorization still requires a post-restart evaluation path rather than replay itself. Sync the crash-flow specs and every `specs/CONTRACT.md` restatement of the same AT-935 semantics (replay-safe summaries, Phase 1 subset, CSP traceability tables, and the change ledger) so the contract stays internally coherent without reopening broader Phase 2 reconciliation scope.

**Tech Stack:** Markdown contract editing, YAML flow-spec editing, Python spec validators, `./plans/verify.sh quick`, `./plans/verify.sh full`.

---

### Task 1: Rewrite the restart-safety rules in `§2.4`

**Files:**
- Modify: `specs/CONTRACT.md`
- Review: `docs/plans/2026-03-05-phase-1-contract-remediation-plan.md`

**Step 1: Capture the current mismatch**

Run: `sed -n '3218,3305p' specs/CONTRACT.md`
Expected: `§2.4` and the AT blocks still describe replay/restart behavior, and `AT-935` still says restart dispatches an unsent OPEN exactly once.

**Step 2: Rewrite the normative replay rule**

Edit `§2.4` / `§2.4.1` so the contract says all of the following without changing AT IDs:
- replayed WAL state is audit/reconciliation input, not independent authorization for a fresh OPEN,
- startup recovery must reconcile before any OPEN-capable path is reachable,
- if restart evidence shows an intent was already sent or ACKed, resend is forbidden,
- if restart evidence shows a recorded-but-unsent OPEN, replay keeps it visible for reconciliation and later evaluation, but replay alone does not dispatch it.

**Step 3: Rewrite the restart AT text**

Update the three AT blocks in the same section:
- `AT-233`: keep the no-resend + reconcile requirement,
- `AT-234`: keep the fill-detection + TLSM/sequencer recovery requirement,
- `AT-935`: change it from “dispatch exactly once across two restarts” to the conservative Phase 1 rule:
  - restart rebuilds/reconciles the recorded unsent OPEN,
  - replay-driven dispatch count remains `0`,
  - any later OPEN dispatch requires a fresh post-restart evaluation path outside replay.

**Step 4: Re-scan the contract wording**

Run: `rg -n "AT-233|AT-234|AT-935|Replay Safe|fresh OPEN|replay alone|dispatch exactly once|sent once after reconcile|recorded intent dispatches exactly once|unsent" specs/CONTRACT.md`
Expected: the old “restart dispatches exactly once” wording is gone from `AT-935`, and the new “replay alone does not dispatch a fresh OPEN” wording appears in `§2.4` / `§2.4.1`. Any remaining “unsent” wording outside those sections is clearly non-authorizing and consistent with the rewritten AT text.

**Step 5: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: narrow replay authorization in phase1 contract"
```

### Task 2: Move the Phase 1 boundary and sync the contract restatements

**Files:**
- Modify: `specs/CONTRACT.md`

**Step 1: Inspect the current Phase 1 subset and semantic restatements**

Run: `rg -n "Phase 1 AT Subset|Deferred to Phase 2|Replay Safe|dispatch exactly once|sent once after reconcile|recorded intent dispatches exactly once|AT-935" specs/CONTRACT.md`
Expected: the Phase 1 AT subset still defers `AT-233`, `AT-234`, and `AT-935` to Phase 2, and the replay/idempotency summaries or CSP traceability tables still restate the older dispatch-once behavior.

**Step 2: Rewrite the Phase 1 AT subset**

Edit the Phase 1 roadmap section so:
- `AT-233`, `AT-234`, and the rewritten `AT-935` move into “Required for Phase 1 completion,”
- the deferred list keeps only the broader Phase 2-only proofs (full PolicyGuard assertions, broader restart/latch/ws-gap/session-recovery scope, and any reconcile-clear semantics not proven by the conservative Phase 1 subset),
- the wording explicitly says Phase 1 restart safety is limited to “replay is safe and non-authorizing for fresh OPEN,” not full Phase 2 reconciliation governance.

**Step 3: Sync the contract restatements outside `§2.4`**

Update the replay/idempotency summaries and CSP traceability tables in `specs/CONTRACT.md` so they do not preserve the older `AT-935` wording. In particular:
- the “Replay Safe” / idempotency summary text must no longer imply that “WAL says unsent” is enough for replay itself to dispatch an OPEN,
- the CSP traceability rows must no longer describe `AT-935` as “dispatch exactly once” or “sent once after reconcile,”
- the surrounding text must still preserve the no-duplicate-send and reconcile-first guarantees without expanding Phase 2 scope.

**Step 4: Append the contract change ledger row**

Add one new `CONTRACT_CHANGE_LEDGER` row describing:
- the sections touched (`§2.4`, `§2.4.1`, Phase 1 roadmap/AT subset, replay/idempotency summaries, CSP traceability tables),
- the semantic change (“restart safety is Phase 1 scope, but replay cannot create fresh OPEN exposure”),
- the impacted ATs (`AT-233`, `AT-234`, `AT-935`).

**Step 5: Re-scan the Phase 1 boundary and contract restatements**

Run: `rg -n "Phase 1 AT Subset|Deferred to Phase 2|Replay Safe|AT-233|AT-234|AT-935|fresh OPEN|dispatch exactly once|sent once after reconcile|recorded intent dispatches exactly once" specs/CONTRACT.md`
Expected: the Phase 1 subset now includes the restart-safety ATs, the deferred section no longer claims that these three ATs are Phase 2-only, and no appendix/traceability text still describes `AT-935` with the old dispatch-once wording.

**Step 6: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: pull conservative restart safety into phase1"
```

### Task 3: Sync the crash-flow specs that restate the same semantics

**Files:**
- Modify: `specs/flows/CRASH_MATRIX.md`
- Modify: `specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml`

**Step 1: Inspect the stale flow text**

Run: `rg -n "AT-233|AT-234|AT-935|dispatch exactly once|unsent and OPEN is permitted|replay alone" specs/flows/CRASH_MATRIX.md specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml`
Expected: both files still restate the older unsent-OPEN restart behavior for `AT-935`.

**Step 2: Rewrite `CM-011` in the crash matrix**

Update `specs/flows/CRASH_MATRIX.md` so `CM-011` says:
- restart replays and reconciles the unsent OPEN,
- replay alone does not dispatch it,
- resend remains forbidden unless a later fresh evaluation authorizes a new OPEN path under the post-restart rules.

Do the same for any summary line in that file that still says “never resend unless WAL says unsent” in a way that implies replay itself may authorize the OPEN.

**Step 3: Rewrite `CR-935` in the YAML spec**

Update `specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml` so `CR-935` requires:
- reconcile before any dispatch-capable evaluation,
- zero replay-driven OPEN dispatches for the recovered unsent intent,
- later OPEN authorization only through a fresh post-restart evaluation path.

Do not renumber IDs or change unrelated crash points.

**Step 4: Commit**

```bash
git add specs/flows/CRASH_MATRIX.md specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml
git commit -m "docs: align crash specs with conservative phase1 replay rule"
```

### Task 4: Run contract/spec validation and record the known follow-up

**Files:**
- Verify: `specs/CONTRACT.md`
- Verify: `specs/flows/CRASH_MATRIX.md`
- Verify: `specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml`
- Review only: `crates/soldier_infra/tests/test_crash_mid_intent.rs`
- Review only: `plans/prd.json`

**Step 1: Run the crash-specific validators**

Run: `python3 scripts/check_crash_matrix.py && python3 scripts/check_crash_replay_idempotency.py`
Expected: both validators pass against the edited contract and flow specs.

**Step 2: Run the canonical quick verify for iteration**

Run: `./plans/verify.sh quick`
Expected: quick verify passes, or it fails on an unrelated existing branch/worktree blocker with artifact-backed logs.

**Step 3: Run the final full verify (or CI equivalent)**

Run: `./plans/verify.sh full`
Expected: full verify passes on a trustworthy tree, or a clean-checkout CI run is designated as the required final proof if local full verify cannot be trusted. Do not stop at quick verify alone; full mode is required because it runs the final crossref/coverage gates that quick mode skips.

**Step 4: Handle dirty-tree full verify correctly**

If `./plans/verify.sh full` cannot be trusted because the worktree is dirty, do **not** use `VERIFY_ALLOW_DIRTY=1` by default. Use one of:
- CI full verify on a clean checkout,
- a cleaned local tree,
- or an owner-approved dirty-tree exception recorded in `plans/progress.txt`.

**Step 5: Record the runtime follow-up explicitly in `plans/progress.txt`**

Add a short note in `plans/progress.txt` that the current Rust proof coverage is internally split and must be reconciled by the next implementation task:
- `plans/prd.json` already expects “replay alone does not dispatch OPEN,”
- `crates/soldier_infra/tests/test_crash_mid_intent.rs::test_crash_mid_intent_no_duplicate_dispatch` and `::test_mixed_states_on_restart` already assert that created/unsent intents must NOT be replay-dispatched,
- `crates/soldier_infra/tests/test_crash_mid_intent.rs::test_at935_unsent_dispatches_exactly_once_across_two_restarts` still proves the old “dispatch once after restart” rule.

Do not “fix” that runtime/test contradiction in this doc-only change; track it as the next implementation task.

**Step 6: Commit**

```bash
git add specs/CONTRACT.md specs/flows/CRASH_MATRIX.md specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml plans/progress.txt
git commit -m "docs: verify phase1 restart safety boundary"
```

## Deferred Work

- Do not widen this patch into Phase 2 latch, WS-gap, or session-termination semantics beyond the minimum wording needed to keep the conservative Phase 1 restart subset coherent.
- Do not renumber or replace `AT-233`, `AT-234`, or `AT-935`; keep IDs stable so `plans/prd.json` and existing traceability stay anchored.
- Do not update runtime code or Rust tests in this plan; that is a separate follow-up because current implementation evidence contains conflicting restart proofs that still need a runtime/test reconciliation pass.
- Re-check `plans/prd.json` only after the contract edit lands; it already carries the target conservative wording, so PRD edits should be unnecessary unless a validator or review proves otherwise.
