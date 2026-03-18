#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.ralph"

CONTRACT_COVERAGE_OUT="${CONTRACT_COVERAGE_OUT:-$ROOT/.ralph/contract_coverage.md}" \
  "$ROOT/plans/verify.sh" "$@"
