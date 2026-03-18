from __future__ import annotations

import importlib.util
import json
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType

import pytest


ROOT = Path(__file__).resolve().parents[1]
STOIC_CLI_PATH = ROOT / "stoic-cli"


def _load_stoic_cli_module() -> ModuleType:
  loader = SourceFileLoader("stoic_cli_under_test", str(STOIC_CLI_PATH))
  spec = importlib.util.spec_from_loader(loader.name, loader)
  assert spec is not None
  module = importlib.util.module_from_spec(spec)
  loader.exec_module(module)
  return module


@pytest.fixture(scope="module")
def stoic_cli_module() -> ModuleType:
  return _load_stoic_cli_module()


@pytest.mark.parametrize(
  ("raw_mode", "expected"),
  [
    ("Active", "ACTIVE"),
    ("ReduceOnly", "REDUCE_ONLY"),
    ("Kill", "KILL"),
    ("ACTIVE", "ACTIVE"),
    ("REDUCE_ONLY", "REDUCE_ONLY"),
    ("reduce_only", "REDUCE_ONLY"),
    ("KILL", "KILL"),
    ("reduce-only", "REDUCE_ONLY"),
    ("unknown-mode", "KILL"),
  ],
)
def test_normalize_runtime_mode_aliases(
  stoic_cli_module: ModuleType,
  raw_mode: str,
  expected: str,
) -> None:
  assert stoic_cli_module._normalize_runtime_mode(raw_mode) == expected


@pytest.mark.parametrize(
  ("raw_mode", "expected"),
  [
    ("Active", "ACTIVE"),
    ("ReduceOnly", "REDUCE_ONLY"),
    ("reduce_only", "REDUCE_ONLY"),
    ("Kill", "KILL"),
    ("reduce-only", "REDUCE_ONLY"),
  ],
)
def test_load_runtime_state_accepts_mode_aliases(
  stoic_cli_module: ModuleType,
  tmp_path: Path,
  raw_mode: str,
  expected: str,
) -> None:
  state_path = tmp_path / "runtime_state.json"
  state_path.write_text(
    json.dumps(
      {
        "schema_version": stoic_cli_module.RUNTIME_STATE_SCHEMA_VERSION,
        "trading_mode": raw_mode,
        "orders_in_flight": 0,
        "pending_orders": [],
      }
    ),
    encoding="utf-8",
  )

  state, errors = stoic_cli_module._load_runtime_state(state_path)

  assert errors == []
  assert state["trading_mode"] == expected


def test_load_runtime_state_rejects_unknown_mode(
  stoic_cli_module: ModuleType,
  tmp_path: Path,
) -> None:
  state_path = tmp_path / "runtime_state.json"
  state_path.write_text(
    json.dumps(
      {
        "schema_version": stoic_cli_module.RUNTIME_STATE_SCHEMA_VERSION,
        "trading_mode": "NOT_A_MODE",
        "orders_in_flight": 0,
        "pending_orders": [],
      }
    ),
    encoding="utf-8",
  )

  state, errors = stoic_cli_module._load_runtime_state(state_path)

  assert state["trading_mode"] == "KILL"
  assert any("invalid trading_mode" in err for err in errors), errors
