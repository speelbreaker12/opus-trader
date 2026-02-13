# Cross-Reference Validator Design v9
## Fixed: Strict Mode Accounting, CLI Contract, Canonical Profile Parsing

**Version:** 9.0  
**Status:** Corrected - Aligned with canonical validator semantics  
**Approach:** Standalone Python tools with minimal assumptions

---

## 1. Problem Acknowledgment

Design v8 had issues identified in review:
- **MEDIUM:** Strict-mode `with_producers` count inflated (filtered gaps but computed from required count)
- **MEDIUM:** `--strict` CLI contract mismatch (said "only STORY_OWNED" but included UNKNOWN)
- **MEDIUM:** Profile parsing used broad `re.search()` instead of canonical anchored regex

**v9 Solution:** 
- Compute `with_producers` from actual producer matches (independent of display filtering)
- Fix `--strict` to include only STORY_OWNED gaps
- Align profile parsing with `check_contract_profiles.py` semantics

---

## 2. Evidence Gap Policy

Not all evidence gaps are errors. Gaps fall into categories:

| Category | Description | Example | Action |
|----------|-------------|---------|--------|
| **STORY_OWNED** | Produced by PRD story test or scope | `intent_hashes.txt`, `restart_100_cycles.log` | Flag if missing producer |
| **GLOBAL_MANUAL** | Checklist-required, not story-owned | `README.md`, `ci_links.md` | Expected gap (no producer by design) |
| **UNKNOWN** | Cannot categorize | N/A | Include in non-strict mode |

The tool reports gaps based on category filtering; statistics always reflect actual producer coverage.

---

## 3. Profile Parsing Alignment

Aligned with `tools/ci/check_contract_profiles.py`:

| Aspect | Canonical | v9 Design |
|--------|-----------|-----------|
| Profile regex | `^Profile:\s+(CSP\|GOP\|FULL)\s*$` | Same anchored approach |
| AT regex | `^\s*(AT-\d+)\s*$` | Same anchored approach |
| FULL handling | Rejected for AT inheritance | Track but warn (cannot assign to AT) |
| Inheritance | Last CSP/GOP above AT | Same state-machine approach |

---

## 4. Two Standalone Tools Only

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

**Success criteria:**
- CSP=258, GOP=75 (cross-validated with check_contract_profiles.py)
- No UNKNOWN profile ATs
- No ATs with Profile: FULL inheritance

---

### Tool 2: roadmap-evidence-audit
**Purpose:** Compare roadmap evidence requirements to PRD story outputs

**Usage:**
```bash
# Standard mode: show all gaps categorized
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output evidence_gaps.json

# Strict mode: only STORY_OWNED gaps (for CI gates)
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --strict
```

**Outputs:**
- JSON list of gaps with category and sources
- Human-readable summary to stdout
- Exit 0 always (informational tool)

**Success criteria (invariant-based):**
| Invariant | Expected |
|-----------|----------|
| `restart_100_cycles.log` in gaps (strict) | YES |
| `intent_hashes.txt` NOT in gaps | YES |
| `with_producers` accurate in strict mode | Matches actual producer count |
| STORY_OWNED only in strict mode | No GLOBAL_MANUAL or UNKNOWN |

---

## 5. Tool Specifications (Python)

### at_coverage_report.py

```python
#!/usr/bin/env python3
"""Generate AT coverage report from Contract and PRD."""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime

# Aligned with check_contract_profiles.py semantics
PROFILE_RE = re.compile(r"^Profile:\s*(CSP|GOP|FULL)\s*$")
AT_RE = re.compile(r"^\s*(AT-\d+)\s*$")


def extract_contract_ats(contract_path):
    """Extract AT-### definitions with profiles from contract.
    
    Aligned with check_contract_profiles.py:
    - Anchored regex for Profile lines
    - Anchored regex for AT lines
    - FULL profile tracked but cannot be assigned to ATs
    - CSP/GOP inheritance from most recent Profile above
    
    Returns dict: at_id -> {'profile': 'CSP|GOP|UNKNOWN', 'section': '...'}
    """
    ats = {}
    content = Path(contract_path).read_text()
    lines = content.split('\n')
    
    current_profile = None
    current_section = 'unknown'
    
    for i, line in enumerate(lines):
        # Check for Profile declaration (anchored, like canonical validator)
        profile_match = PROFILE_RE.match(line)
        if profile_match:
            profile = profile_match.group(1)
            if profile == 'FULL':
                # FULL is tracked but not assigned to ATs
                current_profile = 'FULL'
            else:
                current_profile = profile
            continue
        
        # Update section from headings (for context)
        heading_match = re.match(r'^(#{2,}|\*\*)\s*(.+?)(?:\*\*|$)', line)
        if heading_match:
            current_section = heading_match.group(2).strip()
            continue
        
        # Check for AT definition (anchored with optional whitespace)
        at_match = AT_RE.match(line)
        if at_match:
            at_id = at_match.group(1)
            
            # Check for explicit Profile on same line (rare but possible)
            explicit_match = re.search(r'Profile:\s*(CSP|GOP)', line)
            if explicit_match:
                profile = explicit_match.group(1)
            elif current_profile in ('CSP', 'GOP'):
                profile = current_profile
            else:
                # current_profile is None or FULL - cannot inherit
                profile = 'UNKNOWN'
            
            ats[at_id] = {'profile': profile, 'section': current_section}
    
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
        pass


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
    
    # Collect requirements and producers
    evidence_paths = [args.roadmap] + args.checklist
    required = extract_roadmap_evidence(evidence_paths)
    producers = extract_prd_evidence_outputs(args.prd)
    
    # Find all gaps first (for accurate counting)
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
    
    # Filter gaps based on strict mode (v9 fix: CLI contract aligned)
    if args.strict:
        # Strict mode: ONLY STORY_OWNED gaps
        displayed_gaps = [g for g in all_gaps if g['category'] == 'STORY_OWNED']
    else:
        # Non-strict: all gaps
        displayed_gaps = all_gaps
    
    # v9 fix: Compute with_producers from actual producer matches (not filtered gaps)
    paths_with_producers = set()
    for req in required:
        has_prod, _ = has_producer_fuzzy(req['path'], producers)
        if has_prod:
            paths_with_producers.add(req['path'])
    actual_with_producers = len(paths_with_producers)
    
    # Build report
    report = {
        'total_required': len(required),
        'with_producers': actual_with_producers,  # v9 fix: actual count, not derived
        'gaps_count': len(displayed_gaps),
        'all_gaps_count': len(all_gaps),  # For debugging
        'gaps': displayed_gaps,
        'producers_summary': {path: len(stories) for path, stories in producers.items()}
    }
    
    if args.output:
        Path(args.output).write_text(json.dumps(report, indent=2))
        print(f"Report written: {args.output}")
    
    # Console output
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
    
    # Invariant verification
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
        # Strict mode invariant: only STORY_OWNED gaps
        non_story_gaps = [g for g in displayed_gaps if g['category'] != 'STORY_OWNED']
        if non_story_gaps:
            print(f"  ✗ Strict mode has {len(non_story_gaps)} non-STORY_OWNED gaps (CLI contract violation)")
        else:
            print("  ✓ Strict mode includes only STORY_OWNED gaps")
    
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
```

---

## 6. Implementation Steps

```bash
# Create tools
mkdir -p tools
cat > tools/at_coverage_report.py << 'EOF'
# [paste v9 spec above]
EOF
cat > tools/roadmap_evidence_audit.py << 'EOF'
# [paste v9 spec above]
EOF

# Test compilation
python3 -m py_compile tools/*.py

# Test AT coverage
python3 tools/at_coverage_report.py \
  --contract specs/CONTRACT.md \
  --prd plans/prd.json \
  --output-json /tmp/coverage.json

# Verify CSP=258, GOP=75, UNKNOWN=0
cat /tmp/coverage.json | jq '.stats'

# Test roadmap audit (standard mode)
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --output /tmp/gaps.json

# Test strict mode
python3 tools/roadmap_evidence_audit.py \
  --roadmap docs/ROADMAP.md \
  --checklist docs/PHASE0_CHECKLIST_BLOCK.md \
  --checklist docs/PHASE1_CHECKLIST_BLOCK.md \
  --prd plans/prd.json \
  --strict

# Verify invariants:
# - restart_100_cycles.log flagged
# - intent_hashes.txt NOT flagged
# - Strict mode: only STORY_OWNED gaps
# - with_producers count accurate in both modes
```

---

## 7. Success Criteria (Invariant-Based)

### AT Coverage Tool

| Invariant | Expected |
|-----------|----------|
| CSP count | 258 (matches canonical validator) |
| GOP count | 75 (matches canonical validator) |
| UNKNOWN | 0 |
| Profile regex | Anchored (`^Profile:`) like canonical |

### Roadmap Evidence Audit Tool

| Invariant | Expected |
|-----------|----------|
| `restart_100_cycles.log` in gaps (strict) | YES |
| `intent_hashes.txt` NOT in gaps | YES |
| `with_producers` accurate | Counts actual producer matches |
| Strict mode contract | Only STORY_OWNED gaps included |
| Non-strict mode | All gaps included with categorization |

---

## 8. Design Changes from v8

| Finding | Fix |
|---------|-----|
| Strict-mode accounting | `with_producers` computed from actual producer matches, not `len(required) - len(filtered_gaps)` |
| CLI contract mismatch | `--strict` now includes **only** STORY_OWNED (excludes GLOBAL_MANUAL and UNKNOWN) |
| Profile parsing drift | Aligned with canonical: anchored regex (`^Profile:`, `^\s*AT-`), FULL tracking without assignment |

---

## 9. No More Design Iterations

**v9 is the final design document.**

If v9 tools have bugs when implemented, fix them in implementation phase. Don't redesign.

---

*End of v9 (Final Design - Aligned with Canonical Validator)*
