from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "tools" / "validate_status.py"
FIXTURE_DIR = ROOT / "tests" / "fixtures" / "status_semantics"


def _run_validator_fixture(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR_PATH),
            "--file",
            str(path),
            "--schema",
            "python/schemas/status_csp_exact.schema.json",
            "--strict",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_legacy_v1_fixture_passes() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "legacy_v1_pass.json")
    assert proc.returncode == 0, proc.stderr


def test_legacy_v1_active_when_latched_fails() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "legacy_v1_fail_active_when_latched.json")
    assert proc.returncode == 1
    assert "[DECISION-A] latch=true prohibits trading_mode='Active'" in proc.stderr


def test_legacy_v1_reason_without_latch_fails() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "legacy_v1_fail_reason_without_latch.json")
    assert proc.returncode == 1
    assert "[LATCH] latch=false requires open_permission_reason_codes=[]" in proc.stderr


def test_v2_manifest_latch_reason_fixture_passes() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "v2_pass_manifest_latch_reason.json")
    assert proc.returncode == 0, proc.stderr


def test_v2_token_rejected_under_v1_fixture() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "v2_fail_new_token_under_v1.json")
    assert proc.returncode == 1
    assert "REDUCEONLY_OPEN_PERMISSION_LATCHED" in proc.stderr


def test_v2_requires_explicit_semantics_version_field() -> None:
    proc = _run_validator_fixture(FIXTURE_DIR / "v2_fail_missing_semantics_version.json")
    assert proc.returncode == 1
    assert "open_permission_semantics_version" in proc.stderr
