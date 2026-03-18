#!/usr/bin/env python3
"""
check_reconciliation_matrix.py

Mechanical linter for RECONCILIATION_MATRIX.md.

Behavior:
- Table exists and has required columns.
- Each RM row has required non-empty fields.
- Reason codes are limited to the OpenPermissionReasonCode registry.
- ATs column:
  - If explicit AT-### values are present, they must exist in CONTRACT.md.
  - If ATs is blank/'-'/AUTO, resolve ATs from Contract refs sections and require at
    least one definitional AT block in those sections.
- Optional registry override (RM-ID keyed): specs/flows/RECONCILIATION_ATS.yaml.
  - If a registry entry exists for an RM-ID, it must match the ATs column (or be
    used when ATs is AUTO).

Exit codes:
0 pass
1 warnings only
2 errors
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

RE_ROW_RE = re.compile(r"^\|\s*(RM-\d+)\s*\|")
AT_RE = re.compile(r"\bAT-\d+\b")
AT_DEF_RE = re.compile(r"^\s*AT-(\d+)\b")  # definitional block line
SEC_REF_RE = re.compile(r"§\s*(\d+(?:\\?\.(?:\d+|[A-Za-z]))*)")
NUM_SEC_RE = re.compile(r"\b(\d+(?:\\?\.(?:\d+|[A-Za-z]))*)\b")

# OpenPermissionReasonCode allowed values (registry)
ALLOWED_RECONCILE_REASONS = {
    "RESTART_RECONCILE_REQUIRED",
    "WS_BOOK_GAP_RECONCILE_REQUIRED",
    "WS_TRADES_GAP_RECONCILE_REQUIRED",
    "INVENTORY_MISMATCH_RECONCILE_REQUIRED",
    "SESSION_TERMINATION_RECONCILE_REQUIRED",
}
REASON_TOKEN_RE = re.compile(r"\b[A-Z0-9_]+_RECONCILE_REQUIRED\b")

HEADING_RE = re.compile(r"^(?P<indent>\s{0,3})(?P<hashes>#{1,6})\s+(?P<title>.*)$")
HEADING_ID_RE = re.compile(
    r"^\s{0,3}#{1,6}\s+(?:\*\*)?(?P<id>\d+(?:\\?\.(?:\d+|[A-Za-z]))*)(?:\*\*)?"
)

PLACEHOLDER_ATS = {"", "-", "AUTO"}


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def split_row(line: str) -> List[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def find_table(lines: List[str]) -> Tuple[int, int]:
    """Find the first markdown table whose header contains 'RM-ID'. Return (start_idx, end_idx) 0-based."""
    for i, line in enumerate(lines):
        if "RM-ID" in line and line.strip().startswith("|"):
            end = i
            k = i
            while k < len(lines) and lines[k].strip().startswith("|"):
                end = k
                k += 1
            return i, end
    return -1, -1


def normalize_section_id(sid: str) -> str:
    return sid.replace("\\.", ".")


def index_sections(contract_lines: List[str]) -> Dict[str, Tuple[int, int, int]]:
    """
    Build map: section_id -> (start_line_inclusive, end_line_inclusive, heading_level)
    Lines are 1-based for reporting.
    """
    headings: List[Tuple[int, int, str]] = []
    for i, line in enumerate(contract_lines, start=1):
        m = HEADING_RE.match(line)
        if not m:
            continue
        level = len(m.group("hashes"))
        mid = HEADING_ID_RE.match(line)
        if mid:
            sid = normalize_section_id(mid.group("id"))
            headings.append((i, level, sid))

    idx: Dict[str, Tuple[int, int, int]] = {}
    for n, (line_no, level, sid) in enumerate(headings):
        end = len(contract_lines)
        for j in range(n + 1, len(headings)):
            nxt_line, nxt_level, _ = headings[j]
            if nxt_level <= level:
                end = nxt_line - 1
                break
        if sid not in idx:
            idx[sid] = (line_no, end, level)
    return idx


def ats_defined_in_range(contract_lines: List[str], start: int, end: int) -> Set[str]:
    """Return set of definitional AT ids (AT-###) within [start,end], 1-based."""
    out: Set[str] = set()
    for ln in range(start, end + 1):
        m = AT_DEF_RE.match(contract_lines[ln - 1])
        if m:
            out.add(f"AT-{m.group(1)}")
    return out


def is_placeholder_ats(ats_cell: str) -> bool:
    return ats_cell.strip().upper() in PLACEHOLDER_ATS


def extract_section_ids_from_refs(refs_cell: str) -> List[str]:
    """Extract section IDs from Contract refs cell."""
    ids = [normalize_section_id(m.group(1)) for m in SEC_REF_RE.finditer(refs_cell)]
    if ids:
        return ids
    candidates = [normalize_section_id(m.group(1)) for m in NUM_SEC_RE.finditer(refs_cell)]
    return [c for c in candidates if "." in c]


def parse_registry(text: str) -> Dict[str, Set[str]]:
    """
    Parse a simple RM-ID keyed YAML mapping:
      RM-001:
        - AT-010
        - AT-011
      RM-002: [AT-120, AT-121]
    """
    out: Dict[str, Set[str]] = {}
    current: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r"^\s*(RM-\d+)\s*:\s*(.*)$", line)
        if m:
            current = m.group(1)
            out.setdefault(current, set())
            tail = m.group(2).strip()
            if tail:
                out[current].update(AT_RE.findall(tail))
            continue
        if current and line.lstrip().startswith("-"):
            out[current].update(AT_RE.findall(line))
    return out


def pick_registry_path(user_path: str) -> Path | None:
    if user_path:
        p = Path(user_path)
        if not p.exists():
            print(f"ERROR: registry not found: {p}", file=sys.stderr)
            return None
        return p
    default = Path("specs/flows/RECONCILIATION_ATS.yaml")
    if default.exists():
        return default
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--matrix", required=True, help="Path to RECONCILIATION_MATRIX.md")
    ap.add_argument("--contract", required=True, help="Path to CONTRACT.md")
    ap.add_argument("--registry", default="", help="Path to RECONCILIATION_ATS.yaml (optional)")
    ap.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    args = ap.parse_args()

    matrix_path = Path(args.matrix)
    contract_path = Path(args.contract)

    if not matrix_path.exists():
        print(f"ERROR: matrix not found: {matrix_path}", file=sys.stderr)
        return 2
    if not contract_path.exists():
        print(f"ERROR: contract not found: {contract_path}", file=sys.stderr)
        return 2

    registry_path = pick_registry_path(args.registry)
    if args.registry and registry_path is None:
        return 2
    registry: Dict[str, Set[str]] = {}
    if registry_path is not None:
        registry = parse_registry(read_text(registry_path))

    matrix_lines = read_text(matrix_path).splitlines()
    contract_lines = read_text(contract_path).splitlines()

    contract_ats_anywhere = set(AT_RE.findall("\n".join(contract_lines)))
    sec_index = index_sections(contract_lines)

    start, end = find_table(matrix_lines)
    if start < 0:
        print("ERROR: could not find a markdown table with header containing 'RM-ID'.", file=sys.stderr)
        return 2

    header = split_row(matrix_lines[start])
    required_cols = {
        "RM-ID",
        "Trigger",
        "Gate action (must be explicit)",
        "Required reconciliation actions (deterministic order)",
        "Clear criteria (must all hold)",
        "ATs",
        "Contract refs",
    }
    missing_cols = required_cols - set(header)
    if missing_cols:
        print(f"ERROR: matrix table missing required columns: {sorted(missing_cols)}", file=sys.stderr)
        print(f"Found columns: {header}", file=sys.stderr)
        return 2

    idx = {name: header.index(name) for name in header}

    errors: List[str] = []
    warns: List[str] = []

    # Validate rows
    for i in range(start + 2, end + 1):  # skip header + separator row
        line = matrix_lines[i].strip()
        if not line.startswith("|"):
            continue
        if not RE_ROW_RE.match(line):
            continue

        cells = split_row(line)
        if len(cells) != len(header):
            errors.append(f"L{i+1}: column count mismatch: expected {len(header)} got {len(cells)}")
            continue

        rm_id = cells[idx["RM-ID"]]
        trigger = cells[idx["Trigger"]]
        gate = cells[idx["Gate action (must be explicit)"]]
        actions = cells[idx["Required reconciliation actions (deterministic order)"]]
        clear = cells[idx["Clear criteria (must all hold)"]]
        ats_cell = cells[idx["ATs"]]
        refs_cell = cells[idx["Contract refs"]]

        # Required non-empty fields (ATs handled separately).
        for field_name, val in [
            ("Trigger", trigger),
            ("Gate action", gate),
            ("Actions", actions),
            ("Clear criteria", clear),
            ("Contract refs", refs_cell),
        ]:
            if not val.strip():
                errors.append(f"L{i+1} {rm_id}: empty required field: {field_name}")

        # Latch mention warning: only if gate is meaningful (not N/A/meta).
        gate_low = gate.strip().lower()
        if gate.strip() and "n/a" not in gate_low and "meta" not in gate_low:
            if "open_permission_blocked_latch" not in gate and "latch" not in gate_low:
                warns.append(
                    f"L{i+1} {rm_id}: gate action does not mention latch explicitly "
                    "(expected open_permission_blocked_latch=true/false)"
                )

        # Validate reason codes used are from registry.
        reason_tokens = set(REASON_TOKEN_RE.findall(line))
        unknown_reasons = sorted([r for r in reason_tokens if r not in ALLOWED_RECONCILE_REASONS])
        if unknown_reasons:
            errors.append(f"L{i+1} {rm_id}: unknown reconcile reason code(s): {unknown_reasons}")

        # AT validation with optional registry override.
        row_ats = set(AT_RE.findall(ats_cell))
        has_registry = rm_id in registry
        registry_ats = registry.get(rm_id, set())

        if has_registry:
            if not registry_ats:
                errors.append(f"L{i+1} {rm_id}: registry entry has no ATs.")
            if row_ats:
                if row_ats != registry_ats:
                    errors.append(
                        f"L{i+1} {rm_id}: ATs column does not match registry: "
                        f"{sorted(row_ats)} != {sorted(registry_ats)}"
                    )
            else:
                if not is_placeholder_ats(ats_cell):
                    errors.append(
                        f"L{i+1} {rm_id}: ATs column contains no AT-### and is not a placeholder "
                        "(use '-', 'AUTO', or explicit AT-###)."
                    )
            missing_ats = sorted([a for a in registry_ats if a not in contract_ats_anywhere])
            if missing_ats:
                errors.append(f"L{i+1} {rm_id}: AT(s) not found in CONTRACT: {missing_ats}")
            continue

        if row_ats:
            missing_ats = sorted([a for a in row_ats if a not in contract_ats_anywhere])
            if missing_ats:
                errors.append(f"L{i+1} {rm_id}: AT(s) not found in CONTRACT: {missing_ats}")
        else:
            if not is_placeholder_ats(ats_cell):
                errors.append(
                    f"L{i+1} {rm_id}: ATs column contains no AT-### and is not a placeholder "
                    "(use '-', 'AUTO', or explicit AT-###)."
                )
            else:
                sec_ids = extract_section_ids_from_refs(refs_cell)
                if not sec_ids:
                    errors.append(
                        f"L{i+1} {rm_id}: ATs is AUTO/blank but Contract refs has no §section ids."
                    )
                else:
                    auto_ats: Set[str] = set()
                    missing_secs = []
                    for sid in sec_ids:
                        if sid not in sec_index:
                            missing_secs.append(sid)
                            continue
                        s, e, _lvl = sec_index[sid]
                        auto_ats |= ats_defined_in_range(contract_lines, s, e)
                    if missing_secs:
                        errors.append(
                            f"L{i+1} {rm_id}: Contract refs section id(s) not found in CONTRACT headings: "
                            f"{sorted(missing_secs)}"
                        )
                    if not auto_ats:
                        errors.append(
                            f"L{i+1} {rm_id}: ATs is AUTO/blank but no definitional AT blocks found "
                            f"within referenced sections {sec_ids}."
                        )

    if warns:
        print("WARNINGS:")
        for w in warns:
            print(" -", w)
        print()

    if errors:
        print("ERRORS:", file=sys.stderr)
        for e in errors:
            print(" -", e, file=sys.stderr)
        return 2

    print("OK: RECONCILIATION_MATRIX checks passed.")
    return 1 if warns and not args.strict else 0


if __name__ == "__main__":
    raise SystemExit(main())
