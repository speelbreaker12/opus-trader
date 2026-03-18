# Cross-Reference Validator Design v2
## Incremental Extension to Existing Gates

**Version:** 2.0  
**Status:** Revised Design  
**Target:** Extend existing gates, avoid duplication

---

## 1. Design Philosophy Change

**v1 Approach (rejected):** Build parallel parser stack, heavy preflight integration
**v2 Approach (accepted):** Extend existing gates (`prd_ref_check.sh`, `prd_lint.sh`, `verify_fork.sh`) with incremental capabilities

**Principles:**
1. **Reuse > Rewrite:** Extend `prd_lint.sh` and `prd_ref_check.sh`, don't replace
2. **Fast preflight:** Keep preflight O(seconds), move heavy analysis to `verify.sh full`
3. **Explicit signals:** Use exit codes and structured counts, not file non-emptiness
4. **Run-scoped artifacts:** All outputs under `artifacts/verify/<run_id>/`

---

## 2. Current Gate Inventory

| Existing Gate | Purpose | What It Already Checks |
|---------------|---------|----------------------|
| `plans/prd_ref_check.sh:168` | PRD→Contract refs | `contract_refs` resolve to ATs/Anchors |
| `plans/prd_lint.sh:495` | Anchor existence | All anchors referenced exist in contract |
| `plans/prd_lint.sh:522` | Validation rules | `enforcing_contract_ats` exist, AT format valid |
| `plans/verify_fork.sh:262` | Contract crossref | Runtime contract cross-reference validation |

**Gap Analysis:**
- ✅ AT existence: Covered by `prd_ref_check.sh` + `prd_lint.sh`
- ✅ Anchor existence: Covered by `prd_lint.sh`
- ❌ **AT coverage dashboard:** No visual tracking of which ATs have stories
- ❌ **Roadmap evidence→story mapping:** No check that roadmap artifacts have producing stories
- ❌ **Slice consistency:** No validation that story `slice_ref` matches actual plan structure

---

## 3. Incremental Additions Only

### Addition 1: AT Coverage Index (Lightweight)

**Extends:** `plans/prd_lint.sh`
**Location:** After existing AT validation (around line 530)

**What it does:**
```bash
# New function in prd_lint.sh
generate_at_coverage_index() {
  # Input: already-parsed contract ATs, already-parsed PRD stories
  # Output: artifacts/verify/${RUN_ID}/at_coverage_index.json
  
  # Structure:
  # {
  #   "contract_version": "5.2",
  #   "generated_at": "2026-02-12T12:00:00Z",
  #   "stats": {
  #     "total_csp_ats": 142,
  #     "referenced_by_stories": 128,
  #     "unreferenced_csp_ats": 14
  #   },
  #   "unreferenced": ["AT-1048", "AT-1053", ...],
  #   "coverage_by_phase": {
  #     "phase_0": {"required": 25, "covered": 25},
  #     "phase_1": {"required": 60, "covered": 48}
  #   }
  # }
}
```

**Preflight check:** NONE (informational only)
**Verify full:** Generate and include in artifacts
**Cost:** O(n) where n = stories × contract_refs; negligible vs existing parsing

---

### Addition 2: Roadmap Evidence Coverage Check

**New Script:** `plans/roadmap_evidence_check.sh`
**Pattern:** Follows `plans/prd_gate.sh` structure

**What it does:**
1. Parse `docs/ROADMAP.md` for `evidence/phase{N}/...` requirements
2. Parse `docs/PHASE{0,1}_CHECKLIST_BLOCK.md` for evidence requirements
3. Check `plans/prd.json` for stories that produce these artifacts
4. Report gaps (roadmap requires evidence, but no story produces it)

**Scope:** Phase 1 only for now (Phase 0 is complete)

**Expected gaps to find:**
```
evidence/phase1/restart_loop/restart_100_cycles.log
  - Required by: ROADMAP.md Phase 1 Acceptance
  - Producer story: NONE FOUND
  - Suggestion: Add S1-EVIDENCE-003

evidence/phase1/determinism/intent_hashes.txt
  - Required by: ROADMAP.md P1-B
  - Producer story: NONE FOUND
  - Suggestion: Add S1-EVIDENCE-002
```

**Integration:**
```bash
# plans/verify_fork.sh - add new gate
check_roadmap_evidence_coverage() {
  log_info "Checking roadmap evidence coverage..."
  
  python3 tools/roadmap_evidence_check.py \
    --roadmap docs/ROADMAP.md \
    --checklists docs/PHASE0_CHECKLIST_BLOCK.md docs/PHASE1_CHECKLIST_BLOCK.md \
    --prd plans/prd.json \
    --output artifacts/verify/${RUN_ID}/roadmap_evidence_gaps.json
  
  GAPS=$(jq '.gaps | length' artifacts/verify/${RUN_ID}/roadmap_evidence_gaps.json)
  
  if [[ $GAPS -gt 0 ]]; then
    log_warn "Found ${GAPS} roadmap evidence items without producing stories"
    # Non-blocking for now, informational
  fi
  
  return 0  # Never blocking, informational only
}
```

**Preflight:** NO (not run in preflight)
**Verify full:** YES, run as informational gate
**Cost:** Single pass through roadmap + checklist files

---

### Addition 3: Slice Consistency Check (Fast)

**Extends:** `plans/prd_lint.sh`
**Location:** With existing PRD schema validation

**What it validates:**
```bash
# For each story in PRD:
# 1. story.slice_ref should match "Slice {N}" pattern
# 2. story.plan_refs should reference same slice
# 3. story.phase should match slice's phase

# Example violations to catch:
# - Story says "slice_ref": "Slice 1" but "phase": 2 (inconsistent)
# - Story says "plan_refs": ["Slice 2"] but "slice_ref": "Slice 1" (mismatch)
```

**Implementation:**
```bash
# In prd_lint.sh - new check function
check_slice_consistency() {
  local prd_file=$1
  local errors=0
  
  # Extract all stories with slice inconsistencies
  python3 -c "
import json
import sys

with open('$prd_file') as f:
    data = json.load(f)

errors = []
for item in data.get('items', []):
    slice_ref = item.get('slice_ref', '')
    phase = item.get('phase')
    plan_refs = item.get('plan_refs', [])
    
    # Parse slice number from slice_ref
    if 'Slice' in slice_ref:
        slice_num = int(slice_ref.split()[1].split()[0])
        expected_phase = ((slice_num - 1) // 5) + 1  # 1-5=phase1, 6-9=phase2, etc.
        
        if phase != expected_phase:
            errors.append(f\"{item['id']}: phase={phase} but slice={slice_num} implies phase={expected_phase}\")
    
    # Check plan_refs consistency
    for ref in plan_refs:
        if 'Slice' in ref and item.get('id', '').startswith('S'):
            ref_slice = ref.split('—')[0].strip()
            if ref_slice != slice_ref:
                errors.append(f\"{item['id']}: slice_ref='{slice_ref}' but plan_refs has '{ref_slice}'\")

for e in errors:
    print(e)
sys.exit(len(errors))
"
  
  errors=$?
  return $errors
}
```

**Preflight:** YES (fast check, O(n) stories)
**Verify full:** YES (redundant but cheap)
**Blocking:** YES for schema violations (this is a real bug)

---

## 4. Artifact Strategy (Run-Scoped)

All new outputs go to run-scoped locations:

```
artifacts/verify/${RUN_ID}/
├── at_coverage_index.json          # Addition 1 output
├── roadmap_evidence_gaps.json      # Addition 2 output
├── slice_consistency_report.json   # Addition 3 output
└── crossref_summary.md             # Human-readable rollup
```

**Never write to:**
- `artifacts/crossref/` (shared, collision risk)
- `artifacts/` root (clutter)

---

## 5. Preflight vs Verify Division

| Check | Location | Duration | Blocking |
|-------|----------|----------|----------|
| AT existence (`prd_ref_check.sh`) | Preflight | <1s | YES |
| Anchor existence (`prd_lint.sh`) | Preflight | <1s | YES |
| AT format valid (`prd_lint.sh`) | Preflight | <1s | YES |
| **Slice consistency (NEW)** | **Preflight** | **<1s** | **YES** |
| AT coverage index | Verify full | ~2s | NO |
| Roadmap evidence gaps | Verify full | ~3s | NO |

**Preflight stays fast:** 4 quick checks, all O(n) or better
**Verify full adds:** Coverage analysis (informational)

---

## 6. Report Format (Human-Readable)

`artifacts/verify/${RUN_ID}/crossref_summary.md`:

```markdown
# Cross-Reference Summary
Run: 2026-02-12T12:00:00Z

## Contract Coverage
| Profile | Total ATs | Referenced | Coverage |
|---------|-----------|------------|----------|
| CSP | 142 | 128 | 90% |
| GOP | 45 | 12 | 27% |

## Phase Coverage (CSP ATs only)
| Phase | Required | Covered | % |
|-------|----------|---------|---|
| Phase 0 | 25 | 25 | 100% ✅ |
| Phase 1 | 60 | 48 | 80% ⚠️ |
| Phase 2 | 35 | 22 | 63% ⚠️ |

## Unreferenced CSP ATs (Blocking for Live)
- AT-1048 (Axis Resolver Enumerability) - PolicyGuard slice
- AT-1053 (Axis Resolver Monotonicity) - PolicyGuard slice

## Roadmap Evidence Gaps
Missing stories for required artifacts:
- `evidence/phase1/restart_loop/restart_100_cycles.log`
  - Required by: ROADMAP.md Phase 1
  - Status: NO PRODUCER STORY
  - Suggest: Add S1-EVIDENCE-003

## Slice Consistency
✅ All 73 stories have consistent phase/slice references
```

---

## 7. Implementation Plan

### Step 1: Slice Consistency (Week 1, Day 1-2)
**Risk:** Low (extends existing prd_lint.sh)
**Work:**
- Add `check_slice_consistency()` to `prd_lint.sh`
- Add unit test in `plans/tests/test_prd_lint.sh`
- Verify on current PRD (expect: clean or fix existing issues)

**Exit criteria:**
```bash
./plans/prd_lint.sh; echo $?  # Should exit 0
```

### Step 2: AT Coverage Index (Week 1, Day 3-4)
**Risk:** Low (informational only)
**Work:**
- Add `generate_at_coverage_index()` to `prd_lint.sh` or `verify_fork.sh`
- Output to run-scoped artifact
- Do NOT block on coverage percentage (informational)

**Exit criteria:**
```bash
./plans/verify.sh full
# Check artifacts/verify/*/at_coverage_index.json exists
```

### Step 3: Roadmap Evidence Check (Week 1, Day 5)
**Risk:** Medium (new script)
**Work:**
- Create `tools/roadmap_evidence_check.py` (small, focused)
- Wire into `verify_fork.sh` as informational gate
- Generate human-readable gaps report

**Exit criteria:**
```bash
./plans/verify.sh full
# Check artifacts/verify/*/roadmap_evidence_gaps.json
# Expect: finds Phase 1 evidence gaps (S1-EVIDENCE-xxx missing)
```

### Step 4: Integration & Rollup (Week 2, Day 1-2)
**Risk:** Low
**Work:**
- Create `crossref_summary.md` generator that rolls up all 3 checks
- Add to `verify.sh full` artifact bundle
- Update `plans/workflow_acceptance.sh` to assert new artifacts exist

---

## 8. Files Changed (Minimal)

```
plans/prd_lint.sh                    # Add slice_consistency check
plans/verify_fork.sh                 # Add AT coverage + roadmap checks
tools/roadmap_evidence_check.py      # NEW: focused gap finder (~150 LOC)
tools/generate_coverage_rollup.py    # NEW: markdown report generator (~100 LOC)
plans/tests/test_prd_lint.sh         # Add slice consistency test
plans/tests/test_roadmap_evidence.sh # NEW: fixture-based test
config/crossref.yaml                 # OPTIONAL: thresholds for warnings
```

**Total new code:** ~400 LOC (vs ~2000 LOC for v1 parallel stack)

---

## 9. Success Metrics

| Metric | Before | After v2 |
|--------|--------|----------|
| Preflight duration | ~5s | ~6s (+1s slice check) |
| Verify full duration | ~120s | ~125s (+coverage) |
| AT coverage visibility | Manual | Automated dashboard |
| Roadmap evidence gaps | Unknown | Tracked in artifacts |
| False preflight failures | N/A | 0 (explicit exit codes) |

---

## 10. Open Questions (Smaller Scope)

1. **Should AT coverage % be blocking at phase exit?**
   - Suggest: NO for Phase 1 (in progress), YES for Phase 1 exit gate
   
2. **Which roadmap evidence items are truly required vs aspirational?**
   - Suggest: Only validate items in `PHASE{N}_CHECKLIST_BLOCK.md` (canonical)
   
3. **Should GOP ATs be tracked separately?**
   - Suggest: YES, separate table; CSP is mandatory, GOP is advisory

---

*End of Revised Design*
