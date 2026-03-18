from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_probe(mode: str) -> dict:
  proc = subprocess.run(
    ["npx", "-y", "tsx", "tests/probes/status_contract_probe.ts", mode],
    cwd=ROOT,
    text=True,
    capture_output=True,
    check=False,
  )
  if proc.returncode != 0:
    raise AssertionError(f"probe failed [{mode}] rc={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}")
  return json.loads(proc.stdout)


def test_apply_upsert_status_contract_idempotency_and_pointer_updates() -> None:
  result = run_probe("idempotent")

  assert result["first"]["duplicate"] is False
  assert result["duplicate"]["duplicate"] is True
  assert result["advanced"]["duplicate"] is False

  assert result["snapshot_count"] == 2
  assert result["pointer_count"] == 1
  assert result["latest_snapshot"] == "h-2"
  assert result["latest_state"] in {"FRESH", "STALE", "UNKNOWN"}


def test_get_latest_status_freshness_state_reasoning() -> None:
  result = run_probe("freshness")

  assert result["fresh"] == "FRESH"
  assert result["stale"] == "STALE"
  assert result["invalid"] == "UNKNOWN"
  assert result["invalid_reason"].startswith("generated_at is not parseable")
