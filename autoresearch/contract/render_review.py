#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, NoReturn

from jsonschema import Draft202012Validator

HASH_PATTERN = r"^[0-9a-f]{64}$"
CONTRACT_PATCH_PATH = "specs/CONTRACT.md"


def fail(message: str) -> NoReturn:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")
    return None


def canonical_json_hash(payload: Any) -> str:
    data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except FileNotFoundError:
        fail(f"missing file required for hash provenance: {path}")
    return ""


def load_schema(path: Path) -> dict[str, Any]:
    schema = load_json(path)
    if not isinstance(schema, dict):
        fail(f"schema must be a JSON object: {path}")
    return schema


def validate_json(instance: Any, schema: dict[str, Any], label: str) -> None:
    validator = Draft202012Validator(schema)
    errors = sorted(
        validator.iter_errors(instance), key=lambda e: list(e.absolute_path)
    )
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        fail(f"{label} schema validation failed at {location}: {first.message}")


def phase2_root(repo_root: Path) -> Path:
    return repo_root / "autoresearch" / "contract" / "phase2"


def review_path_for_run(phase2_dir: Path, run_id: str) -> Path:
    return phase2_dir / "review" / f"REVIEW_DECISIONS_{run_id}.json"


def proposals_markdown_path(phase2_dir: Path, run_id: str) -> Path:
    return phase2_dir / "proposals" / f"CONTRACT_PROPOSALS_{run_id}.md"


def review_markdown_path(phase2_dir: Path, run_id: str) -> Path:
    return phase2_dir / "review" / f"CONTRACT_REVIEW_{run_id}.md"


def patch_output_path(phase2_dir: Path, run_id: str) -> Path:
    return phase2_dir / "review" / f"CONTRACT_PATCH_{run_id}.patch"


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def index_entries(index_data: Any) -> list[dict[str, Any]]:
    if isinstance(index_data, list):
        entries = index_data
    elif isinstance(index_data, dict):
        if isinstance(index_data.get("entries"), list):
            entries = index_data["entries"]
        elif isinstance(index_data.get("runs"), list):
            entries = index_data["runs"]
        else:
            fail(
                "phase2/proposals_index.json must be a list or contain an entries/runs array"
            )
    else:
        fail("phase2/proposals_index.json must be a JSON array or object")
    for entry in entries:
        if not isinstance(entry, dict):
            fail("phase2/proposals_index.json contains a non-object entry")
    return entries


def load_index_entry(phase2_dir: Path, run_id: str) -> dict[str, Any] | None:
    index_path = phase2_dir / "proposals_index.json"
    if not index_path.exists():
        return None
    data = load_json(index_path)
    for entry in index_entries(data):
        if entry.get("run_id") == run_id:
            return entry
    return None


def discover_run_id(phase2_dir: Path) -> str:
    outputs_dir = phase2_dir / "outputs"
    if not outputs_dir.exists():
        fail("phase2/outputs is missing; no run_id to discover")
    run_dirs = [path for path in outputs_dir.iterdir() if path.is_dir()]
    if not run_dirs:
        fail("phase2/outputs has no run directories; pass --run-id")
    latest = max(run_dirs, key=lambda path: (path.stat().st_mtime_ns, path.name))
    return latest.name


def load_proposals(
    phase2_dir: Path, run_id: str
) -> tuple[list[Path], list[dict[str, Any]], str]:
    outputs_dir = phase2_dir / "outputs" / run_id
    if not outputs_dir.exists():
        fail(f"missing run output directory: {outputs_dir}")

    schema = load_schema(phase2_dir / "proposals.schema.json")
    proposal_paths = sorted(outputs_dir.glob("*/proposals.json"))
    if not proposal_paths:
        fail(f"no proposals.json files found under {outputs_dir}")

    combined_for_hash: list[dict[str, Any]] = []
    proposals: list[dict[str, Any]] = []

    for path in proposal_paths:
        payload = load_json(path)
        validate_json(payload, schema, str(path))
        fixture_id = path.parent.name
        combined_for_hash.append(
            {
                "fixture_id": fixture_id,
                "path": str(path.relative_to(phase2_dir.parent.parent)),
                "payload": payload,
            }
        )
        for proposal in payload.get("proposals", []):
            proposal_copy = dict(proposal)
            proposal_copy["_fixture_id"] = fixture_id
            proposal_copy["_source_path"] = str(
                path.relative_to(phase2_dir.parent.parent)
            )
            proposals.append(proposal_copy)

    if not proposals:
        fail(f"run {run_id} contains no proposals")

    proposal_ids = [proposal["proposal_id"] for proposal in proposals]
    if len(set(proposal_ids)) != len(proposal_ids):
        fail(f"duplicate proposal_id detected in run {run_id}")

    dedupe_keys = [proposal["dedupe_key"] for proposal in proposals]
    if len(set(dedupe_keys)) != len(dedupe_keys):
        fail(f"duplicate dedupe_key detected across fixtures in run {run_id}")

    return proposal_paths, proposals, canonical_json_hash(combined_for_hash)


def render_proposals_markdown(
    run_id: str, proposals_hash: str, proposals: list[dict[str, Any]]
) -> str:
    lines = [
        "# Contract Proposals",
        "",
        f"- run_id: `{run_id}`",
        f"- proposals_file_hash: `{proposals_hash}`",
        f"- proposal_count: `{len(proposals)}`",
        "",
    ]
    for proposal in proposals:
        lines.extend(
            [
                f"## {proposal['proposal_id']}",
                "",
                f"- fixture: `{proposal['_fixture_id']}`",
                f"- source_path: `{proposal['_source_path']}`",
                f"- section: `{proposal['section']}`",
                f"- source_finding: `{proposal['source_finding']}`",
                f"- source_finding_category: `{proposal['source_finding_category']}`",
                f"- change_type: `{proposal['change_type']}`",
                f"- status: `{proposal['status']}`",
                f"- dedupe_key: `{proposal['dedupe_key']}`",
                "",
                "### Rationale",
                "",
                proposal["rationale"].strip() or "_none_",
                "",
            ]
        )
        if proposal.get("proposed_text"):
            lines.extend(
                [
                    "### Proposed Text",
                    "",
                    "```text",
                    proposal["proposed_text"].rstrip(),
                    "```",
                    "",
                ]
            )
        if proposal.get("diff_preview"):
            lines.extend(
                [
                    "### Diff Preview",
                    "",
                    "```diff",
                    proposal["diff_preview"].rstrip(),
                    "```",
                    "",
                ]
            )
    return "\n".join(lines).rstrip() + "\n"


def render_review_markdown(
    run_id: str,
    contract_file_hash: str,
    proposals_hash: str,
    proposals: list[dict[str, Any]],
) -> str:
    lines = [
        "# Contract Review Package",
        "",
        f"- run_id: `{run_id}`",
        f"- contract_file_hash: `{contract_file_hash}`",
        f"- proposals_file_hash: `{proposals_hash}`",
        f"- proposal_count: `{len(proposals)}`",
        "",
        "## Manual Review Checklist",
        "",
        "1. Read every proposal below.",
        "2. Record one decision per proposal in `REVIEW_DECISIONS_<run_id>.json`.",
        "3. Use `accepted`, `rejected`, or `pending_scope_review` only.",
        "4. Re-run `harness.sh contract render-review --accepted-only` after writing review decisions.",
        "5. Do not apply any accepted-only patch if the live `CONTRACT.md` hash differs from the recorded `contract_file_hash`.",
        "",
    ]
    for proposal in proposals:
        lines.extend(
            [
                f"## {proposal['proposal_id']} — {proposal['source_finding_category']}",
                "",
                f"- fixture: `{proposal['_fixture_id']}`",
                f"- source_path: `{proposal['_source_path']}`",
                f"- section: `{proposal['section']}`",
                f"- change_type: `{proposal['change_type']}`",
                f"- source_finding: `{proposal['source_finding']}`",
                f"- current_status: `{proposal['status']}`",
                "",
                "### Rationale",
                "",
                proposal["rationale"].strip() or "_none_",
                "",
            ]
        )
        if proposal.get("proposed_text"):
            lines.extend(
                [
                    "### Proposed Text",
                    "",
                    "```text",
                    proposal["proposed_text"].rstrip(),
                    "```",
                    "",
                ]
            )
        if proposal.get("diff_preview"):
            lines.extend(
                [
                    "### Diff Preview",
                    "",
                    "```diff",
                    proposal["diff_preview"].rstrip(),
                    "```",
                    "",
                ]
            )
    return "\n".join(lines).rstrip() + "\n"


def normalize_patch_fragment(fragment: str, proposal_id: str) -> str:
    text = fragment.strip("\n")
    if not text:
        fail(f"accepted proposal {proposal_id} is missing diff_preview")
    lines = text.splitlines()
    git_headers = [line for line in lines if line.startswith("diff --git ")]
    minus_headers = [line for line in lines if line.startswith("--- ")]
    plus_headers = [line for line in lines if line.startswith("+++ ")]

    has_git_header = len(git_headers) == 1
    has_unified_headers = len(minus_headers) == 1 and len(plus_headers) == 1
    if not has_git_header and not has_unified_headers:
        fail(
            f"accepted proposal {proposal_id} diff_preview is not a git-applicable patch fragment"
        )
    if len(git_headers) > 1 or len(minus_headers) > 1 or len(plus_headers) > 1:
        fail(f"accepted proposal {proposal_id} diff_preview touches multiple files")
    if has_git_header and not has_unified_headers:
        fail(
            f"accepted proposal {proposal_id} diff_preview must include both ---/+++ "
            "unified diff headers"
        )

    forbidden_headers = (
        "rename from ",
        "rename to ",
        "new file mode ",
        "deleted file mode ",
        "similarity index ",
        "copy from ",
        "copy to ",
    )
    for line in lines:
        if line.startswith(forbidden_headers):
            fail(
                f"accepted proposal {proposal_id} uses unsupported patch header '{line}'"
            )

    expected_git_header = f"diff --git a/{CONTRACT_PATCH_PATH} b/{CONTRACT_PATCH_PATH}"
    expected_minus = f"--- a/{CONTRACT_PATCH_PATH}"
    expected_plus = f"+++ b/{CONTRACT_PATCH_PATH}"

    if has_git_header and git_headers[0] != expected_git_header:
        fail(
            f"accepted proposal {proposal_id} diff_preview must target only {CONTRACT_PATCH_PATH}"
        )
    if has_unified_headers and (minus_headers[0] != expected_minus or plus_headers[0] != expected_plus):
        fail(
            f"accepted proposal {proposal_id} diff_preview must target only {CONTRACT_PATCH_PATH}"
        )

    return text + "\n"


def load_review_decisions(
    phase2_dir: Path,
    run_id: str,
    review_override: Path | None,
    contract_file_hash: str,
    proposals_hash: str,
    proposal_ids: list[str],
) -> dict[str, dict[str, Any]]:
    path = (
        review_override
        if review_override is not None
        else review_path_for_run(phase2_dir, run_id)
    )
    payload = load_json(path)
    schema = load_schema(phase2_dir / "review.schema.json")
    validate_json(payload, schema, str(path))

    if payload["run_id"] != run_id:
        fail(f"review run_id mismatch: expected {run_id}, found {payload['run_id']}")
    if payload["contract_file_hash"] != contract_file_hash:
        fail("review contract_file_hash does not match current batch metadata")
    if payload["proposals_file_hash"] != proposals_hash:
        fail("review proposals_file_hash does not match current batch proposals hash")

    decision_map: dict[str, dict[str, Any]] = {}
    for decision in payload["decisions"]:
        proposal_id = decision["proposal_id"]
        if proposal_id in decision_map:
            fail(f"duplicate review decision for proposal_id {proposal_id}")
        decision_map[proposal_id] = decision

    expected = set(proposal_ids)
    actual = set(decision_map)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        fail("review decisions omitted proposal ids: " + ", ".join(missing))
    if extra:
        fail("review decisions reference unknown proposal ids: " + ", ".join(extra))

    return decision_map


def write_text(path: Path, content: str) -> None:
    ensure_parent(path)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render contract autoresearch review artifacts"
    )
    parser.add_argument(
        "--root", type=Path, default=default_repo_root(), help="Repository root"
    )
    parser.add_argument("--run-id", help="Phase 2 run id")
    parser.add_argument(
        "--accepted-only",
        action="store_true",
        help="Render CONTRACT_PATCH_<run_id>.patch from accepted review decisions",
    )
    parser.add_argument(
        "--review",
        type=Path,
        help="Path to REVIEW_DECISIONS_<run_id>.json (defaults to phase2/review/...)",
    )
    args = parser.parse_args()

    repo_root = args.root.resolve()
    p2 = phase2_root(repo_root)
    run_id = args.run_id or discover_run_id(p2)
    _, proposals, proposals_hash = load_proposals(p2, run_id)
    index_entry = load_index_entry(p2, run_id)
    if index_entry is None:
        fail(f"missing proposals_index entry for run_id={run_id}")
    contract_file_hash = index_entry.get("contract_file_hash")
    if not isinstance(contract_file_hash, str) or not re.fullmatch(
        HASH_PATTERN, contract_file_hash
    ):
        fail(
            f"run_id={run_id} is missing a valid contract_file_hash in proposals_index.json"
        )

    proposals_md = render_proposals_markdown(run_id, proposals_hash, proposals)
    review_md = render_review_markdown(
        run_id, contract_file_hash, proposals_hash, proposals
    )
    write_text(proposals_markdown_path(p2, run_id), proposals_md)
    write_text(review_markdown_path(p2, run_id), review_md)

    if args.accepted_only:
        live_contract_hash = file_sha256(repo_root / CONTRACT_PATCH_PATH)
        if live_contract_hash != contract_file_hash:
            fail(
                "live specs/CONTRACT.md hash differs from recorded contract_file_hash; "
                "re-run contract autoresearch before rendering accepted-only patches"
            )
        proposal_ids = [proposal["proposal_id"] for proposal in proposals]
        decisions = load_review_decisions(
            p2,
            run_id,
            args.review.resolve() if args.review is not None else None,
            contract_file_hash,
            proposals_hash,
            proposal_ids,
        )
        contract_path = repo_root / CONTRACT_PATCH_PATH
        if not contract_path.exists():
            fail(f"live contract file not found: {contract_path}")
        contract_text = contract_path.read_text(encoding="utf-8")

        accepted_fragments: list[str] = []
        for proposal in proposals:
            pid = proposal["proposal_id"]
            decision = decisions[pid]["decision"]
            if decision == "accepted":
                replace_span = proposal.get("replace_span")
                if replace_span is not None:
                    old_text = replace_span.get("old_text", "")
                    if old_text and old_text not in contract_text:
                        fail(
                            f"accepted proposal {pid} replace_span.old_text not found in live "
                            f"{CONTRACT_PATCH_PATH} — contract may have changed since proposals "
                            f"were generated; re-run harness.sh contract refresh-common"
                        )
                accepted_fragments.append(
                    normalize_patch_fragment(
                        proposal.get("diff_preview", ""),
                        pid,
                    )
                )
        write_text(patch_output_path(p2, run_id), "".join(accepted_fragments))

    print(f"OK: rendered review artifacts for run_id={run_id}")
    if args.accepted_only:
        print(f"OK: rendered accepted-only patch at {patch_output_path(p2, run_id)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
