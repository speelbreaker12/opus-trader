# Cross-Reference Validator Design v10
## Canonical Semantics: Fail-Closed FULL, Duplicate Counting

**Version:** 10.0  
**Status:** Canonical-aligned - Matches check_contract_profiles.py exactly  
**Approach:** Standalone Python tools with canonical semantics

---

## 1. Problem Acknowledgment

Design v9 had issues identified in review:
- **MEDIUM:** Profile: FULL handling differed from canonical (v9=UNKNOWN, canonical=error)
- **MEDIUM:** Duplicate AT counting differed (v9=deduplicated dict, canonical=count each occurrence)

**v10 Solution:** 
- Implement **exact canonical semantics** for FULL handling (error, not UNKNOWN)
- Implement **exact canonical counting** (each AT line occurrence counted)
- Document canonical divergence if intentional differences remain

---

## 2. Canonical Semantics Reference

Aligned exactly with `tools/ci/check_contract_profiles.py`:

| Behavior | Canonical | v10 |
|----------|-----------|-----|
| Profile regex | `^Profile:\s+(CSP\|GOP\|FULL)\s*$` | Same |
| AT regex | `^\s*(AT-\d+)\s*$` | Same |
| FULL for inheritance | Error (fail-closed) | Error (fail-closed) |
| Duplicate AT IDs | Count each occurrence | Count each occurrence |
| Profile conflict | Error | Error |

---

## 3. Two Standalone Tools Only

### Tool 1: at-coverage-report
**Purpose:** Generate AT coverage report from Contract and PRD

**Usage:**
```bash
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-md coverage_report.md \
  --output-json coverage_report.json
```

**Success criteria:**
- CSP=258, GOP=75 (matches canonical validator exactly)
- No UNKNOWN profile ATs (contract is clean)
- No FULL inheritance errors (contract is clean)

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

**Success criteria:**
- `restart_100_cycles.log` flagged (no producer)
- `intent_hashes.txt` NOT flagged (producer: S6-001)
- `with_producers` accurate (actual producer count)

---

## 4. Tool Specifications (Python)

### at_coverage_report.py

```python
#!/usr/bin/env python3
"""Generate AT coverage report from Contract and PRD.

Canonical semantics aligned with tools/ci/check_contract_profiles.py:
- Profile regex: ^Profile:\s+(CSP|GOP|FULL)\s*$
- AT regex: ^\s*(AT-\d+)\s*$
- FULL profile: Error (not allowed for AT inheritance)
- Duplicate ATs: Count each occurrence
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime

# Canonical regex patterns (exact match to check_contract_profiles.py)
PROFILE_RE = re.compile(r"^Profile:\s+(CSP|GOP|FULL)\s*$")
AT_RE = re.compile(r"^\s*(AT-\d+)\s*$")


def extract_contract_ats(contract_path):
    """Extract AT-### definitions with profiles from contract.
    
    Canonical semantics (exact match to check_contract_profiles.py):
    1. Anchored regex for Profile lines (^Profile:...$)
    2. Anchored regex for AT lines (^\s*AT-...$)
    3. Profile: FULL -> error (not allowed for AT inheritance)
    4. Each AT line occurrence counted (duplicates not collapsed)
    5. Profile conflict -> error
    
    Returns: (ats_list, errors)
        ats_list: list of {'id': 'AT-###', 'profile': 'CSP|GOP', 'section': '...'}
        errors: list of error strings
    """
    content = Path(contract_path).read_text()
    lines = content.split('\n')
    
    ats_list = []
    errors = []
    current_profile = None
    current_section = 'unknown'
    at_profiles = {}  # Track profile for each AT ID (for conflict detection)
    
    for i, line in enumerate(lines, start=1):
        # Check for Profile declaration (anchored)
        profile_match = PROFILE_RE.match(line)
        if profile_match:
            profile = profile_match.group(1)
            if profile == 'FULL':
                errors.append(f"{contract_path}:{i}: Profile: FULL is not allowed for AT inheritance")
                continue
            current_profile = profile
            continue
        
        # Update section from headings
        heading_match = re.match(r'^(#{2,}|\*\*)\s*(.+?)(?:\*\*|$)', line)
        if heading_match:
            current_section = heading_match.group(2).strip()
            continue
        
        # Check for AT definition (anchored with optional whitespace)
        at_match = AT_RE.match(line)
        if at_match:
            at_id = at_match.group(1)            
            if current_profile is None:
                errors.append(f"{contract_path}:{i}: {at_id} has no Profile tag in scope")
                continue
            
            # Check for profile conflict (same AT ID with different profiles)
            existing_profile = at_profiles.get(at_id)
            if existing_profile and existing_profile != current_profile:
                errors.append(f"{contract_path}:{i}: {at_id} profile conflict ({existing_profile} vs {current_profile})")
            
            # Track this AT occurrence (canonical: count each occurrence, don't dedupe)
            at_profiles[at_id] = current_profile
            ats_list.append({
                'id': at_id,
                'profile': current_profile,
                'section': current_section
            })
    
    return ats_list, errors


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
            match = re.search(r'CSP=(\d+).*GOP=(\d+)', result.stdout)
            if match:
                expected_csp = int(match.group(1))
                expected_gop = int(match.group(2))
                if stats['csp_total'] != expected_csp or stats['gop_total'] != expected_gop:
                    print(f"Warning: Count mismatch with check_contract_profiles.py", file=sys.stderr)
                    print(f"  Expected: CSP={expected_csp}, GOP={expected_gop}", file=sys.stderr)
                    print(f"  Got: CSP={stats['csp_total']}, GOP={stats['gop_total']}", file=sys.stderr)
                else:
                    print(f"Canonical validation passed: CSP={expected_csp}, GOP={expected_gop}")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass


def main():
    parser = argparse.ArgumentParser(description='Generate AT coverage report')
    parser.add_argument('--contract', required=True, help='Path to CONTRACT.md')
    parser.add_argument('--prd', required=True, help='Path to prd.json')
    parser.add_argument('--output-md', help='Output markdown report path')
    parser.add_argument('--output-json', help='Output JSON report path')
    args = parser.parse_args()
    
    ats_list, errors = extract_contract_ats(args.contract)
    
    # Report errors (canonical semantics validation)
    if errors:
        print("Contract validation errors:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1
    
    coverage = extract_prd_at_references(args.prd)
    
    # Build profile-based stats (count each AT occurrence)
    csp_ats = [at for at in ats_list if at['profile'] == 'CSP']
    gop_ats = [at for at in ats_list if at['profile'] == 'GOP']
    
    # For coverage analysis, dedupe by AT ID (one reference covers all occurrences)
    csp_ids = {at['id'] for at in csp_ats}
    gop_ids = {at['id'] for at in gop_ats}
    
    csp_referenced = {at_id for at_id in csp_ids if at_id in coverage}
    csp_unreferenced = csp_ids - csp_referenced
    
    report = {
        'generated_at': datetime.now().isoformat(),
        'contract_file': args.contract,
        'prd_file': args.prd,
        'stats': {
            'total_ats': len(ats_list),  # Count each occurrence (canonical)
            'csp_total': len(csp_ats),   # Count CSP occurrences
            'csp_unique': len(csp_ids),  # Unique CSP AT IDs
            'csp_referenced': len(csp_referenced),
            'csp_unreferenced': len(csp_unreferenced),
            'csp_coverage_pct': round(len(csp_referenced) / len(csp_ids) * 100, 1) if csp_ids else 0,
            'gop_total': len(gop_ats),
            'gop_unique': len(gop_ids),
            'gop_referenced': len([at_id for at_id in gop_ids if at_id in coverage]),
        },
        'unreferenced_csp_ats': sorted(list(csp_unreferenced)),
        'coverage_map': {at_id: sorted(stories) for at_id, stories in coverage.items()},
    }
    
    validate_with_check_contract_profiles(args.contract, {
        'csp_total': len(csp_ats),
        'gop_total': len(gop_ats)
    })
    
    if args.output_json:
        Path(args.output_json).write_text(json.dumps(report, indent=2))
        print(f"JSON report: {args.output_json}")
    
    if args.output_md:
        md_lines = [
            '# AT Coverage Report',
            f'Generated: {report["generated_at"]}',
            '',
            '## Summary',
            f'| Profile | Total Occurrences | Unique | Referenced | Coverage |',
            f'|---------|------------------|--------|------------|----------|',
            f'| CSP | {report["stats"]["csp_total"]} | {report["stats"]["csp_unique"]} | {report["stats"]["csp_referenced"]} | {report["stats"]["csp_coverage_pct"]}% |',
            f'| GOP | {report["stats"]["gop_total"]} | {report["stats"]["gop_unique"]} | {report["stats"]["gop_referenced"]} | (advisory) |',
            '',
            '## Unreferenced CSP ATs (Required for Live)',
        ]
        for at_id in sorted(csp_unreferenced):
            # Find section from first occurrence
            section = next((at['section'] for at in csp_ats if at['id'] == at_id), 'unknown')
            md_lines.append(f'- **{at_id}**: {section}')        
        md_lines.extend([
            '',
            '## Coverage Detail',
            'See JSON output for full coverage map.',
        ])
        
        Path(args.output_md).write_text('\n'.join(md_lines))
        print(f"Markdown report: {args.output_md}")
    
    print(f"\nCSP Coverage: {report['stats']['csp_referenced']}/{report['stats']['csp_unique']} "
          f"({report['stats']['csp_coverage_pct']}%)")
    if csp_unreferenced:
        print(f"Unreferenced: {len(csp_unreferenced)} CSP ATs need stories")
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
    if path.startswith('OR '):
        path = path[3:]
    match = re.match(r'(evidence/phase[0-9]+/[^\s]+)', path)
    if match:
        return match.group(1)
    return path


def extract_roadmap_evidence(paths):
    """Extract evidence paths from roadmap and checklists.
    
    Uses finditer to catch multiple paths per line.
    Preserves ALL sources for each path (multi-source provenance).
    """
    required = {}
    
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
            
            for match in re.finditer(r'`?(evidence/phase[0-9]+/[^`\s\]]+)`?', line):
                evidence_path = match.group(1)
                normalized_path = normalize_evidence_path(evidence_path)
                
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
                
                if normalized_path not in required:
                    required[normalized_path] = []
                if source not in required[normalized_path]:
                    required[normalized_path].append(source)
    
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
    producers = {}
    
    with open(prd_path) as f:
        prd = json.load(f)
    
    for item in prd.get('items', []):
        story_id = item.get('id')
        if not story_id:
            continue
        
        paths_to_add = []
        
        for ev in item.get('evidence', []):
            if isinstance(ev, str) and 'evidence/' in ev:
                paths_to_add.append(ev)
        
        scope = item.get('scope', {})
        for t in scope.get('touch', []):
            if isinstance(t, str) and 'evidence/' in t:
                paths_to_add.append(t)
        for c in scope.get('create', []):
            if isinstance(c, str) and 'evidence/' in c:
                paths_to_add.append(c)
        
        for path in paths_to_add:
            normalized = normalize_evidence_path(path)
            producers.setdefault(normalized, []).append(story_id)
    
    return producers


def has_producer_fuzzy(required_path, producers):
    """Check if required path has a producer using fuzzy matching."""
    if required_path in producers:
        return True, producers[required_path]
    
    for prod_path, stories in producers.items():
        if required_path in prod_path or prod_path.endswith(required_path):
            return True, stories
        
        req_parts = required_path.split('/')
        prod_parts = prod_path.split('/')
        if len(req_parts) <= len(prod_parts):
            if prod_parts[-len(req_parts):] == req_parts:
                return True, stories
    
    return False, []


def categorize_gap(path):
    """Categorize a gap by expected policy."""
    global_manual = ['README.md', 'ci_links.md']
    if any(path.endswith(f) for f in global_manual):
        return 'GLOBAL_MANUAL'
    
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
                       help='Only include STORY_OWNED gaps (exclude GLOBAL_MANUAL and UNKNOWN)')
    args = parser.parse_args()
    
    evidence_paths = [args.roadmap] + args.checklist
    required = extract_roadmap_evidence(evidence_paths)
    producers = extract_prd_evidence_outputs(args.prd)
    
    all_gaps = []
    for req in required:
        path = req['path']
        has_prod, prod_stories = has_producer_fuzzy(path, producers)
        
        if not has_prod:
            category = categorize_gap(path)
            all_gaps.append({
                'path': path,
                'category': category,
                'required_by': req['primary_source'],
                'all_sources': req['sources'],
                'status': 'NO_PRODUCER'
            })
    
    if args.strict:
        displayed_gaps = [g for g in all_gaps if g['category'] == 'STORY_OWNED']
    else:
        displayed_gaps = all_gaps
    
    paths_with_producers = set()
    for req in required:
        has_prod, _ = has_producer_fuzzy(req['path'], producers)
        if has_prod:
            paths_with_producers.add(req['path'])
    actual_with_producers = len(paths_with_producers)
    
    report = {
        'total_required': len(required),
        'with_producers': actual_with_producers,
        'gaps_count': len(displayed_gaps),
        'all_gaps_count': len(all_gaps),
        'gaps': displayed_gaps,
        'producers_summary': {path: len(stories) for path, stories in producers.items()}
    }
    
    if args.output:
        Path(args.output).write_text(json.dumps(report, indent=2))
        print(f"Report written: {args.output}")
    
    print(f"\nRoadmap Evidence Audit")
    print(f"Required: {report['total_required']}")
    print(f"With producers: {report['with_producers']}")
    if args.strict:
        print(f"Gaps (strict - STORY_OWNED only): {report['gaps_count']}")
    else:
        print(f"Gaps: {report['gaps_count']}")
    
    if displayed_gaps:
        print("\nGaps (no producing PRD story):")
        story_owned_gaps = [g for g in displayed_gaps if g['category'] == 'STORY_OWNED']
        global_manual_gaps = [g for g in displayed_gaps if g['category'] == 'GLOBAL_MANUAL']
        unknown_gaps = [g for g in displayed_gaps if g['category'] == 'UNKNOWN']
        
        if story_owned_gaps:
            print("\n  STORY_OWNED (action required):")
            for gap in story_owned_gaps[:10]:
                print(f"    - {gap['path']}")
        
        if global_manual_gaps:
            print("\n  GLOBAL_MANUAL (expected - no story producer by design):")
            for gap in global_manual_gaps[:5]:
                print(f"    - {gap['path']}")
        
        if unknown_gaps:
            print("\n  UNKNOWN (please categorize):")
            for gap in unknown_gaps[:5]:
                print(f"    - {gap['path']}")
    
    print("\nInvariant Verification:")
    gap_paths = {g['path'] for g in displayed_gaps}
    
    if 'evidence/phase1/restart_loop/restart_100_cycles.log' in gap_paths:
        print("  ✓ restart_100_cycles.log correctly flagged (no producer)")
    else:
        print("  ✗ restart_100_cycles.log NOT flagged (unexpected)")
    
    if 'evidence/phase1/determinism/intent_hashes.txt' in gap_paths:
        print("  ✗ intent_hashes.txt flagged as gap (unexpected - has producer S6-001)")
    else:
        print("  ✓ intent_hashes.txt correctly NOT flagged (has producer)")
    
    if args.strict:
        non_story_gaps = [g for g in displayed_gaps if g['category'] != 'STORY_OWNED']
        if non_story_gaps:
            print(f"  ✗ Strict mode has {len(non_story_gaps)} non-STORY_OWNED gaps")
        else:
            print("  ✓ Strict mode includes only STORY_OWNED gaps")
    
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

---

## 5. Test Fixtures (Deterministic)

### Profile: FULL Test
```bash
# Create test contract
cat > /tmp/test_full.md << 'EOF'
Profile: FULL
AT-001
EOF

# Run tool
python3 tools/at_coverage_report.py --contract /tmp/test_full.md --prd plans/prd.json

# Expected canonical errors:
# - "Profile: FULL is not allowed for AT inheritance"
# - "AT-001 has no Profile tag in scope"
# Exit code: non-zero (fail-closed)
```

### Duplicate AT Test
```bash
# Create test contract
cat > /tmp/test_dup.md << 'EOF'
Profile: CSP
AT-001
AT-001
AT-002
EOF

# Run tool
python3 tools/at_coverage_report.py --contract /tmp/test_dup.md --prd plans/prd.json --output-json /tmp/dup.json

# Expected: 
# - total_ats: 3 (each occurrence counted)
# - csp_unique: 2 (AT-001 and AT-002)
# - No errors (duplicate with same profile is OK)
```

---

## 6. Success Criteria

| Tool | Invariant | Expected |
|------|-----------|----------|
| AT Coverage | Profile: FULL handling | Error (fail-closed) |
| AT Coverage | Duplicate AT counting | Each occurrence counted |
| AT Coverage | CSP count | Matches canonical (258) |
| AT Coverage | GOP count | Matches canonical (75) |
| Roadmap Audit | restart_100_cycles.log | Flagged in strict mode |
| Roadmap Audit | intent_hashes.txt | NOT flagged |
| Roadmap Audit | with_producers | Accurate (actual matches) |
| Roadmap Audit | Strict mode gaps | Only STORY_OWNED |

---

## 7. Design Changes from v9

| Finding | Fix |
|---------|-----|
| FULL handling mismatch | Error on Profile: FULL (not UNKNOWN) - canonical fail-closed |
| Duplicate counting | Count each AT occurrence (list), not deduped (dict) |

---

## 8. No More Design Iterations

**v10 is the final design document with canonical semantics.**

If v10 tools have bugs when implemented, fix them in implementation phase. Don't redesign.

---

*End of v10 (Final Design - Canonical Semantics)*
