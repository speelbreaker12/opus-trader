# Cross-Reference Validator Design v8
## Fixed: Invariant-Based Acceptance, Import Bug, Gap Policy

**Version:** 8.0  
**Status:** Corrected - Uses invariant-based acceptance criteria  
**Approach:** Standalone Python tools with minimal assumptions

---

## 1. Problem Acknowledgment

Design v7 had issues identified in review:
- **HIGH:** Success criteria asserted "only restart_100_cycles.log gap" but actual docs/PRD yield 5 gaps (finding P1)
- **MEDIUM:** `sys.stderr` used but `sys` imported only in `__main__` block (finding P2)

**v8 Solution:** 
- Use **invariant-based acceptance** (specific required gaps must be present, specific covered items must NOT be gaps)
- Fix import placement
- Document policy for manual vs story-owned evidence

---

## 2. Evidence Gap Policy

Not all evidence gaps are errors. Gaps fall into categories:

| Category | Description | Example | Action |
|----------|-------------|---------|--------|
| **Story-owned AUTO** | Produced by PRD story test | `intent_hashes.txt` | Must have producer |
| **Story-owned MANUAL** | Touched by PRD story scope | `rejection_cases.md` | Must have producer |
| **Global manual** | Checklist-required, not story-owned | `README.md`, `ci_links.md` | Expected gap (no producer) |
| **Missing story** | Required but no producer assigned | `restart_100_cycles.log` | Flag as gap |

The tool reports all gaps; interpretation depends on policy context.

---

## 3. Two Standalone Tools Only

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

**Success criteria (invariant-based):**
- CSP count matches `check_contract_profiles.py` output (currently CSP=258, GOP=75)
- No UNKNOWN profile ATs (inheritance working correctly)
- Coverage % calculated from actual CSP total

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
- JSON list of gaps with all sources
- Human-readable summary to stdout
- Exit 0 always (informational tool)

**Success criteria (invariant-based):**
| Invariant | Expected |
|-----------|----------|
| `restart_100_cycles.log` in gaps | YES (no producer currently assigned) |
| `intent_hashes.txt` NOT in gaps | YES (producer: S6-001) |
| Global manual files in gaps | Expected (README.md, ci_links.md have no producers by design) |
| Total gaps count | Informational only (depends on manual vs story-owned policy) |

---

## 4. Tool Specifications (Python)

### at_coverage_report.py

```python
#!/usr/bin/env python3
"""Generate AT coverage report from Contract and PRD."""

import argparse
import json
import re
import subprocess
import sys  # Import at module level for validate_with_check_contract_profiles
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
    
    current_profile = None
    
    for i, line in enumerate(lines):
        # Check for Profile declaration - updates current context for inheritance
        profile_match = re.search(r'Profile:\s*(CSP|GOP)', line)
        if profile_match and not line.strip().startswith('AT-'):
            current_profile = profile_match.group(1)
            continue
        
        # Check for AT definition
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
    """Extract AT references from a string or dict."""
    if isinstance(ref_item, str):
        matches = re.findall(r'AT-(\d+)', ref_item)
        return [f"AT-{m}" for m in matches]
    elif isinstance(ref_item, dict):
        at_val = ref_item.get('at') or ref_item.get('AT') or ref_item.get('id')
        if at_val:
            matches = re.findall(r'AT-(\d+)', str(at_val))
            return [f"AT-{m}" for m in matches]
    return []


def extract_prd_at_references(prd_path):
    """Extract AT references from PRD stories."""
    coverage = {}
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        refs = set()
        
        for ref in item.get('contract_refs', []):
            refs.update(extract_at_refs(ref))
        
        for ref in item.get('enforcing_contract_ats', []):
            refs.update(extract_at_refs(ref))
        
        obs = item.get('observability', {})
        for ref in obs.get('status_contract_ats', []):
            refs.update(extract_at_refs(ref))
        
        for at in refs:
            coverage.setdefault(at, []).append(story_id)
    
    return coverage


def validate_with_check_contract_profiles(contract_path, stats):
    """Cross-validate counts with check_contract_profiles.py if available."""
    try:
        result = subprocess.run(
            ['python3', 'tools/ci/check_contract_profiles.py', '--contract', contract_path],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and 'CSP=' in result.stdout:
            # Parse output like "OK: 333 AT definitions tagged (CSP=258, GOP=75)."
            match = re.search(r'CSP=(\d+).*GOP=(\d+)', result.stdout)
            if match:
                expected_csp = int(match.group(1))
                expected_gop = int(match.group(2))
                if stats['csp_total'] != expected_csp or stats['gop_total'] != expected_gop:
                    print(f"Warning: Count mismatch with check_contract_profiles.py", file=sys.stderr)
                    print(f"  Expected: CSP={expected_csp}, GOP={expected_gop}", file=sys.stderr)
                    print(f"  Got: CSP={stats['csp_total']}, GOP={stats['gop_total']}", file=sys.stderr)
                else:
                    print(f"Validated: CSP={expected_csp}, GOP={expected_gop}")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass  # Validation tool not available


def main():
    parser = argparse.ArgumentParser(description='Generate AT coverage report')
    parser.add_argument('--contract', required=True, help='Path to CONTRACT.md')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output-md', help='Output markdown report path')
    parser.add_argument('--output-json', help='Output JSON report path')
    args = parser.parse_args()
    
    ats = extract_contract_ats(args.contract)
    coverage = extract_prd_at_references(args.prd)
    
    csp_ats = {k: v for k, v in ats.items() if v.get('profile') == 'CSP'}
    gop_ats = {k: v for k, v in ats.items() if v.get('profile') == 'GOP'}
    unknown_ats = {k: v for k, v in ats.items() if v.get('profile') == 'UNKNOWN'}
    
    csp_referenced = {at for at in csp_ats if at in coverage}
    csp_unreferenced = {at for at in csp_ats if at not in coverage}
    
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
    
    # Cross-validate with check_contract_profiles.py
    validate_with_check_contract_profiles(args.contract, report['stats'])
    
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2))
        print(f"JSON report: {args.output_json}")
    
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
    
    print(f"\nCSP Coverage: {report['stats']['csp_referenced']}/{report['stats']['csp_total']} "
          f"({report['stats']['csp_coverage_pct']}%)")
    if csp_unreferenced:
        print(f"Unreferenced: {len(csp_unreferenced)} CSP ATs need stories")
    if unknown_ats:
        print(f"Warning: {len(unknown_ats)} ATs with unknown profile")
    
    return 0


if __name__ == '__main__':
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


def normalize_evidence_path(path):
    """Normalize path for comparison (strip extra text, handle OR prefix)."""
    path = path.strip()
    # Handle "OR evidence/..." pattern
    if path.startswith('OR '):
        path = path[3:]
    # Match evidence/phaseN/... pattern and extract just the path
    match = re.match(r'(evidence/phase[0-9]+/[^\s]+)', path)
    if match:
        return match.group(1)
    return path


def extract_roadmap_evidence(paths):
    """Extract evidence paths from roadmap and checklists.
    
    Uses finditer to catch multiple paths per line.
    Preserves ALL sources for each path (multi-source provenance).
    """
    # Use dict to collect all sources for each path
    required = {}  # path -> [source1, source2, ...]
    
    for path in paths:
        if not Path(path).exists():
            continue
        content = Path(path).read_text()
        lines = content.split('\n')
        
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
                in_evidence_pack = False
                in_required_section = False
            elif re.match(r'^#{1,3}\s+', line):
                if any(marker in lower_line for marker in [
                    'required evidence', 'manual evidence', 'auto gate',
                    'evidence pack', 'unblock condition'
                ]):
                    in_required_section = True
                    section_marker_line = i
                elif line.startswith('# '):
                    in_required_section = False
            
            # Use finditer to get ALL evidence paths on this line
            for match in re.finditer(r'`?(evidence/phase[0-9]+/[^`\s\]]+)`?', line):
                evidence_path = match.group(1)
                
                # Normalize the extracted path
                normalized_path = normalize_evidence_path(evidence_path)
                
                # Check context
                context_start = max(0, i - 5)
                context_window = '\n'.join(lines[context_start:i + 1]).lower()
                
                is_required = False
                
                if any(marker in context_window for marker in [
                    'required evidence', 'manual evidence', 'auto gate',
                    'auto/manual', 'evidence pack (required)',
                    'unblock condition', 'must exist', 'required files',
                ]):
                    is_required = True
                
                if line.strip().startswith('- ') or line.strip().startswith('* '):
                    if in_evidence_pack or in_required_section:
                        is_required = True
                    for j in range(i-1, max(0, i-10), -1):
                        prev_lower = lines[j].lower()
                        if any(marker in prev_lower for marker in [
                            'required evidence:', 'manual evidence:', 'auto gate:',
                            'required files:', 'evidence:'
                        ]):
                            is_required = True
                            break
                        if lines[j].strip().startswith('#'):
                            break
                
                if in_evidence_pack and ('evidence/' in line or '`evidence/' in line):
                    is_required = True
                
                if not is_required:
                    continue
                
                line_num = i + 1
                source = f'{path}:{line_num}'
                
                # Add to list of sources for this path
                if normalized_path not in required:
                    required[normalized_path] = []
                if source not in required[normalized_path]:
                    required[normalized_path].append(source)
    
    # Convert to list format for return
    result = []
    for path, sources in required.items():
        result.append({
            'path': path,
            'sources': sources,
            'primary_source': sources[0]
        })
    
    return result


def extract_prd_evidence_outputs(prd_path):
    """Extract evidence outputs from PRD stories."""
    producers = {}  # normalized_path -> [story_ids]
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        paths_to_add = []
        
        # Check evidence field
        for ev in item.get('evidence', []):
            if isinstance(ev, str) and 'evidence/' in ev:
                paths_to_add.append(ev)
        
        # Check scope
        scope = item.get('scope', {})
        for t in scope.get('touch', []):
            if isinstance(t, str) and 'evidence/' in t:
                paths_to_add.append(t)
        for c in scope.get('create', []):
            if isinstance(c, str) and 'evidence/' in c:
                paths_to_add.append(c)
        
        # Normalize and add
        for path in paths_to_add:
            normalized = normalize_evidence_path(path)
            producers.setdefault(normalized, []).append(story_id)
    
    return producers


def has_producer_fuzzy(required_path, producers):
    """Check if required path has a producer using fuzzy matching.
    
    Handles:
    - Exact match
    - Required path is suffix of producer path
    - Producer path contains required path
    """
    # Exact match
    if required_path in producers:
        return True, producers[required_path]
    
    # Check if any producer path contains or ends with required path
    for prod_path, stories in producers.items():
        if required_path in prod_path or prod_path.endswith(required_path):
            return True, stories
        
        # Also check path components match (handle subdirs)
        req_parts = required_path.split('/')
        prod_parts = prod_path.split('/')
        if len(req_parts) <= len(prod_parts):
            if prod_parts[-len(req_parts):] == req_parts:
                return True, stories
    
    return False, []


def categorize_gap(path):
    """Categorize a gap by expected policy."""
    # Global manual files (not story-owned by design)
    global_manual = ['README.md', 'ci_links.md']
    if any(path.endswith(f) for f in global_manual):
        return 'GLOBAL_MANUAL'
    
    # Story-owned files that should have producers
    story_owned_patterns = [
        'restart_100_cycles.log',
        'intent_hashes.txt',
        'rejection_cases.md',
        'sample_rejection_log.txt',
        'missing_keys_matrix.json',
        'drill.md',
        'key_scope_probe.json',
        'health_endpoint_snapshot.md',
        'launch_policy_snapshot.md',
        'policy_config_snapshot.json',
        'env_matrix_snapshot.md',
        'runbook_snapshot.md',
        'log_excerpt.txt',
    ]
    
    for pattern in story_owned_patterns:
        if pattern in path:
            return 'STORY_OWNED'
    
    return 'UNKNOWN'


def main():
    parser = argparse.ArgumentParser(description='Audit roadmap evidence coverage')
    parser.add_argument('--roadmap', required=True, help='Path to ROADMAP.md')
    parser.add_argument('--checklist', action='append', default=[],
                       help='Path to PHASE*_CHECKLIST_BLOCK.md (can specify multiple)')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output', help='Output JSON file')
    parser.add_argument('--strict', action='store_true',
                       help='Only flag STORY_OWNED gaps (ignore GLOBAL_MANUAL)')
    args = parser.parse_args()
    
    # Collect requirements
    evidence_paths = [args.roadmap] + args.checklist
    required = extract_roadmap_evidence(evidence_paths)
    
    # Collect producers
    producers = extract_prd_evidence_outputs(args.prd)
    
    # Find gaps using fuzzy matching
    gaps = []
    for req in required:
        path = req['path']
        has_prod, prod_stories = has_producer_fuzzy(path, producers)
        
        if not has_prod:
            category = categorize_gap(path)
            # Skip global manual if strict mode
            if args.strict and category == 'GLOBAL_MANUAL':
                continue
            
            gaps.append({
                'path': path,
                'category': category,
                'required_by': req['primary_source'],
                'all_sources': req['sources'],
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
        story_owned_gaps = [g for g in gaps if g['category'] == 'STORY_OWNED']
        global_manual_gaps = [g for g in gaps if g['category'] == 'GLOBAL_MANUAL']
        
        if story_owned_gaps:
            print("\n  STORY_OWNED (should have producers):")
            for gap in story_owned_gaps[:10]:
                print(f"    - {gap['path']}")
        
        if global_manual_gaps and not args.strict:
            print("\n  GLOBAL_MANUAL (expected - no story producer by design):")
            for gap in global_manual_gaps[:5]:
                print(f"    - {gap['path']}")
    
    # Invariant verification
    print("\nInvariant Verification:")
    gap_paths = {g['path'] for g in gaps}
    
    # Required invariants
    if 'evidence/phase1/restart_loop/restart_100_cycles.log' in gap_paths:
        print("  ✓ restart_100_cycles.log correctly flagged (no producer)")
    else:
        print("  ✗ restart_100_cycles.log NOT flagged (unexpected - should have no producer)")
    
    if 'evidence/phase1/determinism/intent_hashes.txt' in gap_paths:
        print("  ✗ intent_hashes.txt flagged as gap (unexpected - has producer S6-001)")
    else:
        print("  ✓ intent_hashes.txt correctly NOT flagged (has producer)")
    
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

---

## 5. Implementation Steps

### Phase 1: Build & Test Tools

```bash
# Create tools
mkdir -p tools
cat > tools/at_coverage_report.py << 'EOF'
# [paste v8 spec above]
EOF
cat > tools/roadmap_evidence_audit.py << 'EOF'
# [paste v8 spec above]
EOF

# Test compilation
python3 -m py_compile tools/*.py

# Test AT coverage
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-md /tmp/coverage.md \
  --output-json /tmp/coverage.json

# Verify: CSP should be 258, GOP should be 75
cat /tmp/coverage.json | jq '.stats'

# Test roadmap audit
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output /tmp/gaps.json

# Check invariants
cat /tmp/gaps.json | jq '.gaps[] | select(.path | contains("restart_100_cycles")) | .path'
cat /tmp/gaps.json | jq '.gaps[] | select(.path | contains("intent_hashes")) | .path'  # Should be empty

# Test strict mode (only story-owned gaps)
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --strict
```

---

## 6. Success Criteria (Invariant-Based)

### AT Coverage Tool

| Invariant | Check |
|-----------|-------|
| CSP count | Matches check_contract_profiles.py (258) |
| GOP count | Matches check_contract_profiles.py (75) |
| No UNKNOWN profiles | All ATs have CSP or GOP assignment |
| Cross-validation passes | Tool counts match check_contract_profiles.py |

### Roadmap Evidence Audit Tool

| Invariant | Expected |
|-----------|----------|
| restart_100_cycles.log in gaps | YES |
| intent_hashes.txt NOT in gaps | YES |
| Coverage tools compile | No NameError on sys.stderr |

Note: Total gap count is informational only and depends on manual vs story-owned policy decisions.

---

## 7. Design Changes from v7

| Finding | Fix |
|---------|-----|
| P1 Over-constrained acceptance | Changed from "only 1 gap" to **invariant-based** criteria |
| P1 False failure risk | Added gap categorization (GLOBAL_MANUAL vs STORY_OWNED) |
| P2 Import bug | Moved `import sys` to module level (line 13) |
| - | Added `--strict` flag to filter global manual gaps |

---

## 8. No More Design Iterations

**v8 is the final design document.**

If v8 tools have bugs when implemented, fix them in implementation phase. Don't redesign.

---

*End of v8 (Final Design - Invariant-Based Acceptance)*
