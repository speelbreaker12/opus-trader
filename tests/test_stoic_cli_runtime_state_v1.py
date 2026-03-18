from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

import pytest

ROOT = Path(__file__).resolve().parents[1]


def _run_stoic_cli(args: list[str], env: dict[str, str]) -> None:
  cmd = [sys.executable, str(ROOT / "stoic-cli"), *args]
  completed = subprocess.run(
    cmd,
    cwd=ROOT,
    env=env,
    check=False,
    text=True,
    capture_output=True,
  )
  if completed.returncode != 0:
    raise AssertionError(
      f"stoic-cli failed: rc={completed.returncode}, stdout={completed.stdout}, stderr={completed.stderr}",
    )


def _runtime_state_schema() -> dict:
  return json.loads((ROOT / "python" / "schemas" / "runtime_state_v1.schema.json").read_text(encoding="utf-8"))


@pytest.fixture()
def stoic_runtime_env(tmp_path: Path) -> dict[str, str]:
  env = os.environ.copy()
  env.update(
    {
      "STOIC_RUNTIME_STATE_PATH": str(tmp_path / "runtime_state.phase0.json"),
      "STOIC_RUNTIME_STATE_V1_PATH": str(tmp_path / "runtime_state.json"),
      "STOIC_ALLOW_EXTERNAL_RUNTIME_STATE": "1",
      "STOIC_UNSAFE_EXTERNAL_STATE_ACK": "I_UNDERSTAND",
      "STOIC_DRILL_MODE": "1",
    }
  )
  return env


def test_simulate_open_writes_runtime_state_v1(stoic_runtime_env: dict[str, str]) -> None:
  _run_stoic_cli(
    ["simulate-open", "--instrument", "BTC-PERP", "--count", "1"],
    stoic_runtime_env,
  )

  legacy_path = Path(stoic_runtime_env["STOIC_RUNTIME_STATE_PATH"])
  v1_path = Path(stoic_runtime_env["STOIC_RUNTIME_STATE_V1_PATH"])

  assert legacy_path.exists(), "legacy runtime state file not written"
  assert v1_path.exists(), "runtime_state.v1 file not written"

  v1_payload = json.loads(v1_path.read_text(encoding="utf-8"))
  Draft202012Validator(_runtime_state_schema()).validate(v1_payload)
  assert v1_payload["snapshot_seq"] == 1
  assert v1_payload["safety"]["trading_mode"] == "NORMAL"


def test_simulate_open_increments_snapshot_seq(stoic_runtime_env: dict[str, str]) -> None:
  v1_path = Path(stoic_runtime_env["STOIC_RUNTIME_STATE_V1_PATH"])
  _run_stoic_cli(
    ["simulate-open", "--instrument", "BTC-PERP", "--count", "1"],
    stoic_runtime_env,
  )
  _run_stoic_cli(
    ["simulate-open", "--instrument", "BTC-PERP", "--count", "1"],
    stoic_runtime_env,
  )

  payload = json.loads(v1_path.read_text(encoding="utf-8"))
  assert payload["snapshot_seq"] == 2
