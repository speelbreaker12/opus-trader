#!/usr/bin/env python3
"""Fail-closed scanner for leaked status-reason display strings.

This gate ensures contract-owned status reason display strings stay centralized
in generated owner files and are not duplicated ad-hoc across crate sources.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, List, Set, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect leaked status-reason display strings in source files."
    )
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--scan-root", required=True, type=Path)
    parser.add_argument(
        "--allow-path",
        action="append",
        default=[],
        help="Path allowed to contain display strings (repeatable).",
    )
    return parser.parse_args()


def _collect_display_strings(node: object, out: Set[str]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "display" and isinstance(value, str):
                text = value.strip()
                if text:
                    out.add(text)
            _collect_display_strings(value, out)
        return
    if isinstance(node, list):
        for item in node:
            _collect_display_strings(item, out)


def load_display_strings(manifest_path: Path) -> List[str]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        raise SystemExit(2)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in manifest {manifest_path}: {exc}", file=sys.stderr)
        raise SystemExit(2)

    displays: Set[str] = set()
    registries = manifest.get("registries")
    if not isinstance(registries, dict):
        print("ERROR: manifest.registries must be an object", file=sys.stderr)
        raise SystemExit(2)
    _collect_display_strings(registries, displays)
    return sorted(displays, key=len, reverse=True)


def iter_source_files(scan_root: Path) -> Iterable[Path]:
    if not scan_root.exists():
        print(f"ERROR: scan root not found: {scan_root}", file=sys.stderr)
        raise SystemExit(2)
    for path in sorted(scan_root.rglob("*.rs")):
        if path.is_file():
            yield path


def normalize_allow_paths(paths: List[str], cwd: Path) -> Set[Path]:
    normalized: Set[Path] = set()
    for item in paths:
        p = Path(item)
        normalized.add((p if p.is_absolute() else (cwd / p)).resolve())
    return normalized


def find_leaks(
    files: Iterable[Path], display_strings: List[str], allow_paths: Set[Path]
) -> List[Tuple[Path, int, str]]:
    leaks: List[Tuple[Path, int, str]] = []
    for file_path in files:
        resolved = file_path.resolve()
        if resolved in allow_paths:
            continue
        try:
            text = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            # Rust source should be utf-8; fail-closed if unreadable.
            print(f"ERROR: non-utf8 source file: {file_path}", file=sys.stderr)
            raise SystemExit(2)

        if not any(token in text for token in display_strings):
            continue

        lines = text.splitlines()
        for line_no, line in enumerate(lines, start=1):
            for token in display_strings:
                if token in line:
                    leaks.append((file_path, line_no, token))
                    break
    return leaks


def main() -> int:
    args = parse_args()
    cwd = Path.cwd()
    display_strings = load_display_strings(args.manifest)
    if not display_strings:
        print("ERROR: no display strings found in manifest", file=sys.stderr)
        return 2

    allow_paths = normalize_allow_paths(args.allow_path, cwd)
    leaks = find_leaks(iter_source_files(args.scan_root), display_strings, allow_paths)
    if leaks:
        print("FAIL: leaked status-reason display strings found:", file=sys.stderr)
        for path, line_no, token in leaks[:50]:
            print(f"  {path}:{line_no}: {token}", file=sys.stderr)
        if len(leaks) > 50:
            print(f"  ... and {len(leaks) - 50} more", file=sys.stderr)
        return 1

    print("status reason leak guard: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
