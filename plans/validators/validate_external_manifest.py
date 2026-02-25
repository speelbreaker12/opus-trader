#!/usr/bin/env python3
"""Validate R3/R7 external manifest JSON — gate validator for external review completion.

Implements the 6-step validation algorithm:
  Step A — Load + schema validate
  Step B — Manifest provenance checks
  Step C — Required combo checks
  Step D — Referenced artifact checks (existence, sha256, header validation)
  Step E — Cycle-specific semantic checks
  Step F — Consistency check (manifest PASS claim vs computed result)

Exit codes:
  0 = PASS
  1 = CLI_USAGE_ERROR
  2 = FILE_IO_ERROR
  3 = PARSE_OR_SCHEMA_ERROR
  4 = VALIDATION_FAIL
  5 = INTERNAL_ERROR
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import traceback
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Import validate_review_header for Step D
# ---------------------------------------------------------------------------
_VALIDATORS_DIR = Path(__file__).resolve().parent
if str(_VALIDATORS_DIR) not in sys.path:
    sys.path.insert(0, str(_VALIDATORS_DIR))

from validate_review_header import (  # noqa: E402
    validate as validate_header,
    extract_provenance_md,
    extract_provenance_json,
)
from lib_review_artifacts import (  # noqa: E402
    explain_failure_code,
    HEXSHA_RE as _LIB_HEXSHA_RE,
    SHA256_RE as _LIB_SHA256_RE,
    ISO8601Z_RE as _LIB_ISO8601Z_RE,
)

# Optional: JSON Schema validation
try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VERSION = "v1"
VALIDATOR_NAME = "validate_external_manifest"

HEXSHA_RE = _LIB_HEXSHA_RE
SHA256_RE = _LIB_SHA256_RE
ISO8601Z_RE = _LIB_ISO8601Z_RE

VALID_TOOLS = {"codex", "opus", "kimi"}
VALID_PROMPT_STYLES = {"generic", "enriched"}

REQUIRED_COMBOS_DEFAULT = [
    ("codex", "enriched"),
    ("codex", "generic"),
    ("kimi", "enriched"),
    ("kimi", "generic"),
]

R3_MANIFEST_PROV_REQUIRED = [
    "tool", "model", "prompt_style", "cycle", "phase_equivalent",
    "review_basis", "story_id", "slice_id", "head_commit",
    "generated_at", "artifact_provenance", "schema_version",
]
R7_MANIFEST_PROV_REQUIRED = R3_MANIFEST_PROV_REQUIRED + ["base_commit"]

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


def _resolve_required_combos_from_manifest(
    data: dict[str, Any],
    r: ManifestValidationResult,
) -> list[tuple[str, str]]:
    """Resolve required C2 combos from manifest cycle2_path when present.

    Defaults to the legacy dual-combo flow when cycle2_path is absent.
    """
    phase = data.get("phase", "")
    if phase != "R7d":
        return list(REQUIRED_COMBOS_DEFAULT)

    cycle2_path = data.get("cycle2_path")
    if not isinstance(cycle2_path, dict):
        r.warn("cycle2_path missing; defaulting to legacy dual_combo mode")
        return list(REQUIRED_COMBOS_DEFAULT)

    mode = cycle2_path.get("mode", "")
    if mode == "dual_combo":
        return list(REQUIRED_COMBOS_DEFAULT)

    if mode == "recon_clean_single":
        choice = cycle2_path.get("single_combo_choice")
        if not isinstance(choice, dict):
            r.fail("R7D_C2_SINGLE_MISMATCH")
            r.warn("recon_clean_single requires cycle2_path.single_combo_choice")
            return list(REQUIRED_COMBOS_DEFAULT)

        tool = str(choice.get("tool", ""))
        prompt_style = str(choice.get("prompt_style", ""))
        if tool not in VALID_TOOLS or prompt_style not in VALID_PROMPT_STYLES:
            r.fail("R7D_C2_SINGLE_MISMATCH")
            return list(REQUIRED_COMBOS_DEFAULT)

        required = [(tool, prompt_style)]

        declared = data.get("required_combinations")
        if not isinstance(declared, list) or len(declared) != 1:
            r.fail("R7D_C2_SINGLE_MISMATCH")
            return required

        first = declared[0]
        if not isinstance(first, dict) or first.get("tool") != tool or first.get("prompt_style") != prompt_style:
            r.fail("R7D_C2_SINGLE_MISMATCH")
            return required

        justification = cycle2_path.get("single_combo_justification", "")
        if not isinstance(justification, str) or justification.strip() == "":
            r.fail("R7D_C2_SINGLE_MISMATCH")
            r.warn("recon_clean_single requires non-empty cycle2_path.single_combo_justification")

        return required

    r.fail("R7D_C2_MODE_MISMATCH")
    r.warn(f"unsupported cycle2_path.mode={mode!r}; defaulting to dual combo")
    return list(REQUIRED_COMBOS_DEFAULT)


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------

class ManifestValidationResult:
    def __init__(self, manifest_path: str) -> None:
        self.manifest_path = manifest_path
        self.phase: str = ""
        self.cycle: str = ""
        self.story_id: str = ""
        self.slice_id: str = ""
        self.checks: dict[str, bool] = {}
        self.combos_required: list[str] = []
        self.combos_found: list[str] = []
        self.artifacts: list[dict[str, Any]] = []
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
            "manifest_path": self.manifest_path,
            "phase": self.phase,
            "cycle": self.cycle,
            "story_id": self.story_id,
            "slice_id": self.slice_id,
            "checks": self.checks,
            "combos_required": self.combos_required,
            "combos_found": self.combos_found,
            "artifacts": self.artifacts,
            "failure_codes": self.failure_codes,
            "warnings": self.warnings,
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _parse_combo(s: str) -> tuple[str, str]:
    """Parse 'tool:prompt_style' string."""
    parts = s.split(":", 1)
    if len(parts) != 2:
        raise ValueError(f"invalid combo format: {s!r} (expected tool:prompt_style)")
    return (parts[0], parts[1])


def _combo_str(tool: str, ps: str) -> str:
    return f"{tool}:{ps}"


# ---------------------------------------------------------------------------
# Step A — Load + schema validate
# ---------------------------------------------------------------------------

def step_a_load_and_schema(
    manifest_path: Path,
    schema_path: Path | None,
    r: ManifestValidationResult,
) -> dict[str, Any] | None:
    """Load manifest JSON and optionally validate against JSON Schema."""
    # Load manifest
    if not manifest_path.exists():
        r.fail("MANIFEST_MISSING")
        return None

    try:
        with open(manifest_path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        r.fail("MANIFEST_JSON_INVALID")
        return None

    if not isinstance(data, dict):
        r.fail("MANIFEST_JSON_INVALID")
        return None

    # Load and validate schema
    if schema_path is not None:
        if not schema_path.exists():
            r.fail("SCHEMA_MISSING")
            return data

        try:
            with open(schema_path) as f:
                schema = json.load(f)
        except json.JSONDecodeError:
            r.fail("SCHEMA_INVALID")
            return data

        if HAS_JSONSCHEMA:
            try:
                jsonschema.validate(instance=data, schema=schema)
                r.check("manifest_schema_valid", True)
            except jsonschema.ValidationError as e:
                r.fail("SCHEMA_VALIDATION_FAILED")
                r.check("manifest_schema_valid", False)
                r.warn(f"schema validation: {e.message}")
            except jsonschema.SchemaError as e:
                r.fail("SCHEMA_INVALID")
                r.check("manifest_schema_valid", False)
                r.warn(f"schema error: {e.message}")
        else:
            r.fail("SCHEMA_VALIDATION_SKIPPED")
            r.warn("jsonschema not installed — schema validation skipped (install: pip install jsonschema)")
            r.check("manifest_schema_valid", False)
    else:
        r.check("manifest_schema_valid", True)

    return data


# ---------------------------------------------------------------------------
# Step B — Manifest provenance checks
# ---------------------------------------------------------------------------

def step_b_provenance(
    data: dict[str, Any],
    args: argparse.Namespace,
    r: ManifestValidationResult,
) -> None:
    """Validate manifest-level provenance object."""
    prov = data.get("provenance")
    if not isinstance(prov, dict):
        r.fail("MANIFEST_PROVENANCE_INVALID")
        r.check("manifest_provenance_valid", False)
        return

    phase = data.get("phase", "")
    cycle = data.get("cycle", "")
    r.phase = phase
    r.cycle = cycle
    r.story_id = data.get("story_id", "")
    r.slice_id = data.get("slice_id", "")

    valid = True

    # Required fields by type
    required = R7_MANIFEST_PROV_REQUIRED if phase == "R7d" else R3_MANIFEST_PROV_REQUIRED
    for field in required:
        if field not in prov or not prov[field]:
            r.fail("MANIFEST_PROVENANCE_INVALID")
            valid = False

    # Manifest provenance const checks
    if prov.get("tool") != "script":
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False
    if prov.get("prompt_style") != "none":
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False

    # Cycle check
    expected_cycle = args.cycle or ("C1" if phase == "R3" else "C2" if phase == "R7d" else "")
    if expected_cycle and prov.get("cycle") != expected_cycle:
        r.fail("MANIFEST_CYCLE_MISMATCH")
        valid = False
    if expected_cycle and cycle != expected_cycle:
        r.fail("MANIFEST_CYCLE_MISMATCH")
        valid = False

    # Phase check
    expected_phase = args.expect_phase or ""
    if expected_phase and prov.get("phase_equivalent") != expected_phase:
        r.fail("MANIFEST_PHASE_MISMATCH")
        valid = False
    if expected_phase and phase != expected_phase:
        r.fail("MANIFEST_PHASE_MISMATCH")
        valid = False

    # Review basis
    if phase == "R3":
        expected_basis = "STORY_SCOPE (Cycle 1)"
    elif phase == "R7d":
        expected_basis = "FIX_DIFF + AT_REGRESSION (Cycle 2)"
    else:
        expected_basis = ""
    if expected_basis and prov.get("review_basis") != expected_basis:
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False

    # Schema version
    if phase == "R3" and prov.get("schema_version") != "r3_external_manifest.v2":
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False
    if phase == "R7d" and prov.get("schema_version") != "r7_external_manifest.v2":
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False

    # HEAD/base commit format
    head = prov.get("head_commit", "")
    if head and not HEXSHA_RE.match(head):
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False

    base = prov.get("base_commit", "")
    if phase == "R7d" and (not base or not HEXSHA_RE.match(base)):
        r.fail("MANIFEST_PROVENANCE_INVALID")
        valid = False

    # Expectation checks
    if args.expect_story_id and data.get("story_id") != args.expect_story_id:
        r.fail("MANIFEST_STORY_ID_MISMATCH")
        valid = False
    if args.expect_slice_id and data.get("slice_id") != args.expect_slice_id:
        r.fail("MANIFEST_SLICE_ID_MISMATCH")
        valid = False
    if args.expect_head_commit and head != args.expect_head_commit:
        r.fail("MANIFEST_HEAD_COMMIT_MISMATCH")
        valid = False
    if args.expect_base_commit and base != args.expect_base_commit:
        r.fail("MANIFEST_BASE_COMMIT_MISMATCH")
        valid = False

    r.check("manifest_provenance_valid", valid)


# ---------------------------------------------------------------------------
# Step C — Required combo checks
# ---------------------------------------------------------------------------

def step_c_combos(
    data: dict[str, Any],
    required_combos: list[tuple[str, str]],
    r: ManifestValidationResult,
) -> None:
    """Verify reviews[] contains all required tool:prompt_style combos."""
    reviews = data.get("reviews", [])
    if not isinstance(reviews, list):
        r.fail("MANIFEST_REQUIRED_COMBO_MISSING")
        r.check("required_combinations_present", False)
        return

    r.combos_required = [_combo_str(t, p) for t, p in required_combos]

    found: dict[str, int] = {}
    for entry in reviews:
        if not isinstance(entry, dict):
            continue
        tool = entry.get("tool", "")
        ps = entry.get("prompt_style", "")
        if not tool or not ps:
            continue
        combo = _combo_str(tool, ps)
        r.combos_found.append(combo)
        found[combo] = found.get(combo, 0) + 1

        # Validate tool/prompt_style values
        if tool not in VALID_TOOLS:
            r.fail("MANIFEST_UNEXPECTED_TOOL")
        if ps not in VALID_PROMPT_STYLES:
            r.fail("MANIFEST_UNEXPECTED_PROMPT_STYLE")

    # Deduplicate combos_found for display
    r.combos_found = sorted(set(r.combos_found))

    # Check required combos present
    all_present = True
    for combo_t, combo_p in required_combos:
        combo = _combo_str(combo_t, combo_p)
        if found.get(combo, 0) < 1:
            r.fail("MANIFEST_REQUIRED_COMBO_MISSING")
            all_present = False

    # Check for duplicates (same tool:prompt_style appearing multiple times)
    for combo, count in found.items():
        if count > 1:
            r.fail("MANIFEST_DUPLICATE_COMBO")
            r.warn(f"duplicate combo: {combo} appears {count} times")

    r.check("required_combinations_present", all_present)


# ---------------------------------------------------------------------------
# Step D — Referenced artifact checks
# ---------------------------------------------------------------------------

def step_d_artifacts(
    data: dict[str, Any],
    repo_root: Path,
    r: ManifestValidationResult,
) -> None:
    """For each review entry, verify artifact exists, sha256 matches, header validates."""
    reviews = data.get("reviews", [])
    if not isinstance(reviews, list):
        r.check("referenced_artifacts_exist", False)
        r.check("referenced_artifact_hashes_match", False)
        r.check("artifact_header_validation_pass", False)
        return

    all_exist = True
    all_hashes = True
    all_headers = True
    phase = data.get("phase", "")
    prov = data.get("provenance", {})

    for i, entry in enumerate(reviews):
        if not isinstance(entry, dict):
            continue

        artifact_info: dict[str, Any] = {
            "tool": entry.get("tool", ""),
            "prompt_style": entry.get("prompt_style", ""),
            "artifact_path": entry.get("artifact_path", ""),
            "exists": False,
            "sha256_match": False,
            "header_validation_status": "SKIP",
            "header_failure_codes": [],
        }

        artifact_path_str = entry.get("artifact_path", "")
        if not artifact_path_str:
            artifact_info["exists"] = False
            r.fail("REVIEW_ARTIFACT_MISSING")
            all_exist = False
            r.artifacts.append(artifact_info)
            continue

        # Resolve path relative to repo root
        artifact_path = repo_root / artifact_path_str
        if not artifact_path.exists():
            # Try relative to manifest dir
            manifest_dir = Path(r.manifest_path).parent
            artifact_path = manifest_dir / artifact_path_str
        if not artifact_path.exists():
            # Try absolute
            artifact_path = Path(artifact_path_str)

        if not artifact_path.exists():
            artifact_info["exists"] = False
            r.fail("REVIEW_ARTIFACT_MISSING")
            all_exist = False
            r.artifacts.append(artifact_info)
            continue

        artifact_info["exists"] = True

        # SHA-256 check
        expected_sha = entry.get("artifact_sha256", "")
        if expected_sha and SHA256_RE.match(expected_sha):
            actual_sha = _sha256_file(artifact_path)
            if actual_sha != expected_sha:
                artifact_info["sha256_match"] = False
                r.fail("REVIEW_ARTIFACT_HASH_MISMATCH")
                all_hashes = False
            else:
                artifact_info["sha256_match"] = True
        elif expected_sha:
            # Non-empty but malformed hash — fail-closed
            artifact_info["sha256_match"] = False
            r.fail("REVIEW_ARTIFACT_HASH_FORMAT_INVALID")
            all_hashes = False
        else:
            artifact_info["sha256_match"] = True  # no hash to check

        # Header validation via validate_review_header
        try:
            content = artifact_path.read_text(encoding="utf-8")
        except OSError:
            artifact_info["header_validation_status"] = "ERROR"
            r.fail("REVIEW_ARTIFACT_HEADER_VALIDATION_FAILED")
            all_headers = False
            r.artifacts.append(artifact_info)
            continue

        if artifact_path.suffix == ".json":
            try:
                json_data = json.loads(content)
                header_prov = extract_provenance_json(json_data)
            except json.JSONDecodeError:
                header_prov = None
        else:
            header_prov = extract_provenance_md(content)

        if header_prov is None:
            artifact_info["header_validation_status"] = "FAIL"
            artifact_info["header_failure_codes"] = ["PROVENANCE_BLOCK_MISSING"]
            r.fail("REVIEW_ARTIFACT_HEADER_VALIDATION_FAILED")
            all_headers = False
            r.artifacts.append(artifact_info)
            continue

        # Build args for header validator with expectations from this entry
        header_args = _build_header_args(entry, prov, phase)
        header_result = validate_header(artifact_path, content, header_prov, header_args)

        artifact_info["header_validation_status"] = header_result.status
        artifact_info["header_failure_codes"] = header_result.failure_codes

        if header_result.failure_codes:
            r.fail("REVIEW_ARTIFACT_HEADER_VALIDATION_FAILED")
            all_headers = False

        r.artifacts.append(artifact_info)

    r.check("referenced_artifacts_exist", all_exist)
    r.check("referenced_artifact_hashes_match", all_hashes)
    r.check("artifact_header_validation_pass", all_headers)


def _build_header_args(
    entry: dict[str, Any],
    manifest_prov: dict[str, Any],
    phase: str,
) -> argparse.Namespace:
    """Build a Namespace matching validate_review_header's expected args.

    Note: cycle, phase_equivalent, review_basis, story_id, slice_id are
    manifest-level fields that review_logged.sh does NOT write to .md
    artifact headers. We validate them at the manifest level (Steps B/E),
    not per-artifact.
    """
    return argparse.Namespace(
        expect_tool=entry.get("tool"),
        expect_cycle=None,  # manifest-level; .md artifacts don't carry this
        expect_phase=None,  # phase_equivalent varies; manifest-level
        expect_prompt_style=entry.get("prompt_style"),
        expect_review_basis=None,  # checked in Step E at manifest level
        expect_story_id=None,  # manifest-level
        expect_slice_id=None,  # manifest-level
        expect_head_commit=entry.get("head_commit"),
        expect_base_commit=entry.get("base_commit") if phase == "R7d" else None,
        require_external_review_meta=True,
        require_preexisting_citations=False,  # checked at manifest level in Step E
        require_diff_only_rejected=False,  # checked at manifest level in Step E
        strict=False,
        fmt="json",
    )


# ---------------------------------------------------------------------------
# Step E — Cycle-specific semantic checks
# ---------------------------------------------------------------------------

def step_e_cycle_semantics(
    data: dict[str, Any],
    r: ManifestValidationResult,
) -> None:
    """Enforce cycle-specific semantic requirements on reviews and validation checks."""
    phase = data.get("phase", "")
    reviews = data.get("reviews", [])
    prov = data.get("provenance", {})
    validation = data.get("validation", {})

    if phase == "R3":
        _step_e_r3(reviews, validation, r)
    elif phase == "R7d":
        _step_e_r7(data, reviews, validation, prov, r)


def _step_e_r3(
    reviews: list[Any],
    validation: dict[str, Any],
    r: ManifestValidationResult,
) -> None:
    """R3/C1 semantic checks."""
    # review_basis_check must be PASS
    rb_check = validation.get("review_basis_check")
    if rb_check != "PASS":
        r.fail("REVIEW_BASIS_MISMATCH")
    r.check("review_basis_check", rb_check == "PASS")

    # Verify every review has correct review_basis
    expected_basis = "STORY_SCOPE (Cycle 1)"
    for i, entry in enumerate(reviews):
        if not isinstance(entry, dict):
            continue
        entry_basis = entry.get("review_basis", "")
        if entry_basis != expected_basis:
            r.fail("REVIEW_BASIS_MISMATCH")
            r.checks["review_basis_check"] = False

    # preexisting_enforcement_citation_check must be PASS
    ec_check = validation.get("preexisting_enforcement_citation_check")
    if ec_check != "PASS":
        r.fail("PREEXISTING_ENFORCEMENT_CITATION_MISSING")
    r.check("preexisting_enforcement_citation_check", ec_check == "PASS")

    # preexisting_test_citation_check must be PASS
    tc_check = validation.get("preexisting_test_citation_check")
    if tc_check != "PASS":
        r.fail("PREEXISTING_TEST_CITATION_MISSING")
    r.check("preexisting_test_citation_check", tc_check == "PASS")

    # diff_only_review_check must be PASS
    dr_check = validation.get("diff_only_review_check")
    if dr_check != "PASS":
        r.fail("DIFF_ONLY_REVIEW_REJECTED_CHECK_FAILED")
    r.check("diff_only_review_check", dr_check == "PASS")


def _step_e_r7(
    data: dict[str, Any],
    reviews: list[Any],
    validation: dict[str, Any],
    prov: dict[str, Any],
    r: ManifestValidationResult,
) -> None:
    """R7d/C2 semantic checks."""
    # review_basis_check must be PASS
    rb_check = validation.get("review_basis_check")
    if rb_check != "PASS":
        r.fail("REVIEW_BASIS_MISMATCH")
    r.check("review_basis_check", rb_check == "PASS")

    # Verify every review has correct review_basis
    expected_basis = "FIX_DIFF + AT_REGRESSION (Cycle 2)"
    for i, entry in enumerate(reviews):
        if not isinstance(entry, dict):
            continue
        entry_basis = entry.get("review_basis", "")
        if entry_basis != expected_basis:
            r.fail("REVIEW_BASIS_MISMATCH")
            r.checks["review_basis_check"] = False

    # Recompute head/base commit alignment (don't trust self-reported flags)
    manifest_head = prov.get("head_commit", "")
    manifest_base = prov.get("base_commit", "")
    regression = data.get("regression_scope", {})
    reg_head = regression.get("head_commit", "") if isinstance(regression, dict) else ""
    reg_base = regression.get("base_commit", "") if isinstance(regression, dict) else ""

    head_aligned = True
    base_aligned = True

    for entry in reviews:
        if not isinstance(entry, dict):
            continue
        entry_head = entry.get("head_commit", "")
        entry_base = entry.get("base_commit", "")

        if entry_head and manifest_head and entry_head != manifest_head:
            head_aligned = False
        if entry_base and manifest_base and entry_base != manifest_base:
            base_aligned = False

    # Also check regression_scope alignment with provenance
    if reg_head and manifest_head and reg_head != manifest_head:
        head_aligned = False
    if reg_base and manifest_base and reg_base != manifest_base:
        base_aligned = False

    if not head_aligned:
        r.fail("HEAD_COMMIT_ALIGNMENT_FAILED")
    r.check("head_commit_alignment_check", head_aligned)

    if not base_aligned:
        r.fail("BASE_COMMIT_ALIGNMENT_FAILED")
    r.check("base_commit_alignment_check", base_aligned)


# ---------------------------------------------------------------------------
# Step F — Consistency check
# ---------------------------------------------------------------------------

def step_f_consistency(
    data: dict[str, Any],
    r: ManifestValidationResult,
) -> None:
    """Check manifest's self-reported validation.status against computed result."""
    validation = data.get("validation", {})
    if not isinstance(validation, dict):
        return

    manifest_status = validation.get("status", "")

    # If we computed failures but manifest claims PASS → inconsistent
    computed_pass = len(r.failure_codes) == 0
    if manifest_status == "PASS" and not computed_pass:
        r.fail("MANIFEST_CHECK_SUMMARY_INCONSISTENT")
        r.warn(
            f"manifest claims validation.status=PASS but validator found "
            f"{len(r.failure_codes)} failure(s)"
        )

    # Overall status check (validation.status must be PASS for gate)
    if manifest_status != "PASS":
        r.fail("MANIFEST_VALIDATION_STATUS_FAIL")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="validate_external_manifest.py",
        description="Validate R3/R7 external manifest JSON — gate validator.",
    )
    p.add_argument("--manifest", required=True, help="Path to manifest JSON")
    p.add_argument("--schema", default=None, help="Path to JSON Schema file")
    p.add_argument("--format", dest="fmt", choices=["json", "text"], default="text",
                   help="Output format")
    p.add_argument("--repo-root", default=".", help="Repository root for artifact resolution")
    p.add_argument("--cycle", default=None, choices=["C1", "C2"],
                   help="Expected cycle")
    p.add_argument("--expect-phase", default=None, choices=["R3", "R7d"],
                   help="Expected phase")
    p.add_argument("--expect-story-id", default=None)
    p.add_argument("--expect-slice-id", default=None)
    p.add_argument("--expect-head-commit", default=None)
    p.add_argument("--expect-base-commit", default=None)
    p.add_argument("--require-combo", action="append", default=[],
                   help="Required tool:prompt_style combo (repeatable)")
    p.add_argument("--strict", action="store_true",
                   help="Enable strict mode")

    # Legacy compatibility flags (from old CLI)
    p.add_argument("--check-files", action="store_true",
                   help="(Legacy) equivalent to providing --repo-root")
    return p


def _emit_error(fmt: str, manifest_path: str, code: str, message: str) -> None:
    """Emit an error in the appropriate format."""
    if fmt == "json":
        print(json.dumps({
            "validator": VALIDATOR_NAME,
            "version": VERSION,
            "status": "FAIL",
            "manifest_path": manifest_path,
            "error": message,
            "failure_codes": [code],
        }, indent=2))
    else:
        print(f"ERROR: {message}", file=sys.stderr)


def main() -> int:
    parser = build_parser()
    try:
        args = parser.parse_args()
    except SystemExit:
        return 1  # CLI_USAGE_ERROR

    manifest_path = Path(args.manifest)
    schema_path = Path(args.schema) if args.schema else None
    repo_root = Path(args.repo_root).resolve()

    # Parse required combos
    required_combos: list[tuple[str, str]]
    if args.require_combo:
        required_combos = []
        for combo_str in args.require_combo:
            try:
                required_combos.append(_parse_combo(combo_str))
            except ValueError as e:
                _emit_error(args.fmt, str(manifest_path), "CLI_USAGE_ERROR", str(e))
                return 1
    else:
        required_combos = list(REQUIRED_COMBOS_DEFAULT)

    r = ManifestValidationResult(str(manifest_path))

    # ── Step A: Load + schema validate ────────────────────────────────
    data = step_a_load_and_schema(manifest_path, schema_path, r)
    if data is None:
        # Fatal — can't continue
        if args.fmt == "json":
            print(json.dumps(r.to_dict(), indent=2))
        else:
            for code in r.failure_codes:
                print(f"FAIL: {code}", file=sys.stderr)
        return 2 if "MANIFEST_MISSING" in r.failure_codes else 3

    # Detect type
    phase = data.get("phase", "")
    if phase not in ("R3", "R7d"):
        r.fail("MANIFEST_PHASE_MISMATCH")
        if args.fmt == "json":
            print(json.dumps(r.to_dict(), indent=2))
        else:
            print(f"FAIL: unknown phase={phase!r} (expected R3 or R7d)", file=sys.stderr)
        return 4

    if not args.require_combo:
        required_combos = _resolve_required_combos_from_manifest(data, r)

    # ── Step B: Manifest provenance ───────────────────────────────────
    try:
        step_b_provenance(data, args, r)
    except Exception:
        r.fail("MANIFEST_PROVENANCE_INVALID")
        r.warn(f"provenance check error: {traceback.format_exc()}")

    # ── Step C: Required combo checks ─────────────────────────────────
    try:
        step_c_combos(data, required_combos, r)
    except Exception:
        r.fail("MANIFEST_REQUIRED_COMBO_MISSING")
        r.warn(f"combo check error: {traceback.format_exc()}")

    # ── Step D: Referenced artifact checks ────────────────────────────
    try:
        step_d_artifacts(data, repo_root, r)
    except Exception:
        r.fail("REVIEW_ARTIFACT_MISSING")
        r.warn(f"artifact check error: {traceback.format_exc()}")

    # ── Step E: Cycle-specific semantic checks ────────────────────────
    try:
        step_e_cycle_semantics(data, r)
    except Exception:
        r.fail("REVIEW_BASIS_MISMATCH")
        r.warn(f"semantic check error: {traceback.format_exc()}")

    # ── Step F: Consistency check ─────────────────────────────────────
    try:
        step_f_consistency(data, r)
    except Exception:
        r.fail("CONSISTENCY_CHECK_ERROR")
        r.warn(f"consistency check error: {traceback.format_exc()}")

    # ── Output ────────────────────────────────────────────────────────
    if args.fmt == "json":
        print(json.dumps(r.to_dict(), indent=2))
    else:
        if r.status == "PASS":
            print(f"PASS: {phase} external manifest ({manifest_path.name})")
        else:
            print(f"FAIL: {phase} external manifest ({manifest_path.name})")
            for code in r.failure_codes:
                action = explain_failure_code(code)
                print(f"  - {code}: {action}")
        for w in r.warnings:
            print(f"  WARN: {w}")

    return 4 if r.failure_codes else 0


if __name__ == "__main__":
    sys.exit(main())
