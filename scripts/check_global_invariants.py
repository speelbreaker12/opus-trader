#!/usr/bin/env python3
"""check_global_invariants.py
Mechanical linter for GLOBAL_INVARIANTS.md.

Enforces (hard errors):
- Every GI-### block contains required fields (Name, Scope, Forbidden states, Fail-closed,
  Enforcement point, Observability, Contract refs, AT coverage)
- Scope must be Global
- Enforcement point must reference exactly one EP-### defined in the enforcement point registry
- Contract refs must include >=1 section reference (e.g., §2.2.3)
- AT coverage must include >=1 AT-###
- No banned wording in invariant blocks (TBD, TODO, should, ideally)
- Contract refs and AT refs resolve to CONTRACT.md
- Duplicate GI-### ids are errors

Exit codes:
- 0: pass
- 2: errors present
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

GI_HEADER_RE = re.compile(r"^###\s+(GI-\d{3})\b")
EP_LINE_RE = re.compile(r"^\s*-\s+(EP-\d{3})\s*:")
EP_RE = re.compile(r"\bEP-\d{3}\b")
AT_RE = re.compile(r"\bAT-\d+\b")
SECTION_RE = re.compile(r"§\s*(\d+(?:\.(?:\d+|[A-Za-z]))*)")
BANNED_WORD_RE = re.compile(r"\b(tbd|todo|should|ideally)\b", re.IGNORECASE)

FIELD_RE = {
    "name": re.compile(r"^-\s+\*\*Name:\*\*\s*(.*)\s*$"),
    "scope": re.compile(r"^-\s+\*\*Scope:\*\*\s*(.*)\s*$"),
    "forbidden": re.compile(r"^-\s+\*\*Forbidden states:\*\*\s*(.*)\s*$"),
    "fail_closed": re.compile(r"^-\s+\*\*Fail-closed:\*\*\s*(.*)\s*$"),
    "enforcement": re.compile(r"^-\s+\*\*Enforcement point:\*\*\s*(.*)\s*$"),
    "observability": re.compile(r"^-\s+\*\*Observability:\*\*\s*(.*)\s*$"),
    "contract": re.compile(r"^-\s+\*\*Contract refs:\*\*\s*(.*)\s*$"),
    "at": re.compile(r"^-\s+\*\*AT coverage:\*\*\s*(.*)\s*$"),
}

HEADING_ID_RE = re.compile(
    r"^\s{0,3}#{1,6}\s+(?:\*\*)?"
    r"(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)"
    r"(?:\*\*)?"
)


@dataclass(frozen=True)
class Finding:
    gi_id: str
    line: int
    message: str


def load_lines(path: Path) -> List[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def split_blocks(lines: List[str]) -> List[Tuple[str, int, List[str]]]:
    headers: List[Tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        m = GI_HEADER_RE.match(line.strip())
        if m:
            headers.append((m.group(1), i))

    blocks: List[Tuple[str, int, List[str]]] = []
    for idx, (gi_id, start_line) in enumerate(headers):
        start_idx = start_line - 1
        end_line = (headers[idx + 1][1] - 1) if idx + 1 < len(headers) else len(lines)
        blocks.append((gi_id, start_line, lines[start_idx:end_line]))
    return blocks


def extract_field(block_lines: List[str], field_re: re.Pattern) -> Optional[Tuple[int, str]]:
    for offset, line in enumerate(block_lines):
        m = field_re.match(line.strip())
        if m:
            return (offset, m.group(1).strip())
    return None


def index_enforcement_points(lines: List[str]) -> Set[str]:
    eps: Set[str] = set()
    in_section = False
    for line in lines:
        if line.strip() == "## Enforcement Points":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            m = EP_LINE_RE.match(line)
            if m:
                eps.add(m.group(1))
    return eps


def index_contract_headings(lines: List[str]) -> Set[str]:
    ids: Set[str] = set()
    for line in lines:
        m = HEADING_ID_RE.match(line)
        if m:
            ids.add(m.group("id"))
    return ids


def index_defined_ats(lines: List[str]) -> Set[str]:
    defined: Set[str] = set()
    for line in lines:
        m = re.match(r"^\s*AT-(\d{1,4})\b", line)
        if m:
            defined.add(m.group(1))
    return defined


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="specs/invariants/GLOBAL_INVARIANTS.md", help="Path to GLOBAL_INVARIANTS.md")
    ap.add_argument("--contract", default="specs/CONTRACT.md", help="Path to CONTRACT.md")
    args = ap.parse_args()

    inv_path = Path(args.file)
    if not inv_path.exists():
        print(f"ERROR: file not found: {inv_path}", file=sys.stderr)
        return 2

    contract_path = Path(args.contract)
    if not contract_path.exists():
        print(f"ERROR: contract file not found: {contract_path}", file=sys.stderr)
        return 2

    inv_lines = load_lines(inv_path)
    contract_lines = load_lines(contract_path)

    enforcement_points = index_enforcement_points(inv_lines)
    if not enforcement_points:
        print("ERROR: no enforcement points found (expected ## Enforcement Points section).", file=sys.stderr)
        return 2

    headings = index_contract_headings(contract_lines)
    defined_ats = index_defined_ats(contract_lines)

    blocks = split_blocks(inv_lines)
    findings: List[Finding] = []

    if not blocks:
        findings.append(Finding("GI-???", 1, "No GI-### blocks found (expected headings like '### GI-001')."))

    ids = [b[0] for b in blocks]
    if len(set(ids)) != len(ids):
        findings.append(Finding("GI-???", 1, "Duplicate GI-### ids detected."))

    for gi_id, start_line, block in blocks:
        # banned wording
        for offset, line in enumerate(block):
            if BANNED_WORD_RE.search(line):
                findings.append(Finding(gi_id, start_line + offset, "Banned wording found (TBD/TODO/should/ideally)."))

        # required fields
        fields: Dict[str, Optional[Tuple[int, str]]] = {}
        for key, field_re in FIELD_RE.items():
            fields[key] = extract_field(block, field_re)
            if fields[key] is None:
                findings.append(Finding(gi_id, start_line, f"Missing '- **{key.replace('_', ' ').title()}:**' line."))

        name = fields.get("name")
        if name is not None and not name[1]:
            findings.append(Finding(gi_id, start_line + name[0], "Name must not be empty."))

        scope = fields.get("scope")
        if scope is not None and scope[1].lower() != "global":
            findings.append(Finding(gi_id, start_line + scope[0], "Scope must be Global."))

        forbidden = fields.get("forbidden")
        if forbidden is not None and not forbidden[1]:
            findings.append(Finding(gi_id, start_line + forbidden[0], "Forbidden states must not be empty."))

        fail_closed = fields.get("fail_closed")
        if fail_closed is not None:
            if not fail_closed[1]:
                findings.append(Finding(gi_id, start_line + fail_closed[0], "Fail-closed must not be empty."))
            if not re.search(r"\b(missing|unparseable|unknown|invalid)\b", fail_closed[1], re.IGNORECASE):
                findings.append(Finding(gi_id, start_line + fail_closed[0], "Fail-closed must describe missing/unknown behavior."))

        observability = fields.get("observability")
        if observability is not None:
            if not observability[1]:
                findings.append(Finding(gi_id, start_line + observability[0], "Observability must not be empty."))
            if not re.search(r"/status|event:|metric:", observability[1]):
                findings.append(Finding(gi_id, start_line + observability[0], "Observability must include /status or event: or metric:."))

        enforcement = fields.get("enforcement")
        if enforcement is not None:
            eps = EP_RE.findall(enforcement[1])
            if len(eps) != 1:
                findings.append(Finding(gi_id, start_line + enforcement[0], "Enforcement point must reference exactly one EP-###."))
            else:
                if eps[0] not in enforcement_points:
                    findings.append(Finding(gi_id, start_line + enforcement[0], f"Enforcement point {eps[0]} not defined."))

        contract = fields.get("contract")
        if contract is not None:
            sections = SECTION_RE.findall(contract[1])
            if not sections:
                findings.append(Finding(gi_id, start_line + contract[0], "Contract refs must include at least one § section."))
            for sid in sections:
                if sid not in headings:
                    findings.append(Finding(gi_id, start_line + contract[0], f"Contract ref §{sid} not found in CONTRACT.md."))

        at = fields.get("at")
        if at is not None:
            at_ids = AT_RE.findall(at[1])
            if not at_ids:
                findings.append(Finding(gi_id, start_line + at[0], "AT coverage must include at least one AT-###."))
            for at_id in at_ids:
                num = at_id.split("-")[-1]
                if num not in defined_ats:
                    findings.append(Finding(gi_id, start_line + at[0], f"AT-{num} not defined in CONTRACT.md."))

    if findings:
        print("ERRORS:", file=sys.stderr)
        for f in findings:
            print(f"  {f.gi_id} @L{f.line}: {f.message}", file=sys.stderr)
        return 2

    print("INVARIANTS OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
