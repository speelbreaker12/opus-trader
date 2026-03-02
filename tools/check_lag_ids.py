#!/usr/bin/env python3
"""
Fail when duplicate `## LAG-###` headings exist in a contract lag tracker doc.

Exit codes:
  0 = no duplicate IDs
  1 = duplicate IDs found
  2 = setup/configuration error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class SetupError(RuntimeError):
    """Raised for deterministic setup/configuration failures."""


LAG_HEADING_RE = re.compile(r"^\s*##\s+(LAG-\d+)\b")


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect duplicate LAG IDs in markdown headings."
    )
    parser.add_argument(
        "--file",
        default="docs/CONTRACT_IMPL_LAG.md",
        help="Path to markdown lag tracker (default: docs/CONTRACT_IMPL_LAG.md)",
    )
    return parser.parse_args()


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        raise SetupError(f"file does not exist: {path}")
    if not path.is_file():
        raise SetupError(f"path is not a file: {path}")
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except OSError as ex:
        raise SetupError(f"failed to read '{path}': {ex}") from ex


def collect_lag_ids(lines: list[str]) -> dict[str, list[int]]:
    lag_lines: dict[str, list[int]] = {}
    for lineno, line in enumerate(lines, start=1):
        match = LAG_HEADING_RE.match(line)
        if not match:
            continue
        lag_id = match.group(1)
        lag_lines.setdefault(lag_id, []).append(lineno)
    return lag_lines


def main() -> int:
    args = parse_args()
    target = Path(args.file)
    try:
        lines = read_lines(target)
        lag_lines = collect_lag_ids(lines)
    except SetupError as ex:
        eprint(f"FAIL: SETUP ERROR: {ex}")
        return 2

    duplicates = {lag_id: seen for lag_id, seen in lag_lines.items() if len(seen) > 1}
    if duplicates:
        eprint(f"FAIL: duplicate LAG IDs found in {target}")
        for lag_id in sorted(duplicates):
            joined = ", ".join(str(n) for n in duplicates[lag_id])
            eprint(f"  - {lag_id}: lines {joined}")
        return 1

    print(f"OK: no duplicate LAG IDs found in {target} (headings={len(lag_lines)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
