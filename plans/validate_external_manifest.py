#!/usr/bin/env python3
"""Validate external review manifest completeness.

Usage: plans/validate_external_manifest.py <manifest.json> [--check-files]

Checks:
  1. JSON parses and matches schema structure
  2. schema_version is r3_external_manifest.v1 or r7_external_manifest.v1
  3. All required fields present and non-null
  4. At least 1 tool entry
  5. Each tool has both enriched and generic artifacts
  6. Cycle-specific validations:
     - C1: validated_preexisting_enforcement_citation + test_citation must be true
     - C2: base_commit must be present
  7. --check-files: verify artifact paths exist relative to manifest directory

Exit codes:
  0 = valid
  1 = invalid (stderr has field-level errors)
  2 = usage error
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

VALID_TOOLS = {"codex", "opus", "kimi"}
VALID_STATUSES = {"completed", "partial", "failed"}

C1_REQUIRED = {
    "schema_version", "head_commit", "created_at", "story_id", "cycle",
    "review_basis", "tools", "validated_preexisting_enforcement_citation",
    "validated_preexisting_test_citation", "validation_status",
}

C2_REQUIRED = {
    "schema_version", "head_commit", "created_at", "story_id", "cycle",
    "review_basis", "base_commit", "tools", "validation_status",
}


def validate(manifest_path: Path, check_files: bool = False) -> list[str]:
    """Validate manifest JSON. Returns list of errors (empty = valid)."""
    errors: list[str] = []

    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        errors.append(f"Invalid JSON: {e}")
        return errors

    if not isinstance(data, dict):
        errors.append("Root must be a JSON object")
        return errors

    # Determine cycle from schema_version
    sv = data.get("schema_version", "")
    if sv == "r3_external_manifest.v1":
        required = C1_REQUIRED
        expected_cycle = "C1"
    elif sv == "r7_external_manifest.v1":
        required = C2_REQUIRED
        expected_cycle = "C2"
    else:
        errors.append(f"Unknown schema_version: {sv} (expected r3_external_manifest.v1 or r7_external_manifest.v1)")
        return errors

    # Check required fields
    for field in sorted(required):
        if field not in data:
            errors.append(f"Missing required field: {field}")
        elif data[field] is None:
            errors.append(f"Null value for required field: {field}")

    # Validate cycle
    if data.get("cycle") != expected_cycle:
        errors.append(f"cycle mismatch: got {data.get('cycle')!r}, expected {expected_cycle!r}")

    # Validate head_commit length
    hc = data.get("head_commit", "")
    if isinstance(hc, str) and len(hc) < 7:
        errors.append(f"head_commit too short: {hc!r} (min 7 chars)")

    # C2: validate base_commit
    if expected_cycle == "C2":
        bc = data.get("base_commit", "")
        if isinstance(bc, str) and len(bc) < 7:
            errors.append(f"base_commit too short: {bc!r} (min 7 chars)")

    # C1: validate citation booleans
    if expected_cycle == "C1":
        if data.get("validated_preexisting_enforcement_citation") is not True:
            errors.append("validated_preexisting_enforcement_citation must be true for C1")
        if data.get("validated_preexisting_test_citation") is not True:
            errors.append("validated_preexisting_test_citation must be true for C1")

    # Validate tools array
    tools = data.get("tools", [])
    if not isinstance(tools, list):
        errors.append("tools must be an array")
        return errors
    if len(tools) == 0:
        errors.append("tools array must have at least 1 entry")

    manifest_dir = manifest_path.parent
    for i, tool_entry in enumerate(tools):
        if not isinstance(tool_entry, dict):
            errors.append(f"tools[{i}]: must be an object")
            continue

        tool_name = tool_entry.get("tool", "")
        if tool_name not in VALID_TOOLS:
            errors.append(f"tools[{i}].tool: invalid {tool_name!r} (valid: {', '.join(sorted(VALID_TOOLS))})")

        if "model" not in tool_entry:
            errors.append(f"tools[{i}].model: missing")

        artifacts = tool_entry.get("artifacts", {})
        if not isinstance(artifacts, dict):
            errors.append(f"tools[{i}].artifacts: must be an object")
            continue

        for style in ("enriched", "generic"):
            art = artifacts.get(style)
            if art is None:
                errors.append(f"tools[{i}].artifacts.{style}: missing")
                continue
            if not isinstance(art, dict):
                errors.append(f"tools[{i}].artifacts.{style}: must be an object")
                continue

            art_path = art.get("path", "")
            art_exists = art.get("exists")

            expected_name = f"{tool_name}.{style}.md"
            if art_path != expected_name:
                errors.append(f"tools[{i}].artifacts.{style}.path: expected {expected_name!r}, got {art_path!r}")

            if art_exists is not True:
                errors.append(f"tools[{i}].artifacts.{style}.exists: expected true, got {art_exists!r}")

            # Optionally check file on disk
            if check_files and art_path:
                full_path = manifest_dir / art_path
                if not full_path.exists():
                    errors.append(f"tools[{i}].artifacts.{style}: file not found: {full_path}")

    # Validate validation_status
    vs = data.get("validation_status", "")
    if vs not in VALID_STATUSES:
        errors.append(f"validation_status: invalid {vs!r} (valid: {', '.join(sorted(VALID_STATUSES))})")

    return errors


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: validate_external_manifest.py <manifest.json> [--check-files]", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        return 2

    check_files = "--check-files" in sys.argv

    errors = validate(path, check_files=check_files)
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1

    sv = json.loads(path.read_text(encoding="utf-8")).get("schema_version", "?")
    print(f"OK: {path.name} — manifest valid ({sv})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
