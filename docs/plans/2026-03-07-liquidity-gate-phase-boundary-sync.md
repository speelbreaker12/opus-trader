# Liquidity Gate Phase Boundary Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the Phase 1 versus Phase 2 Liquidity Gate contradiction across the contract, implementation plan, and PRD so Liquidity Gate compliance is owned by Phase 2 and Phase 1 closure no longer depends on §3.1 fallback infrastructure.

**Architecture:** Treat this as a source-of-truth sync, not a feature build. Patch the normative roadmap language in `specs/CONTRACT.md`, then align `specs/IMPLEMENTATION_PLAN.md` and `plans/prd.json` to the same ownership model while preserving historical evidence artifacts. Keep the fix fail-closed: under stale L2, regular CLOSE/HEDGE placement remains rejected per `AT-421`; only §3.1 deterministic emergency close may use the fallback ladder.

**Tech Stack:** Markdown spec editing, JSON PRD editing, generated artifact refresh (`docs/contract_kernel.json`, `docs/contract_coverage.md`), PRD validation, contract-kernel validation, `./plans/verify.sh quick` on a clean checkout or CI.

---

### Task 1: Repair the normative roadmap boundary in `specs/CONTRACT.md`

**Files:**
- Modify: `specs/CONTRACT.md:4650`
- Modify: `specs/CONTRACT.md:4694`
- Modify: `specs/CONTRACT.md:6509`
- Refresh: `docs/contract_kernel.json`

**Step 1: Capture the conflicting roadmap text**

Run: `nl -ba specs/CONTRACT.md | sed -n '4648,4703p'`
Expected: the Phase 1 profile note still lists `Liquidity Gate`, the Phase 1 bullets omit it, the Phase 1 AT subset omits all Liquidity Gate ATs, and the Phase 2 bullets already mention liquidity safety gates.

**Step 2: Patch the Phase 1 profile note**

Rewrite the Phase 1 normative note so it:
- lists only `TLSM`, `s4:` labeling schema, and `WAL/durable ledger` as the Phase 1 roadmap deliverables,
- says Liquidity Gate is deferred to Phase 2 because the stale-L2 risk-reducing path depends on `§3.1`,
- preserves the existing “Phase 1 AT Subset is the closure gate” wording,
- does not weaken the non-deployable rule.

**Step 3: Add an explicit deferral cue near the Phase 1 subset**

Add one short sentence after the Phase 1 AT subset or Phase 1 closure rule that names the deferred Liquidity Gate AT family:
- `AT-222`
- `AT-344`
- `AT-909`
- `AT-421`
- `AT-1216`

Purpose: remove any remaining “profile note is normative, AT subset is just illustrative” argument.

**Step 4: Tighten the Phase 2 deliverable wording**

Add or rewrite the Phase 2 bullet so it says Phase 2 owns:
- Pre-Trade Liquidity Gate compliance under `§1.3`,
- the `§3.1` fallback-ladder dependency required for stale-L2 emergency-close behavior,
- without implying that ordinary CLOSE/HEDGE placement bypasses `AT-421`.

Use wording that matches the current contract semantics:
- OPEN with stale/missing L2 -> reject with `Rejected(LiquidityGateNoL2)`
- CANCEL-only -> allowed
- ordinary CLOSE/HEDGE order placement -> rejected under stale/missing L2
- deterministic emergency close -> may use the `§3.1` fallback ladder and fails closed only when no valid fallback price source exists

**Step 5: Append the contract-change-ledger row**

Add a new `CCL-2026-03-07-0X` row in Appendix `CONTRACT_CHANGE_LEDGER` covering:
- roadmap Phase 1/Phase 2 wording,
- the explicit Liquidity Gate deferral,
- the clarification that the fallback ladder belongs to the emergency-close path rather than generic CLOSE/HEDGE placement.

**Step 6: Refresh and validate the contract kernel**

Run:
- `python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`
- `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`

Expected: the kernel rebuild succeeds and matches the edited contract hash.

### Task 2: Align `specs/IMPLEMENTATION_PLAN.md` to the same phase ownership

**Files:**
- Modify: `specs/IMPLEMENTATION_PLAN.md:1`
- Modify: `specs/IMPLEMENTATION_PLAN.md:71`
- Modify: `specs/IMPLEMENTATION_PLAN.md:474`
- Modify: `specs/IMPLEMENTATION_PLAN.md:591`
- Modify: `specs/IMPLEMENTATION_PLAN.md:693`

**Step 1: Remove Liquidity Gate from Phase 1 exit-criterion language**

Update the Phase table, Phase 1 objective, and Phase 1 exit criteria so they no longer claim Liquidity Gate compliance as a Phase 1 closure condition.

Specifically remove or rewrite wording such as:
- `Liquidity+NetEdge+Fee staleness fail-closed (tests)`
- any Phase 1 objective text that implies full Liquidity Gate compliance or plain `phase != foundation` is itself the thing that authorizes foundation exit; the legal runtime transition remains the separate `specs/CONTRACT.md` §7.0 rule

Keep Phase 1 focused on deterministic intent construction, WAL/TLSM, fee/net-edge/pricer ordering, and non-deployable chokepoint behavior.

**Step 2: Preserve traceability without renumbering Slice 5**

Do not renumber the Slice 5 story family. Instead, add a short legacy-traceability note that explains:
- Slice 5 retains its existing label/history for continuity,
- full Liquidity Gate phase ownership is no longer a Phase 1 closure claim,
- Phase 2 owns the deployable/integrated behavior because it depends on `§3.1`.

This avoids broad churn across story IDs, old review artifacts, and existing references.

**Step 3: Rewrite the `S5.1` subsection as a boundary note or primitive-only prerequisite**

Replace the current Phase 1 `S5.1 — Liquidity Gate` implementation language with one of these equivalent shapes:
- preferred: a short “primitive landed early, but not a Phase 1 completion gate” note, or
- fallback: a deprecation note that forwards contractual ownership to Phase 2.

The rewritten subsection must no longer claim that the `AT-222/344/909/421` proof bundle belongs to Phase 1 completion.

**Step 4: Move integrated ownership into Phase 2 `S7.3`**

Extend `S7.3 — Deterministic emergency close + hedge fallback` so it explicitly owns the stale-L2 dependency bundle needed for Liquidity Gate Phase 2 compliance:
- `AT-236`
- `AT-937`
- `AT-938`
- `AT-1217`

Also add a short note that Phase 2 Liquidity Gate compliance depends on this bundle plus the standalone gate mechanics proven earlier.

**Step 5: Add the missing Liquidity Gate positive-path proof to the Phase 2 plan text**

The current contradiction analysis depends on the fact that `AT-1216` is absent from the Phase 1 subset. Make the Phase 2 implementation plan explicitly own that positive-path proof:
- fresh/parseable L2,
- slippage within budget,
- all non-liquidity gates forced pass,
- dispatch count increases by 1.

**Step 6: Recheck the local plan text for stale Phase 1 claims**

Run: `rg -n "Phase 1.*Liquidity|Liquidity Gate.*Phase 1|AT-222|AT-344|AT-909|AT-421|AT-1216|S5.1" specs/IMPLEMENTATION_PLAN.md`
Expected: any remaining `Phase 1` Liquidity Gate references are clearly labeled legacy-traceability notes or explicit deferrals, not closure obligations.

### Task 3: Realign PRD ownership without rewriting history

**Files:**
- Modify: `plans/prd.json`
- Refresh: `docs/contract_coverage.md`
- Update if needed: `plans/progress.txt`

**Step 1: Re-scope `S5-000` as historical early work, not the active phase owner**

Edit `S5-000` so it no longer reads as the Phase 1 authoritative Liquidity Gate deliverable.

Because `S5-000` currently carries `passes=true`, treat this rewrite as invalidating the old pass artifact set. Set `passes=false` before editing the story text, and do not restore `passes=true` unless fresh current-HEAD full-verify artifacts later revalidate the rewritten story through `plans/prd_set_pass.sh`.

Preserve:
- the historical story ID,
- code/test scope for the standalone primitive,
- primitive-only evidence references only if they still prove the narrowed standalone gate mechanics after the ownership split.

Change:
- description / acceptance language that claims deployable Phase 2 ownership,
- any `§3.1`-dependent stale-L2 fallback acceptance/evidence/verify text so it no longer lives on `S5-000`,
- `VR-011` ownership on `S5-000` if `S7-002` becomes the active owner,
- contract AT ownership if that ownership is being transferred,
- any wording that makes `S5-000` a Phase 1 closure gate,
- the stale inherited `passes=true` state until fresh verification re-proves the rewritten story.

**Step 2: Transfer active contract ownership to a Phase 2 story**

Prefer reusing `S7-002` instead of inventing a new story ID. Update `S7-002` so it owns the integrated Phase 2 Liquidity Gate contract surface:
- add `VR-011` as the active Liquidity Gate validation-rule owner,
- add `§1.3` and `LiquidityGateNoL2` contract refs,
- add `AT-222`, `AT-344`, `AT-909`, `AT-421`, `AT-1216`,
- keep `AT-236`, `AT-937`, `AT-938`, and add `AT-1217`,
- inherit the moved stale-L2 fallback acceptance/evidence language from `S5-000` so the `§3.1`-dependent proof lives on the same Phase 2 story that owns the fallback ladder,
- add dependency on `S5-000` if the standalone gate primitive remains the prerequisite implementation.

This keeps historical review artifacts intact while moving present-tense phase ownership to the Phase 2 story that already owns the fallback ladder.

**Step 3: Correct the stale-L2 fallback semantics in the PRD acceptance text**

The current `S7-002` wording for `AT-938` is contract-drifted. Fix it so:
- `AT-937` = L1 fallback dispatches,
- `AT-938` = venue-band fallback dispatches when L1 is unavailable,
- `AT-1217` = fail closed with `Rejected(EmergencyCloseNoPrice)` only when L2, L1, and venue-band fallback are all unavailable.

Also move any fallback-specific acceptance/evidence wording out of `S5-000` and into `S7-002`; after this sync, `S5-000` should only describe standalone Liquidity Gate mechanics that do not depend on `§3.1`.

Do not let the PRD imply that ordinary CLOSE/HEDGE placement bypasses `AT-421`.

**Step 4: Refresh the coverage matrix after PRD ownership changes**

Run: `python3 plans/contract_coverage_matrix.py`
Expected: `docs/contract_coverage.md` regenerates and `VR-011` points only at `S7-002`; if `S5-000` or both stories still appear, the ownership transfer is incomplete.

**Step 5: Record the historical-artifact boundary**

If the PRD/progress text needs an explicit note, add one sentence in `plans/progress.txt` stating:
- canonical sources were realigned,
- dated reconciliation/audit artifacts were intentionally left untouched as historical evidence,
- new audits should use the updated contract + implementation plan + PRD.

Do not rewrite dated reconciliation reports or archived story-review artifacts.

### Task 4: Validate the PRD and verification surfaces

**Files:**
- Verify: `plans/prd.json`
- Verify: `docs/contract_kernel.json`
- Verify: `docs/contract_coverage.md`

**Step 1: Run PRD validation**

Run:
- `./plans/prd_gate.sh`
- `./plans/prd_audit_check.sh`

Expected:
- `prd_gate` passes schema/ref validation,
- `prd_audit_check` either passes against fresh artifacts or fails closed with a hash mismatch.

**Step 2: If audit hashes are stale, rerun the auditor**

Run: `AUDITOR_TIMEOUT=1800 ./plans/run_prd_auditor.sh`

Then rerun:
- `./plans/prd_audit_check.sh`

Expected: the regenerated audit artifacts match the updated `plans/prd.json`.

**Step 3: Run a focused diff/term sweep**

Run:
- `git diff -- specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md plans/prd.json docs/contract_kernel.json docs/contract_coverage.md`
- `rg -n "Liquidity Gate|LiquidityGateNoL2|VR-011|AT-1216|AT-1217|AT-938|Phase 1.*Liquidity|Phase 2.*Liquidity|§3.1" specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md plans/prd.json docs/contract_coverage.md`

Expected: all active sources agree that Liquidity Gate compliance is Phase 2-owned, `VR-011` is owned by `S7-002`, and stale-L2 fallback belongs only to the emergency-close path.

**Step 4: Run the canonical quick verify in a clean environment**

Preferred:
- fresh worktree / clean checkout
- or CI clean-checkout verify on the branch

Run: `./plans/verify.sh quick`

Expected: quick verify passes without using `VERIFY_ALLOW_DIRTY=1`.

Current repo note: this working tree is already dirty, so local quick verify from here is not trustworthy for final sign-off unless the tree is cleaned first.

**Step 5: Revalidate any rewritten `passes=true` story before restoring the pass bit**

If the rewritten `S5-000` should remain passed after the ownership/acceptance edit, run this in a clean checkout or CI after the PRD text is final:
- `./plans/verify.sh full`
- `./plans/prd_set_pass.sh S5-000 true`

Expected:
- the pass flip uses full-mode artifacts from the current `HEAD`,
- the rewritten `S5-000` does not retain stale pass state from the pre-sync definition,
- if full verify is not available yet, `S5-000` remains `passes=false` in this sync branch.

**Step 6: Run review before merge**

After the multi-file source-of-truth edit is complete, run the `code-review-expert` skill on the final diff before merge or pass-flip decisions. This is mandatory for a significant contract/PRD/plan realignment.

### Task 5: Keep the blast radius bounded

**Files:**
- Review only: `docs/reconcile/**`
- Review only: `artifacts/story/**`
- Review only: dated audit docs outside the active canonical set

**Step 1: Do not rewrite historical evidence**

Treat these as immutable historical records unless a separate reconciliation task is explicitly opened:
- `docs/reconcile/**`
- `reviews/reconciliations/**`
- `artifacts/story/**`
- prior review digests and dated audit reports

**Step 2: If a current doc becomes misleading, add a supersession note instead of mutating history**

Only if needed, add a short present-tense note in a live canonical doc (`plans/progress.txt` or a new dated plan note) that newer source-of-truth documents supersede older phase-boundary assumptions.

**Step 3: Commit in one bounded unit**

Use one focused commit once validation is green:

```bash
git add specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md plans/prd.json docs/contract_kernel.json docs/contract_coverage.md plans/progress.txt docs/plans/2026-03-07-liquidity-gate-phase-boundary-sync.md
git commit -m "docs: realign liquidity gate to phase 2 ownership"
```

Keep unrelated dirty-tree changes out of this commit.
