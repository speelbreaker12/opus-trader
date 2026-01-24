#!/usr/bin/env python3
"""
check_crash_matrix.py
Mechanical lint checker for CRASH_MATRIX.md against CONTRACT.md.

Checks:
- Table exists under '## Crash Matrix'
- Each row contains:
  - Crash Point ID (CM-###)
  - At least one AT-### in Proof column
  - Non-empty Recovery action + Resend rule
- Each referenced AT-### exists in CONTRACT.md (string match)

Exit codes:
0 = OK
2 = FAIL (errors)
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Set

AT_RE = re.compile(r"\bAT-\d+\b")
CM_RE = re.compile(r"^CM-\d{3}$")

EXPECTED_HEADER = [
    "Crash Point ID",
    "Boundary / crash moment",
    "Durable facts at crash",
    "Deterministic recovery action",
    "Resend rule",
    "Proof (AT)",
    "Contract refs",
]

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def extract_table(md: str) -> List[List[str]]:
    lines = md.splitlines()
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == "## Crash Matrix":
            start = i
            break
    if start is None:
        return []
    table_lines: List[str] = []
    for ln in lines[start+1:]:
        if ln.strip().startswith("|"):
            table_lines.append(ln.rstrip())
        elif table_lines:
            break
    rows: List[List[str]] = []
    for ln in table_lines:
        if re.fullmatch(r"\|\s*-+\s*(\|\s*-+\s*)+\|?", ln.strip()):
            continue
        parts = [c.strip() for c in ln.strip().strip("|").split("|")]
        rows.append(parts)
    return rows

def pick_default_path(user_path: str, candidates: list[str]) -> Path:
    if user_path:
        return Path(user_path)
    for cand in candidates:
        p = Path(cand)
        if p.exists():
            return p
    return Path(candidates[0])

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--matrix", default="", help="Path to CRASH_MATRIX.md (default tries specs/flows/CRASH_MATRIX.md then CRASH_MATRIX.md)")
    ap.add_argument("--contract", default="", help="Path to CONTRACT.md (default tries specs/CONTRACT.md then CONTRACT.md)")
    args = ap.parse_args()

    mp = pick_default_path(args.matrix, ["specs/flows/CRASH_MATRIX.md", "CRASH_MATRIX.md"])
    cp = pick_default_path(args.contract, ["specs/CONTRACT.md", "CONTRACT.md"])

    if not mp.exists():
        print(f"ERROR: missing matrix file: {mp}", file=sys.stderr)
        return 2
    if not cp.exists():
        print(f"ERROR: missing contract file: {cp}", file=sys.stderr)
        return 2

    md = read_text(mp)
    rows = extract_table(md)
    if not rows:
        print("ERROR: could not find crash matrix table.", file=sys.stderr)
        return 2

    header = rows[0]
    if [h.strip() for h in header] != EXPECTED_HEADER:
        print("ERROR: crash matrix header mismatch.", file=sys.stderr)
        print("Expected:", EXPECTED_HEADER, file=sys.stderr)
        print("Found   :", header, file=sys.stderr)
        return 2

    contract = read_text(cp)
    contract_ats: Set[str] = set(AT_RE.findall(contract))

    errors: List[str] = []

    for idx, row in enumerate(rows[1:], start=1):
        if len(row) != len(EXPECTED_HEADER):
            errors.append(f"Row {idx}: wrong column count ({len(row)} != {len(EXPECTED_HEADER)}).")
            continue

        cm_id, _, _, recovery, resend, proof, _ = row

        if not CM_RE.match(cm_id):
            errors.append(f"Row {idx}: invalid Crash Point ID '{cm_id}' (expected CM-###).")

        if not recovery:
            errors.append(f"Row {idx} ({cm_id}): empty recovery action.")
        if not resend:
            errors.append(f"Row {idx} ({cm_id}): empty resend rule.")

        ats = set(AT_RE.findall(proof))
        if not ats:
            errors.append(f"Row {idx} ({cm_id}): Proof column missing AT-###.")
        else:
            missing = sorted(a for a in ats if a not in contract_ats)
            if missing:
                errors.append(f"Row {idx} ({cm_id}): ATs not found in CONTRACT.md: {missing}")

    if errors:
        print("FAIL: CRASH_MATRIX lint errors:", file=sys.stderr)
        for e in errors:
            print(" -", e, file=sys.stderr)
        return 2

    print("OK: CRASH_MATRIX.md looks mechanically consistent.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
