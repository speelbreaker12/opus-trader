# Open PR Review — 2026-02-17

Reviewed all 5 substantive open PRs. Organized by priority (highest-impact first).

---

## PR #96 — `feat: JSONL durable storage, WAL gate trait, TLSM sink, CSP.3.2 fix`

**Branch:** `feature/slice4-cherry-pick` → `main`
**Size:** +4,290 / -1,133 across 34 files
**Status:** Mergeable (unstable — no CI status checks reported)

### Summary

Cherry-picks from PR #72. Adds RecordedBeforeDispatchGate trait, TlsmTransitionSink, JSONL durable WAL storage, DurableWalGate adapter, CSP.3.2 compliance fix (gate 10 only blocks OPEN intents on WAL failure), and thread-safe TradeIdRegistry. Has gone through 5 rounds of review with all reviewers approving.

### Verdict: COMMENT (close to APPROVE — 3 items to address)

### Correctness

- [x] Gate 10 CSP.3.2 logic is correct — OPEN intents blocked, CLOSE/HEDGE/CANCEL pass through with warning log ✅
- [x] Persist-before-mutate atomicity pattern properly implemented in `persist_and_apply()` ✅
- [x] WAL crash recovery correctly tolerates trailing corrupt lines but rejects mid-file corruption ✅
- [x] Fail-closed defaults throughout (missing WAL adapter → `wal_recorded=false`) ✅
- [x] `replay()` now sorts `in_flight_hashes` for deterministic ordering ✅ (Copilot review comment already addressed)
- [x] TradeIdRegistry mutex poison handling is fail-closed ✅

### Open Review Comments (9 threads, all unresolved)

**Should Address:**

1. **`contract_prd_matrix.py:104` — Profile inheritance proximity bug** (copilot-reviewer)
   The `break` after finding the first match within 2 lines is iteration-order dependent, not distance-based. If two Profile declarations exist within 2 lines, the first in iteration order wins instead of the closest. **This is a real bug.** Fix:
   ```python
   explicit = None
   explicit_distance = 3
   for decl_line, prof in profile_decls:
       distance = at_line - decl_line
       if 0 <= distance <= 2 and distance < explicit_distance:
           explicit = prof
           explicit_distance = distance
   ```

2. **`scripts/check_gate_integrity.py:229` — Missing directory pruning** (copilot-reviewer)
   `.worktrees` and `artifacts` not pruned from `os.walk`. Already partially addressed in latest commit (`.worktrees` and `artifacts` now in prune list), but verify it's in the final diff.

**Informational / Nice-to-Have:**

3. `build_order_intent.rs:448` — CSP.3.2 warning log for Close/Hedge WAL failures: Already present in the code at lines 454-459 with `tracing::warn!`. The reviewer's comment appears to be outdated or based on an earlier commit. ✅ Already addressed.

4. `wal.rs` — Comment about "no-op" being outdated: The comment in `simulate_fsync_barrier()` is a no-op placeholder. The suggestion to clarify is reasonable but low-priority.

5. `test_recorded_before_dispatch_gate.rs` — Debug string assertion: Using `format!("{gate:?}")` in test assertions. Would be cleaner to compare enum values directly, but test is functional.

6. `.gates/gate_integrity.yml` — Config comment describes "CONTRACT.md format drifts" incorrectly: Minor documentation accuracy issue.

7. `.github/workflows/codeql.yml` — "Rust is not yet supported by CodeQL" is outdated: True, CodeQL supports Rust now. Minor comment fix.

8. `check_gate_integrity.py` — `yaml.safe_load()` type validation: Already addressed in the latest code — the `isinstance(loaded, dict)` check is present.

9. `ledger.rs:455` — `replay()` deterministic ordering: Already addressed — `in_flight_hashes.sort()` is in the code.

### Performance

- [x] `sync_all()` on every WAL write is acknowledged Phase 1 limitation (0.2-2ms block). Documented with plan for async WAL writer.
- [x] File handle kept open to avoid per-event reopen ✅
- [ ] **Note:** `WalLedger` stores all events in `latest_by_hash` without bound beyond `capacity`. For long-running processes, terminal intents accumulate. Documented as Phase 1 limitation.

### Testing

- [x] 8 WAL gate tests including 3 CSP.3.2 compliance tests ✅
- [x] 3 TLSM sink tests ✅
- [x] Crash recovery tests (AT-935, AT-233, AT-234) ✅
- [x] Trade-ID registry durability + thread safety tests ✅
- [x] Gate ordering updated for 10-gate trace ✅

### Security

- [x] No hardcoded secrets ✅
- [x] Fail-closed patterns throughout ✅
- [x] No injection risks ✅

### Recommendations

1. **Fix the profile inheritance proximity bug** in `contract_prd_matrix.py:104` (lines 100-108) — this is a correctness issue that could assign wrong profiles to ATs.
2. Consider addressing the test assertion style (Debug string vs enum comparison) for maintainability.
3. The PR is large (34 files) but coherent — all changes relate to WAL durability and CSP.3.2 compliance.

---

## PR #72 — `Slice4: sync remediation branch and restore verify-full pass`

**Branch:** `story/slice4-contract-remediation` → `main`
**Size:** +1,512 / -528 across 27 files
**Status:** Unknown mergeable state (likely behind `main`)

### Summary

Syncs the Slice 4 remediation branch with main, preserves WAL/TLSM/trade-id durability work, restores missing execution/risk exports, and fixes merge regressions. PR #96 cherry-picks the valuable parts from this PR.

### Verdict: COMMENT (consider closing in favor of #96)

### Key Observations

1. **Superseded by PR #96**: PR #96 explicitly cherry-picks the valuable additions from this PR onto main. If #96 is merged, this PR's core value is already captured.
2. **Behind main**: The base SHA is stale (`f3bcf43c`), meaning it will likely have merge conflicts with current main.
3. **Review comments from #72 already addressed in #96**: The WAL error detail capture, unbounded memory growth warning, and stale evidence reference are either fixed or documented in #96.

### Open Review Comments (4 threads)

1. **`build_order_intent.rs:411` — WAL gate error details discarded**: Valid concern. The error string from `record_before_dispatch()` is now captured in #96 via `wal_error` variable.
2. **`ledger.rs:268` — Unbounded `events` vector**: The `events` field was removed in #96, now using only `latest_by_hash`.
3. **`ledger.rs` — `sync_all()` on every write**: Acknowledged Phase 1 limitation, documented in #96.
4. **`prd.json` — Stale evidence reference**: Test rename not reflected in evidence list.

### Recommendation

**Close this PR** in favor of #96, which captures all the valuable changes with a cleaner history and addresses the review feedback from this PR.

---

## PR #94 — `tracking: PRD audit fixes (reason codes, enforcement points, acceptance)`

**Branch:** `tracking/prd-audit-fixes-log` → `main`
**Size:** +42 / -0 across 1 file
**Status:** Mergeable (behind main)

### Summary

Tracking PR that adds `artifacts/adhoc/prd_audit_fixes_tracking.md` documenting fixes already pushed to main. Pure documentation/audit trail.

### Verdict: APPROVE (minor nit)

### Correctness

- [x] Tracking document accurately describes fixes applied to main ✅
- [x] AT coverage metrics match (335/335, 100%) ✅

### Open Review Comments (1 thread)

1. **Conflict ID numbering gap**: IDs skip from C2 to C6 (missing C1). The header says "6 blocking conflicts" but only 5 are listed. Should either:
   - Add the missing C1 entry, or
   - Renumber to C1-C5 and change header to "5 blocking conflicts"

### Recommendation

Fix the numbering discrepancy and merge. This is a low-risk documentation PR.

---

## PR #79 — `test: validate multi-cycle Copilot aftercare automation`

**Branch:** `test/copilot-multicycle-happy` → `main`
**Size:** +814 / -1 across 26 files
**Status:** Unknown mergeable state

### Summary

**Test-only PR** with intentionally imperfect code to trigger Copilot review cycles. Explicitly marked **DO NOT MERGE** in the description. Contains magic numbers, non-idiomatic patterns, and inefficient loops by design.

### Verdict: DO NOT MERGE (as intended)

### Key Observations

1. The PR achieved its purpose — Copilot reviewed and posted 8 review comments identifying the intentional issues (magic numbers, `len() > 0` vs `is_empty()`, index loops vs iterators, unnecessary clones, f64 comparison).
2. All review comments are outdated (marked as such), suggesting the code was updated in response.
3. The test module is added as `pub mod` under `#[cfg(test)]` — should be `mod` (private) or moved to integration tests.

### Recommendation

**Close without merging** — the PR has served its validation purpose. The test infrastructure learnings should be captured separately if needed.

---

## PR #78 — `fix: wire slice cache drift fixture into preflight smoke profile`

**Branch:** `fix/slice2-review-issues` → `main`
**Size:** +53,132 / -4,408 across 456 files
**Status:** Unknown mergeable state

### Summary

Wires a slice cache drift fixture into the preflight smoke profile and updates expected fixture count from 15 to 16. However, the PR includes a massive amount of generated artifact files (53K+ lines added across 456 files).

### Verdict: REQUEST_CHANGES

### Critical Issues

1. **Enormous generated artifact churn**: 456 files changed with 53K+ additions. Most appear to be checked-in artifact/comparison reports. This makes review impractical and bloats the repository.

2. **Absolute paths leaked in artifacts** (3 review comments):
   - `artifacts/phase1_compare/*/diffs/*.diff` — contains `/tmp/...` paths
   - `artifacts/phase1_compare/*/report.md` — leaks local filesystem paths including usernames
   - `artifacts/phase1_compare/*/report.json` — absolute local paths in JSON

3. **Security concern**: Local filesystem paths with usernames in committed artifacts is sensitive information disclosure.

### Open Review Comments (4 threads)

All 4 comments relate to the checked-in artifacts containing absolute local paths and recommending either:
- Excluding artifacts from version control via `.gitignore`
- Sanitizing paths at generation time

### Recommendations

1. **Add `artifacts/phase1_compare/` to `.gitignore`** to prevent committing generated comparison reports.
2. **Rebase to only include the 3 actual fix files** (fixture wiring, profile test, count update) — the stated change is tiny but the PR includes massive unrelated artifact churn.
3. **Sanitize report generators** to emit repo-relative paths instead of absolute paths.

---

## Summary Table

| PR | Title | Size | Verdict | Priority |
|----|-------|------|---------|----------|
| **#96** | JSONL durable storage, WAL gate trait, CSP.3.2 fix | +4,290/-1,133 | **COMMENT** (near APPROVE) | 🔴 High — fix profile bug, then merge |
| **#72** | Slice4 sync remediation | +1,512/-528 | **COMMENT** | ⚪ Close in favor of #96 |
| **#94** | PRD audit fixes tracking | +42/-0 | **APPROVE** (minor nit) | 🟢 Low — fix numbering, merge |
| **#79** | Copilot aftercare test | +814/-1 | **DO NOT MERGE** | ⚪ Close — served its purpose |
| **#78** | Slice cache drift fixture | +53,132/-4,408 | **REQUEST_CHANGES** | 🟡 Medium — strip artifacts, re-submit |

## Recommended Merge Order

1. **#94** (tracking doc, trivially safe) — fix numbering nit, merge
2. **#96** (core WAL durability) — fix profile proximity bug, merge
3. **#72** — close in favor of #96
4. **#79** — close without merge
5. **#78** — strip generated artifacts, resubmit as focused 3-file PR
