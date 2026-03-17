#!/usr/bin/env python3
"""Validate reconciliation step report JSON (fail-closed for weak reports).

Exit codes:
  0 = valid
  1 = invalid content
  2 = usage error
  3 = report file missing
  4 = invalid JSON / schema load error
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import jsonschema  # type: ignore

    HAS_JSONSCHEMA = True
except Exception:  # pragma: no cover - optional dependency
    HAS_JSONSCHEMA = False


STEP_INDEX = {
    "preflight": 0,
    "implement": 1,
    "self_review": 2,
    "cycle1": 3,
    "fix": 4,
    "cycle2": 5,
    "resolution": 6,
    "verify_full": 7,
    "pass": 8,
}

HAND_WAVY = {
    "",
    "n/a",
    "na",
    "unknown",
    "tbd",
    "todo",
    "none provided",
    "not sure",
    "unsure",
    "maybe",
}
PLACEHOLDER_RE = re.compile(r"\{\{.+\}\}|<[^>]+>|^\s*todo\b|^\s*tbd\b", re.IGNORECASE)


def _is_hand_wavy(text: str, *, allow_none: bool = False) -> bool:
    raw = text.strip()
    lowered = raw.lower()
    if allow_none and lowered == "none":
        return False
    if lowered in HAND_WAVY:
        return True
    if PLACEHOLDER_RE.search(raw):
        return True
    return False


def _schema_default() -> Path:
    return (
        Path(__file__).resolve().parent.parent
        / "specs"
        / "schemas"
        / "recon"
        / "recon_step_report.schema.json"
    )


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("report JSON must be an object")
    return data


def _validate_schema(data: dict[str, Any], schema_path: Path, errors: list[str]) -> None:
    if not schema_path.exists():
        errors.append(f"schema file not found: {schema_path}")
        return
    try:
        with schema_path.open("r", encoding="utf-8") as f:
            schema = json.load(f)
    except json.JSONDecodeError as exc:
        errors.append(f"schema JSON invalid: {exc}")
        return

    if not HAS_JSONSCHEMA:
        # Keep validator dependency-optional.
        return

    try:
        jsonschema.validate(instance=data, schema=schema)
    except jsonschema.ValidationError as exc:  # type: ignore[attr-defined]
        errors.append(f"schema validation failed: {exc.message}")
    except jsonschema.SchemaError as exc:  # type: ignore[attr-defined]
        errors.append(f"schema invalid: {exc.message}")


def _validate_semantics(data: dict[str, Any], errors: list[str]) -> None:
    step_name = str(data.get("step_name", ""))
    step_index = data.get("step_index")
    expected = STEP_INDEX.get(step_name)
    if expected is None:
        errors.append(f"unknown step_name: {step_name!r}")
    elif step_index != expected:
        errors.append(f"step_index mismatch for {step_name!r}: got {step_index!r}, expected {expected}")

    commands = data.get("commands_run")
    if not isinstance(commands, list) or not commands:
        errors.append("commands_run must contain at least one command")
    else:
        for i, cmd in enumerate(commands):
            if not isinstance(cmd, str) or _is_hand_wavy(cmd):
                errors.append(f"commands_run[{i}] is empty/hand-wavy")

    files_changed = data.get("files_changed")
    if not isinstance(files_changed, list) or not files_changed:
        errors.append("files_changed must contain at least one entry")
    else:
        for i, path in enumerate(files_changed):
            if not isinstance(path, str) or _is_hand_wavy(path, allow_none=True):
                errors.append(f"files_changed[{i}] is empty/hand-wavy")

    strongest = str(data.get("strongest_evidence", ""))
    if _is_hand_wavy(strongest) or len(strongest.strip()) < 8:
        errors.append("strongest_evidence is empty/hand-wavy")

    not_done = str(data.get("not_done", ""))
    if _is_hand_wavy(not_done, allow_none=True):
        errors.append("not_done is empty/hand-wavy")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate reconciliation step report JSON.")
    parser.add_argument("report_json", help="Path to recon step report JSON")
    parser.add_argument(
        "--schema",
        default=str(_schema_default()),
        help="Path to JSON schema (default: specs/schemas/recon/recon_step_report.schema.json)",
    )
    args = parser.parse_args()

    report_path = Path(args.report_json)
    schema_path = Path(args.schema)

    if not report_path.exists():
        print(f"ERROR: report file not found: {report_path}", file=sys.stderr)
        return 3

    try:
        data = _load_json(report_path)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON: {exc}", file=sys.stderr)
        return 4
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 4

    errors: list[str] = []
    _validate_schema(data, schema_path, errors)
    _validate_semantics(data, errors)

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"OK: step report valid: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
