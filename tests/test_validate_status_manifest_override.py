from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType


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
    "contract_version": "5.2",
    "trading_mode": "ReduceOnly",
    "mode_reasons": ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
    "open_permission_blocked_latch": True,
    "open_permission_reason_codes": ["RESTART_RECONCILE_REQUIRED"],
    "open_permission_requires_reconcile": True,
  }


def test_manifest_override_open_permission_reason_membership() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  manifest["registries"]["OpenPermissionReasonCode"]["values"] = ["CUSTOM_REASON"]
  status["open_permission_reason_codes"] = ["CUSTOM_REASON"]

  errors = validator.check_contract_invariants(status, manifest)
  assert not errors, errors


def test_manifest_override_decision_a_reason_uses_manifest_value() -> None:
  validator = _load_validator_module()
  manifest = _base_manifest()
  status = _base_status()

  custom_latch_reason = "REDUCEONLY_OPEN_PERMISSION_ALT_LATCH_REASON"
  manifest["registries"]["ModeReasonCode"]["ReduceOnly"] = [custom_latch_reason]
  status["mode_reasons"] = [custom_latch_reason]

  errors = validator.check_contract_invariants(status, manifest)
  assert not errors, errors


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
