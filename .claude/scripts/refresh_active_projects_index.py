#!/usr/bin/env python3
"""Generate a deterministic root Obsidian dashboard for local workspace links."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from urllib.parse import quote


def parse_frontmatter(content: str) -> tuple[dict[str, object], str]:
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, content

    frontmatter: dict[str, object] = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped == "---":
            return frontmatter, "\n".join(lines[i + 1 :])
        if not stripped:
            i += 1
            continue

        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", line)
        if not match:
            i += 1
            continue

        key = match.group(1)
        raw_value = (match.group(2) or "").strip()
        if raw_value.startswith("[") and raw_value.endswith("]"):
            items = [clean_scalar(item) for item in raw_value[1:-1].split(",") if clean_scalar(item)]
            frontmatter[key] = items
            i += 1
            continue

        if raw_value:
            frontmatter[key] = clean_scalar(raw_value)
            i += 1
            continue

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

    return frontmatter, content


def clean_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1].strip()
    return value


def fm_scalar(frontmatter: dict[str, object], key: str) -> str:
    value = frontmatter.get(key, "")
    if isinstance(value, list):
        return ", ".join(str(item).strip() for item in value if str(item).strip())
    return str(value).strip() if value is not None else ""


def file_uri(path: Path) -> str:
    return f"file://{quote(str(path.resolve()), safe=':/')}"


def safe_cell(value: str) -> str:
    return value.replace("|", "\\|")


def status_rank(status: str) -> int:
    value = status.lower()
    if value in {"in-progress", "in progress", "active", "implementing"}:
        return 0
    if value in {"blocked", "waiting", "pending", "review", "pausing"}:
        return 1
    if value in {"done", "completed", "closed"}:
        return 2
    return 3


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate obsidian/Active Projects.md from project notes.")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Repository root (defaults to current working directory).",
    )
    parser.add_argument(
        "--projects-dir",
        type=Path,
        default=None,
        help="Projects directory. Defaults to <repo-root>/obsidian/Projects.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output file. Defaults to <repo-root>/obsidian/Active Projects.md.",
    )

    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    projects_dir = args.projects_dir or (repo_root / "obsidian/Projects")
    output_path = args.output or (repo_root / "obsidian/Active Projects.md")

    rows = []
    for path in sorted(projects_dir.glob("*.md")):
        content = path.read_text(encoding="utf-8")
        frontmatter, _ = parse_frontmatter(content)
        status = fm_scalar(frontmatter, "status") or "unknown"
        worktree = fm_scalar(frontmatter, "worktree") or "unassigned"
        obsidian_path = fm_scalar(frontmatter, "worktree_obsidian") or ""
        if not obsidian_path and worktree not in {"", "unassigned"}:
            obsidian_path = str(Path(worktree) / "obsidian")

        obsidian_abs = repo_root / obsidian_path if obsidian_path else None
        if obsidian_abs is not None and obsidian_abs.exists():
            workspace_cell = f"[open]({file_uri(obsidian_abs)})"
        else:
            workspace_cell = f"`{safe_cell(obsidian_path or 'missing')}`"

        rows.append(
            {
                "name": path.stem,
                "status": status,
                "status_sort": status_rank(status),
                "branch": fm_scalar(frontmatter, "branch") or "unassigned",
                "worktree": worktree,
                "workspace_cell": workspace_cell,
            }
        )

    rows.sort(key=lambda row: (row["status_sort"], row["name"].lower()))

    lines: list[str] = []
    lines.append("# Active Projects")
    lines.append("")
    lines.append(
        "Generated from `obsidian/Projects/*.md` frontmatter so each project links directly to its local worktree notes."
    )
    lines.append("")
    lines.append("No branch-local note mirroring is performed into main.")
    lines.append("")
    lines.append("| Project | Status | Branch | Worktree | Obsidian Folder |")
    lines.append("| --- | --- | --- | --- | --- |")

    for row in rows:
        project_link = f"[[{safe_cell(row['name'])}]]"
        status = safe_cell(row["status"])
        branch = safe_cell(row["branch"])
        worktree = f"`{safe_cell(row['worktree'])}`"
        workspace = row["workspace_cell"]

        lines.append(f"| {project_link} | {status} | {branch} | {worktree} | {workspace} |")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
