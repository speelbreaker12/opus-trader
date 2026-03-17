"""Shared parsing library for review artifact validators.

Provides canonical implementations of:
  - Markdown front-matter parsing
  - JSON artifact provenance extraction
  - SHA-256 computation
  - Provenance validation against expectations
  - review_meta YAML block extraction

Both validate_review_header.py and validate_external_manifest.py should
import from here to prevent drift.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

HEXSHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ISO8601Z_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

YAML_FENCE_RE = re.compile(r"^---\s*$")
REVIEW_META_SECTION_RE = re.compile(r"^review_meta:\s*$")

# ---------------------------------------------------------------------------
# Key map for markdown dash-prefixed headers (review_logged.sh output)
# ---------------------------------------------------------------------------

MD_HEADER_KEY_MAP: dict[str, str] = {
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


# ---------------------------------------------------------------------------
# Provenance extraction
# ---------------------------------------------------------------------------

def parse_markdown_frontmatter(content: str) -> dict[str, str] | None:
    """Extract provenance from markdown review artifact.

    Handles two formats:
    1. YAML front matter (--- delimited block at top)
    2. Dash-prefixed lines: ``- Key: Value``
    """
    prov: dict[str, str] = {}
    lines = content.split("\n")

    # Try YAML front matter first
    if lines and lines[0].strip() == "---":
        for line in lines[1:]:
            if line.strip() == "---":
                break
            m = re.match(r"^([a-z_]+):\s*(.+)$", line.strip())
            if m:
                prov[m.group(1)] = m.group(2).strip()
        if prov:
            return prov

    # Fall back to dash-prefixed header lines
    for line in lines:
        m = re.match(r"^- ([^:]+):\s*(.+)$", line)
        if m:
            raw_key = m.group(1).strip().lower()
            val = m.group(2).strip()
            mapped = MD_HEADER_KEY_MAP.get(raw_key)
            if mapped:
                prov[mapped] = val
            else:
                prov[raw_key.replace(" ", "_")] = val

    return prov if prov else None


def parse_json_artifact(data: dict[str, Any]) -> dict[str, Any] | None:
    """Extract provenance from JSON artifact with top-level provenance object."""
    prov = data.get("provenance")
    if isinstance(prov, dict):
        return prov
    return None


# ---------------------------------------------------------------------------
# SHA-256
# ---------------------------------------------------------------------------

def compute_sha256(path: Path) -> str:
    """Compute SHA-256 hex digest of a file."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Provenance validation
# ---------------------------------------------------------------------------

def validate_provenance(
    prov: dict[str, Any],
    expectations: dict[str, str | None],
) -> list[str]:
    """Validate provenance fields against expectations.

    Returns list of failure_code strings. Empty = PASS.

    expectations is a dict of field_name -> expected_value.
    If expected_value is None, the check is skipped.
    """
    failures: list[str] = []
    for field, expected in expectations.items():
        if expected is None:
            continue
        actual = prov.get(field, "")
        if str(actual) != str(expected):
            failures.append(f"{field.upper()}_MISMATCH")
    return failures


# ---------------------------------------------------------------------------
# review_meta extraction
# ---------------------------------------------------------------------------

def extract_external_review_meta(content: str) -> dict[str, Any] | None:
    """Parse review_meta YAML block from markdown content.

    Looks for a block bounded by --- markers containing review_meta:.
    Returns parsed dict or None if not found.
    """
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
# Failure code → human action mapping (§6)
# ---------------------------------------------------------------------------

FAILURE_CODE_ACTIONS: dict[str, str] = {
    # ── Manifest-level failures ──
    "MANIFEST_MISSING": "manifest JSON file not found on disk",
    "MANIFEST_JSON_INVALID": "manifest file is not valid JSON or not a JSON object",
    "MANIFEST_PROVENANCE_INVALID": "manifest provenance block has missing/invalid fields",
    "MANIFEST_CYCLE_MISMATCH": "manifest cycle (C1/C2) doesn't match expected value",
    "MANIFEST_PHASE_MISMATCH": "manifest phase (R3/R7d) doesn't match expected value",
    "MANIFEST_STORY_ID_MISMATCH": "manifest story_id doesn't match expected value",
    "MANIFEST_SLICE_ID_MISMATCH": "manifest slice_id doesn't match expected value",
    "MANIFEST_HEAD_COMMIT_MISMATCH": "manifest head_commit doesn't match expected value",
    "MANIFEST_BASE_COMMIT_MISMATCH": "manifest base_commit doesn't match expected value",
    "R7D_C2_MODE_MISMATCH": "invalid or unsupported cycle2_path.mode",
    "R7D_C2_SINGLE_MISMATCH": "recon_clean_single cycle2_path declaration does not match required_combinations",
    "MANIFEST_REQUIRED_COMBO_MISSING": "missing Codex plus Sonnet-or-Opus generic/enriched run",
    "MANIFEST_DUPLICATE_COMBO": "same tool:prompt_style combo appears multiple times",
    "MANIFEST_UNEXPECTED_TOOL": "review uses unrecognized tool (expected: codex/sonnet/opus/kimi)",
    "MANIFEST_UNEXPECTED_PROMPT_STYLE": "review uses unrecognized prompt_style (expected: generic/enriched)",
    "MANIFEST_CHECK_SUMMARY_INCONSISTENT": "manifest claims PASS but computed validation disagrees",
    "MANIFEST_VALIDATION_STATUS_FAIL": "manifest's own validation.status is FAIL",
    # ── Schema failures ──
    "SCHEMA_MISSING": "JSON Schema file not found on disk",
    "SCHEMA_INVALID": "JSON Schema file is not valid JSON or has schema errors",
    "SCHEMA_VALIDATION_FAILED": "manifest does not conform to JSON Schema",
    "SCHEMA_VALIDATION_SKIPPED": "jsonschema package not installed — schema check could not run",
    # ── Review basis / cycle semantics ──
    "REVIEW_BASIS_MISSING": "reviewer didn't include cycle scope line",
    "REVIEW_BASIS_MISMATCH": "review_basis doesn't match expected cycle scope",
    "PREEXISTING_ENFORCEMENT_CITATION_MISSING": "C1 review not anchored to real pre-existing enforcement",
    "PREEXISTING_TEST_CITATION_MISSING": "C1 review lacks proof-test anchor",
    "DIFF_ONLY_REVIEW_REJECTED_CHECK_FAILED": "reviewer likely audited diff only",
    # ── Artifact integrity ──
    "REVIEW_ARTIFACT_MISSING": "referenced review artifact file not found on disk",
    "REVIEW_ARTIFACT_HASH_MISMATCH": "artifact mutated after manifest generation",
    "REVIEW_ARTIFACT_HASH_FORMAT_INVALID": "artifact_sha256 field is malformed (not a valid 64-char hex digest)",
    "REVIEW_ARTIFACT_HEADER_VALIDATION_FAILED": "review artifact provenance header invalid",
    # ── Commit alignment ──
    "HEAD_COMMIT_ALIGNMENT_FAILED": "review artifact not for current head",
    "BASE_COMMIT_ALIGNMENT_FAILED": "C2 review diff anchor incorrect",
    # ── Internal errors ──
    "CONSISTENCY_CHECK_ERROR": "consistency check (Step F) crashed — fail-closed",
}


def explain_failure_code(code: str) -> str:
    """Return human-readable explanation for a failure code."""
    return FAILURE_CODE_ACTIONS.get(code, f"(no explanation available for {code})")
