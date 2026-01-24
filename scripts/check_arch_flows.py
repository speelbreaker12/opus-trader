#!/usr/bin/env python3
"""
Mechanical checker for ARCH_FLOW_INDEX in SPEC_INDEX/ARCH_FLOWS.

Validates:
- Flow refs (AT-###, §x.y) exist in CONTRACT.md
- Flow 'where' paths exist in CONTRACT.md's "Where:" lines (or are explicitly allowed)
- Every CONTRACT "Where:" is covered by at least one flow (warn/error)
"""

from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

try:
    import yaml  # pip install pyyaml
except ImportError:
    print("ERROR: PyYAML not installed. pip install pyyaml", file=sys.stderr)
    sys.exit(2)

AT_RE = re.compile(r"\bAT-\d+\b")
AT_LINE_RE = re.compile(r"^\s*AT-\d+\b")
HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+")
HEADING_ID_RE = re.compile(
    r'^\s{0,3}#{1,6}\s+(?:\*\*)?'
    r'(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)'
    r'(?:\*\*)?'
)
WHERE_BLOCK_START_RE = re.compile(r"^\s*(\*\*Where:\*\*|Where:)\s*$")
LIST_ITEM_RE = re.compile(r"^\s*[-*]\s+")
BACKTICK_RE = re.compile(r"`([^`]+)`")
WHERE_PATH_RE = re.compile(r"\.(rs|py|sh)$")


def looks_like_where_path(token: str) -> bool:
    tok = token.strip()
    if "/" not in tok:
        return False
    return bool(WHERE_PATH_RE.search(tok))

def load_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def extract_contract_sets(contract_text: str) -> tuple[set[str], set[str], set[str]]:
    ats = set(AT_RE.findall(contract_text))

    secs: set[str] = set()
    lines = contract_text.splitlines()
    for line in lines:
        m = HEADING_ID_RE.match(line)
        if m:
            secs.add(f"§{m.group('id')}")

    wheres: set[str] = set()
    i = 0
    while i < len(lines):
        line = lines[i]
        if "Where:" in line:
            for m in BACKTICK_RE.finditer(line):
                tok = m.group(1).strip()
                if looks_like_where_path(tok):
                    wheres.add(tok)

            if WHERE_BLOCK_START_RE.match(line):
                j = i + 1
                while j < len(lines):
                    next_line = lines[j]
                    if not next_line.strip():
                        break
                    if HEADING_RE.match(next_line):
                        break
                    if not LIST_ITEM_RE.match(next_line):
                        break
                    for m in BACKTICK_RE.finditer(next_line):
                        tok = m.group(1).strip()
                        if looks_like_where_path(tok):
                            wheres.add(tok)
                    j += 1
                i = j
                continue
        i += 1
    return ats, secs, wheres

def extract_section_ats(contract_text: str) -> dict[str, set[str]]:
    section_ats: dict[str, set[str]] = {}
    current_section: str | None = None
    for line in contract_text.splitlines():
        m = HEADING_ID_RE.match(line)
        if m:
            current_section = f"§{m.group('id')}"
            section_ats.setdefault(current_section, set())
            continue
        if current_section and AT_LINE_RE.match(line):
            section_ats[current_section].update(AT_RE.findall(line))
    return section_ats

def extract_flow_refs(flow: dict) -> tuple[set[str], set[str], set[str]]:
    refs = flow.get("refs", {}) or {}
    at_list = refs.get("acceptance_tests", []) or []
    sec_list = refs.get("sections", []) or []
    where_list = flow.get("where", []) or []
    return set(at_list), set(sec_list), set(where_list)

def normalize_depends(dep_val: object) -> list[str]:
    if isinstance(dep_val, str):
        return [dep_val.strip()] if dep_val.strip() else []
    if isinstance(dep_val, list):
        out: list[str] = []
        for item in dep_val:
            s = str(item).strip()
            if s:
                out.append(s)
        return out
    return []

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", default="specs/CONTRACT.md")
    ap.add_argument("--flows", default="specs/flows/ARCH_FLOWS.yaml", help="YAML file containing arch_flow_index_version + flows")
    ap.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    args = ap.parse_args()

    contract_path = Path(args.contract)
    flows_path = Path(args.flows)

    contract_text = load_text(contract_path)
    contract_ats, contract_secs, contract_wheres = extract_contract_sets(contract_text)
    section_ats = extract_section_ats(contract_text)

    flows_doc = yaml.safe_load(load_text(flows_path))
    flows = (flows_doc.get("flows") if isinstance(flows_doc, dict) else None)
    if not isinstance(flows, list):
        print("ERROR: flows file must contain top-level 'flows: [...]' YAML.", file=sys.stderr)
        return 2

    errors: list[str] = []
    warnings: list[str] = []

    flow_by_id = {
        f.get("id"): f for f in flows
        if isinstance(f, dict) and isinstance(f.get("id"), str) and f.get("id")
    }

    dep_at_cache: dict[str, set[str]] = {}
    dep_sec_cache: dict[str, set[str]] = {}

    def collect_dep_ats(flow_id: str, visiting: set[str]) -> set[str]:
        if flow_id in dep_at_cache:
            return dep_at_cache[flow_id]
        if flow_id in visiting:
            warnings.append(f"{flow_id}: depends_on cycle detected: {sorted(visiting)}")
            return set()
        visiting.add(flow_id)
        flow = flow_by_id.get(flow_id)
        if not flow:
            visiting.remove(flow_id)
            return set()
        deps = normalize_depends(flow.get("depends_on"))
        dep_ats: set[str] = set()
        for dep in deps:
            if dep not in flow_by_id:
                errors.append(f"{flow_id}: depends_on references missing flow id: {dep}")
                continue
            dep_flow = flow_by_id[dep]
            dep_at_refs, _, _ = extract_flow_refs(dep_flow)
            dep_ats |= dep_at_refs
            dep_ats |= collect_dep_ats(dep, visiting)
        visiting.remove(flow_id)
        dep_at_cache[flow_id] = dep_ats
        return dep_ats

    def collect_dep_sections(flow_id: str, visiting: set[str]) -> set[str]:
        if flow_id in dep_sec_cache:
            return dep_sec_cache[flow_id]
        if flow_id in visiting:
            warnings.append(f"{flow_id}: depends_on cycle detected: {sorted(visiting)}")
            return set()
        visiting.add(flow_id)
        flow = flow_by_id.get(flow_id)
        if not flow:
            visiting.remove(flow_id)
            return set()
        deps = normalize_depends(flow.get("depends_on"))
        dep_secs: set[str] = set()
        for dep in deps:
            if dep not in flow_by_id:
                errors.append(f"{flow_id}: depends_on references missing flow id: {dep}")
                continue
            dep_flow = flow_by_id[dep]
            _, dep_sec_refs, _ = extract_flow_refs(dep_flow)
            dep_secs |= dep_sec_refs
            dep_secs |= collect_dep_sections(dep, visiting)
        visiting.remove(flow_id)
        dep_sec_cache[flow_id] = dep_secs
        return dep_secs

    covered_wheres: set[str] = set()

    for f in flows:
        fid = f.get("id", "<missing id>")
        at_refs, sec_refs, where_refs = extract_flow_refs(f)
        covered_wheres |= where_refs
        deps = normalize_depends(f.get("depends_on"))
        dep_ats = collect_dep_ats(fid, set()) if deps else set()
        effective_ats = at_refs | dep_ats

        # AT existence
        missing_ats = sorted(a for a in effective_ats if a not in contract_ats)
        if missing_ats:
            errors.append(f"{fid}: missing ATs in CONTRACT.md: {missing_ats}")

        # § existence (best-effort: if you store 'Definitions' etc, skip strict match)
        for s in sec_refs:
            if s.startswith("§"):
                if s not in contract_secs:
                    errors.append(f"{fid}: missing section ref in CONTRACT.md: {s}")

        # Where existence (if not found, warn; some flows legitimately reference modules not declared)
        allow_unknown = bool(f.get("where_unknown_ok", False))
        missing_where = sorted(w for w in where_refs if w not in contract_wheres)
        if missing_where and not allow_unknown:
            warnings.append(f"{fid}: where paths not found as `Where:` lines in CONTRACT.md: {missing_where}")

        # Basic shape checks
        if not f.get("invariants") and str(fid) != "PHASE-1":
            warnings.append(f"{fid}: has no invariants[] (flow is non-auditable).")

        if deps:
            dep_secs = collect_dep_sections(fid, set())
            shared_secs = {s for s in sec_refs if s in dep_secs and s.startswith("§")}
            required_ats: set[str] = set()
            for s in shared_secs:
                required_ats |= section_ats.get(s, set())
            missing_required = sorted(a for a in required_ats if a not in effective_ats)
            if missing_required:
                warnings.append(
                    f"{fid}: acceptance_tests missing for shared sections with depends_on "
                    f"coverage: {missing_required}"
                )

    # Orphan Where: modules (contract has Where but no flow covers them)
    orphan_wheres = sorted(w for w in contract_wheres if w not in covered_wheres)
    if orphan_wheres:
        msg = f"Orphan CONTRACT 'Where:' modules not covered by any flow: {orphan_wheres}"
        (errors if args.strict else warnings).append(msg)

    if warnings:
        print("\nWARNINGS:")
        for w in warnings:
            print(" -", w)

    if errors:
        print("\nERRORS:", file=sys.stderr)
        for e in errors:
            print(" -", e, file=sys.stderr)
        return 1

    print("OK: ARCH_FLOW_INDEX checks passed.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
