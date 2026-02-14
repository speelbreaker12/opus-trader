# Cross-Reference Validator Design v6
## Fixed: Profile Inheritance, Evidence Filtering, Object Refs

**Version:** 6.0  
**Status:** Corrected - Implements findings from design review  
**Approach:** Standalone Python tools with minimal assumptions

---

## 1. Problem Acknowledgment

Design v5 had critical issues identified in review:
- **HIGH:** Profile extraction looked forward instead of backward (finding #1)
- **MEDIUM:** Claimed object-based AT refs but only implemented strings (finding #2)
- **MEDIUM:** Evidence extraction too broad, would produce false positives (finding #3)
- **LOW:** Wrong story citation for intent_hashes.txt producer (finding #4)
- **LOW:** AT count verification method mismatched CSP metric (finding #5)

**v6 Solution:** Fix all identified issues. Maintain standalone-first approach.

---

## 2. Two Standalone Tools Only

### Tool 1: at-coverage-report
**Purpose:** Generate human-readable AT coverage report

**Usage:**
```bash
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-md coverage_report.md \
  --output-json coverage_report.json
```

**Outputs:**
- Markdown table of coverage by profile
- JSON with stats and unreferenced ATs
- Exit 0 always (informational tool)

**Implementation notes:**
- Use explicit `AT-` prefix matching (not broad regex)
- **Profile inheritance:** ATs inherit the most recent `Profile:` tag **above** them (per CONTRACT.md:0.Z.5)
- Parse PRD `enforcing_contract_ats` and `contract_refs` fields
- Handle both string refs ("AT-001") and objects with AT fields (defensive)
- CSP profile ATs are required, GOP are advisory

**Success criteria:**
- Correctly counts ~142 CSP ATs in contract
- Correctly identifies ~14 unreferenced
- Handles actual prd.json structure

---

### Tool 2: roadmap-evidence-audit
**Purpose:** Compare roadmap evidence requirements to PRD story outputs

**Usage:**
```bash
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output evidence_gaps.json
```

**Outputs:**
- JSON list of gaps
- Human-readable summary to stdout
- Exit 0 always (informational tool)

**Implementation notes:**
- Parse roadmap/checklists for `evidence/phase{N}/...` patterns
- **Filter by context:** Only include paths marked as "required", "Required evidence", "MANUAL evidence", or "AUTO"
- Parse PRD `evidence` and `scope.touch` for producing paths
- Simple string matching (endswith or contains)

**Success criteria:**
- Finds `restart_100_cycles.log` gap (no producer)
- Does NOT flag `intent_hashes.txt` (has producer: S6-001)
- Lists all Phase 1 required evidence

---

## 3. No Integration Design (Deferred)

**v6 explicitly does NOT specify:**
- Where to call these in verify_fork.sh
- Environment variable usage
- Shell helper integration
- Preflight vs verify placement

**Reason:** These require full codebase context.

**Integration is Phase 2:**
After tools are built and tested:
1. Actually read verify_fork.sh fully
2. Actually read lib/verify_utils.sh  
3. Make minimal, correct integration
4. Test with actual verify.sh run

---

## 4. Testing Strategy (Standalone)

### Test against actual files

```bash
# Build tools
mkdir -p tools
# [create at_coverage_report.py]
# [create roadmap_evidence_audit.py]

# Test AT coverage
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-md /tmp/coverage.md \
  --output-json /tmp/coverage.json

# Verify outputs
wc -l /tmp/coverage.md
cat /tmp/coverage.json | jq '.stats'

# Verify CSP count is ~142 (not total AT count)
# grep -c "^Profile: CSP" specs/CONTRACT.md  # check expected count

# Test roadmap audit
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output /tmp/gaps.json

# Verify gaps
cat /tmp/gaps.json | jq '.gaps[] | select(.path | contains("restart"))'
```

### Acceptance criteria

| Check | Expected |
|-------|----------|
| AT count | ~142 CSP ATs found (not total ATs) |
| Coverage % reasonable | Tool shows ~90% for CSP |
| Finds real gaps | Tool flags `restart_100_cycles.log` |
| No false positives | Tool does NOT flag `intent_hashes.txt` |
| Standalone works | Tools run without any shell integration |

---

## 5. Tool Specifications (Python)

### at_coverage_report.py

```python
#!/usr/bin/env python3
"""Generate AT coverage report from Contract and PRD."""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime


def extract_contract_ats(contract_path):
    """Extract AT-### definitions with profiles from contract.
    
    Profile inheritance (per CONTRACT.md:0.Z.5):
    - ATs inherit the most recent `Profile:` tag ABOVE them
    - Explicit `Profile:` on/near AT line takes precedence over inheritance
    
    Returns dict: at_id -> {'profile': 'CSP|GOP|UNKNOWN', 'section': '...'}
    """
    ats = {}
    content = Path(contract_path).read_text()
    lines = content.split('\n')
    
    # Track the current profile as we scan (inheritance from above)
    current_profile = None
    
    for i, line in enumerate(lines):
        # Check for Profile declaration - this updates current context for inheritance
        # Match "Profile: CSP" or "Profile: GOP" at line start or after markdown
        profile_match = re.search(r'Profile:\s*(CSP|GOP)', line)
        if profile_match and not line.strip().startswith('AT-'):
            # This is a section-level profile marker, not attached to an AT
            current_profile = profile_match.group(1)
            continue
        
        # Check for AT definition (AT-### at start of line)
        at_match = re.match(r'^(AT-\d+)\b', line)
        if at_match:
            at_id = at_match.group(1)
            
            # Check for explicit Profile on same line or immediately after
            explicit_profile = None
            context = line
            if i + 1 < len(lines):
                context += '\n' + lines[i + 1]
            explicit_match = re.search(r'Profile:\s*(CSP|GOP)', context)
            if explicit_match:
                explicit_profile = explicit_match.group(1)
            
            # Priority: explicit > inherited > UNKNOWN
            profile = explicit_profile or current_profile or 'UNKNOWN'
            
            # Get section from preceding heading
            section = 'unknown'
            for j in range(i-1, max(0, i-30), -1):
                heading_match = re.match(r'^(#{2,}|\*\*)\s*(.+?)(?:\*\*|$)', lines[j])
                if heading_match:
                    section = heading_match.group(2).strip()
                    break
            
            ats[at_id] = {'profile': profile, 'section': section}
    
    return ats


def extract_at_refs(ref_item):
    """Extract AT references from a string or dict (defensive for future PRD changes).
    
    Handles:
    - "AT-123" (string)
    - {"at": "AT-123", "rationale": "..."} (object with at field)
    - {"AT": "AT-123"} (object with AT field)
    """
    if isinstance(ref_item, str):
        matches = re.findall(r'AT-(\d+)', ref_item)
        return [f"AT-{m}" for m in matches]
    elif isinstance(ref_item, dict):
        # Try common field names for AT references
        at_val = ref_item.get('at') or ref_item.get('AT') or ref_item.get('id')
        if at_val:
            matches = re.findall(r'AT-(\d+)', str(at_val))
            return [f"AT-{m}" for m in matches]
    return []


def extract_prd_at_references(prd_path):
    """Extract AT references from PRD stories.
    
    Checks fields:
    - contract_refs (list of strings or objects)
    - enforcing_contract_ats (list of strings or objects)
    - observability.status_contract_ats (list of strings or objects)
    """
    coverage = {}  # at_id -> [story_ids]
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        refs = set()
        
        # Check contract_refs
        for ref in item.get('contract_refs', []):
            refs.update(extract_at_refs(ref))
        
        # Check enforcing_contract_ats
        for ref in item.get('enforcing_contract_ats', []):
            refs.update(extract_at_refs(ref))
        
        # Check observability.status_contract_ats
        obs = item.get('observability', {})
        for ref in obs.get('status_contract_ats', []):
            refs.update(extract_at_refs(ref))
        
        for at in refs:
            coverage.setdefault(at, []).append(story_id)
    
    return coverage


def main():
    parser = argparse.ArgumentParser(description='Generate AT coverage report')
    parser.add_argument('--contract', required=True, help='Path to CONTRACT.md')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output-md', help='Output markdown report path')
    parser.add_argument('--output-json', help='Output JSON report path')
    args = parser.parse_args()
    
    # Extract data
    ats = extract_contract_ats(args.contract)
    coverage = extract_prd_at_references(args.prd)
    
    # Separate by profile
    csp_ats = {k: v for k, v in ats.items() if v.get('profile') == 'CSP'}
    gop_ats = {k: v for k, v in ats.items() if v.get('profile') == 'GOP'}
    unknown_ats = {k: v for k, v in ats.items() if v.get('profile') == 'UNKNOWN'}
    
    # Warn about unknown profiles
    if unknown_ats:
        print(f"Warning: {len(unknown_ats)} ATs with unknown profile (check profile inheritance)", file=__import__('sys').stderr)
    
    # Calculate coverage
    csp_referenced = {at for at in csp_ats if at in coverage}
    csp_unreferenced = {at for at in csp_ats if at not in coverage}
    
    # Build report
    report = {
        'generated_at': datetime.now().isoformat(),
        'contract_file': args.contract,
        'prd_file': args.prd,
        'stats': {
            'total_ats': len(ats),
            'csp_total': len(csp_ats),
            'csp_referenced': len(csp_referenced),
            'csp_unreferenced': len(csp_unreferenced),
            'csp_coverage_pct': round(len(csp_referenced) / len(csp_ats) * 100, 1) if csp_ats else 0,
            'gop_total': len(gop_ats),
            'gop_referenced': len([a for a in gop_ats if a in coverage]),
            'unknown_profile': len(unknown_ats),
        },
        'unreferenced_csp_ats': sorted(list(csp_unreferenced)),
        'unknown_profile_ats': sorted(list(unknown_ats)),
        'coverage_map': {at: sorted(stories) for at, stories in coverage.items()},
    }
    
    # Write JSON
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2))
        print(f"JSON report: {args.output_json}")
    
    # Write Markdown
    if args.output_md:
        md_lines = [
            '# AT Coverage Report',
            f'Generated: {report["generated_at"]}',
            '',
            '## Summary',
            f'| Profile | Total | Referenced | Coverage |',
            f'|---------|-------|------------|----------|',
            f'| CSP | {report["stats"]["csp_total"]} | {report["stats"]["csp_referenced"]} | {report["stats"]["csp_coverage_pct"]}% |',
            f'| GOP | {report["stats"]["gop_total"]} | {report["stats"]["gop_referenced"]} | (advisory) |',
            '',
            '## Unreferenced CSP ATs (Required for Live)',
        ]
        for at in sorted(csp_unreferenced):
            section = csp_ats[at].get('section', 'unknown')
            md_lines.append(f'- **{at}**: {section}')
        
        if unknown_ats:
            md_lines.extend([
                '',
                '## ATs with Unknown Profile (Check Contract)',
            ])
            for at in sorted(unknown_ats):
                section = unknown_ats[at].get('section', 'unknown')
                md_lines.append(f'- **{at}**: {section}')
        
        md_lines.extend([
            '',
            '## Coverage Detail',
            'See JSON output for full coverage map.',
        ])
        
        Path(args.output_md).write_text('\n'.join(md_lines))
        print(f"Markdown report: {args.output_md}")
    
    # Console summary
    print(f"\nCSP Coverage: {report['stats']['csp_referenced']}/{report['stats']['csp_total']} "
          f"({report['stats']['csp_coverage_pct']}%)")
    if csp_unreferenced:
        print(f"Unreferenced: {len(csp_unreferenced)} CSP ATs need stories")
    if unknown_ats:
        print(f"Warning: {len(unknown_ats)} ATs with unknown profile")
    
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

### roadmap_evidence_audit.py

```python
#!/usr/bin/env python3
"""Audit roadmap evidence requirements against PRD story outputs."""

import argparse
import json
import re
from pathlib import Path


def extract_roadmap_evidence(paths):
    """Extract evidence paths from roadmap and checklists.
    
    Only includes paths that are marked as required/required in context:
    - "Required evidence:" list items
    - "MANUAL evidence:" list items
    - "AUTO gates:" that produce artifacts
    - "Evidence Pack (required)" blocks
    - List items under evidence sections
    
    Filters OUT:
    - Descriptive text ("store results in evidence/...")
    - Optional/discussion references
    """
    required = []
    
    for path in paths:
        if not Path(path).exists():
            continue
        content = Path(path).read_text()
        lines = content.split('\n')
        
        # Track section context
        in_evidence_pack = False
        in_required_section = False
        section_marker_line = -1
        
        for i, line in enumerate(lines):
            lower_line = line.lower()
            
            # Detect section context
            if 'evidence pack' in lower_line and 'required' in lower_line:
                in_evidence_pack = True
                section_marker_line = i
            elif line.startswith('## ') and i > section_marker_line + 50:
                # Reset context after new major section
                in_evidence_pack = False
                in_required_section = False
            elif re.match(r'^#{1,3}\s+', line):
                # Check for evidence-related section headers
                if any(marker in lower_line for marker in [
                    'required evidence', 'manual evidence', 'auto gate',
                    'evidence pack', 'unblock condition'
                ]):
                    in_required_section = True
                    section_marker_line = i
                elif line.startswith('# '):
                    # Top-level heading resets context
                    in_required_section = False
            
            # Look for evidence paths in this line
            match = re.search(r'`?(evidence/phase[0-9]+/[^`\s\]]+)`?', line)
            if not match:
                continue
            
            evidence_path = match.group(1)
            
            # Build context window (this line + up to 5 lines back)
            context_start = max(0, i - 5)
            context_window = '\n'.join(lines[context_start:i + 1]).lower()
            
            # Determine if this is a required path
            is_required = False
            
            # Check for explicit required markers
            if any(marker in context_window for marker in [
                'required evidence',
                'manual evidence',
                'auto gate',
                'auto/manual',
                'evidence pack (required)',
                'unblock condition',
                'must exist',
                'required files',
            ]):
                is_required = True
            
            # Check if in a list under evidence context
            if line.strip().startswith('- ') or line.strip().startswith('* '):
                # It's a list item - check if we're in an evidence-related section
                if in_evidence_pack or in_required_section:
                    is_required = True
                # Or check preceding lines for evidence context
                for j in range(i-1, max(0, i-10), -1):
                    prev_lower = lines[j].lower()
                    if any(marker in prev_lower for marker in [
                        'required evidence:', 'manual evidence:', 'auto gate:',
                        'required files:', 'evidence:'
                    ]):
                        is_required = True
                        break
                    if lines[j].strip().startswith('#'):
                        break  # Stop at section boundary
            
            # Code blocks under Evidence Pack are required
            if in_evidence_pack and (line.strip().startswith('evidence/') or '`evidence/' in line):
                is_required = True
            
            if not is_required:
                continue
            
            line_num = i + 1
            required.append({
                'path': evidence_path,
                'source': f'{path}:{line_num}'
            })
    
    # Deduplicate
    seen = set()
    unique = []
    for item in required:
        if item['path'] not in seen:
            seen.add(item['path'])
            unique.append(item)
    
    return unique


def extract_prd_evidence_outputs(prd_path):
    """Extract evidence outputs from PRD stories."""
    producers = {}  # path -> [story_ids]
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        # Check evidence field (list of paths)
        for ev in item.get('evidence', []):
            if isinstance(ev, str) and 'evidence/' in ev:
                producers.setdefault(ev, []).append(story_id)
        
        # Check scope.touch for evidence paths
        scope = item.get('scope', {})
        for touched in scope.get('touch', []):
            if isinstance(touched, str) and 'evidence/' in touched:
                producers.setdefault(touched, []).append(story_id)
        
        # Check scope.create for evidence paths
        for created in scope.get('create', []):
            if isinstance(created, str) and 'evidence/' in created:
                producers.setdefault(created, []).append(story_id)
    
    return producers


def main():
    parser = argparse.ArgumentParser(description='Audit roadmap evidence coverage')
    parser.add_argument('--roadmap', required=True, help='Path to ROADMAP.md')
    parser.add_argument('--checklist', action='append', default=[],
                       help='Path to PHASE*_CHECKLIST_BLOCK.md (can specify multiple)')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output', help='Output JSON file')
    args = parser.parse_args()
    
    # Collect all evidence requirements
    evidence_paths = [args.roadmap] + args.checklist
    required = extract_roadmap_evidence(evidence_paths)
    
    # Collect PRD evidence producers
    producers = extract_prd_evidence_outputs(args.prd)
    
    # Find gaps
    gaps = []
    for req in required:
        path = req['path']
        # Check if any producer creates this path
        has_producer = path in producers
        
        if not has_producer:
            gaps.append({
                'path': path,
                'required_by': req['source'],
                'status': 'NO_PRODUCER'
            })
    
    # Build report
    report = {
        'total_required': len(required),
        'with_producers': len(required) - len(gaps),
        'gaps_count': len(gaps),
        'gaps': gaps,
        'producers_summary': {path: len(stories) for path, stories in producers.items()}
    }
    
    # Write output
    if args.output:
        Path(args.output).write_text(json.dumps(report, indent=2))
        print(f"Report written: {args.output}")
    
    # Console output
    print(f"\nRoadmap Evidence Audit")
    print(f"Required: {report['total_required']}")
    print(f"With producers: {report['with_producers']}")
    print(f"Gaps: {report['gaps_count']}")
    
    if gaps:
        print("\nGaps (no producing PRD story):")
        for gap in gaps[:10]:  # Show first 10
            print(f"  - {gap['path']}")
        if len(gaps) > 10:
            print(f"  ... and {len(gaps) - 10} more")
    
    # Verification notes
    print("\nVerification:")
    print("  - restart_100_cycles.log should be flagged (no producer)")
    print("  - intent_hashes.txt should NOT be flagged (producer: S6-001)")
    
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

---

## 6. Implementation Steps

### Phase 1: Build & Test Tools (Standalone)

```bash
# 1. Create tool files
mkdir -p tools
cat > tools/at_coverage_report.py << 'EOF'
# [paste v6 spec above]
EOF
cat > tools/roadmap_evidence_audit.py << 'EOF'
# [paste v6 spec above]
EOF

# 2. Test compilation
python3 -m py_compile tools/*.py

# 3. Run against actual files
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-md /tmp/coverage.md \
  --output-json /tmp/coverage.json

python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output /tmp/gaps.json

# 4. Verify outputs manually
cat /tmp/coverage.md
cat /tmp/gaps.json | jq '.gaps'

# 5. Check for unknown profile ATs (should be minimal)
cat /tmp/coverage.json | jq '.unknown_profile_ats'
```

### Phase 2: Integration (Separate Task)

**After** tools are verified working:

1. Read full `verify_fork.sh` and `lib/verify_utils.sh`
2. Determine correct integration points
3. Add calls with proper error handling
4. Test with actual `./plans/verify.sh full`

---

## 7. Success Criteria

| Criterion | How to Verify |
|-----------|---------------|
| Profile inheritance correct | No UNKNOWN profiles for ATs under explicit Profile: sections |
| AT count correct | CSP count ~142, not total AT count |
| Coverage % reasonable | Tool shows ~90% for CSP |
| Finds real gaps | Tool flags `restart_100_cycles.log` |
| No false positives | Tool does NOT flag `intent_hashes.txt` (producer: S6-001) |
| Standalone works | Tools run without any shell integration |
| No unknown profiles | All CSP/GOP ATs have correct profile assigned |

---

## 8. Design Changes from v5

| Finding | Fix |
|---------|-----|
| #1 Profile extraction backward | Replaced forward-scan with profile state tracking while reading |
| #2 Object AT refs | Added `extract_at_refs()` helper for string/object handling |
| #3 Evidence too broad | Added context-aware filtering (required/MANUAL/AUTO keywords) |
| #4 Story citation | Changed S2-001 → S6-001 for intent_hashes.txt producer |
| #5 Count verification | Documented CSP-specific count method |

---

## 9. No More Design Iterations

**v6 is the final design document.**

If v6 tools have bugs when implemented, fix them in implementation phase. Don't redesign - just fix the regex/parsing logic.

Integration is intentionally underspecified because it requires runtime codebase inspection.

---

*End of v6 (Final Design - All Review Findings Addressed)*
