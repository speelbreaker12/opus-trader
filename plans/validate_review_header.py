#!/usr/bin/env python3
"""Validate YAML front matter provenance on review artifacts.

Usage: plans/validate_review_header.py <artifact.md> [--strict]

Checks:
  1. YAML front matter exists (--- delimited)
  2. provenance: block present
  3. 5 mandatory fields present and valid
  4. --strict: all 13 fields present

Exit codes:
  0 = valid
  1 = invalid (stderr has field-level errors)
  2 = usage error
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Optional

MANDATORY_FIELDS = {"tool", "model", "prompt_style", "cycle", "phase_equivalent"}

FULL_FIELDS = MANDATORY_FIELDS | {
    "review_basis", "story_id", "slice_id", "head_commit",
    "base_commit", "generated_at", "artifact_provenance", "schema_version",
}

VALID_TOOLS = {"codex", "opus", "kimi", "internal", "script"}
VALID_PROMPT_STYLES = {"generic", "enriched", "none"}
VALID_CYCLES = {"C1", "C2", "SELF", "NONE"}
VALID_PHASES = {
    "R1", "R2", "R3", "R4", "R4b", "R5", "R5b", "R6",
    "R7a", "R7b", "R7c", "R7d", "R7e", "R7f",
}


def extract_front_matter(text: str) -> Optional[str]:
    """Extract YAML front matter between --- delimiters."""
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    return m.group(1) if m else None


def parse_yaml_simple(yaml_text: str) -> dict[str, str]:
    """Minimal YAML parser for flat provenance block.

    Handles:
      provenance:
        key: value
        key: "quoted value"
    """
    result: dict[str, str] = {}
    in_provenance = False
    for line in yaml_text.splitlines():
        stripped = line.strip()
        if stripped == "provenance:":
            in_provenance = True
            continue
        if in_provenance:
            if not line.startswith("  ") and stripped:
                break  # exited provenance block
            m = re.match(r'\s+(\w+):\s+"?([^"]*)"?\s*$', line)
            if m:
                result[m.group(1)] = m.group(2)
    return result


def validate(path: Path, strict: bool = False) -> list[str]:
    """Validate provenance header. Returns list of errors (empty = valid)."""
    errors: list[str] = []

    text = path.read_text(encoding="utf-8")
    fm = extract_front_matter(text)
    if fm is None:
        errors.append("Missing YAML front matter (--- delimiters)")
        return errors

    fields = parse_yaml_simple(fm)
    if not fields:
        errors.append("No provenance: block found in front matter")
        return errors

    # Check mandatory fields
    required = FULL_FIELDS if strict else MANDATORY_FIELDS
    for field in sorted(required):
        if field == "base_commit":
            # base_commit only required for C2
            if fields.get("cycle") == "C2" and field not in fields:
                errors.append(f"Missing mandatory field: {field} (required for C2)")
            continue
        if field not in fields:
            errors.append(f"Missing mandatory field: {field}")

    # Validate enum values
    if "tool" in fields and fields["tool"] not in VALID_TOOLS:
        errors.append(f"Invalid tool: {fields['tool']} (valid: {', '.join(sorted(VALID_TOOLS))})")
    if "prompt_style" in fields and fields["prompt_style"] not in VALID_PROMPT_STYLES:
        errors.append(f"Invalid prompt_style: {fields['prompt_style']} (valid: {', '.join(sorted(VALID_PROMPT_STYLES))})")
    if "cycle" in fields and fields["cycle"] not in VALID_CYCLES:
        errors.append(f"Invalid cycle: {fields['cycle']} (valid: {', '.join(sorted(VALID_CYCLES))})")
    if "phase_equivalent" in fields and fields["phase_equivalent"] not in VALID_PHASES:
        errors.append(f"Invalid phase_equivalent: {fields['phase_equivalent']} (valid: {', '.join(sorted(VALID_PHASES))})")

    # Validate head_commit length
    if "head_commit" in fields and len(fields["head_commit"]) < 7:
        errors.append(f"head_commit too short: {fields['head_commit']} (min 7 chars)")

    return errors


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: validate_review_header.py <artifact.md> [--strict]", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        return 2

    strict = "--strict" in sys.argv

    errors = validate(path, strict=strict)
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1

    print(f"OK: {path.name} — provenance valid ({'strict' if strict else 'basic'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
