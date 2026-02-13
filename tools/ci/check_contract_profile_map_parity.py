#!/usr/bin/env python3
"""Fail-closed AT profile map parity checker.

Compares two AT->Profile maps and enforces exact equality:
- same AT ID set
- same profile assignment per AT ID
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

AT_ID_RE = re.compile(r"^AT-\d+$")

EXIT_PASS = 0
EXIT_TOOL_ERROR = 2
EXIT_PARITY_MISMATCH = 6


class ToolError(RuntimeError):
    """Deterministic tool/config error."""


def load_map(path: Path, label: str) -> dict[str, str]:
    if not path.exists():
        raise ToolError(f"missing {label} map: {path}")

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ToolError(f"invalid JSON in {label} map {path}: {exc}") from exc

    if not isinstance(payload, dict):
        raise ToolError(f"{label} map must be a JSON object: {path}")

    out: dict[str, str] = {}
    for key, value in payload.items():
        if not isinstance(key, str) or not AT_ID_RE.match(key):
            raise ToolError(f"{label} map has invalid AT key: {key!r}")
        if value not in ("CSP", "GOP"):
            raise ToolError(f"{label} map has invalid profile for {key}: {value!r}")
        out[key] = value

    return out


def compare_maps(checker_map: dict[str, str], report_map: dict[str, str]) -> dict[str, object]:
    checker_ids = set(checker_map.keys())
    report_ids = set(report_map.keys())

    missing_in_checker = sorted(report_ids - checker_ids)
    missing_in_report = sorted(checker_ids - report_ids)

    mismatches = []
    for at_id in sorted(checker_ids & report_ids):
        checker_profile = checker_map[at_id]
        report_profile = report_map[at_id]
        if checker_profile != report_profile:
            mismatches.append(
                {
                    "at": at_id,
                    "checker": checker_profile,
                    "report": report_profile,
                }
            )

    parity_ok = not missing_in_checker and not missing_in_report and not mismatches

    return {
        "checker_total": len(checker_map),
        "report_total": len(report_map),
        "missing_in_checker": missing_in_checker,
        "missing_in_report": missing_in_report,
        "profile_mismatches": mismatches,
        "parity_ok": parity_ok,
    }


def write_report(path: Path, report: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check AT->Profile map parity")
    parser.add_argument(
        "--checker-map",
        required=True,
        help="AT->Profile map emitted by check_contract_profiles.py",
    )
    parser.add_argument(
        "--report-map",
        required=True,
        help="AT->Profile map emitted by at_coverage_report.py",
    )
    parser.add_argument(
        "--out",
        default="",
        help="Optional JSON report output path",
    )
    args = parser.parse_args()

    try:
        checker_map = load_map(Path(args.checker_map), "checker")
        report_map = load_map(Path(args.report_map), "report")
        report = compare_maps(checker_map, report_map)
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    if args.out:
        try:
            write_report(Path(args.out), report)
        except OSError as exc:
            print(f"ERROR: failed writing report: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    if report["parity_ok"]:
        print(f"OK: AT profile map parity passed ({report['checker_total']} AT IDs).")
        return EXIT_PASS

    print("AT profile map parity failed:", file=sys.stderr)

    missing_in_checker = report["missing_in_checker"]
    if missing_in_checker:
        preview = ", ".join(missing_in_checker[:20])
        suffix = " ..." if len(missing_in_checker) > 20 else ""
        print(f"  - missing_in_checker: {preview}{suffix}", file=sys.stderr)

    missing_in_report = report["missing_in_report"]
    if missing_in_report:
        preview = ", ".join(missing_in_report[:20])
        suffix = " ..." if len(missing_in_report) > 20 else ""
        print(f"  - missing_in_report: {preview}{suffix}", file=sys.stderr)

    mismatches = report["profile_mismatches"]
    if mismatches:
        preview = ", ".join(
            f"{row['at']}({row['checker']}!={row['report']})" for row in mismatches[:20]
        )
        suffix = " ..." if len(mismatches) > 20 else ""
        print(f"  - profile_mismatches: {preview}{suffix}", file=sys.stderr)

    return EXIT_PARITY_MISMATCH


if __name__ == "__main__":
    raise SystemExit(main())
