#!/usr/bin/env python3
"""
Artifact Loader Utilities.

Extracts Slices from IMPLEMENTATION_PLAN.md, PRD items from prd.json,
and loads code files for the downstream patch suggester.

Usage:
    from scripts.utils.artifact_loader import (
        extract_slice,
        extract_prd_item,
        load_file_content,
        extract_contract_clause,
    )
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


def extract_slice(plan_path: Path, slice_ref: str) -> Optional[str]:
    """
    Extract a Slice section from IMPLEMENTATION_PLAN.md.

    Args:
        plan_path: Path to IMPLEMENTATION_PLAN.md
        slice_ref: Reference like "Slice-7" or "#Slice-7"

    Returns:
        Extracted slice content or None if not found
    """
    # Normalize slice reference
    slice_num = slice_ref.replace("#", "").replace("Slice-", "")

    try:
        content = plan_path.read_text(encoding="utf-8")
    except Exception:
        return None

    # Pattern to find Slice N header and capture until next Slice or Phase
    # Slices are formatted as "Slice N — Title" or "Slice N —"
    slice_pattern = rf'(Slice\s+{slice_num}\s*[—\-].+?)(?=\nSlice\s+\d+\s*[—\-]|\nPHASE\s+\d+|\Z)'

    match = re.search(slice_pattern, content, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()

    # Try alternate pattern with markdown headers
    slice_pattern_alt = rf'(#+\s*Slice\s+{slice_num}.+?)(?=\n#+\s*Slice\s+\d+|\n#+\s*PHASE|\Z)'
    match = re.search(slice_pattern_alt, content, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return None


def extract_story(plan_path: Path, story_ref: str) -> Optional[str]:
    """
    Extract a Story section (S{slice}.{n}) from IMPLEMENTATION_PLAN.md.

    Args:
        plan_path: Path to IMPLEMENTATION_PLAN.md
        story_ref: Reference like "S7.1" or "#S7.1"

    Returns:
        Extracted story content or None if not found
    """
    # Normalize story reference
    story_id = story_ref.replace("#", "").upper()
    if not story_id.startswith("S"):
        story_id = f"S{story_id}"

    try:
        content = plan_path.read_text(encoding="utf-8")
    except Exception:
        return None

    # Pattern to find Story header and capture until next Story
    # Stories are formatted as "S7.1 — Title" or just "S7.1"
    story_pattern = rf'({re.escape(story_id)}\s*[—\-].+?)(?=\nS\d+\.\d+\s*[—\-]|\nSlice\s+\d+|\nPHASE|\Z)'

    match = re.search(story_pattern, content, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return None


def load_file_content(file_path: Path, base_path: Optional[Path] = None) -> Optional[str]:
    """
    Load content from a file path.

    Args:
        file_path: Path to the file (can be relative)
        base_path: Base directory to resolve relative paths

    Returns:
        File content or None if not found
    """
    # Handle relative paths
    if not file_path.is_absolute():
        if base_path:
            file_path = base_path / file_path
        else:
            file_path = Path.cwd() / file_path

    try:
        return file_path.read_text(encoding="utf-8")
    except Exception:
        return None


def extract_contract_clause(
    contract_path: Path,
    clause_id: str,
) -> Optional[str]:
    """
    Extract a CSP clause section from CONTRACT.md.

    Args:
        contract_path: Path to CONTRACT.md
        clause_id: Clause ID like "CSP-007"

    Returns:
        Extracted clause content or None if not found
    """
    try:
        content = contract_path.read_text(encoding="utf-8")
    except Exception:
        return None

    # Find the clause marker and extract surrounding content
    # Look for <!-- CSP-XXX --> marker and get the section
    marker = f"<!-- {clause_id} -->"
    marker_pos = content.find(marker)

    if marker_pos == -1:
        return None

    # Find section start (look backwards for **X) header)
    section_start = content.rfind("\n**", 0, marker_pos)
    if section_start == -1:
        section_start = content.rfind("\n####", 0, marker_pos)
    if section_start == -1:
        section_start = max(0, marker_pos - 200)  # Fallback: 200 chars before

    # Find section end (next **X) header or next CSP marker)
    next_section = content.find("\n**", marker_pos + len(marker))
    next_csp = content.find("<!-- CSP-", marker_pos + len(marker))

    if next_section == -1:
        next_section = len(content)
    if next_csp == -1:
        next_csp = len(content)

    section_end = min(next_section, next_csp)

    return content[section_start:section_end].strip()


def get_clause_diff(
    contract_path: Path,
    clause_id: str,
    base_ref: str = "origin/main",
) -> Optional[str]:
    """
    Get unified diff of a specific clause between current and base ref.

    Args:
        contract_path: Path to CONTRACT.md
        clause_id: Clause ID like "CSP-007"
        base_ref: Git ref for comparison

    Returns:
        Unified diff of the clause section or None
    """
    import subprocess
    import tempfile

    # Get current clause content
    current_clause = extract_contract_clause(contract_path, clause_id)
    if not current_clause:
        return None

    # Get base clause content
    try:
        result = subprocess.run(
            ["git", "show", f"{base_ref}:{contract_path}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return None

        base_content = result.stdout
    except Exception:
        return None

    # Extract clause from base content
    marker = f"<!-- {clause_id} -->"
    marker_pos = base_content.find(marker)

    if marker_pos == -1:
        # Clause was added (not in base)
        base_clause = ""
    else:
        # Extract using same logic
        section_start = base_content.rfind("\n**", 0, marker_pos)
        if section_start == -1:
            section_start = base_content.rfind("\n####", 0, marker_pos)
        if section_start == -1:
            section_start = max(0, marker_pos - 200)

        next_section = base_content.find("\n**", marker_pos + len(marker))
        next_csp = base_content.find("<!-- CSP-", marker_pos + len(marker))

        if next_section == -1:
            next_section = len(base_content)
        if next_csp == -1:
            next_csp = len(base_content)

        section_end = min(next_section, next_csp)
        base_clause = base_content[section_start:section_end].strip()

    # Generate diff
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f_base:
        f_base.write(base_clause)
        base_file = f_base.name

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f_current:
        f_current.write(current_clause)
        current_file = f_current.name

    try:
        result = subprocess.run(
            ["diff", "-u", base_file, current_file],
            capture_output=True,
            text=True,
            check=False,
        )
        diff = result.stdout

        # Clean up header lines with temp file names
        lines = diff.split("\n")
        if len(lines) >= 2:
            lines[0] = f"--- a/{clause_id}"
            lines[1] = f"+++ b/{clause_id}"
            diff = "\n".join(lines)

        return diff if diff.strip() else None
    finally:
        Path(base_file).unlink(missing_ok=True)
        Path(current_file).unlink(missing_ok=True)


def parse_artifact_path(artifact_ref: str) -> Tuple[str, Optional[str]]:
    """
    Parse an artifact reference from TRACE.yaml.

    Args:
        artifact_ref: Reference like "specs/IMPLEMENTATION_PLAN.md#Slice-7"

    Returns:
        Tuple of (file_path, anchor_or_none)
    """
    if "#" in artifact_ref:
        path, anchor = artifact_ref.split("#", 1)
        return path, anchor
    return artifact_ref, None


def extract_prd_item(prd_path: Path, item_id: str) -> Optional[Dict[str, Any]]:
    """
    Extract a PRD item from prd.json by its ID.

    Args:
        prd_path: Path to prd.json
        item_id: Item ID like "S2-001" or "#S2-001"

    Returns:
        The PRD item dict or None if not found
    """
    # Normalize item ID
    item_id = item_id.lstrip("#")

    try:
        content = json.loads(prd_path.read_text(encoding="utf-8"))
    except Exception:
        return None

    items = content.get("items", [])
    for item in items:
        if item.get("id") == item_id:
            return item

    return None


def format_prd_item_for_patch(item: Dict[str, Any]) -> str:
    """
    Format a PRD item as text for patching context.

    Args:
        item: PRD item dict

    Returns:
        Formatted text representation of the PRD item
    """
    lines = []
    lines.append(f"PRD Item: {item.get('id', 'unknown')}")
    lines.append(f"Story: {item.get('story_ref', 'N/A')}")
    lines.append(f"Category: {item.get('category', 'N/A')}")
    lines.append(f"Description: {item.get('description', 'N/A')}")
    lines.append("")

    # Contract references
    contract_refs = item.get("contract_refs", [])
    if contract_refs:
        lines.append("Contract References:")
        for ref in contract_refs:
            lines.append(f"  - {ref}")
        lines.append("")

    # Plan references
    plan_refs = item.get("plan_refs", [])
    if plan_refs:
        lines.append("Plan References:")
        for ref in plan_refs:
            lines.append(f"  - {ref}")
        lines.append("")

    # Acceptance criteria
    acceptance = item.get("acceptance", [])
    if acceptance:
        lines.append("Acceptance Criteria:")
        for criterion in acceptance:
            lines.append(f"  - {criterion}")
        lines.append("")

    # Steps
    steps = item.get("steps", [])
    if steps:
        lines.append("Steps:")
        for i, step in enumerate(steps, 1):
            lines.append(f"  {i}. {step}")
        lines.append("")

    return "\n".join(lines)


def get_prd_item_json(prd_path: Path, item_id: str) -> Optional[str]:
    """
    Get the JSON representation of a PRD item for patching.

    Args:
        prd_path: Path to prd.json
        item_id: Item ID like "S2-001"

    Returns:
        JSON string of the item, or None if not found
    """
    item = extract_prd_item(prd_path, item_id)
    if not item:
        return None

    return json.dumps(item, indent=2)
