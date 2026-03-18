#!/usr/bin/env python3
"""Render R3/R7 external manifest JSON as human-readable markdown.

Usage:
    render_external_manifest.py <manifest.json>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def render_provenance(prov: dict[str, Any]) -> str:
    """Render top-level provenance as YAML-style front matter."""
    lines = ["---"]
    for key in [
        "tool", "model", "prompt_style", "cycle", "phase_equivalent",
        "review_basis", "story_id", "slice_id", "head_commit", "base_commit",
        "generated_at", "artifact_provenance", "schema_version",
    ]:
        if key in prov:
            lines.append(f"{key}: {prov[key]}")
    lines.append("---")
    return "\n".join(lines)


def render_reviews_table(reviews: list[dict[str, Any]], manifest_type: str) -> str:
    """Render reviews[] as a markdown table."""
    lines: list[str] = []
    lines.append("## Reviews")
    lines.append("")

    if manifest_type == "r3":
        lines.append(
            "| # | Tool | Prompt | Model | Phase | SHA256 (trunc) | "
            "Basis | Enforce | Test | DiffReject |"
        )
        lines.append(
            "|---|------|--------|-------|-------|----------------|"
            "------|---------|------|------------|"
        )
        for i, r in enumerate(reviews):
            sha_trunc = r.get("artifact_sha256", "")[:12] + "..."
            checks = r.get("checks", {})
            lines.append(
                f"| {i+1} "
                f"| {r.get('tool', '?')} "
                f"| {r.get('prompt_style', '?')} "
                f"| {r.get('model', '?')} "
                f"| {r.get('phase_equivalent', '?')} "
                f"| `{sha_trunc}` "
                f"| {_bool_icon(checks.get('review_basis_present'))} "
                f"| {_bool_icon(checks.get('preexisting_enforcement_citation_present'))} "
                f"| {_bool_icon(checks.get('preexisting_test_citation_present'))} "
                f"| {_bool_icon(checks.get('diff_only_review_rejected'))} |"
            )
    else:  # r7
        lines.append(
            "| # | Tool | Prompt | Model | Phase | SHA256 (trunc) | "
            "Basis | HeadMatch | BaseMatch |"
        )
        lines.append(
            "|---|------|--------|-------|-------|----------------|"
            "------|-----------|-----------|"
        )
        for i, r in enumerate(reviews):
            sha_trunc = r.get("artifact_sha256", "")[:12] + "..."
            checks = r.get("checks", {})
            lines.append(
                f"| {i+1} "
                f"| {r.get('tool', '?')} "
                f"| {r.get('prompt_style', '?')} "
                f"| {r.get('model', '?')} "
                f"| {r.get('phase_equivalent', '?')} "
                f"| `{sha_trunc}` "
                f"| {_bool_icon(checks.get('review_basis_present'))} "
                f"| {_bool_icon(checks.get('head_commit_matches_manifest'))} "
                f"| {_bool_icon(checks.get('base_commit_matches_manifest'))} |"
            )

    # Artifact paths
    lines.append("")
    lines.append("### Artifact Paths")
    lines.append("")
    for i, r in enumerate(reviews):
        lines.append(f"- [{i+1}] `{r.get('artifact_path', '?')}`")

    return "\n".join(lines)


def render_validation(val: dict[str, Any], manifest_type: str) -> str:
    """Render validation section as PASS/FAIL table."""
    lines: list[str] = []
    lines.append("## Validation")
    lines.append("")
    lines.append(f"**Overall status: {val.get('status', '?')}**")
    lines.append("")
    lines.append("| Check | Result |")
    lines.append("|-------|--------|")

    if manifest_type == "r3":
        check_keys = [
            "review_basis_check",
            "preexisting_enforcement_citation_check",
            "preexisting_test_citation_check",
            "diff_only_review_check",
        ]
    else:
        check_keys = [
            "review_basis_check",
            "required_combinations_check",
            "head_commit_alignment_check",
            "base_commit_alignment_check",
        ]

    for ck in check_keys:
        result = val.get(ck, "?")
        icon = "PASS" if result == "PASS" else "FAIL" if result == "FAIL" else "?"
        lines.append(f"| {ck} | {icon} |")

    errors = val.get("errors", [])
    if errors:
        lines.append("")
        lines.append("### Errors")
        lines.append("")
        for e in errors:
            lines.append(f"- {e}")

    return "\n".join(lines)


def render_regression_scope(rs: dict[str, Any]) -> str:
    """Render R7 regression_scope section."""
    lines: list[str] = []
    lines.append("## Regression Scope")
    lines.append("")
    lines.append(f"- **Base commit:** `{rs.get('base_commit', '?')}`")
    lines.append(f"- **Head commit:** `{rs.get('head_commit', '?')}`")
    lines.append("")

    ats = rs.get("affected_ats", [])
    if ats:
        lines.append("### Affected ATs")
        lines.append("")
        for at in ats:
            lines.append(f"- {at}")
        lines.append("")

    files = rs.get("changed_files", [])
    if files:
        lines.append("### Changed Files")
        lines.append("")
        for f in files:
            lines.append(f"- `{f}`")

    return "\n".join(lines)


def render_required_combos(combos: list[dict[str, Any]]) -> str:
    """Render required_combinations as a short list."""
    lines: list[str] = []
    lines.append("## Required Combinations")
    lines.append("")
    for c in combos:
        lines.append(f"- {c.get('tool', '?')} x {c.get('prompt_style', '?')}")
    return "\n".join(lines)


def _bool_icon(val: Any) -> str:
    if val is True:
        return "PASS"
    if val is False:
        return "FAIL"
    return "?"


def render(data: dict[str, Any]) -> str:
    """Render a complete manifest to markdown."""
    phase = data.get("phase", "?")
    cycle = data.get("cycle", "?")
    story = data.get("story_id", "?")
    slice_id = data.get("slice_id", "?")
    manifest_type = "r3" if phase == "R3" else "r7"

    sections: list[str] = []

    # Header
    sections.append(f"# {phase} External Manifest — {story} ({slice_id}, {cycle})")

    # Provenance
    prov = data.get("provenance", {})
    if prov:
        sections.append(render_provenance(prov))

    # Required combos
    combos = data.get("required_combinations", [])
    if combos:
        sections.append(render_required_combos(combos))

    # Reviews
    reviews = data.get("reviews", [])
    if reviews:
        sections.append(render_reviews_table(reviews, manifest_type))

    # Regression scope (R7 only)
    if manifest_type == "r7":
        rs = data.get("regression_scope", {})
        if rs:
            sections.append(render_regression_scope(rs))

    # Validation
    val = data.get("validation", {})
    if val:
        sections.append(render_validation(val, manifest_type))

    return "\n\n".join(sections) + "\n"


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: render_external_manifest.py <manifest.json>", file=sys.stderr)
        return 2

    manifest_path = Path(sys.argv[1])
    if not manifest_path.exists():
        print(f"ERROR: file not found: {manifest_path}", file=sys.stderr)
        return 1

    try:
        with open(manifest_path) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON: {e}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print("ERROR: manifest must be a JSON object", file=sys.stderr)
        return 1

    print(render(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
