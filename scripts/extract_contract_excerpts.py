#!/usr/bin/env python3
"""extract_contract_excerpts.py
Mechanical excerpt packer for CONTRACT.md.

It can extract:
A) explicit section tokens via --sections "2.2,2.2.3,Definitions,Appendix A"
B) sections referenced by a flow in specs/flows/ARCH_FLOWS.yaml via --flows specs/flows/ARCH_FLOWS.yaml --flow-id ACF-001

Modes:
- Excerpts only (default): write just the extracted contract excerpts.
- Flow spec only: --emit-flow-spec (requires --flows + --flow-id)
- Bundle: --bundle outputs BOTH the flow spec and the excerpts in a single markdown file.

Examples:
  # Show numeric heading IDs you can extract
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md --show-available > headings.txt

  # Extract by explicit section IDs
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md \
    --sections "2.2,2.2.1,2.2.1.1,2.2.3" --out excerpts_ACF-001.md --line-numbers

  # Extract by flow id from specs/flows/ARCH_FLOWS.yaml
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml --list-flows
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml \
    --flow-id ACF-003 --out excerpts_ACF-003.md --line-numbers
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml \
    --flow-id ACF-003 --emit-flow-spec

  # Bundle flow spec + excerpts (recommended for audits)
  python3 scripts/extract_contract_excerpts.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml \
    --flow-id ACF-003 --bundle --out bundle_ACF-003.md --line-numbers
"""

from __future__ import annotations
import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import yaml  # PyYAML
except Exception:
    yaml = None

HEADING_RE = re.compile(r'^(?P<indent>\s{0,3})(?P<hashes>#{1,6})\s+(?P<title>.*)$')
HEADING_ID_RE = re.compile(r'^\s{0,3}#{1,6}\s+(?:\*\*)?(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)(?:\*\*)?')
APPENDIX_A_RE = re.compile(r'^\s{0,3}#{1,6}\s+.*Appendix\s+A\b', re.IGNORECASE)
DEFINITIONS_RE = re.compile(r'^\s{0,3}#{1,6}\s+.*Definitions\b', re.IGNORECASE)

@dataclass(frozen=True)
class Heading:
    line_no: int
    level: int
    id: Optional[str]
    title: str

def read_lines(path: Path) -> List[str]:
    return path.read_text(encoding='utf-8', errors='replace').splitlines()

def parse_headings(lines: List[str]) -> List[Heading]:
    out: List[Heading] = []
    for i, line in enumerate(lines, start=1):
        m = HEADING_RE.match(line)
        if not m:
            continue
        level = len(m.group('hashes'))
        title = m.group('title').strip()
        mid = HEADING_ID_RE.match(line)
        hid = mid.group('id') if mid else None
        out.append(Heading(line_no=i, level=level, id=hid, title=title))
    return out

def normalize(tok: str) -> str:
    return tok.strip().replace('§', '').strip()

def find_heading(headings: List[Heading], lines: List[str], token: str) -> Optional[Heading]:
    t = normalize(token)

    # numeric id
    if re.fullmatch(r'\d+(?:\.(?:\d+|[A-Za-z]))*', t):
        for h in headings:
            if h.id == t:
                return h
        return None

    # Appendix A / Definitions
    if t.lower() == 'appendix a':
        for h in headings:
            if APPENDIX_A_RE.match(lines[h.line_no - 1]):
                return h
        return None

    if t.lower() == 'definitions':
        for h in headings:
            if DEFINITIONS_RE.match(lines[h.line_no - 1]):
                return h
        return None

    # fallback substring match
    t_low = t.lower()
    for h in headings:
        if t_low in h.title.lower():
            return h
    return None

def bounds(lines: List[str], headings: List[Heading], start_heading: Heading) -> Tuple[int, int]:
    start = start_heading.line_no
    end = len(lines)
    for h in headings:
        if h.line_no <= start:
            continue
        if h.level <= start_heading.level:
            end = h.line_no - 1
            break
    return start, end

def render(lines: List[str], start: int, end: int, line_numbers: bool) -> str:
    if not line_numbers:
        return '\n'.join(lines[start-1:end])
    width = len(str(end))
    return '\n'.join([f"L{ln:>{width}}  {lines[ln-1]}" for ln in range(start, end+1)])

def load_flows(flows_path: Path) -> Dict[str, dict]:
    if yaml is None:
        raise RuntimeError('PyYAML is required but not installed.')
    doc = yaml.safe_load(flows_path.read_text(encoding='utf-8', errors='replace'))
    if not isinstance(doc, dict) or 'flows' not in doc or not isinstance(doc['flows'], list):
        raise ValueError('Flows file must be YAML with top-level key: flows: [ ... ]')
    out: Dict[str, dict] = {}
    for f in doc['flows']:
        if not isinstance(f, dict):
            continue
        fid = f.get('id')
        if isinstance(fid, str) and fid.strip():
            out[fid.strip()] = f
    return out

def flow_sections(flow: dict) -> List[str]:
    refs = flow.get('refs') or {}
    secs = refs.get('sections') or []
    if not isinstance(secs, list):
        return []
    return [normalize(str(s)) for s in secs if str(s).strip()]

def emit_flow_yaml(flow: dict) -> str:
    if yaml is None:
        return str(flow)
    return yaml.safe_dump(flow, sort_keys=False)

def build_bundle_markdown(flow_id: str, flow_obj: dict, flow_yaml: str, excerpts_md: str) -> str:
    name = flow_obj.get('name', '')
    title = f"# Flow Bundle: {flow_id}" + (f" — {name}" if name else '')
    return '\n'.join([
        title,
        '',
        'Use this file as the single paste-source for your flow audit prompt.',
        '',
        '## FLOW_SPEC (YAML)',
        '```yaml',
        flow_yaml.rstrip(),
        '```',
        '',
        '## CONTRACT_EXCERPTS',
        excerpts_md.rstrip(),
        '',
    ])

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--contract', default='specs/CONTRACT.md', help='Path to CONTRACT.md')
    ap.add_argument('--sections', default='', help='Comma-separated list: e.g. "2.2,2.2.3,Appendix A"')
    ap.add_argument('--flows', default='', help='Path to ARCH_FLOWS.yaml containing flows[].id and refs.sections[]')
    ap.add_argument('--flow-id', default='', help='Flow id to extract sections for (e.g., ACF-003)')
    ap.add_argument('--list-flows', action='store_true', help='List flow ids found in --flows file')
    ap.add_argument('--emit-flow-spec', action='store_true', help='Print the YAML block for --flow-id to stdout (no excerpts)')
    ap.add_argument('--bundle', action='store_true', help='Write a single markdown containing FLOW_SPEC + CONTRACT_EXCERPTS (requires --flows and --flow-id)')
    ap.add_argument('--out', default='', help='Write output to this file. If omitted, prints to stdout.')
    ap.add_argument('--line-numbers', action='store_true', help='Prefix each excerpt line with L###')
    ap.add_argument('--show-available', action='store_true', help='Print available numeric heading IDs and titles')
    args = ap.parse_args()

    contract_path = Path(args.contract)
    if not contract_path.exists():
        print(f'ERROR: contract not found: {contract_path}', file=sys.stderr)
        return 2

    lines = read_lines(contract_path)
    headings = parse_headings(lines)

    if args.show_available:
        for h in headings:
            if h.id:
                print(f"{h.id}\t(level {h.level})\t{h.title}")
        return 0

    flow_obj = None
    flow_yaml = ''
    flow_id = ''

    if args.flows:
        flows_path = Path(args.flows)
        if not flows_path.exists():
            print(f'ERROR: flows file not found: {flows_path}', file=sys.stderr)
            return 2
        flows = load_flows(flows_path)

        if args.list_flows:
            for fid in sorted(flows.keys()):
                name = flows[fid].get('name', '')
                print(f"{fid}\t{name}")
            return 0

        if args.flow_id:
            flow_id = args.flow_id.strip()
            flow_obj = flows.get(flow_id)
            if not flow_obj:
                print(f'ERROR: flow id not found in {flows_path}: {args.flow_id}', file=sys.stderr)
                return 2
            flow_yaml = emit_flow_yaml(flow_obj)

            if args.emit_flow_spec and not args.bundle:
                print(flow_yaml)
                return 0

    if args.bundle:
        if flow_obj is None:
            print('ERROR: --bundle requires --flows and --flow-id', file=sys.stderr)
            return 2
        if not args.out:
            print('ERROR: --bundle requires --out bundle_<flow>.md', file=sys.stderr)
            return 2

    # Determine tokens
    tokens: List[str] = []
    if flow_obj is not None:
        tokens = flow_sections(flow_obj)
        if not tokens:
            print(f'ERROR: flow {flow_id} has no refs.sections[] to extract.', file=sys.stderr)
            return 2
    else:
        if not args.sections.strip():
            print('ERROR: provide --sections OR (--flows + --flow-id)', file=sys.stderr)
            return 2
        tokens = [normalize(t) for t in args.sections.split(',') if t.strip()]

    missing = []
    excerpt_parts: List[str] = []

    for tok in tokens:
        h = find_heading(headings, lines, tok)
        if not h:
            missing.append(tok)
            continue
        s, e = bounds(lines, headings, h)
        excerpt_parts.append(f'<!-- EXCERPT: {tok} | starts L{s} | ends L{e} -->')
        excerpt_parts.append(render(lines, s, e, args.line_numbers))
        excerpt_parts.append('\n' + '-'*80 + '\n')

    if missing:
        excerpt_parts.append('<!-- MISSING TOKENS: ' + ', '.join(missing) + ' -->')

    excerpts_md = '\n'.join(excerpt_parts).rstrip() + '\n'
    out_text = build_bundle_markdown(flow_id, flow_obj, flow_yaml, excerpts_md) if args.bundle else excerpts_md

    if args.out:
        Path(args.out).write_text(out_text, encoding='utf-8')
        print(f'Wrote output to {args.out}')
    else:
        print(out_text)

    return 0 if not missing else 1

if __name__ == '__main__':
    raise SystemExit(main())
