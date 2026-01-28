#!/usr/bin/env python3
"""
tools/phase0_meta_test.py

Phase-0 CI meta-test: fail if required Phase-0 docs + evidence artifacts are missing.

This enforces that Phase 0 is not "paper-only":
- Launch policy exists + snapshot
- Env matrix exists + snapshot
- Keys/secrets doc exists + key scope probe JSON exists (valid)
- Break-glass runbook exists + snapshot + executed drill record + logs
- Evidence pack has owner summary + CI links placeholder

Usage:
  python tools/phase0_meta_test.py
Optional:
  --root .   # repo root (default: cwd)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, List


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def must_exist(paths: Iterable[Path]) -> List[str]:
    missing = []
    for p in paths:
        if not p.exists():
            missing.append(str(p))
    return missing


def must_be_nonempty(paths: Iterable[Path]) -> List[str]:
    bad = []
    for p in paths:
        if not p.exists():
            bad.append(f"{p} (missing)")
            continue
        if p.is_dir():
            bad.append(f"{p} (is a directory)")
            continue
        if p.stat().st_size == 0:
            bad.append(f"{p} (empty)")
    return bad


def must_contain_lines(path: Path, min_lines: int) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return [f"{path} (empty)"]
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) < min_lines:
        return [f"{path} (too few lines: {len(lines)} < {min_lines})"]
    return []


def must_be_valid_json(path: Path) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"{path} (invalid JSON: {e})"]
    if obj is None:
        return [f"{path} (JSON is null)"]
    if isinstance(obj, (dict, list)) and len(obj) == 0:
        return [f"{path} (JSON is empty)"]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="Repo root (default: cwd)")
    args = ap.parse_args()

    root = Path(args.root).resolve()

    # Required docs (MANUAL)
    required_docs = [
        root / "docs" / "launch_policy.md",
        root / "docs" / "env_matrix.md",
        root / "docs" / "keys_and_secrets.md",
        root / "docs" / "break_glass_runbook.md",
    ]

    # Required evidence files
    required_evidence = [
        root / "evidence" / "phase0" / "README.md",
        root / "evidence" / "phase0" / "ci_links.md",
        root / "evidence" / "phase0" / "policy" / "launch_policy_snapshot.md",
        root / "evidence" / "phase0" / "env" / "env_matrix_snapshot.md",
        root / "evidence" / "phase0" / "keys" / "key_scope_probe.json",
        root / "evidence" / "phase0" / "break_glass" / "runbook_snapshot.md",
        root / "evidence" / "phase0" / "break_glass" / "drill.md",
        root / "evidence" / "phase0" / "break_glass" / "log_excerpt.txt",
    ]

    errors: List[str] = []

    errors += [f"Missing required doc: {p}" for p in must_exist(required_docs)]
    errors += [f"Bad required doc: {p}" for p in must_be_nonempty(required_docs)]

    errors += [f"Missing required evidence: {p}" for p in must_exist(required_evidence)]
    errors += [f"Bad required evidence: {p}" for p in must_be_nonempty(required_evidence)]

    # Minimal content checks to prevent 1-line placeholders
    errors += must_contain_lines(root / "evidence" / "phase0" / "README.md", min_lines=8)
    errors += must_contain_lines(root / "evidence" / "phase0" / "break_glass" / "drill.md", min_lines=8)
    errors += must_be_valid_json(root / "evidence" / "phase0" / "keys" / "key_scope_probe.json")

    if errors:
        eprint("PHASE 0 META-TEST FAILED")
        for msg in errors:
            eprint(f"- {msg}")
        return 1

    print("PHASE 0 META-TEST OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
