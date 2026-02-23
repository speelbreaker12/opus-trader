#!/usr/bin/env python3
"""Validate a single review artifact's provenance header and review metadata.

Supports:
  - Markdown (.md) with YAML front matter (dash-prefixed provenance lines)
  - JSON (.json) with top-level provenance object

Exit codes:
  0 = PASS
  1 = CLI_USAGE_ERROR
  2 = FILE_IO_ERROR
  3 = PARSE_ERROR
  4 = VALIDATION_FAIL
  5 = INTERNAL_ERROR
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import traceback
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION = "v1"
VALIDATOR_NAME = "validate_review_header"

HEXSHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
ISO8601Z_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

VALID_TOOLS = {"codex", "opus", "kimi", "script"}
VALID_PROMPT_STYLES = {"generic", "enriched", "none"}
VALID_CYCLES = {"C1", "C2", "SELF", "NONE"}
VALID_PHASES = {
    "R1", "R2", "R3", "R4", "R4b", "R5", "R5b",
    "R6", "R7a", "R7b", "R7c", "R7d", "R7e", "R7f",
}

# JSON artifacts (manifest entries) carry full provenance.
REQUIRED_PROVENANCE_FIELDS_JSON = [
    "tool", "model", "prompt_style", "cycle", "phase_equivalent",
]
# Markdown artifacts (review_logged.sh output) carry a smaller set.
# cycle / phase_equivalent / review_basis / slice_id are manifest-level.
# model is only emitted for opus/kimi (codex omits it).
REQUIRED_PROVENANCE_FIELDS_MD = [
    "story_id", "head_commit", "prompt_style", "artifact_provenance",
]
RECOMMENDED_PROVENANCE_FIELDS = [
    "tool", "model", "prompt_style", "cycle", "phase_equivalent",
    "review_basis", "story_id", "slice_id", "head_commit",
    "generated_at", "artifact_provenance",
]

REVIEW_META_SECTION_RE = re.compile(r"^review_meta:\s*$")
YAML_FENCE_RE = re.compile(r"^---\s*$")


# ---------------------------------------------------------------------------
# Provenance extraction
# ---------------------------------------------------------------------------

def extract_provenance_md(content: str) -> dict[str, str] | None:
    """Extract provenance from markdown dash-prefixed header lines.

    Handles two formats:
    1. YAML front matter (--- delimited block at top)
    2. Dash-prefixed lines: ``- Key: Value``
    """
    prov: dict[str, str] = {}

    # Try YAML front matter first (--- block at file start)
    lines = content.split("\n")
    if lines and lines[0].strip() == "---":
        for line in lines[1:]:
            if line.strip() == "---":
                break
            m = re.match(r"^([a-z_]+):\s*(.+)$", line.strip())
            if m:
                prov[m.group(1)] = m.group(2).strip()
        if prov:
            return prov

    # Fall back to dash-prefixed header lines: "- Key: Value"
    key_map = {
        "story": "story_id",
        "slice": "slice_id",
        "timestamp (utc)": "generated_at",
        "head": "head_commit",
        "base ref": "base_commit",
        "branch": "branch",
        "mode": "mode",
        "model": "model",
        "prompt style": "prompt_style",
        "tool": "tool",
        "artifact provenance": "artifact_provenance",
        "generator script": "generator_script",
        "command exit code": "command_exit_code",
        "transcript sha256": "transcript_sha256",
        "transcript bytes": "transcript_bytes",
        "duration seconds": "duration_seconds",
        "codex mode": "codex_mode",
        "commit ref": "commit_ref",
        "files": "files",
        "command": "command",
        "cycle": "cycle",
        "phase equivalent": "phase_equivalent",
        "review basis": "review_basis",
    }
    for line in lines:
        m = re.match(r"^- ([^:]+):\s*(.+)$", line)
        if m:
            raw_key = m.group(1).strip().lower()
            val = m.group(2).strip()
            mapped = key_map.get(raw_key)
            if mapped:
                prov[mapped] = val
            else:
                # Use raw key with underscores
                prov[raw_key.replace(" ", "_")] = val

    return prov if prov else None


def extract_provenance_json(data: dict[str, Any]) -> dict[str, Any] | None:
    """Extract provenance from JSON with top-level provenance object."""
    prov = data.get("provenance")
    if isinstance(prov, dict):
        return prov
    return None


# ---------------------------------------------------------------------------
# Review meta extraction (reused from validate_external_manifest.py)
# ---------------------------------------------------------------------------

def parse_review_meta(content: str) -> dict[str, Any] | None:
    """Parse review_meta YAML block from markdown content."""
    lines = content.split("\n")
    in_meta_block = False
    meta_start = -1

    for i, line in enumerate(lines):
        if YAML_FENCE_RE.match(line.strip()):
            if in_meta_block:
                break
            for j in range(i + 1, min(i + 5, len(lines))):
                if REVIEW_META_SECTION_RE.match(lines[j].strip()):
                    in_meta_block = True
                    meta_start = i + 1
                    break

    if not in_meta_block or meta_start < 0:
        return None

    result: dict[str, Any] = {
        "evidence_citations": {
            "preexisting_enforcement": [],
            "preexisting_tests": [],
        },
        "checks": {},
    }

    current_list: list[str] | None = None
    for line in lines[meta_start:]:
        stripped = line.strip()
        if stripped == "---":
            break
        if stripped in ("review_meta:", "evidence_citations:"):
            continue
        if stripped.startswith("preexisting_enforcement:"):
            rest = stripped.split(":", 1)[1].strip()
            if rest == "[]":
                current_list = None
            else:
                current_list = result["evidence_citations"]["preexisting_enforcement"]
            continue
        if stripped.startswith("preexisting_tests:"):
            rest = stripped.split(":", 1)[1].strip()
            if rest == "[]":
                current_list = None
            else:
                current_list = result["evidence_citations"]["preexisting_tests"]
            continue
        if stripped == "checks:":
            current_list = None
            continue
        if stripped.startswith("diff_only_review_rejected:"):
            val_str = stripped.split(":", 1)[1].strip()
            result["checks"]["diff_only_review_rejected"] = val_str == "true"
            continue
        if stripped.startswith("- ") and current_list is not None:
            val = stripped[2:].strip().strip('"')
            current_list.append(val)

    return result


# ---------------------------------------------------------------------------
# Validation logic
# ---------------------------------------------------------------------------

class ValidationResult:
    def __init__(self, artifact_path: str, artifact_type: str) -> None:
        self.artifact_path = artifact_path
        self.artifact_type = artifact_type
        self.provenance: dict[str, Any] = {}
        self.checks: dict[str, bool] = {}
        self.failure_codes: list[str] = []
        self.warnings: list[str] = []

    @property
    def status(self) -> str:
        return "FAIL" if self.failure_codes else "PASS"

    def fail(self, code: str) -> None:
        if code not in self.failure_codes:
            self.failure_codes.append(code)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def check(self, name: str, passed: bool) -> bool:
        self.checks[name] = passed
        return passed

    def to_dict(self) -> dict[str, Any]:
        return {
            "validator": VALIDATOR_NAME,
            "version": VERSION,
            "status": self.status,
            "artifact_path": self.artifact_path,
            "artifact_type": self.artifact_type,
            "provenance": self.provenance,
            "checks": self.checks,
            "failure_codes": self.failure_codes,
            "warnings": self.warnings,
        }


def validate(
    artifact_path: Path,
    content: str,
    prov: dict[str, Any],
    args: argparse.Namespace,
) -> ValidationResult:
    artifact_type = "json" if artifact_path.suffix == ".json" else "markdown"
    r = ValidationResult(str(artifact_path), artifact_type)
    r.provenance = dict(prov)

    # --- Provenance presence ---
    r.check("provenance_present", True)

    # --- Required fields (type-aware) ---
    required = (REQUIRED_PROVENANCE_FIELDS_JSON if artifact_type == "json"
                else REQUIRED_PROVENANCE_FIELDS_MD)
    all_present = True
    for field in required:
        if field not in prov or not prov[field]:
            r.fail("PROVENANCE_FIELD_MISSING")
            all_present = False
    r.check("required_fields_present", all_present)

    # --- Recommended fields (warn only) ---
    for field in RECOMMENDED_PROVENANCE_FIELDS:
        if field not in prov:
            r.warn(f"recommended field '{field}' missing")

    # --- Empty values ---
    for k, v in prov.items():
        if isinstance(v, str) and v.strip() == "":
            r.fail("PROVENANCE_EMPTY_VALUE")

    # --- Strict: unknown fields ---
    if args.strict:
        known = set(RECOMMENDED_PROVENANCE_FIELDS) | {
            "base_commit", "schema_version", "generator_script",
        }
        for k in prov:
            if k not in known:
                r.fail("PROVENANCE_UNKNOWN_FIELD")
                r.warn(f"unknown provenance field: '{k}'")

    # --- Field enum validity ---
    # Validate values when present; only fail on absence for JSON artifacts
    # (which carry full provenance). MD artifacts rely on REQUIRED_PROVENANCE_FIELDS_MD.
    enums_valid = True
    is_json = artifact_type == "json"

    tool = prov.get("tool", "")
    if tool and tool not in VALID_TOOLS:
        r.fail("TOOL_INVALID")
        enums_valid = False

    model = prov.get("model", "")
    if is_json and not model:
        r.fail("MODEL_MISSING")
        enums_valid = False

    ps = prov.get("prompt_style", "")
    if ps and ps not in VALID_PROMPT_STYLES:
        r.fail("PROMPT_STYLE_INVALID")
        enums_valid = False

    cycle = prov.get("cycle", "")
    if cycle and cycle not in VALID_CYCLES:
        r.fail("CYCLE_INVALID")
        enums_valid = False
    elif is_json and not cycle:
        r.fail("CYCLE_INVALID")
        enums_valid = False

    phase = prov.get("phase_equivalent", "")
    if phase and phase not in VALID_PHASES:
        r.fail("PHASE_EQUIVALENT_INVALID")
        enums_valid = False
    elif is_json and not phase:
        r.fail("PHASE_EQUIVALENT_INVALID")
        enums_valid = False

    head = prov.get("head_commit", "")
    if not head:
        r.fail("HEAD_COMMIT_MISSING")
        enums_valid = False
    elif not HEXSHA_RE.match(head):
        r.fail("HEAD_COMMIT_INVALID")
        enums_valid = False

    gen_at = prov.get("generated_at", "")
    if gen_at and not ISO8601Z_RE.match(gen_at):
        r.fail("TIMESTAMP_INVALID")
        enums_valid = False

    if not prov.get("artifact_provenance"):
        r.fail("ARTIFACT_PROVENANCE_MISSING")
        enums_valid = False

    review_basis = prov.get("review_basis", "")
    if is_json and not review_basis:
        r.fail("REVIEW_BASIS_MISSING")
        enums_valid = False

    if not prov.get("story_id"):
        r.fail("STORY_ID_MISSING")
        enums_valid = False

    slice_id = prov.get("slice_id", "")
    if is_json and not slice_id:
        r.fail("SLICE_ID_MISSING")
        enums_valid = False

    r.check("field_enums_valid", enums_valid)

    # --- Expectation checks ---
    if args.expect_tool and tool != args.expect_tool:
        r.fail("TOOL_INVALID")
    if args.expect_cycle and cycle != args.expect_cycle:
        r.fail("CYCLE_INVALID")
    if args.expect_phase and phase != args.expect_phase:
        r.fail("PHASE_EQUIVALENT_INVALID")
    if args.expect_prompt_style and ps != args.expect_prompt_style:
        r.fail("PROMPT_STYLE_INVALID")
    if args.expect_review_basis:
        basis = prov.get("review_basis", "")
        if basis != args.expect_review_basis:
            r.fail("REVIEW_BASIS_MISMATCH")
        r.check("review_basis_match", basis == args.expect_review_basis)
    else:
        r.check("review_basis_match", True)

    if args.expect_story_id:
        if prov.get("story_id") != args.expect_story_id:
            r.fail("STORY_ID_MISSING")
    if args.expect_slice_id:
        if prov.get("slice_id") != args.expect_slice_id:
            r.fail("SLICE_ID_MISSING")

    if args.expect_head_commit:
        h = prov.get("head_commit", "")
        if h != args.expect_head_commit:
            r.fail("HEAD_COMMIT_MISMATCH")
        r.check("head_commit_match", h == args.expect_head_commit)
    else:
        r.check("head_commit_match", True)

    if args.expect_base_commit:
        b = prov.get("base_commit", "")
        if not b:
            r.fail("BASE_COMMIT_MISSING")
            r.check("base_commit_match", False)
        elif b != args.expect_base_commit:
            r.fail("BASE_COMMIT_MISMATCH")
            r.check("base_commit_match", False)
        else:
            r.check("base_commit_match", True)
    else:
        bc = prov.get("base_commit", "")
        if bc and not HEXSHA_RE.match(bc) and bc != "main":
            r.fail("BASE_COMMIT_INVALID")
        r.check("base_commit_match", True)

    # --- External review meta checks ---
    meta: dict[str, Any] | None = None
    if args.require_external_review_meta:
        meta = parse_review_meta(content)
        if meta is None:
            r.fail("REVIEW_META_MISSING")
            r.check("external_review_meta_present", False)
            r.check("preexisting_enforcement_citation_present", False)
            r.check("preexisting_test_citation_present", False)
            r.check("diff_only_review_rejected", False)
        else:
            r.check("external_review_meta_present", True)
            cites = meta.get("evidence_citations", {})
            meta_checks = meta.get("checks", {})

            enforcement = cites.get("preexisting_enforcement", [])
            tests = cites.get("preexisting_tests", [])

            if "evidence_citations" not in meta or not cites:
                r.fail("EVIDENCE_CITATIONS_MISSING")

            # Enforcement citations
            if args.require_preexisting_citations:
                if not enforcement:
                    r.fail("PREEXISTING_ENFORCEMENT_CITATION_MISSING")
                    r.check("preexisting_enforcement_citation_present", False)
                else:
                    r.check("preexisting_enforcement_citation_present", True)

                if not tests:
                    r.fail("PREEXISTING_TEST_CITATION_MISSING")
                    r.check("preexisting_test_citation_present", False)
                else:
                    r.check("preexisting_test_citation_present", True)
            else:
                r.check("preexisting_enforcement_citation_present", len(enforcement) > 0)
                r.check("preexisting_test_citation_present", len(tests) > 0)

            # Diff-only rejection
            if args.require_diff_only_rejected:
                rejected = meta_checks.get("diff_only_review_rejected")
                if rejected is None:
                    r.fail("DIFF_ONLY_REJECT_FLAG_MISSING")
                    r.check("diff_only_review_rejected", False)
                elif not rejected:
                    r.fail("DIFF_ONLY_REJECT_FLAG_FALSE")
                    r.check("diff_only_review_rejected", False)
                else:
                    r.check("diff_only_review_rejected", True)
            else:
                rejected = meta_checks.get("diff_only_review_rejected") if meta_checks else None
                r.check("diff_only_review_rejected", rejected is True)
    else:
        r.check("external_review_meta_present", True)
        r.check("preexisting_enforcement_citation_present", True)
        r.check("preexisting_test_citation_present", True)
        r.check("diff_only_review_rejected", True)

    return r


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="validate_review_header.py",
        description="Validate review artifact provenance header and metadata.",
    )
    p.add_argument("--artifact", required=True, help="Path to review artifact")
    p.add_argument("--format", dest="fmt", choices=["json", "text"], default="text",
                   help="Output format (default: text)")
    p.add_argument("--expect-tool", default=None)
    p.add_argument("--expect-cycle", default=None)
    p.add_argument("--expect-phase", default=None)
    p.add_argument("--expect-prompt-style", default=None)
    p.add_argument("--expect-review-basis", default=None)
    p.add_argument("--expect-story-id", default=None)
    p.add_argument("--expect-slice-id", default=None)
    p.add_argument("--expect-head-commit", default=None)
    p.add_argument("--expect-base-commit", default=None)
    p.add_argument("--require-external-review-meta", action="store_true")
    p.add_argument("--require-preexisting-citations", action="store_true")
    p.add_argument("--require-diff-only-rejected", action="store_true")
    p.add_argument("--strict", action="store_true",
                   help="Reject unknown provenance fields")
    return p


def main() -> int:
    parser = build_parser()
    try:
        args = parser.parse_args()
    except SystemExit:
        return 1  # CLI_USAGE_ERROR

    artifact_path = Path(args.artifact)

    # --- File IO ---
    if not artifact_path.exists():
        msg = f"file not found: {artifact_path}"
        if args.fmt == "json":
            print(json.dumps({
                "validator": VALIDATOR_NAME, "version": VERSION,
                "status": "FAIL", "artifact_path": str(artifact_path),
                "error": msg, "failure_codes": ["FILE_IO_ERROR"],
            }, indent=2))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2  # FILE_IO_ERROR

    try:
        content = artifact_path.read_text(encoding="utf-8")
    except OSError as e:
        msg = f"cannot read: {e}"
        if args.fmt == "json":
            print(json.dumps({
                "validator": VALIDATOR_NAME, "version": VERSION,
                "status": "FAIL", "artifact_path": str(artifact_path),
                "error": msg, "failure_codes": ["FILE_IO_ERROR"],
            }, indent=2))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2  # FILE_IO_ERROR

    # --- Parse provenance ---
    prov: dict[str, Any] | None = None
    if artifact_path.suffix == ".json":
        try:
            data = json.loads(content)
        except json.JSONDecodeError as e:
            msg = f"invalid JSON: {e}"
            if args.fmt == "json":
                print(json.dumps({
                    "validator": VALIDATOR_NAME, "version": VERSION,
                    "status": "FAIL", "artifact_path": str(artifact_path),
                    "error": msg, "failure_codes": ["PARSE_ERROR"],
                }, indent=2))
            else:
                print(f"ERROR: {msg}", file=sys.stderr)
            return 3  # PARSE_ERROR
        prov = extract_provenance_json(data)
    else:
        prov = extract_provenance_md(content)

    if prov is None:
        msg = "provenance block not found"
        if args.fmt == "json":
            r = ValidationResult(str(artifact_path),
                                 "json" if artifact_path.suffix == ".json" else "markdown")
            r.fail("PROVENANCE_BLOCK_MISSING")
            r.check("provenance_present", False)
            print(json.dumps(r.to_dict(), indent=2))
        else:
            print(f"FAIL: {msg}", file=sys.stderr)
        return 4  # VALIDATION_FAIL

    if not isinstance(prov, dict):
        if args.fmt == "json":
            r = ValidationResult(str(artifact_path),
                                 "json" if artifact_path.suffix == ".json" else "markdown")
            r.fail("PROVENANCE_NOT_OBJECT")
            r.check("provenance_present", False)
            print(json.dumps(r.to_dict(), indent=2))
        else:
            print("FAIL: provenance is not an object", file=sys.stderr)
        return 4  # VALIDATION_FAIL

    # --- Validate ---
    try:
        result = validate(artifact_path, content, prov, args)
    except Exception:
        if args.fmt == "json":
            print(json.dumps({
                "validator": VALIDATOR_NAME, "version": VERSION,
                "status": "FAIL", "artifact_path": str(artifact_path),
                "error": traceback.format_exc(),
                "failure_codes": ["INTERNAL_ERROR"],
            }, indent=2))
        else:
            traceback.print_exc()
        return 5  # INTERNAL_ERROR

    # --- Output ---
    if args.fmt == "json":
        print(json.dumps(result.to_dict(), indent=2))
    else:
        if result.status == "PASS":
            print(f"PASS: {artifact_path.name}")
        else:
            print(f"FAIL: {artifact_path.name}")
            for code in result.failure_codes:
                print(f"  - {code}")
        for w in result.warnings:
            print(f"  WARN: {w}")

    return 4 if result.failure_codes else 0


if __name__ == "__main__":
    sys.exit(main())
