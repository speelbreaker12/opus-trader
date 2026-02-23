#!/usr/bin/env python3
"""Render human-readable .md companion from external manifest JSON.

Usage: plans/render_external_manifest.py <manifest.json> [--output <path>]

Reads R3_EXTERNAL_MANIFEST.json or R7_EXTERNAL_MANIFEST.json and produces
a markdown summary suitable for human review. Output defaults to the same
directory as the input, with .json replaced by .md.

Exit codes:
  0 = success
  1 = render error
  2 = usage error
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def render(data: dict) -> str:
    """Render manifest dict to markdown string."""
    sv = data.get("schema_version", "unknown")
    cycle = data.get("cycle", "?")
    story = data.get("story_id", "?")
    basis = data.get("review_basis", "?")
    head = data.get("head_commit", "?")
    base = data.get("base_commit")
    status = data.get("validation_status", "?")
    created = data.get("created_at", "?")

    lines = [
        "---",
        "provenance:",
        "  tool: script",
        f"  schema_version: {sv}",
        "  model: n/a",
        "  prompt_style: none",
        f"  cycle: {cycle}",
        f"  phase_equivalent: {'R3' if cycle == 'C1' else 'R7d'}",
        f"  story_id: {story}",
        f'  head_commit: "{head}"',
        f'  generated_at: "{datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}"',
        '  artifact_provenance: "renderer-v1"',
        "---",
        "",
        f"# External Review Manifest — {story} (Cycle {cycle[-1]})",
        "",
        f"**Review basis**: {basis}",
        f"**Head commit**: `{head}`",
    ]

    if base:
        lines.append(f"**Base commit**: `{base}`")

    lines.extend([
        f"**Status**: {status}",
        f"**Generated**: {created}",
        "",
        "## Tools",
        "",
        "| Tool | Model | Enriched | Generic |",
        "|------|-------|----------|---------|",
    ])

    tools = data.get("tools", [])
    for t in tools:
        tool_name = t.get("tool", "?")
        model = t.get("model", "?")
        artifacts = t.get("artifacts", {})

        enriched = artifacts.get("enriched", {})
        generic = artifacts.get("generic", {})

        e_path = enriched.get("path", "?")
        e_ok = "exists" if enriched.get("exists") else "MISSING"
        g_path = generic.get("path", "?")
        g_ok = "exists" if generic.get("exists") else "MISSING"

        lines.append(f"| {tool_name} | {model} | `{e_path}` ({e_ok}) | `{g_path}` ({g_ok}) |")

    lines.append("")

    # C1-specific: citation validation
    if cycle == "C1":
        enf = data.get("validated_preexisting_enforcement_citation")
        test = data.get("validated_preexisting_test_citation")
        lines.extend([
            "## Citation Validation (Cycle 1)",
            "",
            f"- Pre-existing enforcement citation: **{'PASS' if enf else 'FAIL'}**",
            f"- Pre-existing test citation: **{'PASS' if test else 'FAIL'}**",
            "",
        ])

    # Summary
    total_tools = len(tools)
    all_exist = all(
        t.get("artifacts", {}).get(s, {}).get("exists") is True
        for t in tools
        for s in ("enriched", "generic")
    )

    lines.extend([
        "## Summary",
        "",
        f"- Tools: {total_tools}",
        f"- All artifacts present: **{'YES' if all_exist else 'NO'}**",
        f"- Validation status: **{status}**",
        "",
    ])

    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: render_external_manifest.py <manifest.json> [--output <path>]", file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    if not input_path.exists():
        print(f"File not found: {input_path}", file=sys.stderr)
        return 2

    # Determine output path
    output_path: Path
    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 >= len(sys.argv):
            print("--output requires a path argument", file=sys.stderr)
            return 2
        output_path = Path(sys.argv[idx + 1])
    else:
        output_path = input_path.with_suffix(".md")

    try:
        data = json.loads(input_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print("Root must be a JSON object", file=sys.stderr)
        return 1

    md = render(data)
    output_path.write_text(md, encoding="utf-8")
    print(f"OK: rendered {output_path.name} ({len(md)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
