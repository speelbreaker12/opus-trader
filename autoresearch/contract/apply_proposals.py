#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any


APPLYABLE_STATUSES = {"proposed"}


def fail(message: str) -> None:
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


def normalize_ws(text: str) -> str:
    return " ".join(text.split())


def load_applyable_proposals(path: Path) -> list[dict[str, Any]]:
    payload = load_json(path)
    proposals = payload.get("proposals")
    if not isinstance(proposals, list):
        fail(f"{path} must contain a proposals array")
    applyable: list[dict[str, Any]] = []
    for proposal in proposals:
        if not isinstance(proposal, dict):
            fail(f"{path} contains a non-object proposal")
        if proposal.get("status") in APPLYABLE_STATUSES:
            applyable.append(proposal)
    return applyable


def validate_mechanical_proposals(fixture_text: str, proposals: list[dict[str, Any]]) -> None:
    occupied: list[tuple[int, int, str]] = []
    fixture_lines = fixture_text.splitlines()

    for proposal in proposals:
        if proposal.get("mechanical_ok") is not True:
            continue
        replace_span = proposal.get("replace_span")
        if not isinstance(replace_span, dict):
            fail(f"{proposal.get('proposal_id', '<unknown>')} missing replace_span")
        start_line = replace_span.get("start_line")
        end_line = replace_span.get("end_line")
        old_text = replace_span.get("old_text")
        new_text = replace_span.get("new_text")
        proposal_id = proposal.get("proposal_id", "<unknown>")

        if not all(isinstance(value, int) for value in (start_line, end_line)):
            fail(f"{proposal_id} has non-integer replace_span line bounds")
        if not all(isinstance(value, str) for value in (old_text, new_text)):
            fail(f"{proposal_id} has non-string replace_span text fields")
        if start_line < 1 or end_line < start_line:
            fail(f"{proposal_id} has invalid replace_span bounds")
        if end_line > len(fixture_lines):
            fail(f"{proposal_id} replace_span exceeds fixture length")

        if fixture_text.count(old_text) != 1:
            fail(f"{proposal_id} old_text does not resolve to one unique exact target slice")

        slice_text = "\n".join(fixture_lines[start_line - 1:end_line])
        if slice_text != old_text:
            fail(f"{proposal_id} replace_span old_text mismatch at declared line range")

        if normalize_ws(old_text) == normalize_ws(new_text):
            fail(f"{proposal_id} replace_span new_text is a no-op after normalization")

        current = (start_line, end_line, proposal_id)
        for other_start, other_end, other_id in occupied:
            if not (end_line < other_start or start_line > other_end):
                fail(f"{proposal_id} overlaps mechanical proposal {other_id}")
        occupied.append(current)


def apply_fixture_proposals(fixture_text: str, proposals: list[dict[str, Any]]) -> tuple[str, int]:
    validate_mechanical_proposals(fixture_text, proposals)
    lines = fixture_text.splitlines()
    applied_count = 0

    mechanical = [
        proposal
        for proposal in proposals
        if proposal.get("mechanical_ok") is True and isinstance(proposal.get("replace_span"), dict)
    ]
    for proposal in sorted(
        mechanical,
        key=lambda item: item["replace_span"]["start_line"],
        reverse=True,
    ):
        replace_span = proposal["replace_span"]
        start = replace_span["start_line"] - 1
        end = replace_span["end_line"]
        replacement_lines = replace_span["new_text"].splitlines()
        lines[start:end] = replacement_lines
        applied_count += 1

    patched = "\n".join(lines)
    append_blocks = [
        proposal["proposed_text"].strip()
        for proposal in proposals
        if proposal.get("change_type") == "new_requirement"
        and proposal.get("status") in APPLYABLE_STATUSES
        and isinstance(proposal.get("proposed_text"), str)
        and proposal["proposed_text"].strip()
    ]
    if append_blocks:
        suffix = "\n\n".join(append_blocks)
        patched = f"{patched.rstrip()}\n\n{suffix}\n"
        applied_count += len(append_blocks)
    elif fixture_text.endswith("\n"):
        patched = f"{patched}\n"

    return patched, applied_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply contract proposals to a fixture copy")
    parser.add_argument("--fixture", required=True, type=Path)
    parser.add_argument("--proposals", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--json", action="store_true", dest="json_output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        fixture_text = args.fixture.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing fixture file: {args.fixture}")

    proposals = load_applyable_proposals(args.proposals)
    patched_text, applied_count = apply_fixture_proposals(fixture_text, proposals)
    changed = patched_text != fixture_text
    if applied_count > 0 and not changed:
        fail("proposal application produced no fixture diff")
    write_text_atomic(args.output, patched_text)

    if args.json_output:
        print(json.dumps({
            "applied_count": applied_count,
            "changed": changed,
            "output_path": str(args.output),
        }))
    else:
        print(f"applied_count={applied_count} changed={'yes' if changed else 'no'} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
