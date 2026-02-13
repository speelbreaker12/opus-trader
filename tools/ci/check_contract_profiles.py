#!/usr/bin/env python3
"""Validate CONTRACT AT profile inheritance (canonical checker)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Keep local import path robust when invoked as a file path in CI/local shells.
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.at_parser import parse_contract_profiles

CANONICAL_MARKER = "This is the canonical contract path. Do not edit other copies."
VERSION_MARKER = "Version: 5.2"

EXIT_PASS = 0
EXIT_TOOL_ERROR = 2
EXIT_PROFILE_INCOMPLETE = 5


def find_contract_path() -> Path | None:
    default = Path("specs/CONTRACT.md")
    if default.exists():
        return default
    for path in Path(".").rglob("*.md"):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if CANONICAL_MARKER in text and VERSION_MARKER in text:
            return path
    return None


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate AT profile inheritance.")
    parser.add_argument(
        "--contract",
        default=None,
        help="Path to canonical contract file (default: specs/CONTRACT.md if present).",
    )
    parser.add_argument(
        "--emit-map",
        default="",
        help="Optional path to write AT->Profile map JSON.",
    )
    parser.add_argument(
        "--emit-summary",
        default="",
        help="Optional path to write summary JSON.",
    )
    args = parser.parse_args()

    contract_path = Path(args.contract) if args.contract else find_contract_path()
    if not contract_path or not contract_path.exists():
        print("ERROR: contract path not found.", file=sys.stderr)
        return EXIT_TOOL_ERROR

    try:
        result = parse_contract_profiles(contract_path)
    except OSError as exc:
        print(f"ERROR: failed reading contract: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    if args.emit_map:
        try:
            write_json(Path(args.emit_map), result.at_profile_map)
        except OSError as exc:
            print(f"ERROR: failed writing emit-map: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    summary = {
        "total": result.counts["CSP"] + result.counts["GOP"],
        "csp_total": result.counts["CSP"],
        "gop_total": result.counts["GOP"],
        "profile_complete": len(result.errors) == 0,
        "errors": result.errors,
    }

    if args.emit_summary:
        try:
            write_json(Path(args.emit_summary), summary)
        except OSError as exc:
            print(f"ERROR: failed writing emit-summary: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    if result.errors:
        print("Profile validation failed:", file=sys.stderr)
        for err in result.errors:
            print(f"  - {err}", file=sys.stderr)
        return EXIT_PROFILE_INCOMPLETE

    total = summary["total"]
    print(f"OK: {total} AT definitions tagged (CSP={result.counts['CSP']}, GOP={result.counts['GOP']}).")
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
