#!/usr/bin/env python3
"""
Convex-side CSP validator parity smoke check:
- validates a fixture-derived payload matrix against:
  - dashboard/convex/validators.ts (via tsx)
  - tools/validate_status.py
- prints a compact js/python pass/fail match matrix.
"""

from __future__ import annotations

import copy
import json
import subprocess
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Tuple


ROOT = Path(__file__).resolve().parents[1]
BASE_FIXTURE = ROOT / "tests" / "fixtures" / "status" / "market_data_stale.json"

TSX_VALIDATE = """
import fs from 'node:fs';
import { validateCspPayload } from './dashboard/convex/validators.ts';

const payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
const report = validateCspPayload(payload);
console.log(JSON.stringify(report));
"""


def load_base_payload() -> dict:
  return json.loads(BASE_FIXTURE.read_text(encoding="utf-8"))


def case(name: str, mutate) -> Tuple[str, callable]:
  return name, mutate


def mutate_noop(payload: dict) -> None:
  return None


def run_js(payload: dict) -> tuple[bool, list[str]]:
  proc = subprocess.run(
    ["npx", "-y", "tsx", "-e", TSX_VALIDATE],
    cwd=ROOT,
    input=json.dumps(payload),
    text=True,
    capture_output=True,
    check=False,
  )
  if proc.returncode != 0:
    return False, [f"JSEXEC_FAIL: {proc.stderr or proc.stdout}"]

  report = json.loads(proc.stdout)
  return report["ok"], [f"{entry['code']}: {entry['message']}" for entry in report["issues"]]


def run_python(payload: dict) -> tuple[bool, list[str]]:
  with NamedTemporaryFile("w", suffix=".json", delete=False) as fp:
    json.dump(payload, fp, separators=(",", ":"), indent=None)
    path = Path(fp.name)

  proc = subprocess.run(
    ["python3", "tools/validate_status.py", "--file", str(path)],
    cwd=ROOT,
    text=True,
    capture_output=True,
    check=False,
  )
  path.unlink()

  if proc.returncode != 0:
    # collect canonical validator messages
    lines = []
    for line in proc.stdout.splitlines():
      line = line.strip()
      if line.startswith("- "):
        lines.append(line[2:])
    if not lines and proc.stderr:
      lines = [line.strip() for line in proc.stderr.splitlines() if line.strip()]
    return False, lines

  return True, []


def run_case(name: str, payload: dict) -> None:
  js_ok, js_issues = run_js(payload)
  py_ok, py_issues = run_python(payload)

  status = "MATCH" if js_ok == py_ok else "MISMATCH"
  print(f"{name}: js={js_ok} py={py_ok} -> {status}")
  if js_ok != py_ok:
    print(f"  JS: {js_issues}")
    print(f"  PY: {py_issues}")


CASES = [
  case(
    "baseline_valid",
    mutate_noop,
  ),
  case(
    "bad_trading_mode",
    lambda p: p.__setitem__("trading_mode", "UnknownMode"),
  ),
  case(
    "decision_a_latch_true_active",
    lambda p: (
      p.__setitem__("open_permission_blocked_latch", True),
      p.__setitem__("open_permission_requires_reconcile", True),
      p.__setitem__("open_permission_reason_codes", ["WS_DATA_STALE_RECONCILE_REQUIRED"]),
      p.__setitem__("trading_mode", "Active"),
      p.__setitem__("mode_reasons", []),
    ),
  ),
  case(
    "tier_purity_bad_kill_reason",
    lambda p: (
      p.__setitem__("trading_mode", "Kill"),
      p.__setitem__("mode_reasons", ["NOT_IN_MANIFEST", "KILL_CORTEX_FORCE_KILL"]),
      p.__setitem__("open_permission_blocked_latch", False),
      p.__setitem__("open_permission_requires_reconcile", False),
      p.__setitem__("open_permission_reason_codes", []),
    ),
  ),
  case(
    "latch_true_empty_reasons",
    lambda p: (
      p.__setitem__("trading_mode", "ReduceOnly"),
      p.__setitem__("mode_reasons", ["REDUCEONLY_OPEN_PERMISSION_LATCHED"]),
      p.__setitem__("open_permission_blocked_latch", True),
      p.__setitem__("open_permission_requires_reconcile", True),
      p.__setitem__("open_permission_reason_codes", []),
    ),
  ),
  case(
    "bad_schema_version",
    lambda p: p.__setitem__("status_schema_version", 2),
  ),
  case(
    "bad_contract_version",
    lambda p: p.__setitem__("contract_version", "4.2"),
  ),
  case(
    "owner_view_nested_malformed",
    lambda p: p.__setitem__(
      "owner_view",
      {
        "primary_owner_reason_code": 123,
        "owner_message": 456,
        "unblock": [
          {"type": "AUTO", "condition": "x", "current": 1, "target": "y"},
        ],
      },
    ),
  ),
]


if __name__ == "__main__":
  base_payload = load_base_payload()
  for name, mutator in CASES:
    payload = copy.deepcopy(base_payload)
    mutator(payload)
    run_case(name, payload)
