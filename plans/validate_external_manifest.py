#!/usr/bin/env python3
"""Validate R3/R7 external manifest JSON against v2 schemas.

DEPRECATED: Use plans/validators/validate_external_manifest.py instead.
This file is kept for backward compatibility and delegates to the new
validator when invoked with the new CLI flags (--manifest).

Legacy usage:
    validate_external_manifest.py <manifest.json> [--check-files]

New usage:
    plans/validators/validate_external_manifest.py --manifest <path> --format json --repo-root .

Options:
    --check-files   Verify artifact_path files exist on disk and sha256 matches
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

HEXSHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ISO8601Z_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

REQUIRED_COMBOS = [
    ("codex", "enriched"),
    ("codex", "generic"),
    ("opus", "enriched"),
    ("opus", "generic"),
]

R3_TOP_REQUIRED = [
    "provenance", "story_id", "slice_id", "phase", "cycle",
    "required_combinations", "reviews", "validation",
]
R7_TOP_REQUIRED = R3_TOP_REQUIRED + ["regression_scope"]

R3_VALIDATION_CHECKS = [
    "status", "review_basis_check",
    "preexisting_enforcement_citation_check",
    "preexisting_test_citation_check",
    "diff_only_review_check",
]
R7_VALIDATION_CHECKS = [
    "status", "review_basis_check",
    "required_combinations_check",
    "head_commit_alignment_check",
    "base_commit_alignment_check",
]

R3_REVIEW_CHECKS = [
    "review_basis_present",
    "preexisting_enforcement_citation_present",
    "preexisting_test_citation_present",
    "diff_only_review_rejected",
]
R7_REVIEW_CHECKS = [
    "review_basis_present",
    "head_commit_matches_manifest",
    "base_commit_matches_manifest",
]

R3_PROV_REQUIRED = [
    "tool", "model", "prompt_style", "cycle", "phase_equivalent",
    "review_basis", "story_id", "slice_id", "head_commit",
    "generated_at", "artifact_provenance", "schema_version",
]
R7_PROV_REQUIRED = R3_PROV_REQUIRED + ["base_commit"]

R3_REVIEW_ENTRY_REQUIRED = [
    "tool", "model", "prompt_style", "cycle", "phase_equivalent",
    "artifact_path", "artifact_sha256", "review_basis", "head_commit",
    "provenance", "checks",
]
R7_REVIEW_ENTRY_REQUIRED = R3_REVIEW_ENTRY_REQUIRED + ["base_commit"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _check_required(obj: dict[str, Any], keys: list[str], ctx: str) -> list[str]:
    """Return list of error strings for missing required keys."""
    errors: list[str] = []
    for k in keys:
        if k not in obj:
            errors.append(f"{ctx}: missing required field '{k}'")
    return errors


def _check_enum(obj: dict[str, Any], key: str, allowed: list[str], ctx: str) -> list[str]:
    val = obj.get(key)
    if val is not None and val not in allowed:
        return [f"{ctx}: '{key}' must be one of {allowed}, got '{val}'"]
    return []


def _check_const(obj: dict[str, Any], key: str, expected: str, ctx: str) -> list[str]:
    val = obj.get(key)
    if val is not None and val != expected:
        return [f"{ctx}: '{key}' must be '{expected}', got '{val}'"]
    return []


def _check_pattern(obj: dict[str, Any], key: str, pattern: re.Pattern[str], ctx: str) -> list[str]:
    val = obj.get(key)
    if val is not None and isinstance(val, str) and not pattern.match(val):
        return [f"{ctx}: '{key}' does not match pattern {pattern.pattern}, got '{val}'"]
    return []


def _check_non_empty_string(obj: dict[str, Any], key: str, ctx: str) -> list[str]:
    val = obj.get(key)
    if val is not None and (not isinstance(val, str) or len(val) == 0):
        return [f"{ctx}: '{key}' must be a non-empty string"]
    return []


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Detect manifest type
# ---------------------------------------------------------------------------

def detect_type(data: dict[str, Any]) -> str | None:
    """Return 'r3' or 'r7' based on phase field, or None if unrecognizable."""
    phase = data.get("phase")
    if phase == "R3":
        return "r3"
    if phase == "R7d":
        return "r7"
    return None


# ---------------------------------------------------------------------------
# Provenance validation
# ---------------------------------------------------------------------------

def validate_provenance_r3(prov: Any, ctx: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(prov, dict):
        return [f"{ctx}: provenance must be an object"]
    errors += _check_required(prov, R3_PROV_REQUIRED, ctx)
    errors += _check_const(prov, "tool", "script", ctx)
    errors += _check_const(prov, "prompt_style", "none", ctx)
    errors += _check_const(prov, "cycle", "C1", ctx)
    errors += _check_const(prov, "phase_equivalent", "R3", ctx)
    errors += _check_const(prov, "review_basis", "STORY_SCOPE (Cycle 1)", ctx)
    errors += _check_const(prov, "schema_version", "r3_external_manifest.v2", ctx)
    errors += _check_pattern(prov, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "generated_at", ISO8601Z_RE, ctx)
    return errors


def validate_provenance_r7(prov: Any, ctx: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(prov, dict):
        return [f"{ctx}: provenance must be an object"]
    errors += _check_required(prov, R7_PROV_REQUIRED, ctx)
    errors += _check_const(prov, "tool", "script", ctx)
    errors += _check_const(prov, "prompt_style", "none", ctx)
    errors += _check_const(prov, "cycle", "C2", ctx)
    errors += _check_const(prov, "phase_equivalent", "R7d", ctx)
    errors += _check_const(prov, "review_basis", "FIX_DIFF + AT_REGRESSION (Cycle 2)", ctx)
    errors += _check_const(prov, "schema_version", "r7_external_manifest.v2", ctx)
    errors += _check_pattern(prov, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "base_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "generated_at", ISO8601Z_RE, ctx)
    return errors


# ---------------------------------------------------------------------------
# Review-entry provenance validation
# ---------------------------------------------------------------------------

def validate_review_provenance_r3(prov: Any, ctx: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(prov, dict):
        return [f"{ctx}: review provenance must be an object"]
    req = [
        "tool", "model", "prompt_style", "cycle", "phase_equivalent",
        "review_basis", "story_id", "slice_id", "head_commit",
        "generated_at", "artifact_provenance",
    ]
    errors += _check_required(prov, req, ctx)
    errors += _check_enum(prov, "tool", ["codex", "opus", "kimi", "gemini"], ctx)
    errors += _check_enum(prov, "prompt_style", ["generic", "enriched"], ctx)
    errors += _check_const(prov, "cycle", "C1", ctx)
    errors += _check_enum(prov, "phase_equivalent", ["R1", "R3"], ctx)
    errors += _check_const(prov, "review_basis", "STORY_SCOPE (Cycle 1)", ctx)
    errors += _check_pattern(prov, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "generated_at", ISO8601Z_RE, ctx)
    errors += _check_non_empty_string(prov, "model", ctx)
    errors += _check_non_empty_string(prov, "story_id", ctx)
    errors += _check_non_empty_string(prov, "slice_id", ctx)
    errors += _check_non_empty_string(prov, "artifact_provenance", ctx)
    return errors


def validate_review_provenance_r7(prov: Any, ctx: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(prov, dict):
        return [f"{ctx}: review provenance must be an object"]
    req = [
        "tool", "model", "prompt_style", "cycle", "phase_equivalent",
        "review_basis", "story_id", "slice_id", "head_commit",
        "base_commit", "generated_at", "artifact_provenance",
    ]
    errors += _check_required(prov, req, ctx)
    errors += _check_enum(prov, "tool", ["codex", "opus", "kimi", "gemini"], ctx)
    errors += _check_enum(prov, "prompt_style", ["generic", "enriched"], ctx)
    errors += _check_const(prov, "cycle", "C2", ctx)
    errors += _check_const(prov, "phase_equivalent", "R7d", ctx)
    errors += _check_const(prov, "review_basis", "FIX_DIFF + AT_REGRESSION (Cycle 2)", ctx)
    errors += _check_pattern(prov, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "base_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(prov, "generated_at", ISO8601Z_RE, ctx)
    errors += _check_non_empty_string(prov, "model", ctx)
    errors += _check_non_empty_string(prov, "story_id", ctx)
    errors += _check_non_empty_string(prov, "slice_id", ctx)
    errors += _check_non_empty_string(prov, "artifact_provenance", ctx)
    return errors


# ---------------------------------------------------------------------------
# Review entry validation
# ---------------------------------------------------------------------------

def validate_review_entry_r3(entry: Any, idx: int, check_files: bool, manifest_dir: Path) -> list[str]:
    ctx = f"reviews[{idx}]"
    errors: list[str] = []
    if not isinstance(entry, dict):
        return [f"{ctx}: must be an object"]
    errors += _check_required(entry, R3_REVIEW_ENTRY_REQUIRED, ctx)
    errors += _check_enum(entry, "tool", ["codex", "opus", "kimi", "gemini"], ctx)
    errors += _check_enum(entry, "prompt_style", ["generic", "enriched"], ctx)
    errors += _check_const(entry, "cycle", "C1", ctx)
    errors += _check_enum(entry, "phase_equivalent", ["R1", "R3"], ctx)
    errors += _check_const(entry, "review_basis", "STORY_SCOPE (Cycle 1)", ctx)
    errors += _check_pattern(entry, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(entry, "artifact_sha256", SHA256_RE, ctx)
    errors += _check_non_empty_string(entry, "model", ctx)
    errors += _check_non_empty_string(entry, "artifact_path", ctx)

    # Checks object
    checks = entry.get("checks")
    if isinstance(checks, dict):
        errors += _check_required(checks, R3_REVIEW_CHECKS, f"{ctx}.checks")
        for ck in R3_REVIEW_CHECKS:
            if ck in checks and not isinstance(checks[ck], bool):
                errors.append(f"{ctx}.checks.{ck}: must be boolean")
    elif checks is not None:
        errors.append(f"{ctx}.checks: must be an object")

    # Review provenance
    if "provenance" in entry:
        errors += validate_review_provenance_r3(entry["provenance"], f"{ctx}.provenance")

    # File checks
    if check_files:
        errors += _verify_artifact_file(entry, idx, manifest_dir)

    return errors


def validate_review_entry_r7(entry: Any, idx: int, check_files: bool, manifest_dir: Path) -> list[str]:
    ctx = f"reviews[{idx}]"
    errors: list[str] = []
    if not isinstance(entry, dict):
        return [f"{ctx}: must be an object"]
    errors += _check_required(entry, R7_REVIEW_ENTRY_REQUIRED, ctx)
    errors += _check_enum(entry, "tool", ["codex", "opus", "kimi", "gemini"], ctx)
    errors += _check_enum(entry, "prompt_style", ["generic", "enriched"], ctx)
    errors += _check_const(entry, "cycle", "C2", ctx)
    errors += _check_const(entry, "phase_equivalent", "R7d", ctx)
    errors += _check_const(entry, "review_basis", "FIX_DIFF + AT_REGRESSION (Cycle 2)", ctx)
    errors += _check_pattern(entry, "head_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(entry, "base_commit", HEXSHA_RE, ctx)
    errors += _check_pattern(entry, "artifact_sha256", SHA256_RE, ctx)
    errors += _check_non_empty_string(entry, "model", ctx)
    errors += _check_non_empty_string(entry, "artifact_path", ctx)

    # Checks object
    checks = entry.get("checks")
    if isinstance(checks, dict):
        errors += _check_required(checks, R7_REVIEW_CHECKS, f"{ctx}.checks")
        for ck in R7_REVIEW_CHECKS:
            if ck in checks and not isinstance(checks[ck], bool):
                errors.append(f"{ctx}.checks.{ck}: must be boolean")
    elif checks is not None:
        errors.append(f"{ctx}.checks: must be an object")

    # Review provenance
    if "provenance" in entry:
        errors += validate_review_provenance_r7(entry["provenance"], f"{ctx}.provenance")

    # File checks
    if check_files:
        errors += _verify_artifact_file(entry, idx, manifest_dir)

    return errors


def _verify_artifact_file(entry: dict[str, Any], idx: int, manifest_dir: Path) -> list[str]:
    errors: list[str] = []
    ctx = f"reviews[{idx}]"
    artifact_path_str = entry.get("artifact_path")
    if not artifact_path_str:
        return errors
    artifact_path = _resolve_artifact_path(artifact_path_str, manifest_dir)
    if artifact_path is None:
        errors.append(f"{ctx}: artifact_path '{artifact_path_str}' not found on disk")
        return errors
    expected_sha = entry.get("artifact_sha256", "")
    if SHA256_RE.match(expected_sha):
        actual_sha = _sha256_file(artifact_path)
        if actual_sha != expected_sha:
            errors.append(
                f"{ctx}: artifact_sha256 mismatch for '{artifact_path_str}': "
                f"expected {expected_sha}, got {actual_sha}"
            )
    # Cross-reference review_meta block against manifest checks
    checks = entry.get("checks", {})
    if isinstance(checks, dict):
        errors += _verify_review_meta(artifact_path, checks, ctx)
    return errors


def _resolve_artifact_path(artifact_path_str: str, manifest_dir: Path) -> Path | None:
    """Resolve artifact path relative to manifest dir or as absolute."""
    candidate = manifest_dir / artifact_path_str
    if candidate.exists():
        return candidate
    candidate = Path(artifact_path_str)
    if candidate.exists():
        return candidate
    return None


REVIEW_META_RE = re.compile(r"^---\s*$")
REVIEW_META_SECTION_RE = re.compile(r"^review_meta:\s*$")


def _parse_review_meta(path: Path) -> dict[str, Any] | None:
    """Parse the review_meta YAML block from a markdown review artifact.

    Looks for a block bounded by --- markers containing review_meta:.
    Returns parsed dict or None if not found. Uses simple line parsing
    to avoid a PyYAML dependency.
    """
    try:
        content = path.read_text(encoding="utf-8")
    except OSError:
        return None

    lines = content.split("\n")
    in_meta_block = False
    meta_start = -1

    # Find the review_meta block (last --- delimited block containing review_meta:)
    for i, line in enumerate(lines):
        if REVIEW_META_RE.match(line.strip()):
            if in_meta_block:
                # End of block — parse what we collected
                break
            # Potential start of block — look ahead for review_meta:
            for j in range(i + 1, min(i + 5, len(lines))):
                if REVIEW_META_SECTION_RE.match(lines[j].strip()):
                    in_meta_block = True
                    meta_start = i + 1
                    break

    if not in_meta_block or meta_start < 0:
        return None

    # Simple parser for the known structure
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
        if stripped == "review_meta:":
            continue
        if stripped == "evidence_citations:":
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


def _verify_review_meta(
    artifact_path: Path, checks: dict[str, Any], ctx: str
) -> list[str]:
    """Cross-reference manifest checks against the artifact's review_meta block."""
    errors: list[str] = []
    meta = _parse_review_meta(artifact_path)
    if meta is None:
        # No review_meta block — warn but don't fail (older artifacts)
        return errors

    cites = meta.get("evidence_citations", {})
    meta_checks = meta.get("checks", {})

    # R3 checks: cross-reference citation presence
    if "preexisting_enforcement_citation_present" in checks:
        manifest_val = checks["preexisting_enforcement_citation_present"]
        actual_has = len(cites.get("preexisting_enforcement", [])) > 0
        if manifest_val is True and not actual_has:
            errors.append(
                f"{ctx}: checks.preexisting_enforcement_citation_present=true "
                f"but review_meta has no enforcement citations"
            )

    if "preexisting_test_citation_present" in checks:
        manifest_val = checks["preexisting_test_citation_present"]
        actual_has = len(cites.get("preexisting_tests", [])) > 0
        if manifest_val is True and not actual_has:
            errors.append(
                f"{ctx}: checks.preexisting_test_citation_present=true "
                f"but review_meta has no test citations"
            )

    if "diff_only_review_rejected" in checks and "diff_only_review_rejected" in meta_checks:
        manifest_val = checks["diff_only_review_rejected"]
        meta_val = meta_checks["diff_only_review_rejected"]
        if manifest_val != meta_val:
            errors.append(
                f"{ctx}: checks.diff_only_review_rejected={manifest_val} "
                f"but review_meta says {meta_val}"
            )

    return errors


# ---------------------------------------------------------------------------
# Required-combo enforcement
# ---------------------------------------------------------------------------

def check_required_combos(reviews: list[dict[str, Any]]) -> list[str]:
    """Verify reviews[] contains all 4 mandatory tool x prompt combos."""
    errors: list[str] = []
    found = set()
    for r in reviews:
        if isinstance(r, dict):
            tool = r.get("tool")
            ps = r.get("prompt_style")
            if tool and ps:
                found.add((tool, ps))
    for combo in REQUIRED_COMBOS:
        if combo not in found:
            errors.append(
                f"required_combinations: missing review for tool={combo[0]}, "
                f"prompt_style={combo[1]}"
            )
    return errors


VALID_TOOLS = {"codex", "opus", "kimi", "gemini"}
VALID_PROMPT_STYLES = {"generic", "enriched"}


def _validate_combo_items(combos: list[Any]) -> list[str]:
    """Validate each required_combinations item has valid tool + prompt_style."""
    errors: list[str] = []
    for i, item in enumerate(combos):
        ctx = f"required_combinations[{i}]"
        if not isinstance(item, dict):
            errors.append(f"{ctx}: must be an object, got {type(item).__name__}")
            continue
        tool = item.get("tool")
        ps = item.get("prompt_style")
        if tool is None:
            errors.append(f"{ctx}: missing required field 'tool'")
        elif tool not in VALID_TOOLS:
            errors.append(f"{ctx}: 'tool' must be one of {sorted(VALID_TOOLS)}, got '{tool}'")
        if ps is None:
            errors.append(f"{ctx}: missing required field 'prompt_style'")
        elif ps not in VALID_PROMPT_STYLES:
            errors.append(f"{ctx}: 'prompt_style' must be one of {sorted(VALID_PROMPT_STYLES)}, got '{ps}'")
    return errors


def _verify_commit_alignment(data: dict[str, Any], reviews: list[dict[str, Any]]) -> list[str]:
    """R7: Recompute commit alignment — verify each review's commits match provenance."""
    errors: list[str] = []
    prov = data.get("provenance", {})
    manifest_head = prov.get("head_commit", "")
    manifest_base = prov.get("base_commit", "")
    for i, r in enumerate(reviews):
        if not isinstance(r, dict):
            continue
        entry_head = r.get("head_commit", "")
        entry_base = r.get("base_commit", "")
        if entry_head and manifest_head and entry_head != manifest_head:
            errors.append(
                f"reviews[{i}]: head_commit='{entry_head}' != "
                f"provenance.head_commit='{manifest_head}'"
            )
        if entry_base and manifest_base and entry_base != manifest_base:
            errors.append(
                f"reviews[{i}]: base_commit='{entry_base}' != "
                f"provenance.base_commit='{manifest_base}'"
            )
    return errors


# ---------------------------------------------------------------------------
# Top-level validators
# ---------------------------------------------------------------------------

def validate_r3(data: dict[str, Any], check_files: bool, manifest_dir: Path) -> list[str]:
    errors: list[str] = []
    errors += _check_required(data, R3_TOP_REQUIRED, "root")
    errors += _check_const(data, "phase", "R3", "root")
    errors += _check_const(data, "cycle", "C1", "root")
    errors += _check_non_empty_string(data, "story_id", "root")
    errors += _check_non_empty_string(data, "slice_id", "root")

    # Provenance
    if "provenance" in data:
        errors += validate_provenance_r3(data["provenance"], "provenance")

    # Required combinations
    combos = data.get("required_combinations")
    if isinstance(combos, list):
        if len(combos) < 4:
            errors.append(f"required_combinations: must have >= 4 items, got {len(combos)}")
        errors += _validate_combo_items(combos)
    elif combos is not None:
        errors.append("required_combinations: must be an array")

    # Reviews
    reviews = data.get("reviews")
    if isinstance(reviews, list):
        if len(reviews) < 4:
            errors.append(f"reviews: must have >= 4 items, got {len(reviews)}")
        for i, entry in enumerate(reviews):
            errors += validate_review_entry_r3(entry, i, check_files, manifest_dir)
        errors += check_required_combos(reviews)
    elif reviews is not None:
        errors.append("reviews: must be an array")

    # Validation object
    val = data.get("validation")
    if isinstance(val, dict):
        errors += _check_required(val, R3_VALIDATION_CHECKS, "validation")
        errors += _check_enum(val, "status", ["PASS", "FAIL"], "validation")
        for ck in R3_VALIDATION_CHECKS[1:]:
            errors += _check_enum(val, ck, ["PASS", "FAIL"], "validation")
    elif val is not None:
        errors.append("validation: must be an object")

    return errors


def validate_r7(data: dict[str, Any], check_files: bool, manifest_dir: Path) -> list[str]:
    errors: list[str] = []
    errors += _check_required(data, R7_TOP_REQUIRED, "root")
    errors += _check_const(data, "phase", "R7d", "root")
    errors += _check_const(data, "cycle", "C2", "root")
    errors += _check_non_empty_string(data, "story_id", "root")
    errors += _check_non_empty_string(data, "slice_id", "root")

    # Provenance
    if "provenance" in data:
        errors += validate_provenance_r7(data["provenance"], "provenance")

    # Required combinations
    combos = data.get("required_combinations")
    if isinstance(combos, list):
        if len(combos) < 4:
            errors.append(f"required_combinations: must have >= 4 items, got {len(combos)}")
        errors += _validate_combo_items(combos)
    elif combos is not None:
        errors.append("required_combinations: must be an array")

    # Reviews
    reviews = data.get("reviews")
    if isinstance(reviews, list):
        if len(reviews) < 4:
            errors.append(f"reviews: must have >= 4 items, got {len(reviews)}")
        for i, entry in enumerate(reviews):
            errors += validate_review_entry_r7(entry, i, check_files, manifest_dir)
        errors += check_required_combos(reviews)
        # Recompute commit alignment — don't trust self-reported flags
        errors += _verify_commit_alignment(data, reviews)
    elif reviews is not None:
        errors.append("reviews: must be an array")

    # Regression scope
    rs = data.get("regression_scope")
    if isinstance(rs, dict):
        errors += _check_required(rs, ["base_commit", "head_commit", "affected_ats", "changed_files"], "regression_scope")
        errors += _check_pattern(rs, "base_commit", HEXSHA_RE, "regression_scope")
        errors += _check_pattern(rs, "head_commit", HEXSHA_RE, "regression_scope")
        for field in ("affected_ats", "changed_files"):
            arr = rs.get(field)
            if arr is not None and not isinstance(arr, list):
                errors.append(f"regression_scope.{field}: must be an array")
    elif rs is not None:
        errors.append("regression_scope: must be an object")

    # Validation object
    val = data.get("validation")
    if isinstance(val, dict):
        errors += _check_required(val, R7_VALIDATION_CHECKS, "validation")
        errors += _check_enum(val, "status", ["PASS", "FAIL"], "validation")
        for ck in R7_VALIDATION_CHECKS[1:]:
            errors += _check_enum(val, ck, ["PASS", "FAIL"], "validation")
    elif val is not None:
        errors.append("validation: must be an object")

    return errors


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _output_json(
    status: str,
    mtype: str | None,
    manifest_path: Path,
    errors: list[str],
) -> None:
    """Print structured JSON result."""
    result = {
        "status": status,
        "manifest_type": mtype,
        "manifest_path": str(manifest_path),
        "error_count": len(errors),
        "errors": errors,
    }
    print(json.dumps(result, indent=2))


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: validate_external_manifest.py <manifest.json> "
            "[--check-files] [--format json]",
            file=sys.stderr,
        )
        return 2

    manifest_path = Path(sys.argv[1])
    check_files = "--check-files" in sys.argv
    fmt = "text"
    if "--format" in sys.argv:
        idx = sys.argv.index("--format")
        if idx + 1 < len(sys.argv):
            fmt = sys.argv[idx + 1]

    if not manifest_path.exists():
        if fmt == "json":
            _output_json("FAIL", None, manifest_path, [f"file not found: {manifest_path}"])
        else:
            print(f"ERROR: file not found: {manifest_path}", file=sys.stderr)
        return 1

    try:
        with open(manifest_path) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        if fmt == "json":
            _output_json("FAIL", None, manifest_path, [f"invalid JSON: {e}"])
        else:
            print(f"ERROR: invalid JSON: {e}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        if fmt == "json":
            _output_json("FAIL", None, manifest_path, ["manifest must be a JSON object"])
        else:
            print("ERROR: manifest must be a JSON object", file=sys.stderr)
        return 1

    manifest_dir = manifest_path.parent
    mtype = detect_type(data)
    if mtype == "r3":
        errors = validate_r3(data, check_files, manifest_dir)
    elif mtype == "r7":
        errors = validate_r7(data, check_files, manifest_dir)
    else:
        phase = data.get("phase", "<missing>")
        msg = f"cannot detect manifest type from phase='{phase}' (expected 'R3' or 'R7d')"
        if fmt == "json":
            _output_json("FAIL", None, manifest_path, [msg])
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 1

    if fmt == "json":
        _output_json("PASS" if not errors else "FAIL", mtype, manifest_path, errors)
    elif errors:
        print(f"FAIL: {len(errors)} validation error(s) in {mtype.upper()} manifest:")
        for e in errors:
            print(f"  - {e}")
    else:
        print(f"PASS: {mtype.upper()} external manifest is valid ({manifest_path.name})")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
