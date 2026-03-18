#!/usr/bin/env python3
"""
tools/phase1_meta_test.py

Phase-1 CI meta-test: fail if required Phase-1 evidence/doc artifacts are missing.

What it enforces:
- Required Phase-1 docs exist (chokepoint + gate invariants + critical config keys)
- Required evidence pack root exists with required summary/link files
- Required proof artifacts exist (or crash-mid-intent has an allowed fallback)

Usage:
  python tools/phase1_meta_test.py

Optional:
  --root .                # repo root (default: cwd)
  --allow-crash-auto-only # if you have AUTO crash test and don't produce drill.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable, List


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def must_exist(paths: Iterable[Path]) -> List[str]:
    missing = []
    for p in paths:
        if not p.exists():
            missing.append(str(p))
    return missing


def must_be_nonempty_files(paths: Iterable[Path]) -> List[str]:
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


def must_be_valid_json(path: Path) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"{path} (invalid JSON: {e})"]
    # minimal sanity: must be object/dict or list and non-empty
    if obj is None:
        return [f"{path} (JSON is null)"]
    if isinstance(obj, (dict, list)) and len(obj) == 0:
        return [f"{path} (JSON is empty)"]
    return []


def must_contain_lines(path: Path, min_lines: int) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    text = read_text(path).strip()
    if not text:
        return [f"{path} (empty)"]
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) < min_lines:
        return [f"{path} (too few lines: {len(lines)} < {min_lines})"]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="Repo root (default: cwd)")
    ap.add_argument(
        "--allow-crash-auto-only",
        action="store_true",
        help="Do not require manual crash drill.md (assumes AUTO crash test exists).",
    )
    args = ap.parse_args()

    root = Path(args.root).resolve()

    # ---- Required repo docs (MANUAL artifacts) ----
    required_docs = [
        root / "docs" / "dispatch_chokepoint.md",
        root / "docs" / "intent_gate_invariants.md",
        root / "docs" / "critical_config_keys.md",
    ]

    # ---- Required evidence pack summary files (MANUAL) ----
    required_phase1_pack = [
        root / "evidence" / "phase1" / "README.md",
        root / "evidence" / "phase1" / "ci_links.md",
    ]

    # ---- Required proof artifacts (AUTO/MANUAL outputs) ----
    required_proof_artifacts = [
        # determinism
        root / "evidence" / "phase1" / "determinism" / "intent_hashes.txt",
        # no-side-effects
        root / "evidence" / "phase1" / "no_side_effects" / "rejection_cases.md",
        # traceability
        root / "evidence" / "phase1" / "traceability" / "sample_rejection_log.txt",
        # config fail-closed
        root / "evidence" / "phase1" / "config_fail_closed" / "missing_keys_matrix.json",
    ]

    # ---- Crash-mid-intent: AUTO preferred; MANUAL fallback allowed ----
    crash_drill = root / "evidence" / "phase1" / "crash_mid_intent" / "drill.md"
    crash_auto_marker = root / "evidence" / "phase1" / "crash_mid_intent" / "auto_test_passed.txt"
    # If you implement AUTO crash test, have it write auto_test_passed.txt.

    errors: List[str] = []

    # Check docs exist and are non-empty
    errors += [f"Missing required doc: {p}" for p in must_exist(required_docs)]
    errors += [f"Bad required doc: {p}" for p in must_be_nonempty_files(required_docs)]

    # Check evidence pack root files
    errors += [f"Missing Phase-1 evidence pack file: {p}" for p in must_exist(required_phase1_pack)]
    errors += [f"Bad Phase-1 evidence pack file: {p}" for p in must_be_nonempty_files(required_phase1_pack)]

    # Proof artifacts exist and have minimal content
    errors += [f"Missing proof artifact: {p}" for p in must_exist(required_proof_artifacts)]
    # Minimal content checks
    errors += must_contain_lines(root / "evidence" / "phase1" / "determinism" / "intent_hashes.txt", min_lines=2)
    errors += must_contain_lines(root / "evidence" / "phase1" / "traceability" / "sample_rejection_log.txt", min_lines=5)
    errors += must_be_valid_json(root / "evidence" / "phase1" / "config_fail_closed" / "missing_keys_matrix.json")

    # Crash-mid-intent proof: either AUTO marker OR manual drill
    if args.allow_crash_auto_only:
        # Require the AUTO marker
        if not crash_auto_marker.exists():
            errors.append(
                f"Crash-mid-intent AUTO proof missing: expected {crash_auto_marker} "
                "(have your AUTO test write this file on success)"
            )
    else:
        # Require either AUTO marker OR manual drill.md
        if not crash_auto_marker.exists() and not crash_drill.exists():
            errors.append(
                "Crash-mid-intent proof missing: need either "
                f"{crash_auto_marker} (AUTO) OR {crash_drill} (MANUAL)."
            )
        if crash_drill.exists():
            errors += must_contain_lines(crash_drill, min_lines=5)

    if errors:
        print("PHASE 1 META-TEST FAILED", file=sys.stderr)
        for msg in errors:
            print(f"- {msg}", file=sys.stderr)
        return 1

    print("PHASE 1 META-TEST OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
