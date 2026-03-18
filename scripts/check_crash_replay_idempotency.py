#!/usr/bin/env python3
"""
check_crash_replay_idempotency.py

Mechanical spec-lint for crash consistency / replay / idempotency.

Enforces:
- Every referenced AT exists in CONTRACT.md
- Every referenced §section exists in CONTRACT.md headings
- All contract crash ATs (AT-### blocks containing 'crash occurs') are covered by spec.crash_points (unless ignored)
- All required idempotency rule_tags are present
"""

from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path
from typing import List, Set

try:
    import yaml  # PyYAML
except Exception:
    yaml = None

HEADING_ID_RE = re.compile(r'^\s{0,3}#{1,6}\s+(?:\*\*)?(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)(?:\*\*)?')
AT_RE = re.compile(r'\bAT-\d{1,4}\b')

def read_text(p: Path) -> str:
    return p.read_text(encoding='utf-8', errors='replace')

def index_section_ids(contract_lines: List[str]) -> Set[str]:
    ids: Set[str] = set()
    for line in contract_lines:
        m = HEADING_ID_RE.match(line)
        if m:
            ids.add(m.group('id'))
    return ids

def extract_all_ats(contract_text: str) -> Set[str]:
    return set(AT_RE.findall(contract_text))

def extract_crash_ats(contract_lines: List[str]) -> Set[str]:
    crash: Set[str] = set()
    i = 0
    while i < len(contract_lines):
        line = contract_lines[i]
        m = re.match(r'^\s*(AT-\d{1,4})\b', line)
        if not m:
            i += 1
            continue
        at_id = m.group(1)
        # Scan until the next AT block to avoid bleeding into the next test.
        block_lines: List[str] = []
        i += 1
        while i < len(contract_lines):
            nxt = contract_lines[i]
            if re.match(r'^\s*AT-\d{1,4}\b', nxt):
                break
            block_lines.append(nxt)
            i += 1
        if 'crash occurs' in '\n'.join(block_lines).lower():
            crash.add(at_id)
        continue
    return crash

def norm_sec(tok: str) -> str:
    return tok.strip().replace('§', '').strip()

def err(msg: str, errors: List[str]):
    errors.append(msg)

def pick_default_path(user_path: str, candidates: List[str]) -> Path:
    if user_path:
        return Path(user_path)
    for cand in candidates:
        p = Path(cand)
        if p.exists():
            return p
    return Path(candidates[0])

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        '--contract',
        default='',
        help='Path to CONTRACT.md (default tries specs/CONTRACT.md then CONTRACT.md)',
    )
    ap.add_argument(
        '--spec',
        default='',
        help='Path to CRASH_REPLAY_IDEMPOTENCY.yaml (default tries specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml then repo root)',
    )
    ap.add_argument('--strict', action='store_true')
    args = ap.parse_args()

    cpath = pick_default_path(args.contract, ['specs/CONTRACT.md', 'CONTRACT.md'])
    spath = pick_default_path(args.spec, ['specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml', 'CRASH_REPLAY_IDEMPOTENCY.yaml'])

    if not cpath.exists():
        print(f'ERROR: contract not found: {cpath}', file=sys.stderr)
        return 2
    if not spath.exists():
        print(f'ERROR: spec not found: {spath}', file=sys.stderr)
        return 2
    if yaml is None:
        print('ERROR: PyYAML not available', file=sys.stderr)
        return 2

    contract_text = read_text(cpath)
    contract_lines = contract_text.splitlines()
    section_ids = index_section_ids(contract_lines)
    all_ats = extract_all_ats(contract_text)
    crash_ats = extract_crash_ats(contract_lines)

    doc = yaml.safe_load(read_text(spath))
    if not isinstance(doc, dict):
        print('ERROR: spec must be YAML mapping', file=sys.stderr)
        return 2

    errors: List[str] = []
    required_tags = set((doc.get('coverage', {}) or {}).get('required_rule_tags', []) or [])
    ignore_crash = set((doc.get('coverage', {}) or {}).get('ignore_crash_at_ids', []) or [])

    def check_sections(sections, ctx):
        for s in sections or []:
            sid = norm_sec(str(s))
            if not re.fullmatch(r'\d+(?:\.(?:\d+|[A-Za-z]))*', sid):
                continue
            if sid not in section_ids:
                err(f'{ctx}: missing section id in CONTRACT.md: {sid}', errors)

    def check_ats(ats, ctx):
        for a in ats or []:
            at = str(a).strip()
            if not at.startswith('AT-'):
                at = 'AT-' + at
            if at not in all_ats:
                err(f'{ctx}: missing AT in CONTRACT.md: {at}', errors)

    covered_crash: Set[str] = set()
    for cp in doc.get('crash_points', []) or []:
        cid = cp.get('id', '<missing>')
        cref = cp.get('contract_refs', {}) or {}
        check_sections(cref.get('sections', []), f'crash_points.{cid}')
        check_ats(cp.get('acceptance_tests', []), f'crash_points.{cid}')
        for a in cp.get('acceptance_tests', []) or []:
            at = str(a).strip()
            if not at.startswith('AT-'):
                at = 'AT-' + at
            covered_crash.add(at)

    missing_crash = sorted((crash_ats - ignore_crash) - covered_crash)
    if missing_crash:
        err(f'Contract crash ATs not covered by spec.crash_points: {missing_crash}', errors)

    seen_tags: Set[str] = set()
    for item in doc.get('idempotency', []) or []:
        iid = item.get('id', '<missing>')
        tag = item.get('rule_tag')
        if isinstance(tag, str):
            seen_tags.add(tag)
        cref = item.get('contract_refs', {}) or {}
        check_sections(cref.get('sections', []), f'idempotency.{iid}')
        check_ats(item.get('acceptance_tests', []), f'idempotency.{iid}')

    missing_tags = sorted(required_tags - seen_tags)
    if missing_tags:
        err(f'Missing required idempotency rule_tags: {missing_tags}', errors)

    for block in ['durability_backpressure', 'replay_inputs_retention']:
        for item in doc.get(block, []) or []:
            iid = item.get('id', '<missing>')
            cref = item.get('contract_refs', {}) or {}
            check_sections(cref.get('sections', []), f'{block}.{iid}')
            check_ats(item.get('acceptance_tests', []), f'{block}.{iid}')

    if errors:
        print('ERRORS:', file=sys.stderr)
        for e in errors:
            print(' - ' + e, file=sys.stderr)
        return 2

    print('OK: crash/replay/idempotency spec checks passed.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
