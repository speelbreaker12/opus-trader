#!/usr/bin/env python3
"""Audit required evidence markers against PRD producers.

In CI mode, canonical checklist markers are the gating source of truth.
Roadmap input remains informational and non-blocking.
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Sequence, Set, Tuple

EXIT_PASS = 0
EXIT_TOOL_ERROR = 2
EXIT_STRICT_GAPS = 4
EXIT_MARKER_SCHEMA = 7

MARKER_RE = re.compile(
    r"<!--\s*(REQUIRED_EVIDENCE(?:_ANY_OF)?|REQUIRED_EVIDENCE_NONE)(?::\s*(.*?))?\s*-->"
)
EVIDENCE_PATH_RE = re.compile(r"\b(evidence/phase[0-9]+/[A-Za-z0-9_./-]+)\b")
GLOB_CHARS = ("*", "?", "[", "]")


class ToolFailure(RuntimeError):
    """Tool/config failure -> EXIT_TOOL_ERROR."""


class SchemaFailure(RuntimeError):
    """Marker/schema failure -> EXIT_MARKER_SCHEMA."""


@dataclass(frozen=True)
class Requirement:
    kind: str  # "ALL" | "ANY_OF"
    paths: Tuple[str, ...]
    source_file: str
    source_line: int


@dataclass(frozen=True)
class Gap:
    key: str
    kind: str
    category: str
    required_by: str
    options: Tuple[str, ...]


def normalize_required_path(raw_path: str) -> str:
    token = raw_path.strip().replace("\\", "/")
    if not token:
        raise SchemaFailure("empty evidence path is not allowed")
    if token.startswith("/"):
        raise SchemaFailure(f"absolute evidence path is not allowed: {raw_path}")
    if token.endswith("/"):
        raise SchemaFailure(f"directory path is not allowed: {raw_path}")
    if any(ch in token for ch in GLOB_CHARS):
        raise SchemaFailure(f"glob patterns are not allowed in evidence paths: {raw_path}")

    norm = posixpath.normpath(token)
    if norm in ("", ".", "..") or norm.startswith("../"):
        raise SchemaFailure(f"path escapes repo root: {raw_path}")
    if norm.startswith("/"):
        raise SchemaFailure(f"absolute evidence path is not allowed: {raw_path}")
    if not norm.startswith("evidence/"):
        raise SchemaFailure(f"evidence path must be repo-relative under evidence/: {raw_path}")

    return norm


def parse_inputs_arg(inputs: Sequence[str]) -> List[str]:
    paths: List[str] = []

    for entry in inputs:
        if entry.startswith("@"):
            list_path = Path(entry[1:])
            if not list_path.exists():
                raise ToolFailure(f"inputs list file not found: {list_path}")
            for line in list_path.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                paths.append(stripped)
        else:
            paths.append(entry)

    # deterministic unique
    return sorted(set(paths))


def parse_markers_from_file(file_path: Path, ci_mode: bool) -> Tuple[List[Requirement], bool]:
    if not file_path.exists():
        raise ToolFailure(f"input file not found: {file_path}")

    lines = file_path.read_text(encoding="utf-8").splitlines()
    requirements: List[Requirement] = []
    marker_count = 0
    none_count = 0

    for line_no, line in enumerate(lines, start=1):
        for marker_match in MARKER_RE.finditer(line):
            marker = marker_match.group(1)
            payload = (marker_match.group(2) or "").strip()
            marker_count += 1

            if marker == "REQUIRED_EVIDENCE_NONE":
                if payload:
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE_NONE must not include payload"
                    )
                none_count += 1
                continue

            if marker == "REQUIRED_EVIDENCE":
                if not payload:
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE requires a path"
                    )
                if "|" in payload:
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE must contain exactly one path"
                    )
                norm = normalize_required_path(payload)
                requirements.append(
                    Requirement(
                        kind="ALL",
                        paths=(norm,),
                        source_file=str(file_path),
                        source_line=line_no,
                    )
                )
                continue

            if marker == "REQUIRED_EVIDENCE_ANY_OF":
                if not payload:
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE_ANY_OF requires one or more paths"
                    )

                options = tuple(normalize_required_path(part) for part in payload.split("|"))
                if not options:
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE_ANY_OF has no valid options"
                    )
                if len(set(options)) != len(options):
                    raise SchemaFailure(
                        f"{file_path}:{line_no}: REQUIRED_EVIDENCE_ANY_OF has duplicate normalized options"
                    )

                requirements.append(
                    Requirement(
                        kind="ANY_OF",
                        paths=tuple(sorted(options)),
                        source_file=str(file_path),
                        source_line=line_no,
                    )
                )
                continue

            raise SchemaFailure(f"{file_path}:{line_no}: unsupported marker: {marker}")

    if ci_mode and marker_count == 0:
        raise ToolFailure(
            f"{file_path}: no REQUIRED_EVIDENCE marker intent found "
            "(expected REQUIRED_EVIDENCE/REQUIRED_EVIDENCE_ANY_OF/REQUIRED_EVIDENCE_NONE)"
        )

    if none_count > 1:
        raise SchemaFailure(f"{file_path}: multiple REQUIRED_EVIDENCE_NONE markers are forbidden")

    if none_count == 1 and requirements:
        raise SchemaFailure(
            f"{file_path}: REQUIRED_EVIDENCE_NONE cannot be combined with REQUIRED_EVIDENCE markers"
        )

    return requirements, none_count == 1


def extract_prd_paths_from_string(value: str) -> Set[str]:
    refs = set(EVIDENCE_PATH_RE.findall(value))
    # If the whole string is a path-like token, keep it too.
    stripped = value.strip()
    if stripped.startswith("evidence/"):
        refs.add(stripped)
    return refs


def extract_prd_producers(prd_path: Path) -> Dict[str, Set[str]]:
    if not prd_path.exists():
        raise ToolFailure(f"PRD file not found: {prd_path}")

    try:
        payload = json.loads(prd_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ToolFailure(f"invalid PRD JSON: {prd_path} ({exc})") from exc

    items = payload.get("items", [])
    if not isinstance(items, list):
        raise ToolFailure("PRD items must be an array")

    producers: Dict[str, Set[str]] = {}

    for item in items:
        if not isinstance(item, dict):
            continue
        story_id = item.get("id")
        if not isinstance(story_id, str) or not story_id:
            continue

        values: List[str] = []

        evidence = item.get("evidence", [])
        if isinstance(evidence, list):
            values.extend(v for v in evidence if isinstance(v, str))

        scope = item.get("scope", {})
        if isinstance(scope, dict):
            for key in ("touch", "create"):
                arr = scope.get(key, [])
                if isinstance(arr, list):
                    values.extend(v for v in arr if isinstance(v, str))

        for raw in values:
            for path in sorted(extract_prd_paths_from_string(raw)):
                try:
                    norm = normalize_required_path(path)
                except SchemaFailure:
                    # PRD may include human prose; invalid path tokens are ignored here.
                    continue
                producers.setdefault(norm, set()).add(story_id)

    return producers


def load_global_manual_allowlist(path: Path, ci_mode: bool) -> Dict[str, dict]:
    if not path.exists():
        raise ToolFailure(f"global manual allowlist not found: {path}")

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ToolFailure(f"invalid allowlist JSON: {path} ({exc})") from exc

    entries = payload.get("entries")
    if not isinstance(entries, list):
        raise SchemaFailure(f"allowlist {path} must contain entries[]")

    out: Dict[str, dict] = {}
    for idx, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise SchemaFailure(f"allowlist {path}: entries[{idx}] must be object")

        for field in ("evidence_path", "justification", "owning_story_id"):
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                raise SchemaFailure(f"allowlist {path}: entries[{idx}] missing non-empty {field}")

        norm_path = normalize_required_path(entry["evidence_path"])
        if norm_path in out:
            raise SchemaFailure(f"allowlist {path}: duplicate evidence_path {norm_path}")

        if ci_mode and not Path(norm_path).exists():
            raise SchemaFailure(f"allowlist {path}: evidence_path not found in repo: {norm_path}")

        out[norm_path] = {
            "justification": entry["justification"].strip(),
            "owning_story_id": entry["owning_story_id"].strip(),
            "timestamp": entry.get("timestamp", ""),
        }

    return out


def pick_fuzzy_match(required: str, producers: Dict[str, Set[str]]) -> Tuple[str, float] | None:
    candidates: List[Tuple[float, str]] = []

    req_parts = required.split("/")
    for candidate in producers.keys():
        if candidate == required:
            continue

        score = 0.0
        if candidate.endswith(required) or required.endswith(candidate):
            score = 0.9
        else:
            cand_parts = candidate.split("/")
            overlap = 0
            while overlap < min(len(req_parts), len(cand_parts)) and req_parts[-(overlap + 1)] == cand_parts[-(overlap + 1)]:
                overlap += 1
            if overlap >= 2:
                score = min(0.8, 0.4 + 0.1 * overlap)

        if score > 0.0:
            candidates.append((score, candidate))

    if not candidates:
        return None

    candidates.sort(key=lambda x: (-x[0], x[1]))
    score, match = candidates[0]
    return match, round(score, 3)


def evaluate_requirements(
    requirements: Sequence[Requirement],
    producers: Dict[str, Set[str]],
    allowlist_paths: Set[str],
    fuzzy: bool,
) -> Tuple[List[Gap], List[dict], Set[str]]:
    gaps: List[Gap] = []
    fuzzy_matches: List[dict] = []
    used_allowlist: Set[str] = set()

    for req in requirements:
        if req.kind == "ALL":
            path = req.paths[0]
            satisfied = path in producers

            if not satisfied and fuzzy:
                fuzzy_match = pick_fuzzy_match(path, producers)
                if fuzzy_match:
                    matched, score = fuzzy_match
                    satisfied = True
                    fuzzy_matches.append(
                        {
                            "required": path,
                            "matched": matched,
                            "score": score,
                            "source": f"{req.source_file}:{req.source_line}",
                        }
                    )

            if satisfied:
                continue

            category = "GLOBAL_MANUAL" if path in allowlist_paths else "STORY_OWNED"
            if category == "GLOBAL_MANUAL":
                used_allowlist.add(path)

            gaps.append(
                Gap(
                    key=path,
                    kind="ALL",
                    category=category,
                    required_by=f"{req.source_file}:{req.source_line}",
                    options=req.paths,
                )
            )
            continue

        # ANY_OF
        satisfied = False
        for option in req.paths:
            if option in producers:
                satisfied = True
                break

            if fuzzy:
                fuzzy_match = pick_fuzzy_match(option, producers)
                if fuzzy_match:
                    matched, score = fuzzy_match
                    satisfied = True
                    fuzzy_matches.append(
                        {
                            "required": option,
                            "matched": matched,
                            "score": score,
                            "source": f"{req.source_file}:{req.source_line}",
                        }
                    )
                    break

        if satisfied:
            continue

        category = "GLOBAL_MANUAL" if all(path in allowlist_paths for path in req.paths) else "STORY_OWNED"
        if category == "GLOBAL_MANUAL":
            used_allowlist.update(req.paths)

        key = "ANY_OF(" + " | ".join(req.paths) + ")"
        gaps.append(
            Gap(
                key=key,
                kind="ANY_OF",
                category=category,
                required_by=f"{req.source_file}:{req.source_line}",
                options=req.paths,
            )
        )

    return gaps, fuzzy_matches, used_allowlist


def parse_requirements(files: Sequence[str], ci_mode: bool) -> Tuple[List[Requirement], Set[str]]:
    requirements: List[Requirement] = []
    files_with_none: Set[str] = set()

    declared_paths: Dict[str, str] = {}

    for file_path in sorted(set(files)):
        parsed, has_none = parse_markers_from_file(Path(file_path), ci_mode=ci_mode)

        if has_none:
            files_with_none.add(file_path)

        for req in parsed:
            for path in req.paths:
                existing_source = declared_paths.get(path)
                source = f"{req.source_file}:{req.source_line}"
                if existing_source:
                    raise SchemaFailure(
                        f"duplicate normalized required evidence path '{path}' "
                        f"declared at {existing_source} and {source}"
                    )
                declared_paths[path] = source
            requirements.append(req)

    return requirements, set(declared_paths.keys())


def format_gap(gap: Gap) -> dict:
    return {
        "key": gap.key,
        "kind": gap.kind,
        "category": gap.category,
        "required_by": gap.required_by,
        "options": list(gap.options),
    }


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit roadmap/checklist evidence requirements")
    parser.add_argument("--prd", required=True, help="Path to plans/prd.json")
    parser.add_argument(
        "--inputs",
        action="append",
        default=[],
        help="Input file(s) to parse; supports @file list syntax",
    )
    parser.add_argument(
        "--checklist",
        action="append",
        default=[],
        help="Checklist file (canonical source in CI mode)",
    )
    parser.add_argument(
        "--roadmap",
        default="",
        help="Optional roadmap file (informational in --ci mode)",
    )
    parser.add_argument(
        "--global-manual-allowlist",
        default="plans/global_manual_allowlist.json",
        help="Path to GLOBAL_MANUAL allowlist JSON",
    )
    parser.add_argument("--ci", action="store_true", help="Enable CI gating semantics")
    parser.add_argument("--strict", action="store_true", help="Enable strict STORY_OWNED gap blocking")
    parser.add_argument("--fuzzy", action="store_true", help="Enable fuzzy producer matching")
    parser.add_argument("--output-json", default="", help="Optional JSON report output")
    args = parser.parse_args()

    try:
        input_files = parse_inputs_arg(args.inputs)
        checklist_files = sorted(set(args.checklist))

        if args.ci:
            gating_files = sorted(set(input_files + checklist_files))
            if not gating_files:
                raise ToolFailure("--ci requires canonical checklist inputs via --inputs/--checklist")
            if args.roadmap:
                # informational only in CI
                pass
        else:
            gating_files = sorted(set(input_files + checklist_files))
            if args.roadmap:
                gating_files.append(args.roadmap)
            gating_files = sorted(set(gating_files))

        if not gating_files:
            raise ToolFailure("no input files provided")

        requirements, declared_paths = parse_requirements(gating_files, ci_mode=args.ci)

        allowlist = load_global_manual_allowlist(Path(args.global_manual_allowlist), ci_mode=args.ci)
        allowlist_paths = set(allowlist.keys())

        if args.ci:
            stale_allowlist = sorted(path for path in allowlist_paths if path not in declared_paths)
            if stale_allowlist:
                raise SchemaFailure(
                    "stale GLOBAL_MANUAL allowlist entries: " + ", ".join(stale_allowlist)
                )

        producers = extract_prd_producers(Path(args.prd))

        gaps, fuzzy_matches, used_allowlist = evaluate_requirements(
            requirements=requirements,
            producers=producers,
            allowlist_paths=allowlist_paths,
            fuzzy=args.fuzzy,
        )

        gaps_sorted = sorted(gaps, key=lambda g: (g.category, g.key, g.required_by))
        story_owned_gaps = [g for g in gaps_sorted if g.category == "STORY_OWNED"]
        global_manual_gaps = [g for g in gaps_sorted if g.category == "GLOBAL_MANUAL"]

        if args.strict:
            displayed = [g for g in gaps_sorted if g.category == "STORY_OWNED"]
        else:
            displayed = gaps_sorted

        report = {
            "mode": {
                "ci": args.ci,
                "strict": args.strict,
                "fuzzy": args.fuzzy,
            },
            "inputs": {
                "gating_files": gating_files,
                "roadmap_informational": bool(args.ci and args.roadmap),
            },
            "requirements": {
                "total": len(requirements),
                "all": len([r for r in requirements if r.kind == "ALL"]),
                "any_of": len([r for r in requirements if r.kind == "ANY_OF"]),
            },
            "producers": {
                "total_paths": len(producers),
            },
            "gaps": [format_gap(g) for g in displayed],
            "all_gaps": [format_gap(g) for g in gaps_sorted],
            "counts": {
                "displayed_gaps": len(displayed),
                "all_gaps": len(gaps_sorted),
                "story_owned_gaps": len(story_owned_gaps),
                "global_manual_gaps": len(global_manual_gaps),
            },
            "global_manual": {
                "allowlist_entries": sorted(allowlist_paths),
                "used_allowlist_entries": sorted(used_allowlist),
            },
            "fuzzy_matches": sorted(
                fuzzy_matches,
                key=lambda row: (row["required"], row["matched"], row["source"]),
            ),
        }

    except SchemaFailure as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_MARKER_SCHEMA
    except ToolFailure as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_TOOL_ERROR

    if args.output_json:
        try:
            write_json(Path(args.output_json), report)
        except OSError as exc:
            print(f"ERROR: failed writing output-json: {exc}", file=sys.stderr)
            return EXIT_TOOL_ERROR

    print(
        "Roadmap evidence audit: "
        f"requirements={report['requirements']['total']} "
        f"gaps={report['counts']['all_gaps']} "
        f"story_owned={report['counts']['story_owned_gaps']}"
    )

    if args.ci:
        if args.strict and report["counts"]["story_owned_gaps"] > 0:
            return EXIT_STRICT_GAPS

    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
