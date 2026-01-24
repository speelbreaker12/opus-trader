#!/usr/bin/env python3
"""check_vq_evidence.py
Minimal checker for VQ_EVIDENCE.md.

Validates each VQ-### record has:
- >=1 contract reference (e.g., §2.2.3 or Definitions/Appendix A)
- >=1 AT reference (AT-###)

Missing file behavior:
- If VQ_EVIDENCE_REQUIRED is truthy -> error
- Else if --allow-missing -> warn and exit 0
- Else -> error
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

VQ_HEADER_RE = re.compile(r"^VQ-\d{3}\b")
CONTRACT_REFS_RE = re.compile(r"^Contract refs:\s*(.*)\s*$")
AT_REFS_RE = re.compile(r"^AT refs:\s*(.*)\s*$")
CLAIM_RE = re.compile(r"^Claim:\s*(.*)\s*$")
STATUS_RE = re.compile(r"^Status:\s*(.*)\s*$")
UPDATED_RE = re.compile(r"^Updated:\s*(.*)\s*$")

AT_RE = re.compile(r"\bAT-\d+\b")
SECTION_RE = re.compile(r"§\s*\d+(?:\.(?:\d+|[A-Za-z]))*")
NORMATIVE_WORD_RE = re.compile(r"\b(Definitions|Appendix\s+A)\b", re.IGNORECASE)
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

SPEC_TEXT = """Minimum record format (v0.1):

VQ-001
Claim: <text>
Contract refs: §2.2.3   (or Definitions / Appendix A)
AT refs: AT-931
Status: VERIFIED | PARTIAL | UNVERIFIED
Updated: YYYY-MM-DD
"""


@dataclass(frozen=True)
class Finding:
    vq_id: str
    line: int
    message: str


def truthy_env(name: str) -> bool:
    raw = os.environ.get(name, "")
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


def load_lines(path: Path) -> List[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def split_blocks(lines: List[str]) -> List[Tuple[str, int, List[str]]]:
    headers: List[Tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        if VQ_HEADER_RE.match(line.strip()):
            headers.append((line.strip().split()[0], i))

    blocks: List[Tuple[str, int, List[str]]] = []
    for idx, (vq_id, start_line) in enumerate(headers):
        start_idx = start_line - 1
        end_line = (headers[idx + 1][1] - 1) if idx + 1 < len(headers) else len(lines)
        blocks.append((vq_id, start_line, lines[start_idx:end_line]))
    return blocks


def extract_field(block_lines: List[str], field_re: re.Pattern) -> Optional[Tuple[int, str]]:
    for offset, line in enumerate(block_lines):
        m = field_re.match(line.strip())
        if m:
            return (offset, m.group(1).strip())
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="specs/flows/VQ_EVIDENCE.md", help="Path to VQ_EVIDENCE.md")
    ap.add_argument("--allow-missing", action="store_true", help="Allow missing file (local dev)")
    ap.add_argument("--print-spec", action="store_true", help="Print the evidence format spec")
    args = ap.parse_args()

    if args.print_spec:
        print(SPEC_TEXT)
        return 0

    required = truthy_env("VQ_EVIDENCE_REQUIRED")
    path = Path(args.file)
    if not path.exists():
        if required:
            print(f"ERROR: VQ evidence required but file missing: {path}", file=sys.stderr)
            return 2
        if args.allow_missing:
            print(f"WARN: VQ evidence file missing (allowed): {path}", file=sys.stderr)
            return 0
        print(f"ERROR: VQ evidence file missing: {path}", file=sys.stderr)
        return 2

    lines = load_lines(path)
    blocks = split_blocks(lines)
    findings: List[Finding] = []

    if not blocks:
        findings.append(Finding("VQ-???", 1, "No VQ-### records found."))

    ids = [b[0] for b in blocks]
    if len(set(ids)) != len(ids):
        findings.append(Finding("VQ-???", 1, "Duplicate VQ-### ids detected."))

    for vq_id, start_line, block in blocks:
        claim = extract_field(block, CLAIM_RE)
        contract = extract_field(block, CONTRACT_REFS_RE)
        at = extract_field(block, AT_REFS_RE)
        status = extract_field(block, STATUS_RE)
        updated = extract_field(block, UPDATED_RE)

        if claim is None:
            findings.append(Finding(vq_id, start_line, "Missing 'Claim:' line."))
        if contract is None:
            findings.append(Finding(vq_id, start_line, "Missing 'Contract refs:' line."))
            contract_text = ""
            contract_line = start_line
        else:
            contract_text = contract[1]
            contract_line = start_line + contract[0]

        if at is None:
            findings.append(Finding(vq_id, start_line, "Missing 'AT refs:' line."))
            at_text = ""
            at_line = start_line
        else:
            at_text = at[1]
            at_line = start_line + at[0]

        if status is None:
            findings.append(Finding(vq_id, start_line, "Missing 'Status:' line."))
        else:
            status_val = status[1].strip().upper()
            if status_val not in {"VERIFIED", "PARTIAL", "UNVERIFIED"}:
                findings.append(Finding(vq_id, start_line + status[0], "Status must be VERIFIED, PARTIAL, or UNVERIFIED."))

        if updated is None:
            findings.append(Finding(vq_id, start_line, "Missing 'Updated:' line."))
        else:
            if not DATE_RE.match(updated[1].strip()):
                findings.append(Finding(vq_id, start_line + updated[0], "Updated must be YYYY-MM-DD."))

        if contract is not None:
            has_section = bool(SECTION_RE.search(contract_text))
            has_norm_word = bool(NORMATIVE_WORD_RE.search(contract_text))
            if not (has_section or has_norm_word):
                findings.append(Finding(
                    vq_id,
                    contract_line,
                    "Contract refs must include at least one §section or Definitions/Appendix A.",
                ))

        if at is not None:
            if not AT_RE.search(at_text):
                findings.append(Finding(
                    vq_id,
                    at_line,
                    "AT refs must include at least one AT-###.",
                ))

    if findings:
        print("ERRORS:", file=sys.stderr)
        for f in findings:
            print(f"  {f.vq_id} @L{f.line}: {f.message}", file=sys.stderr)
        return 2

    print("OK: VQ_EVIDENCE is reference-closed (each record has >=1 Contract ref and >=1 AT).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
