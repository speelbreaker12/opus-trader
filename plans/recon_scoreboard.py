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
PATH_VALUES = {"GREEN", "YELLOW"}
HEXSHA_RE = re.compile(r"^[0-9a-f]{7,40}$")

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


def _resolve_score_head(root: Path, value: str | None) -> str:
    ref = "HEAD" if value is None else value
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--verify", f"{ref}^{{commit}}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"invalid --head value: {value!r} (not a valid commit-ish)")
    return result.stdout.strip()


def _normalize_slice(value: str) -> str:
    match = SLICE_RE.match(value.strip())
    if not match:
        raise ValueError(f"invalid slice value: {value!r} (expected N or SN)")
    return match.group(1)


def _story_slice_id(story_id: str, default_slice_id: str) -> str:
    match = STORY_ID_RE.match(story_id)
    if match:
        return match.group(1)
    return default_slice_id


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


def _receipt_status(receipt_path: Path, score_head: str) -> tuple[str, str | None]:
    if not receipt_path.exists():
        return STATUS_MISSING, None
    try:
        with open(receipt_path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return STATUS_MISSING, None

    if not isinstance(payload, dict):
        return STATUS_MISSING, None

    receipt_head = payload.get("head_sha")
    if not isinstance(receipt_head, str):
        return STATUS_MISSING, None
    if not HEXSHA_RE.match(receipt_head):
        return STATUS_MISSING, None
    if receipt_head == score_head:
        return STATUS_DONE, receipt_head
    return STATUS_STALE, receipt_head


def _derive_path_from_ledger_json(payload: dict[str, Any]) -> str:
    explicit = payload.get("path")
    if isinstance(explicit, str):
        candidate = explicit.strip().upper()
        if candidate in PATH_VALUES:
            return candidate

    stoplight = payload.get("stoplight")
    if isinstance(stoplight, str):
        stoplight = stoplight.strip().upper()
    else:
        stoplight = ""

    at_evidence = payload.get("at_evidence")
    gaps = payload.get("gaps")
    if isinstance(at_evidence, list) and isinstance(gaps, list):
        has_blocking_gap = any(
            isinstance(gap, dict) and str(gap.get("severity", "")).strip().upper() in {"P0", "P1"}
            for gap in gaps
        )
        has_non_proven_verdict = any(
            isinstance(entry, dict)
            and str(entry.get("verdict", "")).strip().upper() not in {"PROVEN", "DEFERRED"}
            for entry in at_evidence
        )
        return "YELLOW" if (has_blocking_gap or has_non_proven_verdict) else "GREEN"

    if stoplight in PATH_VALUES:
        return stoplight

    return "UNKNOWN"


def _read_path_signal_from_markdown(ledger_path: Path) -> str:
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


def _ledger_candidates(root: Path, story_artifacts_root: Path, story_id: str, story_slice: str) -> list[Path]:
    slice_token = f"S{story_slice}"
    candidates = [
        story_artifacts_root / story_id / "cycle1" / "evidence_ledger.json",
        story_artifacts_root / story_id / "evidence_ledger.json",
        story_artifacts_root / story_id / f"{story_id}_reconciliation.json",
        root / "reviews" / "reconciliations" / slice_token / f"{story_id}_reconciliation.json",
        story_artifacts_root / story_id / "cycle1" / "evidence_ledger.md",
        story_artifacts_root / story_id / "evidence_ledger.md",
        story_artifacts_root / story_id / f"{story_id}_reconciliation.md",
        story_artifacts_root / story_id / "preflight" / "audit.md",
        root / "reviews" / "reconciliations" / slice_token / f"{story_id}_reconciliation.md",
    ]

    seen: set[Path] = set()
    ordered: list[Path] = []
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        ordered.append(candidate)
    return ordered


def _resolve_path_signal(root: Path, story_artifacts_root: Path, story_id: str, story_slice: str) -> tuple[str, str]:
    candidates = _ledger_candidates(root, story_artifacts_root, story_id, story_slice)
    existing_json = [p for p in candidates if p.suffix == ".json" and p.exists()]
    if existing_json:
        first_json_path = existing_json[0]
        for ledger_path in existing_json:
            try:
                with open(ledger_path, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(payload, dict):
                continue
            signal = _derive_path_from_ledger_json(payload)
            if signal in PATH_VALUES:
                return signal, str(ledger_path)
        return "UNKNOWN", str(first_json_path)

    for ledger_path in candidates:
        if ledger_path.suffix != ".md" or not ledger_path.exists():
            continue
        signal = _read_path_signal_from_markdown(ledger_path)
        if signal in PATH_VALUES:
            return signal, str(ledger_path)
        return "UNKNOWN", str(ledger_path)

    return "UNKNOWN", ""


def _derive_pass_status(step_status: dict[str, str]) -> str:
    """Derive pass status from the 8 prerequisite workflow steps.

    wf_step.sh `pass` is a gate check and does not write 08_pass.json.
    """
    prereq_steps = STEPS[:-1]
    prereq_statuses = [step_status[s] for s in prereq_steps]
    if any(status == STATUS_MISSING for status in prereq_statuses):
        return STATUS_MISSING
    if any(status == STATUS_STALE for status in prereq_statuses):
        return STATUS_STALE
    return STATUS_DONE


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
    score_head: str | None,
) -> tuple[str, dict[str, Any], bool]:
    prd_path = root / "plans" / "prd.json"
    story_entries = _load_prd_stories(prd_path, slice_id)

    if stories_filter is not None:
        story_entries = [entry for entry in story_entries if entry.story_id in stories_filter]

    repo_head_commit = _head_commit(root)
    resolved_score_head = _resolve_score_head(root, score_head)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    story_artifacts_root = _story_artifacts_root(root)

    story_payloads: list[dict[str, Any]] = []
    all_done = bool(story_entries)

    for entry in story_entries:
        receipt_dir = _receipt_dir_for_story(root, entry.story_id)
        step_status: dict[str, str] = {}
        step_receipt_head_sha: dict[str, str] = {}
        for index, step in enumerate(STEPS[:-1]):
            receipt_path = receipt_dir / f"{index:02d}_{step}.json"
            status, receipt_head_sha = _receipt_status(receipt_path, resolved_score_head)
            step_status[step] = status
            if receipt_head_sha:
                step_receipt_head_sha[step] = receipt_head_sha
            if status != STATUS_DONE:
                all_done = False

        pass_status = _derive_pass_status(step_status)
        step_status["pass"] = pass_status
        if pass_status != STATUS_DONE:
            all_done = False

        story_slice = _story_slice_id(entry.story_id, slice_id)
        path_signal, path_source = _resolve_path_signal(root, story_artifacts_root, entry.story_id, story_slice)

        story_payloads.append(
            {
                "story_id": entry.story_id,
                "passes": entry.passes,
                "path": path_signal,
                "path_source": path_source,
                "head": resolved_score_head,
                "steps": step_status,
                "step_receipt_head_sha": step_receipt_head_sha,
            }
        )

    markdown = _render_markdown(slice_id, generated_at, resolved_score_head, story_payloads)
    json_payload: dict[str, Any] = {
        "slice": int(slice_id),
        "generated_at": generated_at,
        "head_commit": resolved_score_head,
        "repo_head_commit": repo_head_commit,
        "stories": story_payloads,
    }
    return markdown, json_payload, all_done


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate reconciliation scoreboard for a slice")
    parser.add_argument("--slice", required=True, help="Slice number/id (e.g. 2 or S2)")
    parser.add_argument(
        "--head",
        help="Compare receipt head_sha values against this commit-ish (default: current HEAD)",
    )
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
        markdown, json_payload, all_done = build_scoreboard(root, slice_id, stories_filter, args.head)
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
