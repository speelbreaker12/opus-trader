#!/usr/bin/env python3
"""Generate AT coverage report from CONTRACT and PRD.

Hard requirements:
- Uses shared parser from tools/at_parser.py
- Fails closed on profile completeness errors
- Can emit AT->Profile map for parity checks
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.at_parser import parse_contract_profiles

EXIT_PASS = 0
EXIT_TOOL_ERROR = 2
EXIT_PROFILE_INCOMPLETE = 5

AT_REF_RE = re.compile(r"\b(AT-\d+)\b")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def extract_at_refs(value: object) -> Set[str]:
    refs: Set[str] = set()

    if isinstance(value, str):
        refs.update(AT_REF_RE.findall(value))
        return refs

    if isinstance(value, dict):
        for key in ("at", "AT", "id", "ref", "contract_ref"):
            if key in value:
                refs.update(extract_at_refs(value[key]))
        return refs

    if isinstance(value, list):
        for item in value:
            refs.update(extract_at_refs(item))

    return refs


def extract_story_refs(story: Dict[str, object]) -> Set[str]:
    refs: Set[str] = set()

    refs.update(extract_at_refs(story.get("contract_refs", [])))
    refs.update(extract_at_refs(story.get("enforcing_contract_ats", [])))

    observability = story.get("observability")
    if isinstance(observability, dict):
        refs.update(extract_at_refs(observability.get("status_contract_ats", [])))

    return refs


def load_prd_refs(prd_path: Path) -> Dict[str, List[str]]:
    try:
        payload = json.loads(prd_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON in PRD: {prd_path} ({exc})") from exc

    items = payload.get("items", [])
    if not isinstance(items, list):
        raise RuntimeError("PRD root must contain an items[] array")

    coverage: Dict[str, List[str]] = {}

    for item in items:
        if not isinstance(item, dict):
            continue
        story_id = item.get("id")
        if not isinstance(story_id, str) or not story_id:
            continue
        refs = extract_story_refs(item)
        for at_id in sorted(refs):
            coverage.setdefault(at_id, []).append(story_id)

    for at_id in coverage:
        coverage[at_id] = sorted(set(coverage[at_id]))

    return coverage


def render_markdown(report: Dict[str, object]) -> str:
    stats = report["stats"]
    unref = report["unreferenced_csp_ats"]

    lines = [
        "# AT Coverage Report",
        "",
        "## Summary",
        "| Profile | Total Occurrences | Unique IDs | Referenced IDs | Coverage |",
        "|---|---:|---:|---:|---:|",
        f"| CSP | {stats['csp_total']} | {stats['csp_unique']} | {stats['csp_referenced']} | {stats['csp_coverage_pct']}% |",
        f"| GOP | {stats['gop_total']} | {stats['gop_unique']} | {stats['gop_referenced']} | advisory |",
        "",
        "## Unreferenced CSP AT IDs",
    ]

    if unref:
        for at_id in unref:
            lines.append(f"- {at_id}")
    else:
        lines.append("- none")

    lines.extend([
        "",
        "## Notes",
        "- Parity and profile completeness are enforced by separate CI checks.",
    ])

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate AT coverage report")
    parser.add_argument("--contract", required=True, help="Path to CONTRACT.md")
    parser.add_argument("--prd", required=True, help="Path to plans/prd.json")
    parser.add_argument("--output-json", default="", help="Optional JSON report output path")
    parser.add_argument("--output-md", default="", help="Optional markdown report output path")
    parser.add_argument("--emit-map", default="", help="Optional AT->Profile map output path")
    args = parser.parse_args()

    contract_path = Path(args.contract)
    prd_path = Path(args.prd)

    if not contract_path.exists():
        print(f"ERROR: missing contract file: {contract_path}", file=sys.stderr)
        return EXIT_TOOL_ERROR
    if not prd_path.exists():
        print(f"ERROR: missing PRD file: {prd_path}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    try:
        parse_result = parse_contract_profiles(contract_path)
    except OSError as exc:
        print(f"ERROR: failed reading contract: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    if parse_result.errors:
        print("Profile validation failed:", file=sys.stderr)
        for err in parse_result.errors:
            print(f"  - {err}", file=sys.stderr)
        return EXIT_PROFILE_INCOMPLETE

    try:
        coverage = load_prd_refs(prd_path)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR
    except OSError as exc:
        print(f"ERROR: failed reading PRD: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    if args.emit_map:
        try:
            write_json(Path(args.emit_map), parse_result.at_profile_map)
        except OSError as exc:
            print(f"ERROR: failed writing emit-map: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    csp_ids = sorted([at for at, p in parse_result.at_profile_map.items() if p == "CSP"])
    gop_ids = sorted([at for at, p in parse_result.at_profile_map.items() if p == "GOP"])

    csp_id_set = set(csp_ids)
    gop_id_set = set(gop_ids)

    csp_referenced = sorted([at for at in csp_ids if at in coverage])
    gop_referenced = sorted([at for at in gop_ids if at in coverage])
    csp_unref = sorted([at for at in csp_ids if at not in coverage])

    report = {
        "contract_file": str(contract_path),
        "prd_file": str(prd_path),
        "stats": {
            "total_ats": parse_result.counts["CSP"] + parse_result.counts["GOP"],
            "csp_total": parse_result.counts["CSP"],
            "gop_total": parse_result.counts["GOP"],
            "csp_unique": len(csp_id_set),
            "gop_unique": len(gop_id_set),
            "csp_referenced": len(csp_referenced),
            "gop_referenced": len(gop_referenced),
            "csp_coverage_pct": round((len(csp_referenced) / len(csp_id_set)) * 100, 1)
            if csp_id_set
            else 0.0,
        },
        "unreferenced_csp_ats": csp_unref,
        "coverage_map": coverage,
    }

    if args.output_json:
        try:
            write_json(Path(args.output_json), report)
        except OSError as exc:
            print(f"ERROR: failed writing output-json: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    if args.output_md:
        try:
            write_text(Path(args.output_md), render_markdown(report))
        except OSError as exc:
            print(f"ERROR: failed writing output-md: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    print(
        "OK: AT coverage generated "
        f"(CSP unique={len(csp_id_set)}, referenced={len(csp_referenced)}, coverage={report['stats']['csp_coverage_pct']}%)."
    )
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
