#!/usr/bin/env python3
"""Generate a slice-level reconciliation scoreboard.

Produces both human-readable markdown and JSON summaries from PRD + wf_step receipts.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

STEPS: tuple[str, ...] = (
    "preflight",
    "implement",
    "self_review",
    "cycle1",
    "fix",
    "cycle2",
    "resolution",
    "verify_full",
    "pass",
)

STATUS_DONE = "DONE"
STATUS_STALE = "STALE"
STATUS_MISSING = "MISSING"

GLYPHS = {
    STATUS_DONE: "✓",
    STATUS_STALE: "!",
    STATUS_MISSING: "·",
}

PATH_RE = re.compile(r"^PATH:\s*(GREEN|YELLOW)\s*$")
SLICE_RE = re.compile(r"^(?:S|s)?(\d+)$")
STORY_ID_RE = re.compile(r"^S(\d+)-(\d+)$", re.IGNORECASE)


@dataclass(frozen=True)
class StoryEntry:
    story_id: str
    passes: bool


def _repo_root() -> Path:
    script_dir = Path(__file__).resolve().parent
    result = subprocess.run(
        ["git", "-C", str(script_dir), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("not inside a git repository")
    return Path(result.stdout.strip())


def _head_commit(root: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("unable to determine git HEAD")
    return result.stdout.strip()


def _normalize_slice(value: str) -> str:
    match = SLICE_RE.match(value.strip())
    if not match:
        raise ValueError(f"invalid slice value: {value!r} (expected N or SN)")
    return match.group(1)


def _slice_matches(story_slice: Any, target_slice: str) -> bool:
    if story_slice is None:
        return False
    if isinstance(story_slice, int):
        return str(story_slice) == target_slice
    if isinstance(story_slice, str):
        try:
            normalized = _normalize_slice(story_slice)
        except ValueError:
            return False
        return normalized == target_slice
    return False


def _story_sort_key(story_id: str) -> tuple[int, int, str]:
    match = STORY_ID_RE.match(story_id)
    if not match:
        return (10**9, 10**9, story_id)
    return (int(match.group(1)), int(match.group(2)), story_id)


def _parse_story_filter(value: str | None) -> set[str] | None:
    if value is None:
        return None
    selected: set[str] = set()
    for token in value.split(","):
        story = token.strip()
        if story:
            selected.add(story)
    return selected if selected else set()


def _load_prd_stories(prd_path: Path, slice_id: str) -> list[StoryEntry]:
    try:
        with open(prd_path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError as exc:
        raise RuntimeError(f"PRD file missing: {prd_path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON in {prd_path}: {exc}") from exc

    if not isinstance(data, dict):
        raise RuntimeError(f"unexpected PRD shape in {prd_path}: expected JSON object")

    entries: dict[str, StoryEntry] = {}

    items = data.get("items")
    if isinstance(items, list):
        for item in items:
            if not isinstance(item, dict):
                continue
            story_id = item.get("id")
            if not isinstance(story_id, str) or not story_id.strip():
                continue
            if not _slice_matches(item.get("slice"), slice_id):
                continue
            entries[story_id] = StoryEntry(story_id=story_id, passes=bool(item.get("passes") is True))

    legacy = data.get("stories")
    if isinstance(legacy, dict):
        for story_id, payload in legacy.items():
            if not isinstance(story_id, str) or not isinstance(payload, dict):
                continue
            if not _slice_matches(payload.get("slice"), slice_id):
                continue
            if story_id not in entries:
                entries[story_id] = StoryEntry(story_id=story_id, passes=bool(payload.get("passes") is True))

    return sorted(entries.values(), key=lambda entry: _story_sort_key(entry.story_id))


def _receipt_dir_for_story(root: Path, story_id: str) -> Path:
    env_root = os.getenv("WF_RECEIPTS_ROOT")
    if env_root:
        return Path(env_root) / story_id

    env_dir = os.getenv("WF_RECEIPT_DIR")
    if env_dir:
        env_path = Path(env_dir)
        if env_path.name == story_id:
            return env_path
        return env_path / story_id

    return root / ".wf" / "receipts" / story_id


def _story_artifacts_root(root: Path) -> Path:
    raw = os.getenv("STORY_ARTIFACTS_ROOT", "artifacts/story")
    p = Path(raw)
    if p.is_absolute():
        return p
    return root / p


def _receipt_status(receipt_path: Path, head_commit: str) -> str:
    if not receipt_path.exists():
        return STATUS_MISSING
    try:
        with open(receipt_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return STATUS_MISSING

    if not isinstance(payload, dict):
        return STATUS_MISSING

    receipt_head = payload.get("head_sha")
    if isinstance(receipt_head, str) and receipt_head == head_commit:
        return STATUS_DONE
    return STATUS_STALE


def _read_path_signal(ledger_path: Path) -> str:
    if not ledger_path.exists():
        return "UNKNOWN"

    try:
        with open(ledger_path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line:
                    continue
                match = PATH_RE.match(line)
                if match:
                    return match.group(1)
    except OSError:
        return "UNKNOWN"

    return "UNKNOWN"


def _markdown_table_row(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |"


def _render_markdown(
    slice_label: str,
    generated_at: str,
    head_commit: str,
    stories: list[dict[str, Any]],
) -> str:
    lines: list[str] = []
    lines.append(f"# Recon Scoreboard — Slice {slice_label}")
    lines.append("")
    lines.append(f"Generated: {generated_at}")
    lines.append(f"HEAD: `{head_commit}`")
    lines.append("")

    headers = [
        "Story",
        "passes",
        "PATH",
        *STEPS,
        "HEAD",
    ]
    lines.append(_markdown_table_row(headers))
    lines.append(_markdown_table_row(["---"] * len(headers)))

    short_head = head_commit[:12]
    for story in stories:
        step_cells = [GLYPHS[story["steps"][step]] for step in STEPS]
        row = [
            story["story_id"],
            "true" if story["passes"] else "false",
            story["path"],
            *step_cells,
            short_head,
        ]
        lines.append(_markdown_table_row(row))

    lines.append("")
    return "\n".join(lines)


def build_scoreboard(
    root: Path,
    slice_id: str,
    stories_filter: set[str] | None,
) -> tuple[str, dict[str, Any], bool]:
    prd_path = root / "plans" / "prd.json"
    story_entries = _load_prd_stories(prd_path, slice_id)

    if stories_filter is not None:
        story_entries = [entry for entry in story_entries if entry.story_id in stories_filter]

    head_commit = _head_commit(root)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    story_artifacts_root = _story_artifacts_root(root)

    story_payloads: list[dict[str, Any]] = []
    all_done = bool(story_entries)

    for entry in story_entries:
        receipt_dir = _receipt_dir_for_story(root, entry.story_id)
        step_status: dict[str, str] = {}
        for index, step in enumerate(STEPS):
            receipt_path = receipt_dir / f"{index:02d}_{step}.json"
            status = _receipt_status(receipt_path, head_commit)
            step_status[step] = status
            if status != STATUS_DONE:
                all_done = False

        ledger_path = story_artifacts_root / entry.story_id / "cycle1" / "evidence_ledger.md"
        path_signal = _read_path_signal(ledger_path)

        story_payloads.append(
            {
                "story_id": entry.story_id,
                "passes": entry.passes,
                "path": path_signal,
                "head": head_commit,
                "steps": step_status,
            }
        )

    markdown = _render_markdown(slice_id, generated_at, head_commit, story_payloads)
    json_payload: dict[str, Any] = {
        "slice": int(slice_id),
        "generated_at": generated_at,
        "head_commit": head_commit,
        "stories": story_payloads,
    }
    return markdown, json_payload, all_done


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate reconciliation scoreboard for a slice")
    parser.add_argument("--slice", required=True, help="Slice number/id (e.g. 2 or S2)")
    parser.add_argument("--out-md", help="Write markdown output to PATH")
    parser.add_argument("--out-json", help="Write JSON summary output to PATH")
    parser.add_argument("--stories", help="Optional comma-separated story filter (e.g. S2-001,S2-002)")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero if any selected story has missing/stale step receipts",
    )
    args = parser.parse_args(argv)

    try:
        slice_id = _normalize_slice(args.slice)
        root = _repo_root()
        stories_filter = _parse_story_filter(args.stories)
        markdown, json_payload, all_done = build_scoreboard(root, slice_id, stories_filter)
    except (RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if not json_payload["stories"]:
        print(
            f"WARN: no stories found for slice {slice_id}"
            + (" with current --stories filter" if stories_filter is not None else ""),
            file=sys.stderr,
        )

    if args.out_md:
        _write_text(Path(args.out_md), markdown)
    print(markdown, end="")

    if args.out_json:
        json_text = json.dumps(json_payload, indent=2, sort_keys=True)
        _write_text(Path(args.out_json), json_text + "\n")

    if args.strict and not all_done:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
