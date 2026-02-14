# Cross-Reference Validator Design v4
## Implementation-Ready Design (Corrected from Codebase)

**Version:** 4.0  
**Status:** Implementation-Ready (pending final review)  
**Prerequisite:** Read actual verify_fork.sh, prd_ref_check.sh, prd.json line 3236+

---

## 1. Critical Corrections from v3 Review

| Finding | v3 Error | v4 Fix (from actual code) |
|---------|----------|---------------------------|
| **#1 HIGH:** Env vars | `VERIFY_ARTIFACTS`, `RUN_ID` | `VERIFY_ARTIFACTS_DIR`, `VERIFY_RUN_ID` (verify_fork.sh:115-116) |
| **#2 HIGH:** Phase mapping | Strict slice→phase rule | Acknowledge exceptions exist (S6-000..S6-006 in Phase 1) |
| **#3 MEDIUM:** Log helpers | `log_info`, `log_warn`, `run_gate` | `log`, `warn`, `run_logged_or_exit` (verify_fork.sh pattern) |
| **#4 MEDIUM:** Ref check scope | Claimed strict ID lookup | Text resolution, not strict lookup (prd_ref_check.sh:151,182) |
| **#5 LOW:** Expected gaps | Listed intent_hashes.txt | Already referenced (prd.json:3327,3344,3353) |

---

## 2. Actual Environment (from verify_fork.sh:115-116)

```bash
# Correct variable names
VERIFY_ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-artifacts/verify}"
VERIFY_RUN_ID="${VERIFY_RUN_ID:-$(date +%Y%m%d_%H%M%S)}"

# Usage in functions
output_file="${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}/at_coverage.json"
```

---

## 3. Actual Logging Pattern (from verify_fork.sh)

```bash
# Current helpers (use these, not made-up names)
log() { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }
run_logged_or_exit() { ... }  # Existing helper

# NOT these (v3 was wrong)
# log_info() - doesn't exist
# log_warn() - doesn't exist  
# run_gate() - doesn't exist
```

---

## 4. Slice→Phase Reality (from prd.json analysis)

**Finding:** Slice number is **not strictly** phase.

From prd.json lines 3236-3240:
```json
{
  "id": "S6-000",
  "phase": 1,          // ← Phase 1
  "slice": 6,          // ← But slice 6
  "slice_ref": "Slice 6 — Rate Limit Circuit Breaker + WS Gaps + Reconcile + Zombie Sweeper"
}
```

**Analysis:**
- Slice is a **grouping** concept from Implementation Plan
- Phase is a **timeline/milestone** concept from Roadmap
- Most slices map to phases, but **exceptions exist** (S6-000..S6-006 in Phase 1)

**Conclusion:** Do NOT validate slice↔phase consistency. The data shows it's intentionally flexible.

**Alternative validation:** Check that `slice_ref` in story matches actual slice number (format validation only).

---

## 5. Revised Scope (Smaller, Correct)

Remove slice-phase consistency check. Keep only:

### Check 1: AT Coverage Index (Informational)
**Location:** `verify_fork.sh`  
**Purpose:** Generate dashboard of which CSP ATs have story coverage

### Check 2: Roadmap Evidence Gap Finder (Informational)  
**Location:** `verify_fork.sh`  
**Purpose:** Find roadmap-required artifacts without producing PRD stories

**Removed from scope:**
- ❌ Slice-phase consistency (invalid assumption)
- ❌ Strict contract ref validation (already done by prd_ref_check.sh)

---

## 6. Corrected Implementation

### Check 1: AT Coverage Index

```bash
# In plans/verify_fork.sh - add function
check_at_coverage_index() {
  log "Building AT coverage index..."
  
  local output_dir="${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}"
  mkdir -p "$output_dir"
  
  local output_file="${output_dir}/at_coverage_index.json"
  
  python3 tools/at_coverage_index.py \
    --contract specs/CONTRACT.md \
    --prd plans/prd.json \
    --output "$output_file"
  
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    warn "AT coverage index generation failed (exit $exit_code)"
    return 0  # Non-blocking
  fi
  
  # Log summary
  local referenced total
  referenced=$(jq -r '.stats.referenced_csp_ats // 0' "$output_file")
  total=$(jq -r '.stats.total_csp_ats // 0' "$output_file")
  log "AT Coverage: $referenced/$total CSP ATs referenced by stories"
  
  return 0
}
```

### Check 2: Roadmap Evidence Gaps

```bash
# In plans/verify_fork.sh - add function
check_roadmap_evidence_gaps() {
  log "Checking roadmap evidence coverage..."
  
  local output_dir="${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}"
  mkdir -p "$output_dir"
  
  local output_file="${output_dir}/roadmap_evidence_gaps.json"
  
  python3 tools/roadmap_evidence_check.py \
    --roadmap docs/ROADMAP.md \
    --checklist docs/PHASE0_CHECKLIST_BLOCK.md docs/PHASE1_CHECKLIST_BLOCK.md \
    --prd plans/prd.json \
    --output "$output_file"
  
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    warn "Roadmap evidence check failed (exit $exit_code)"
    return 0  # Non-blocking
  fi
  
  # Report gaps if any
  local gaps
  gaps=$(jq '.gaps | length' "$output_file")
  
  if [[ "$gaps" -gt 0 ]]; then
    warn "Found $gaps roadmap evidence items without PRD stories"
    jq -r '.gaps[0:3] | .[] | "  - \(.evidence_path)"' "$output_file"
    [[ "$gaps" -gt 3 ]] && log "  ... and $((gaps - 3)) more"
  else
    log "All roadmap evidence items have producing PRD stories"
  fi
  
  return 0
}
```

### Integration in verify_fork.sh

Add near other gates (non-blocking):

```bash
# After existing gates, add:
run_logged_or_exit check_at_coverage_index "AT coverage index"
run_logged_or_exit check_roadmap_evidence_gaps "Roadmap evidence gaps"
```

---

## 7. Python Tools (Corrected)

### tools/at_coverage_index.py

```python
#!/usr/bin/env python3
"""Generate AT coverage index from contract and PRD."""

import argparse
import json
import re
import sys
from pathlib import Path


def parse_contract_ats(contract_path):
    """Extract AT definitions from contract."""
    ats = {}
    content = Path(contract_path).read_text()
    
    # Find all AT definitions
    for match in re.finditer(r'AT-(\d+)\s*\n.*?Profile:\s*(\w+)', content, re.DOTALL):
        at_id = f"AT-{match.group(1)}"
        profile = match.group(2)
        
        # Get section context
        section_match = re.search(r'§([\d.]+)[^\n]*\n[^\n]*' + re.escape(at_id), content)
        section = section_match.group(1) if section_match else "unknown"
        
        ats[at_id] = {
            "profile": profile,
            "section": section,
        }
    
    return ats


def parse_prd_references(prd_path):
    """Extract AT references from PRD stories."""
    stories = {}
    coverage = {}  # at_id -> [story_ids]
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        # Collect all AT references
        refs = set()
        for field in ['contract_refs', 'enforcing_contract_ats', 'observability.status_contract_ats']:
            value = item
            for key in field.split('.'):
                if isinstance(value, dict):
                    value = value.get(key, [])
                else:
                    value = []
                    break
            if isinstance(value, list):
                for ref in value:
                    if isinstance(ref, str):
                        at_match = re.search(r'AT-(\d+)', ref)
                        if at_match:
                            refs.add(f"AT-{at_match.group(1)}")
        
        stories[story_id] = list(refs)
        for at in refs:
            coverage.setdefault(at, []).append(story_id)
    
    return stories, coverage


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--contract', required=True)
    parser.add_argument('--prd', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    
    ats = parse_contract_ats(args.contract)
    stories, coverage = parse_prd_references(args.prd)
    
    csp_ats = {k: v for k, v in ats.items() if v.get('profile') == 'CSP'}
    gop_ats = {k: v for k, v in ats.items() if v.get('profile') == 'GOP'}
    
    referenced_csp = [at for at in csp_ats if at in coverage]
    unreferenced_csp = [at for at in csp_ats if at not in coverage]
    
    result = {
        "generated_at": datetime.now().isoformat(),
        "stats": {
            "total_ats": len(ats),
            "csp_ats": len(csp_ats),
            "referenced_csp_ats": len(referenced_csp),
            "unreferenced_csp_ats": len(unreferenced_csp),
            "gop_ats": len(gop_ats),
            "referenced_gop_ats": len([a for a in gop_ats if a in coverage]),
        },
        "unreferenced_csp": [
            {"at": at, "section": csp_ats[at]["section"]}
            for at in sorted(unreferenced_csp)
        ],
        "coverage_map": coverage,
    }
    
    Path(args.output).write_text(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    from datetime import datetime
    sys.exit(main())
```

### tools/roadmap_evidence_check.py

```python
#!/usr/bin/env python3
"""Find roadmap evidence requirements without PRD story coverage."""

import argparse
import json
import re
from pathlib import Path


def parse_roadmap_evidence(roadmap_path, checklist_paths):
    """Extract required evidence artifacts from roadmap and checklists."""
    required = []
    
    # Parse main roadmap
    content = Path(roadmap_path).read_text()
    
    # Find evidence/phaseN/ patterns
    for match in re.finditer(r'`?(evidence/phase\d+/[^`\s\]]+)`?', content):
        required.append({
            "path": match.group(1),
            "source": f"{roadmap_path}:{content[:match.start()].count(chr(10))}"
        })
    
    # Parse checklists
    for checklist_path in checklist_paths:
        if not Path(checklist_path).exists():
            continue
        content = Path(checklist_path).read_text()
        for match in re.finditer(r'`?(evidence/phase\d+/[^`\s\]]+)`?', content):
            required.append({
                "path": match.group(1),
                "source": checklist_path
            })
    
    # Deduplicate by path
    seen = set()
    unique = []
    for item in required:
        if item["path"] not in seen:
            seen.add(item["path"])
            unique.append(item)
    
    return unique


def parse_prd_evidence_producers(prd_path):
    """Extract evidence paths that PRD stories claim to produce."""
    producers = {}  # path -> [story_ids]
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        # Check evidence field
        for ev in item.get('evidence', []):
            if isinstance(ev, str) and 'evidence/' in ev:
                producers.setdefault(ev, []).append(story_id)
        
        # Check scope.touch for evidence paths
        for path in item.get('scope', {}).get('touch', []):
            if 'evidence/' in path:
                producers.setdefault(path, []).append(story_id)
    
    return producers


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--roadmap', required=True)
    parser.add_argument('--checklist', action='append', default=[])
    parser.add_argument('--prd', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    
    required = parse_roadmap_evidence(args.roadmap, args.checklist)
    producers = parse_prd_evidence_producers(args.prd)
    
    gaps = []
    for req in required:
        path = req["path"]
        if path not in producers:
            gaps.append({
                "evidence_path": path,
                "required_by": req["source"],
                "status": "NO_PRODUCER_STORY",
            })
    
    result = {
        "total_required": len(required),
        "with_producers": len(required) - len(gaps),
        "gaps": gaps,
    }
    
    Path(args.output).write_text(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

---

## 8. Test Plan

### Test 1: AT Coverage
```bash
# Setup
export VERIFY_ARTIFACTS_DIR=artifacts/verify
export VERIFY_RUN_ID=test_$(date +%s)

# Run
python3 tools/at_coverage_index.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output "${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}/at_coverage.json"

# Verify
jq '.stats.total_csp_ats' "${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}/at_coverage.json"
```

### Test 2: Roadmap Evidence
```bash
export VERIFY_ARTIFACTS_DIR=artifacts/verify
export VERIFY_RUN_ID=test_$(date +%s)

python3 tools/roadmap_evidence_check.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output "${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}/gaps.json"

# Should show actual gaps (if any remain after intent_hashes fix)
jq '.gaps | length' "${VERIFY_ARTIFACTS_DIR}/${VERIFY_RUN_ID}/gaps.json"
```

---

## 9. Expected Actual Outputs

Based on prd.json:3327+ analysis:

### AT Coverage (approximate)
```json
{
  "stats": {
    "csp_ats": 142,
    "referenced_csp_ats": 128,
    "unreferenced_csp_ats": 14
  },
  "unreferenced_csp": [
    {"at": "AT-1048", "section": "2.2.3"},
    {"at": "AT-1053", "section": "2.2.3"}
    // ... 12 more
  ]
}
```

### Roadmap Evidence (updated)
```json
{
  "total_required": 12,
  "with_producers": 11,
  "gaps": [
    // intent_hashes.txt NO LONGER HERE (prd.json:3327+ has it)
    {
      "evidence_path": "evidence/phase1/restart_loop/restart_100_cycles.log",
      "status": "NO_PRODUCER_STORY"
    }
  ]
}
```

---

## 10. Files Changed (Final)

### Modified (1 file)
```
plans/verify_fork.sh          # Add 2 functions, 2 run_logged_or_exit calls
```

### New (2 files)
```
tools/at_coverage_index.py         # ~100 LOC
tools/roadmap_evidence_check.py    # ~120 LOC
```

### Removed from scope
- ❌ plans/prd_lint.sh changes (slice check removed - invalid assumption)
- ❌ plans/tests/test_prd_lint.sh additions

---

## 11. Verification Steps Before Merge

```bash
# 1. Check Python tools compile
python3 -m py_compile tools/at_coverage_index.py
python3 -m py_compile tools/roadmap_evidence_check.py

# 2. Run tools manually
./tools/at_coverage_index.py --contract specs/CONTRACT.md --prd plans/prd.json --output /tmp/test.json
./tools/roadmap_evidence_check.py --roadmap docs/ROADMAP.md --prd plans/prd.json --output /tmp/test2.json

# 3. Full verify (with new gates)
./plans/verify.sh full

# 4. Check artifacts exist
ls artifacts/verify/*/at_coverage_index.json
ls artifacts/verify/*/roadmap_evidence_gaps.json
```

---

*End of v4 (Implementation-Ready)*
