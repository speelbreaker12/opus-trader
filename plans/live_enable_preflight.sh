#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON_BIN_EFFECTIVE="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN_EFFECTIVE" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN_EFFECTIVE="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN_EFFECTIVE="python3"
  else
    echo "FAIL: Missing required command: python (or python3)" >&2
    exit 1
  fi
elif ! command -v "$PYTHON_BIN_EFFECTIVE" >/dev/null 2>&1; then
  echo "FAIL: Missing required command: $PYTHON_BIN_EFFECTIVE" >&2
  exit 1
fi

exec "$PYTHON_BIN_EFFECTIVE" tools/phase0_meta_test.py --root "$ROOT"
