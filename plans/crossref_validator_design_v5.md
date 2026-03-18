# Cross-Reference Validator Design v5
## Standalone Tools First (Integration Deferred)

**Version:** 5.0  
**Status:** Conservative - Build tools first, integrate later  
**Approach:** Standalone Python tools with minimal assumptions

---

## 1. Problem Acknowledgment

Designs v1-v4 repeatedly failed on implementation details:
- Wrong environment variable names
- Wrong helper function signatures  
- Wrong path handling (double-nesting RUN_ID)
- Wrong regex approaches
- Shell semantics (`set -e` interaction)

**Root cause:** Designing integration without full codebase context.

**v5 Solution:** Build standalone, testable tools first. Integration is a separate, smaller task done with full codebase access.

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
- Markdown table of coverage by phase
- JSON with stats and unreferenced ATs
- Exit 0 always (informational tool)

**Implementation notes:**
- Use explicit `AT-` prefix matching (not broad regex)
- Parse PRD `enforcing_contract_ats` and `contract_refs` fields
- Handle both string refs ("AT-001") and objects with AT fields
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
- Parse roadmap for `evidence/phase{N}/...` patterns
- Parse checklists similarly
- Parse PRD `evidence` and `scope.touch` for producing paths
- Simple string matching (endswith or contains)

**Success criteria:**
- Finds `restart_100_cycles.log` gap (no producer)
- Does NOT flag `intent_hashes.txt` (has producer: S2-001)
- Lists all Phase 1 required evidence

---

## 3. No Integration Design (Deferred)

**v5 explicitly does NOT specify:**
- Where to call these in verify_fork.sh
- Environment variable usage
- Shell helper integration
- Preflight vs verify placement

**Reason:** These require full codebase context I don't have.

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
| AT count | ~142 CSP ATs found |
| Coverage | ~128 referenced, ~14 unreferenced |
| Key unreferenced | AT-1048, AT-1053 (Axis Resolver) |
| Roadmap gaps | restart_100_cycles.log flagged |
| Not flagged | intent_hashes.txt (has producer) |

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
    
    Approach:
    1. Read file line by line
    2. Find lines with 'AT-###' pattern at start of section
    3. Look for 'Profile: CSP|GOP' in surrounding context
    4. Return dict: at_id -> {'profile': 'CSP|GOP', 'section': '...'}
    """
    ats = {}
    content = Path(contract_path).read_text()
    lines = content.split('\n')
    
    for i, line in enumerate(lines):
        # Match AT definition lines like "AT-123" or "AT-123 (description)"
        match = re.match(r'^AT-(\d+)\b', line)
        if match:
            at_id = f"AT-{match.group(1)}"
            
            # Look for Profile in next 10 lines
            context = '\n'.join(lines[i:i+10])
            profile_match = re.search(r'Profile:\s*(CSP|GOP)', context)
            profile = profile_match.group(1) if profile_match else 'UNKNOWN'
            
            # Get section from preceding heading
            section = 'unknown'
            for j in range(i-1, max(0, i-20), -1):
                if lines[j].startswith('##') or lines[j].startswith('**'):
                    section = lines[j].strip('#* ')
                    break
            
            ats[at_id] = {'profile': profile, 'section': section}
    
    return ats


def extract_prd_at_references(prd_path):
    """Extract AT references from PRD stories.
    
    Checks fields:
    - contract_refs (list of strings)
    - enforcing_contract_ats (list of strings)
    - observability.status_contract_ats (list of strings)
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
            if isinstance(ref, str):
                at_matches = re.findall(r'AT-(\d+)', ref)
                refs.update(f"AT-{m}" for m in at_matches)
        
        # Check enforcing_contract_ats
        for ref in item.get('enforcing_contract_ats', []):
            if isinstance(ref, str):
                at_matches = re.findall(r'AT-(\d+)', ref)
                refs.update(f"AT-{m}" for m in at_matches)
        
        # Check observability.status_contract_ats
        obs = item.get('observability', {})
        for ref in obs.get('status_contract_ats', []):
            if isinstance(ref, str):
                at_matches = re.findall(r'AT-(\d+)', ref)
                refs.update(f"AT-{m}" for m in at_matches)
        
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
        },
        'unreferenced_csp_ats': sorted(list(csp_unreferenced)),
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
    """Extract evidence paths from roadmap and checklists."""
    required = []
    
    for path in paths:
        if not Path(path).exists():
            continue
        content = Path(path).read_text()
        
        # Find evidence/phaseN/... patterns
        # Match backtick-wrapped or plain paths
        pattern = r'`?(evidence/phase[0-9]+/[^`\s\]]+)`?'
        for match in re.finditer(pattern, content):
            evidence_path = match.group(1)
            # Get line number
            line_num = content[:match.start()].count('\n') + 1
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
# [paste v5 spec above]
EOF
cat > tools/roadmap_evidence_audit.py << 'EOF'
# [paste v5 spec above]
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
| AT count correct | `grep -c "^AT-[0-9]" specs/CONTRACT.md` vs tool output |
| Coverage % reasonable | Tool shows ~90% for CSP |
| Finds real gaps | Tool flags `restart_100_cycles.log` |
| No false positives | Tool does NOT flag `intent_hashes.txt` |
| Standalone works | Tools run without any shell integration |

---

## 8. No More Design Iterations

**v5 is the final design document.**

If v5 tools have bugs when implemented, fix them in implementation phase. Don't redesign - just fix the regex/parsing logic.

Integration is intentionally underspecified because it requires runtime codebase inspection.

---

*End of v5 (Final Design - Build Tools First)*
