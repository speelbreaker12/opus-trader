"""
Shared Obsidian frontmatter parser.

Single implementation used by:
- plans/project_scope_guard.sh (both Python blocks)
- .claude/hooks/obsidian-context-hook.sh

Import with:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from obsidian_frontmatter import parse_frontmatter, clean_scalar, frontmatter_scalar
"""

import re
from typing import Any


def clean_scalar(value: Any) -> Any:
    """Strip quotes from a scalar value. Pass through lists recursively."""
    if isinstance(value, list):
        return [clean_scalar(item) for item in value]
    value = str(value).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1].strip()
    return value


def parse_frontmatter(content: str) -> dict:
    """Parse YAML-like frontmatter between --- delimiters.

    Handles:
    - Scalar values: key: value
    - Inline lists: key: [a, b, c]
    - Block lists: key:\\n  - a\\n  - b
    - Quoted values (single or double)
    """
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    frontmatter: dict = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped == "---":
            break
        if not stripped:
            i += 1
            continue

        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", line)
        if not match:
            i += 1
            continue

        key = match.group(1)
        raw_value = (match.group(2) or "").strip()

        # Inline list: [a, b, c]
        if raw_value.startswith("[") and raw_value.endswith("]"):
            items = [
                clean_scalar(part)
                for part in raw_value[1:-1].split(",")
                if clean_scalar(part)
            ]
            frontmatter[key] = items
            i += 1
            continue

        # Scalar value
        if raw_value:
            frontmatter[key] = clean_scalar(raw_value)
            i += 1
            continue

        # Block list (indented - items)
        items: list[str] = []
        j = i + 1
        while j < len(lines):
            next_line = lines[j]
            next_stripped = next_line.strip()
            if next_stripped == "---":
                break
            if re.match(r"^[A-Za-z0-9_-]+:\s*", next_line):
                break
            if next_stripped.startswith("- "):
                items.append(clean_scalar(next_stripped[2:]))
                j += 1
                continue
            if next_stripped:
                break
            j += 1

        frontmatter[key] = items
        i = j

    return frontmatter


def frontmatter_scalar(frontmatter: dict, key: str) -> str:
    """Extract a scalar string from frontmatter, handling list-wrapped values."""
    value = frontmatter.get(key, "")
    if isinstance(value, list):
        return clean_scalar(value[0]) if value else ""
    return clean_scalar(value)


def frontmatter_list(frontmatter: dict, key: str) -> list[str]:
    """Extract a list from frontmatter, normalizing single-value entries."""
    value = frontmatter.get(key, [])
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []
