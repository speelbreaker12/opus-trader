#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, NoReturn


HEADING_RE = re.compile(r"^(#{2,6})\s+(.+?)\s*$")
SECTION_TOKEN_RE = re.compile(r"^([0-9A-Z]+(?:\.[0-9A-Z]+)*)\b")
AT_ID_RE = re.compile(r"^AT-\d+$")


def fail(message: str, exit_code: int = 1) -> NoReturn:
    raise SystemExit(f"FAIL: {message}")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def write_text_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def write_json_atomic(path: Path, payload: Any) -> None:
    write_text_atomic(path, json.dumps(payload, indent=2) + "\n")


def normalize_heading_text(raw_text: str) -> str:
    text = raw_text.replace("\\", "")
    text = re.sub(r"\*\*", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_sections(contract_text: str) -> list[dict[str, Any]]:
    lines = contract_text.splitlines()
    headings: list[dict[str, Any]] = []
    for index, line in enumerate(lines, start=1):
        match = HEADING_RE.match(line)
        if match is None:
            continue
        heading_text = normalize_heading_text(match.group(2))
        token_match = SECTION_TOKEN_RE.match(heading_text)
        if token_match is None:
            continue
        section_anchor = token_match.group(1)
        title = heading_text[len(section_anchor):].strip(" -")
        headings.append({
            "section_anchor": section_anchor,
            "title": title or heading_text,
            "start_line": index,
        })

    for current, nxt in zip(headings, headings[1:]):
        current["end_line"] = nxt["start_line"] - 1
    if headings:
        headings[-1]["end_line"] = len(lines)
    return headings


def extract_range(contract_lines: list[str], start_line: int, end_line: int) -> str:
    return "\n".join(contract_lines[start_line - 1:end_line]).rstrip() + "\n"


def build_section_index_md(sections: list[dict[str, Any]]) -> str:
    lines = [
        "| section_anchor | title | start_line | end_line |",
        "|---|---|---:|---:|",
    ]
    for section in sections:
        title = str(section["title"]).replace("|", "\\|")
        lines.append(
            f"| {section['section_anchor']} | {title} | {section['start_line']} | {section['end_line']} |"
        )
    return "\n".join(lines) + "\n"


def build_contract_header(contract_lines: list[str], sections: list[dict[str, Any]]) -> str:
    blocks: list[str] = []

    definitions_start = None
    definitions_end = None
    for index, line in enumerate(contract_lines, start=1):
        match = HEADING_RE.match(line)
        if match is None:
            continue
        heading_text = normalize_heading_text(match.group(2))
        if definitions_start is None and heading_text == "Definitions":
            definitions_start = index
            continue
        if definitions_start is not None:
            definitions_end = index - 1
            break
    if definitions_start is not None:
        if definitions_end is None:
            definitions_end = len(contract_lines)
        blocks.append(extract_range(contract_lines, definitions_start, definitions_end))

    for section in sections:
        if section["section_anchor"] == "0.0":
            blocks.append(extract_range(contract_lines, section["start_line"], section["end_line"]))
            break

    if len(blocks) < 2:
        fail("could not extract Definitions and 0.0 from CONTRACT.md")
    return "\n".join(block.rstrip() for block in blocks if block.strip()).rstrip() + "\n"


def build_at_registry(contract_lines: list[str], sections: list[dict[str, Any]]) -> list[dict[str, Any]]:
    section_by_line: list[tuple[int, int, str]] = [
        (section["start_line"], section["end_line"], section["section_anchor"])
        for section in sections
    ]

    def section_for_line(line_no: int) -> str:
        for start, end, anchor in section_by_line:
            if start <= line_no <= end:
                return anchor
        return ""

    registry: list[dict[str, Any]] = []
    for index, line in enumerate(contract_lines, start=1):
        stripped = line.strip()
        if not AT_ID_RE.fullmatch(stripped):
            continue
        description = ""
        cursor = index
        while cursor < len(contract_lines):
            cursor += 1
            candidate = contract_lines[cursor - 1].strip()
            if not candidate:
                continue
            if AT_ID_RE.fullmatch(candidate) or HEADING_RE.match(candidate):
                break
            description = re.sub(r"^\-\s*", "", candidate)
            description = re.sub(r"\s+", " ", description)
            break
        registry.append({
            "at_id": stripped,
            "section_anchor": section_for_line(index),
            "line": index,
            "description": description,
        })
    return registry


def load_snapshot_targets(path: Path) -> list[dict[str, str]]:
    payload = load_json(path)
    targets = payload.get("targets")
    if not isinstance(targets, list):
        fail(f"{path} must contain a targets array")
    cleaned: list[dict[str, str]] = []
    for target in targets:
        if not isinstance(target, dict):
            fail(f"{path} contains a non-object target")
        fixture_path = target.get("fixture_path")
        section_anchor = target.get("section_anchor")
        if not isinstance(fixture_path, str) or not isinstance(section_anchor, str):
            fail(f"{path} target entries require fixture_path and section_anchor")
        cleaned.append({
            "fixture_path": fixture_path,
            "section_anchor": section_anchor,
        })
    return cleaned


def load_gate_input_registry(path: Path) -> dict[str, list[str]]:
    payload = load_json(path)
    fixtures = payload.get("fixtures", {})
    if not isinstance(fixtures, dict):
        fail(f"{path} fixtures must be an object")
    result: dict[str, list[str]] = {}
    for fixture_name, entry in fixtures.items():
        governed_inputs: list[str] = []
        if isinstance(entry, dict):
            raw_inputs = entry.get("governed_inputs", [])
            if not isinstance(raw_inputs, list):
                fail(f"{path} fixture '{fixture_name}' governed_inputs must be an array")
            for item in raw_inputs:
                if not isinstance(item, str):
                    fail(f"{path} fixture '{fixture_name}' governed_inputs entries must be strings")
                governed_inputs.append(item)
        result[fixture_name] = governed_inputs
    return result


def load_existing_manifest(manifest_path: Path) -> tuple[dict[str, str], str, str]:
    if not manifest_path.exists():
        return {}, "", ""

    payload = load_json(manifest_path)
    if not isinstance(payload, dict):
        fail(f"context manifest must be a JSON object: {manifest_path}")

    tracked_files = payload.get("tracked_files", {})
    if not isinstance(tracked_files, dict):
        fail(f"{manifest_path} tracked_files must be an object")
    for rel_path, tracked_hash in tracked_files.items():
        if not isinstance(rel_path, str) or not isinstance(tracked_hash, str):
            fail(f"{manifest_path} tracked_files entries must be string:string")

    legacy_hash = payload.get("contract_content_hash", "")
    common_hash = payload.get("common_contract_hash", legacy_hash)
    snapshot_hash = payload.get("snapshot_contract_hash", legacy_hash)
    if not isinstance(common_hash, str):
        fail(f"{manifest_path} common_contract_hash must be a string")
    if not isinstance(snapshot_hash, str):
        fail(f"{manifest_path} snapshot_contract_hash must be a string")
    return dict(tracked_files), common_hash, snapshot_hash


def collect_common_tracked_files(contract_dir: Path) -> dict[str, str]:
    tracked_files: dict[str, str] = {}
    for path in sorted((contract_dir / "common").glob("*")):
        if path.name == "context_manifest.json" or path.name.startswith("."):
            continue
        if not path.is_file():
            continue
        tracked_files[str(path.relative_to(contract_dir))] = sha256_text(path.read_text(encoding="utf-8"))
    return tracked_files


def collect_snapshot_tracked_files(contract_dir: Path) -> dict[str, str]:
    tracked_files: dict[str, str] = {}
    for path in sorted((contract_dir / "phase2" / "fixtures" / "snapshot").glob("*")):
        if path.name.startswith(".") or not path.is_file():
            continue
        tracked_files[str(path.relative_to(contract_dir))] = sha256_text(path.read_text(encoding="utf-8"))
    return tracked_files


def update_context_manifest(
    contract_dir: Path,
    contract_hash: str,
    *,
    update_common: bool = False,
    update_snapshots: bool = False,
) -> None:
    manifest_path = contract_dir / "common" / "context_manifest.json"
    tracked_files, common_hash, snapshot_hash = load_existing_manifest(manifest_path)

    if update_common:
        tracked_files = {
            rel_path: tracked_hash
            for rel_path, tracked_hash in tracked_files.items()
            if not rel_path.startswith("common/")
        }
        tracked_files.update(collect_common_tracked_files(contract_dir))
        common_hash = contract_hash

    if update_snapshots:
        tracked_files = {
            rel_path: tracked_hash
            for rel_path, tracked_hash in tracked_files.items()
            if not rel_path.startswith("phase2/fixtures/snapshot/")
        }
        tracked_files.update(collect_snapshot_tracked_files(contract_dir))
        snapshot_hash = contract_hash

    write_json_atomic(
        manifest_path,
        {
            "schema_version": 2,
            "tracked_files": tracked_files,
            "contract_content_hash": contract_hash,
            "common_contract_hash": common_hash,
            "snapshot_contract_hash": snapshot_hash,
        },
    )


def refresh_common(root: Path) -> int:
    contract_dir = root / "autoresearch" / "contract"
    common_dir = contract_dir / "common"
    contract_path = root / "specs" / "CONTRACT.md"
    contract_text = contract_path.read_text(encoding="utf-8")
    contract_lines = contract_text.splitlines()
    sections = parse_sections(contract_text)
    if not sections:
        fail("no numbered sections found in CONTRACT.md")

    section_index_md = build_section_index_md(sections)
    contract_header_md = build_contract_header(contract_lines, sections)
    at_registry = build_at_registry(contract_lines, sections)

    fixture_metadata = load_json(contract_dir / "phase1" / "internal" / "fixture_metadata.json")
    fixture_entries = fixture_metadata.get("fixtures", {}) if isinstance(fixture_metadata, dict) else {}
    if not isinstance(fixture_entries, dict):
        fail("phase1/internal/fixture_metadata.json fixtures must be an object")
    known_sections = {section["section_anchor"] for section in sections}
    stale_fixtures: list[str] = []
    for fixture_name, metadata in fixture_entries.items():
        if not isinstance(metadata, dict):
            continue
        section_anchor = metadata.get("section_anchor")
        if isinstance(section_anchor, str) and section_anchor and section_anchor not in known_sections:
            stale_fixtures.append(f"{fixture_name}:{section_anchor}")
    if stale_fixtures:
        fail(
            "Phase 1 planted-gap fixtures reference missing sections: "
            + ", ".join(stale_fixtures)
        )

    write_text_atomic(common_dir / "section_index.md", section_index_md)
    write_text_atomic(common_dir / "contract_header.md", contract_header_md)
    write_json_atomic(common_dir / "at_registry.json", at_registry)
    update_context_manifest(
        contract_dir,
        sha256_text(contract_text),
        update_common=True,
    )
    print("OK: refresh-common complete")
    return 0


def refresh_fixtures(root: Path) -> int:
    contract_dir = root / "autoresearch" / "contract"
    common_dir = contract_dir / "common"
    contract_path = root / "specs" / "CONTRACT.md"
    contract_text = contract_path.read_text(encoding="utf-8")
    contract_lines = contract_text.splitlines()
    sections = parse_sections(contract_text)
    section_map = {section["section_anchor"]: section for section in sections}
    targets = load_snapshot_targets(contract_dir / "phase2" / "internal" / "snapshot_targets.json")
    gate_inputs = load_gate_input_registry(common_dir / "gate_input_registry.json")

    for target in targets:
        section_anchor = target["section_anchor"]
        if section_anchor not in section_map:
            fail(f"section_index stale for {section_anchor}; run 'harness.sh contract refresh-common' first")
        section = section_map[section_anchor]
        fixture_path = contract_dir / target["fixture_path"]
        fixture_text = extract_range(contract_lines, section["start_line"], section["end_line"])
        write_text_atomic(fixture_path, fixture_text)

        fixture_name = fixture_path.name
        for governed_input in gate_inputs.get(fixture_name, []):
            count = fixture_text.count(governed_input)
            if count != 1:
                fail(
                    f"gate_input_registry reference '{governed_input}' for {fixture_name} "
                    f"resolved {count} times"
                )

    update_context_manifest(
        contract_dir,
        sha256_text(contract_text),
        update_snapshots=True,
    )
    print("OK: refresh-fixtures complete")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh contract autoresearch shared context")
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=["common", "fixtures", "all"])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if args.mode == "common":
        return refresh_common(root)
    if args.mode == "fixtures":
        return refresh_fixtures(root)
    refresh_common(root)
    return refresh_fixtures(root)


if __name__ == "__main__":
    raise SystemExit(main())
