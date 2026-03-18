# Cross-Reference Validator Design v7
## Fixed: Actual AT Counts, Fuzzy Matching, Multi-Source Provenance, Multi-Match Lines

**Version:** 7.0  
**Status:** Corrected - Uses actual contract data, implements fuzzy matching  
**Approach:** Standalone Python tools with minimal assumptions

---

## 1. Problem Acknowledgment

Design v6 had issues identified in review:
- **HIGH:** Success criteria used outdated ~142 CSP count; actual contract has CSP=258, GOP=75 (finding #1)
- **HIGH:** Evidence matching claimed "endswith or contains" but used exact match; produced false gaps for existing files (finding #2)
- **MEDIUM:** Deduplication lost multi-source provenance (finding #3)
- **MEDIUM:** Single-match regex missed lines with multiple evidence paths (finding #4)

**v7 Solution:** Use actual contract counts, implement proper fuzzy matching, preserve all sources, use finditer.

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
- Handle both string refs and objects with AT fields (defensive)

**Success criteria (corrected):**
- CSP=258, GOP=75 (validated by `check_contract_profiles.py`)
- Coverage % calculated from actual totals
- No UNKNOWN profile ATs (inheritance working correctly)

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

**Implementation notes:**
- Parse roadmap/checklists for `evidence/phase{N}/...` patterns using **finditer** (all matches per line)
- **Fuzzy matching:** PRD producer path contains/matches required path (handles "with extra text" cases)
- **Multi-source provenance:** Keep all sources that require the same artifact
- Filter to "required" contexts only

**Success criteria:**
- Finds `restart_100_cycles.log` gap (truly has no producer)
- Does NOT flag files with producers (even if paths have extra text like "with 3+ cases")
- Lists all sources requiring each artifact

---

## 3. Tool Specifications (Python)

### at_coverage_report.py

```python
#!/usr/bin/env python3
"""Generate AT coverage report from Contract and PRD."""

import argparse
import json
import re
import subprocess
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


def normalize_evidence_path(path):
    """Normalize path for comparison (strip extra text, handle OR prefix)."""
    path = path.strip()
    # Handle "OR evidence/..." pattern
    if path.startswith('OR '):
        path = path[3:]
    # Take only up to first space or extra text
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
            
            # Use finditer to get ALL evidence paths on this line (finding #4 fix)
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
                
                # Add to list of sources for this path (finding #3 fix - multi-source)
                if normalized_path not in required:
                    required[normalized_path] = []
                if source not in required[normalized_path]:
                    required[normalized_path].append(source)
    
    # Convert to list format for return
    result = []
    for path, sources in required.items():
        result.append({
            'path': path,
            'sources': sources,  # ALL sources requiring this artifact
            'primary_source': sources[0]  # First source for convenience
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
        # Required: evidence/phase1/determinism/intent_hashes.txt
        # Producer: evidence/phase1/determinism/intent_hashes.txt showing identical hashes
        if required_path in prod_path or prod_path.endswith(required_path):
            return True, stories
        
        # Also check path components match (handle subdirs)
        req_parts = required_path.split('/')
        prod_parts = prod_path.split('/')
        if len(req_parts) <= len(prod_parts):
            if prod_parts[-len(req_parts):] == req_parts:
                return True, stories
    
    return False, []


def main():
    parser = argparse.ArgumentParser(description='Audit roadmap evidence coverage')
    parser.add_argument('--roadmap', required=True, help='Path to ROADMAP.md')
    parser.add_argument('--checklist', action='append', default=[],
                       help='Path to PHASE*_CHECKLIST_BLOCK.md (can specify multiple)')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output', help='Output JSON file')
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
            gaps.append({
                'path': path,
                'required_by': req['primary_source'],
                'all_sources': req['sources'],  # Multi-source provenance
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
        for gap in gaps[:10]:
            print(f"  - {gap['path']}")
            if len(gap.get('all_sources', [])) > 1:
                print(f"    (required by {len(gap['all_sources'])} sources)")
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

## 4. Implementation Steps

### Phase 1: Build & Test Tools

```bash
# Create tools
mkdir -p tools
cat > tools/at_coverage_report.py << 'EOF'
# [paste v7 spec above]
EOF
cat > tools/roadmap_evidence_audit.py << 'EOF'
# [paste v7 spec above]
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

# Verify gaps - should only show truly missing evidence
cat /tmp/gaps.json | jq '.gaps[] | .path'
```

---

## 5. Success Criteria (Corrected)

| Criterion | Expected | Validation |
|-----------|----------|------------|
| CSP count | 258 | Cross-validated with check_contract_profiles.py |
| GOP count | 75 | Cross-validated with check_contract_profiles.py |
| UNKNOWN profiles | 0 | All ATs inherit or have explicit profile |
| Coverage calculation | CSP referenced / 258 | Not total AT count |
| restart_100_cycles.log | FLAGGED | No producer in PRD |
| intent_hashes.txt | NOT flagged | Producer S6-001 (fuzzy match) |
| existing files | NOT flagged | Fuzzy matching handles extra text |
| Multi-source | Preserved | gaps[].all_sources contains all requiring sources |

---

## 6. Design Changes from v6

| Finding | Fix |
|---------|-----|
| #1 Wrong CSP totals | Use actual counts (CSP=258, GOP=75), cross-validate with check_contract_profiles.py |
| #2 Fuzzy matching | Implement `has_producer_fuzzy()` with contains/endswith logic |
| #3 Multi-source provenance | Keep `all_sources` list instead of deduping to single source |
| #4 Multi-match lines | Use `re.finditer` instead of `re.search` |

---

## 7. No More Design Iterations

**v7 is the final design document.**

If v7 tools have bugs when implemented, fix them in implementation phase. Don't redesign.

---

*End of v7 (Final Design - All Review Findings Addressed)*
