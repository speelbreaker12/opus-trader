# Cross-Reference Validator Design v3
## Corrected Incremental Extension

**Version:** 3.0  
**Status:** Corrected Design  
**Target:** Fix logic errors, correct gate placements, handle actual formats

---

## 1. Corrections from v2 Review

| Finding | v2 Error | v3 Fix |
|---------|----------|--------|
| **#1 HIGH:** Slice→phase mapping | `((slice_num - 1) // 5) + 1` is wrong | Use actual mapping from IMPLEMENTATION_PLAN.md line 1183, 1295 |
| **#2 HIGH:** plan_refs parsing | Assumed "Slice N — ..." format | Handle actual prd.json formats (mixed refs, section refs) |
| **#3 MEDIUM:** enforcing_contract_ats | Claimed existence checked | Acknowledge only format checked; add explicit lookup |
| **#4 MEDIUM:** Non-existent script | Referenced `workflow_acceptance.sh` | Reference actual files: `plans/tests/test_workflow_allowlist_coverage.sh` |
| **#5 MEDIUM:** Pipeline wiring | Claimed prd_lint in preflight | Place checks where they actually run (verify only) |
| **#6 LOW:** Artifact ownership | RUN_ID in prd_lint.sh | Pass output path as parameter, let caller manage RUN_ID |

---

## 2. Actual Slice→Phase Mapping (from IMPLEMENTATION_PLAN.md)

From specs/IMPLEMENTATION_PLAN.md analysis:
- **Phase 1:** Slices 1–5 (lines 85-557)
- **Phase 2:** Slices 6–9 (lines 560-1165)  
- **Phase 3:** Slices 10–12 (lines 1167-1279)
- **Phase 4:** Slice 13 (lines 1281-1478)

**Correct mapping table:**
```
Slice  1-5  → Phase 1
Slice  6-9  → Phase 2
Slice 10-12 → Phase 3
Slice    13 → Phase 4
```

**Validation function (corrected):**
```bash
get_phase_for_slice() {
  local slice=$1
  if [[ $slice -ge 1 && $slice -le 5 ]]; then echo 1
  elif [[ $slice -ge 6 && $slice -le 9 ]]; then echo 2
  elif [[ $slice -ge 10 && $slice -le 12 ]]; then echo 3
  elif [[ $slice -eq 13 ]]; then echo 4
  else echo "INVALID"
  fi
}
```

---

## 3. Actual plan_refs Formats (from prd.json analysis)

From prd.json line 26-28 and similar patterns:
```json
"plan_refs": [
  "Global Non‑Negotiables (apply to ALL stories)",  // Global ref, no slice
  "IMPLEMENTATION_PLAN.md Slice 1 — Instrument Units...",  // Slice ref
  "IMPLEMENTATION_PLAN.md Slice 1 — ... / S1.1 — ...",  // Slice + story ref
  "Slice 2 — Quantization + Labeling + Idempotency"  // Slice only
]
```

**Parsing strategy:**
- Extract all `Slice \d+` patterns (regex)
- Multiple slice refs allowed (cross-slice dependencies)
- Global refs have no slice number, skip for consistency checks
- Section refs like "S1.1" are story-level, different from slice

**Corrected consistency check:**
```bash
# For a story:
# 1. story.slice_ref → extract slice number (e.g., "Slice 1" → 1)
# 2. story.phase → expected phase from mapping
# 3. story.plan_refs → extract all "Slice N" refs
# 4. Validate: slice number in plan_refs contains slice from slice_ref
```

---

## 4. Corrected Gate Inventory

| Gate | Current Location | What It Actually Checks |
|------|------------------|------------------------|
| `plans/prd_ref_check.sh` | PR merge check | PRD `contract_refs` resolve to valid AT/Anchor IDs |
| `plans/prd_lint.sh` | `prd_gate.sh` (not preflight) | Schema, anchor existence, AT format |
| `plans/prd_schema_check.sh` | `verify.sh` | Schema validity, required fields present |
| `plans/verify_fork.sh:262` | `verify.sh full` | Contract cross-reference runtime check |

**Important:** `prd_lint.sh` is NOT in preflight. It's in `prd_gate.sh`.

---

## 5. Revised Integration Points

### Where Checks Actually Run

| Check | Script | When | Blocking |
|-------|--------|------|----------|
| Slice consistency | `prd_lint.sh` | `prd_gate.sh` | YES |
| AT coverage index | `verify_fork.sh` | `verify.sh full` | NO |
| Roadmap evidence gaps | `verify_fork.sh` | `verify.sh full` | NO |

### Corrected Pipeline Flow

```
PR Open / Commit Push
       ↓
┌─────────────────┐
│ plans/preflight.sh │  (fast: shellcheck, schema, lightweight)
│                 │
│ NEW: None (keep │
│ it fast)        │
└─────────────────┘
       ↓ (pass)
┌─────────────────┐
│ plans/prd_gate.sh │  (PR merge readiness)
│                 │
│ plans/prd_ref_check.sh  │
│ plans/prd_lint.sh       │ ← Add slice consistency here
└─────────────────┘
       ↓ (pass)
┌─────────────────┐
│ ./plans/verify.sh full  │  (comprehensive)
│                 │
│ verify_fork.sh gates    │
│   - unit tests          │
│   - contract coverage   │ ← Add AT coverage here
│   - roadmap evidence    │ ← Add evidence gaps here
└─────────────────┘
```

---

## 6. Corrected Check: Slice Consistency

**Location:** `plans/prd_lint.sh` (already runs on PRD)
**Addition:** After existing checks, around line 730

```bash
# New function in prd_lint.sh
check_slice_phase_consistency() {
  local prd_file="$1"
  local errors=0
  
  python3 -c "
import json
import re
import sys

def phase_for_slice(s):
    if 1 <= s <= 5: return 1
    elif 6 <= s <= 9: return 2
    elif 10 <= s <= 12: return 3
    elif s == 13: return 4
    return None

with open('$prd_file') as f:
    data = json.load(f)

errors = []
for item in data.get('items', []):
    story_id = item.get('id', 'UNKNOWN')
    phase = item.get('phase')
    slice_ref = item.get('slice_ref', '')
    plan_refs = item.get('plan_refs', [])
    
    # Extract slice number from slice_ref
    slice_match = re.search(r'Slice\s+(\d+)', slice_ref)
    if not slice_match:
        continue  # Skip if no slice_ref (some stories are meta)
    
    slice_num = int(slice_match.group(1))
    expected_phase = phase_for_slice(slice_num)
    
    # Check 1: phase matches slice
    if expected_phase and phase != expected_phase:
        errors.append(f\"{story_id}: phase={phase} but slice={slice_num} maps to phase={expected_phase}\")
    
    # Check 2: plan_refs contain compatible slice references
    plan_slices = []
    for ref in plan_refs:
        matches = re.findall(r'Slice\s+(\d+)', ref)
        plan_slices.extend([int(m) for m in matches])
    
    # story's slice should be among plan_refs slices (or plan_refs can have broader refs)
    if plan_slices and slice_num not in plan_slices:
        # This might be OK if plan_refs references parent/global, but flag it
        errors.append(f\"{story_id}: slice_ref={slice_num} not found in plan_refs slices={plan_slices}\")

for e in errors:
    print(e)
sys.exit(len(errors))
" 2>/dev/null
  
  errors=$?
  if [[ $errors -gt 0 ]]; then
    log_error "Slice/phase consistency errors: $errors"
    return 1
  fi
  return 0
}
```

---

## 7. Corrected Check: AT Coverage Index

**Location:** `plans/verify_fork.sh`
**When:** During `verify.sh full`, not preflight

```bash
# In verify_fork.sh - new gate function
check_at_coverage() {
  log_info "Building AT coverage index..."
  
  local output_file="${VERIFY_ARTIFACTS:-artifacts/verify}/${RUN_ID}/at_coverage_index.json"
  mkdir -p "$(dirname "$output_file")"
  
  # Call Python tool with explicit output path (no RUN_ID dependency in tool)
  python3 tools/at_coverage_index.py \
    --contract specs/CONTRACT.md \
    --prd plans/prd.json \
    --output "$output_file"
  
  # Report summary
  local total_csp referenced_csp
  total_csp=$(jq '.stats.total_csp_ats' "$output_file")
  referenced_csp=$(jq '.stats.referenced_csp_ats' "$output_file")
  
  log_info "AT Coverage: $referenced_csp/$total_csp CSP ATs referenced"
  
  # Non-blocking: just informational
  return 0
}
```

**Tool:** `tools/at_coverage_index.py`
- Takes explicit `--output` path
- No RUN_ID awareness (caller manages paths)
- Generates JSON index + human-readable markdown

---

## 8. Corrected Check: Roadmap Evidence Gaps

**Location:** `plans/verify_fork.sh`
**When:** During `verify.sh full`

```bash
check_roadmap_evidence() {
  log_info "Checking roadmap evidence coverage..."
  
  local output_file="${VERIFY_ARTIFACTS:-artifacts/verify}/${RUN_ID}/roadmap_evidence_gaps.json"
  
  python3 tools/roadmap_evidence_check.py \
    --roadmap docs/ROADMAP.md \
    --checklist docs/PHASE0_CHECKLIST_BLOCK.md docs/PHASE1_CHECKLIST_BLOCK.md \
    --prd plans/prd.json \
    --output "$output_file"
  
  local gaps
  gaps=$(jq '.gaps | length' "$output_file")
  
  if [[ $gaps -gt 0 ]]; then
    log_warn "Found $gaps roadmap evidence items without PRD stories"
    # List them in log
    jq -r '.gaps[] | "  - \(.evidence_path): \(.status)"' "$output_file" | head -10
  else
    log_info "All roadmap evidence items have producing PRD stories"
  fi
  
  return 0
}
```

---

## 9. Corrected Wiring in verify_fork.sh

Add to appropriate section (with other gates):

```bash
# In verify_fork.sh, add to gate execution:

run_gate "AT Coverage Index" check_at_coverage || true  # Non-blocking
run_gate "Roadmap Evidence Coverage" check_roadmap_evidence || true  # Non-blocking

# Slice consistency is in prd_lint.sh, already runs in PR gate
```

---

## 10. Test Plan (Using Actual Files)

### Test 1: Slice Consistency
```bash
# Run prd_lint on current PRD
./plans/prd_lint.sh plans/prd.json

# Expected: Exit 0 (or list of actual inconsistencies to fix)
```

### Test 2: AT Coverage
```bash
# Run in verify context
RUN_ID=test_$(date +%s)
python3 tools/at_coverage_index.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output artifacts/verify/${RUN_ID}/at_coverage.json

# Verify output structure
jq '.stats.total_csp_ats' artifacts/verify/${RUN_ID}/at_coverage.json
```

### Test 3: Roadmap Evidence
```bash
RUN_ID=test_$(date +%s)
python3 tools/roadmap_evidence_check.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output artifacts/verify/${RUN_ID}/gaps.json

# Should find: restart_100_cycles.log, intent_hashes.txt gaps
jq '.gaps[] | select(.evidence_path | contains("restart_100"))' artifacts/verify/${RUN_ID}/gaps.json
```

---

## 11. Files to Create/Modify

### Modified (3 files)
```
plans/prd_lint.sh                    # Add check_slice_phase_consistency()
plans/verify_fork.sh                 # Add check_at_coverage(), check_roadmap_evidence()
plans/tests/test_prd_lint.sh         # Add test for slice consistency
```

### New (2 files)
```
tools/at_coverage_index.py           # Generate AT coverage report
tools/roadmap_evidence_check.py      # Find roadmap→PRD gaps
```

### No changes to
- `plans/preflight.sh` (keep it fast, no new checks)
- `plans/prd_ref_check.sh` (already checks contract refs)
- Non-existent files (no more phantom references)

---

## 12. Output Examples (Expected)

### AT Coverage Index
```json
{
  "contract_version": "5.2",
  "generated_at": "2026-02-12T12:00:00Z",
  "stats": {
    "total_ats": 187,
    "csp_ats": 142,
    "referenced_csp_ats": 128,
    "unreferenced_csp_ats": 14,
    "gop_ats": 45,
    "referenced_gop_ats": 12
  },
  "unreferenced_csp": [
    {"at": "AT-1048", "section": "2.2.3", "title": "Axis Resolver Enumerability"},
    {"at": "AT-1053", "section": "2.2.3", "title": "Axis Resolver Monotonicity"}
  ],
  "coverage_by_phase": {
    "phase_0": {"required_csp": 25, "covered": 25, "pct": 100},
    "phase_1": {"required_csp": 60, "covered": 48, "pct": 80}
  }
}
```

### Roadmap Evidence Gaps
```json
{
  "gaps": [
    {
      "evidence_path": "evidence/phase1/restart_loop/restart_100_cycles.log",
      "required_by": ["ROADMAP.md:171", "PHASE1_CHECKLIST_BLOCK.md:189"],
      "status": "NO_PRODUCER_STORY",
      "suggested_story_id": "S1-EVIDENCE-003"
    },
    {
      "evidence_path": "evidence/phase1/determinism/intent_hashes.txt",
      "required_by": ["ROADMAP.md:225"],
      "status": "NO_PRODUCER_STORY",
      "suggested_story_id": "S1-EVIDENCE-002"
    }
  ]
}
```

---

*End of Corrected Design v3*
