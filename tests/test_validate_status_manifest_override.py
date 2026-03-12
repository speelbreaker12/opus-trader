from __future__ import annotations

import json
import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "tools" / "validate_status.py"


def _load_validator_module() -> ModuleType:
  spec = importlib.util.spec_from_file_location(
    "validate_status_under_test",
    VALIDATOR_PATH,
  )
  assert spec is not None
  assert spec.loader is not None
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


def _base_manifest() -> dict:
  return {
    "contract_version": "5.2",
    "registries": {
      "ModeReasonCode": {
        "ReduceOnly": [
          "REDUCEONLY_OPEN_PERMISSION_LATCHED",
        ],
        "Kill": [],
      },
      "OpenPermissionReasonCode": {
        "values": [
          "RESTART_RECONCILE_REQUIRED",
        ],
      },
    },
  }


def _base_status() -> dict:
  return {
    "status_schema_version": 1,
    "contract_version": "5.2",
    "trading_mode": "ReduceOnly",
    "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
    "open_permission_blocked_latch": True,
    "open_permission_reason_codes": ["RESTART_RECONCILE_REQUIRED"],
    "open_permission_requires_reconcile": True,
  }


def _base_foundation_status() -> dict:
  return {
    "service_up": True,
    "build_id": "phase-foundation-test",
    "contract_version": "5.2",
    "dispatch_enabled": False,
    "phase": "foundation",
  }


def _run_validator_cli(status: dict, tmp_path: Path, *extra_args: str) -> subprocess.CompletedProcess[str]:
  status_file = tmp_path / "status.json"
  status_file.write_text(json.dumps(status), encoding="utf-8")
  return subprocess.run(
    [sys.executable, str(VALIDATOR_PATH), "--file", str(status_file), *extra_args],
    cwd=ROOT,
    text=True,
    capture_output=True,
    check=False,
  )


def test_manifest_override_open_permission_reason_membership() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  manifest["registries"]["OpenPermissionReasonCode"]["values"] = ["CUSTOM_REASON"]
  status["open_permission_reason_codes"] = ["CUSTOM_REASON"]

  errors = validator.check_contract_invariants(status, manifest)
  assert not errors, errors


def test_decision_a_v52_requires_canonical_latch_reason() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  custom_latch_reason = "REDUCEONLY_OPEN_PERMISSION_ALT_LATCH_REASON"
  manifest["registries"]["ModeReasonCode"]["ReduceOnly"] = [custom_latch_reason]
  status["mode_reasons"] = [custom_latch_reason]

  errors = validator.check_contract_invariants(status, manifest)
  assert errors
  assert any(
    "must include 'REDUCEONLY_OPEN_PERMISSION_LATCHED'" in err
    for err in errors
  ), errors


def test_decision_a_v2_uses_explicit_manifest_latch_reason() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  custom_latch_reason = "REDUCEONLY_OPEN_PERMISSION_ALT_LATCH_REASON"
  status["status_schema_version"] = 2
  status["open_permission_semantics_version"] = 2
  manifest["registries"]["ModeReasonCode"]["ReduceOnly"] = [custom_latch_reason]
  manifest["registries"]["DecisionALatchReasonCode"] = {
    "code": custom_latch_reason,
  }
  status["mode_reasons"] = [custom_latch_reason]

  errors = validator.check_contract_invariants(status, manifest)
  assert not errors, errors


def test_decision_a_v2_requires_explicit_manifest_latch_reason() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  custom_latch_reason = "REDUCEONLY_OPEN_PERMISSION_ALT_LATCH_REASON"
  status["status_schema_version"] = 2
  status["open_permission_semantics_version"] = 2
  manifest["registries"]["ModeReasonCode"]["ReduceOnly"] = [custom_latch_reason]
  status["mode_reasons"] = [custom_latch_reason]

  errors = validator.check_contract_invariants(status, manifest)
  assert errors
  assert any(
    "registries.DecisionALatchReasonCode must define exactly one code" in err
  for err in errors
  ), errors


def test_foundation_contract_accepts_status_lite_shape() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_foundation_status()

  errors = validator.check_foundation_status_contract(status, manifest)
  assert not errors, errors


def test_foundation_contract_rejects_phase2_canonical_fields() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_foundation_status()
  status["trading_mode"] = "Active"

  errors = validator.check_foundation_status_contract(status, manifest)
  assert errors
  assert any(
    "phase='foundation' forbids field 'trading_mode'" in err
    for err in errors
  ), errors


def test_cli_auto_schema_accepts_foundation_status_lite(tmp_path: Path) -> None:
  proc = _run_validator_cli(_base_foundation_status(), tmp_path, "--strict")
  assert proc.returncode == 0, proc.stderr


def test_cli_auto_schema_rejects_non_foundation_status_lite_payload(tmp_path: Path) -> None:
  status = {
    "service_up": True,
    "build_id": "phase-transition-test",
    "contract_version": "5.2",
    "dispatch_enabled": False,
    "phase": "bootstrap_complete",
  }

  proc = _run_validator_cli(status, tmp_path, "--strict")
  assert proc.returncode == 1
  assert "[SCHEMA]" in proc.stderr
  assert "status_schema_version" in proc.stderr


def test_cli_auto_schema_accepts_csp_payload_outside_foundation(tmp_path: Path) -> None:
  status = json.loads(
    (ROOT / "tests" / "fixtures" / "status" / "market_data_stale.json").read_text(
      encoding="utf-8"
    )
  )

  proc = _run_validator_cli(status, tmp_path, "--strict")
  assert proc.returncode == 0, proc.stderr


def test_cli_auto_schema_rejects_foundation_payload_with_canonical_fields(tmp_path: Path) -> None:
  status = _base_foundation_status()
  status["opens_globally_permitted"] = True

  proc = _run_validator_cli(status, tmp_path, "--strict")
  assert proc.returncode == 1
  assert "phase='foundation' forbids field 'opens_globally_permitted'" in proc.stderr


def test_help_does_not_crash_when_generated_module_is_missing(tmp_path: Path) -> None:
  isolated_script = tmp_path / "validate_status.py"
  isolated_script.write_text(VALIDATOR_PATH.read_text(encoding="utf-8"), encoding="utf-8")

  proc = subprocess.run(
    [sys.executable, str(isolated_script), "--help"],
    text=True,
    capture_output=True,
    check=False,
  )

  assert proc.returncode == 0, proc.stderr
  assert "Traceback" not in proc.stderr


# AT-P0E-NEG: per-key negative tests for each CSP key forbidden in foundation mode.
# Each forbidden key, injected individually, must cause check_foundation_status_contract to reject.
@pytest.mark.parametrize("forbidden_key,sample_value", [
  ("mode_reasons", ["REDUCEONLY_OPEN_PERMISSION_LATCHED"]),
  ("open_permission_blocked_latch", True),
  ("enforced_profile", "CSP"),
  ("trading_mode", "ReduceOnly"),
  ("opens_globally_permitted", False),
  ("open_permission_reason_codes", ["RESTART_RECONCILE_REQUIRED"]),
  ("open_permission_requires_reconcile", True),
  ("is_trading_allowed", True),
])
def test_foundation_contract_rejects_each_forbidden_csp_key(
  forbidden_key: str,
  sample_value: object,
) -> None:
  """AT-P0E-NEG: foundation-mode response containing a single forbidden CSP key must be rejected."""
  validator = _load_validator_module()
  manifest = _base_manifest()
  # Start from a valid foundation status, then inject exactly one forbidden key.
  status = _base_foundation_status()
  status[forbidden_key] = sample_value

  errors = validator.check_foundation_status_contract(status, manifest)

  assert errors, (
    f"Expected validator to reject foundation status with forbidden key '{forbidden_key}', "
    f"but no errors were returned"
  )
  assert any(
    f"phase='foundation' forbids field '{forbidden_key}'" in err
    for err in errors
  ), (
    f"Expected error mentioning \"phase='foundation' forbids field '{forbidden_key}'\", "
    f"got: {errors}"
  )
