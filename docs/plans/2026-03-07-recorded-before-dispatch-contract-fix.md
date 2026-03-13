# RecordedBeforeDispatch Contract Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the enqueue-versus-`WALRecorded` contradiction so the contract has one authoritative OPEN dispatch gate: `WALRecorded` (and `WALDurable` only when configured).

**Architecture:** Keep the current contract model and repair only the contradictory normative wording. `WALQueueAccepted` remains a non-blocking prerequisite and backpressure signal in the hot loop; `RecordedBeforeDispatch` remains satisfied only when the WAL writer publishes `WALRecorded` before any OPEN dispatch attempt.

**Tech Stack:** Markdown contract editing, `rg`/`sed` inspection, contract-kernel refresh if required, `./plans/verify.sh quick`.

---

### Task 1: Rewrite the normative dispatch-gate paragraph

**Files:**
- Modify: `specs/CONTRACT.md:3218`
- Review: `specs/CONTRACT.md:3234`
- Review: `specs/CONTRACT.md:3253`

**Step 1: Capture the conflicting text**

Run: `sed -n '3218,3262p' specs/CONTRACT.md`
Expected: the section shows both `OPEN dispatch requires WALRecorded` and the conflicting enqueue-based gate note.

**Step 2: Edit the architecture-boundary paragraph**

Patch the `§2.4.1` note so it says all of the following in one place:
- the hot loop MUST NOT block on fsync/durability work,
- `WALQueueAccepted` is a prerequisite for writer processing, not dispatch authorization,
- OPEN dispatch is authorized only after `WALRecorded`,
- `WALDurable` is additionally required only when durable-before-dispatch is configured,
- queue-full, enqueue-failure, or missing-`WALRecorded` conditions all fail closed for OPEN.

**Step 3: Re-scan the normative lines**

Run: `rg -n "OPEN dispatch requires \\*\\*WALRecorded\\*\\*|WALQueueAccepted alone is insufficient|gate succeeds upon successful \\*\\*enqueue\\*\\*" specs/CONTRACT.md`
Expected: the `WALRecorded` requirements remain, and the enqueue-as-gate wording is removed or rewritten.

**Step 4: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: clarify recorded-before-dispatch gate"
```

### Task 2: Tighten acceptance coverage around the failure mode

**Files:**
- Modify: `specs/CONTRACT.md:3302`
- Review: `specs/CONTRACT.md:3310`

**Step 1: Strengthen the queue-failure acceptance text**

Update `AT-906` so it continues to prove enqueue failure blocks OPEN, but explicitly describes `WALQueueAccepted` as a prerequisite to `RecordedBeforeDispatch`, not as success of the dispatch gate itself.

**Step 2: Add or extend writer-ack coverage**

Prefer the smallest change that closes the gap:
- first try tightening `AT-1215` so it clearly proves dispatch occurs only after `WALRecorded`, and
- if that still leaves the “enqueue succeeded, `WALRecorded` never arrives” case unproved, add one new AT immediately in this section covering that fail-closed behavior.

**Step 3: Verify the acceptance bundle reads coherently**

Run: `sed -n '3298,3338p' specs/CONTRACT.md`
Expected: one AT covers enqueue/backpressure failure, and one AT covers successful `WALRecorded` dispatch authorization without implying enqueue-only success.

**Step 4: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: tighten wal dispatch acceptance coverage"
```

### Task 3: Sweep contract-internal mirror definitions

**Files:**
- Review: `specs/CONTRACT.md:6211`
- Review: `specs/CONTRACT.md:6266`
- Review: `specs/CONTRACT.md:6312`

**Step 1: Re-read the glossary and CSP summaries**

Run: `sed -n '6208,6320p' specs/CONTRACT.md`
Expected: glossary and CSP sections already define `RecordedBeforeDispatch` in terms of `WALRecorded`.

**Step 2: Patch only if the main edit introduced drift**

If any nearby wording now conflicts with the repaired `§2.4.1` note, fix only those contract-internal lines. Do not touch `plans/prd.json`, derived docs, or workflow files in this pass unless verification proves they are required for consistency.

**Step 3: Run a final contract-only term sweep**

Run: `rg -n "RecordedBeforeDispatch|WALQueueAccepted|WALRecorded|WALDurable" specs/CONTRACT.md`
Expected: no remaining sentence equates `RecordedBeforeDispatch` with enqueue-only success.

**Step 4: Commit**

```bash
git add specs/CONTRACT.md
git commit -m "docs: align wal glossary and summaries"
```

### Task 4: Refresh artifacts and run verification

**Files:**
- Verify: `specs/CONTRACT.md`
- Refresh if needed: `docs/contract_kernel.json`

**Step 1: Refresh the contract kernel if the contract hash changed**

Run: `python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`
Expected: `docs/contract_kernel.json` matches the edited `specs/CONTRACT.md`.

**Step 2: Check the kernel output**

Run: `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`
Expected: kernel check passes with the refreshed contract hash.

**Step 3: Run the canonical quick verify**

Run: `./plans/verify.sh quick`
Expected: quick verify passes, or it fails on an unrelated existing blocker with artifact-backed logs under `artifacts/verify/<run_id>/`.

**Step 4: Handle dirty-tree verification correctly**

If `./plans/verify.sh quick` fails because the worktree is dirty, do **not** use `VERIFY_ALLOW_DIRTY=1` by default. Instead choose one of:
- rely on CI quick/full verify on a clean checkout,
- clean the tree and rerun verify normally,
- or use the owner-approved dirty-tree exception only if that approval is recorded in `plans/progress.txt`.

**Step 5: Commit**

```bash
git add specs/CONTRACT.md docs/contract_kernel.json
git commit -m "docs: verify recorded-before-dispatch contract fix"
```

## Deferred Work

- Do not update `plans/prd.json` in this plan unless the edited contract creates a proven traceability failure.
- Do not touch `docs/bundle_CONTRACT_PHASE1.md` or other derived docs in the same pass unless verification or review shows they are consumed as active authority.
- Do not change runtime behavior from `WALRecorded` to `WALDurable` by default; that would be a separate semantic decision.
