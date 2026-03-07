#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/readme_ci_parity_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

make_fixture() {
  local name="$1"
  local fixture="$tmp_dir/$name"
  mkdir -p "$fixture/.github/workflows"
  cp "$ROOT/README.md" "$fixture/README.md"
  cp "$ROOT/.github/workflows/ci.yml" "$fixture/.github/workflows/ci.yml"
  printf '%s\n' "$fixture"
}

readme_fixture="$(make_fixture readme)"
printf '\nLegacy shortcut: ./verify.sh quick\n' >> "$readme_fixture/README.md"

set +e
readme_out="$(README_CI_PARITY_ROOT="$readme_fixture" "$SCRIPT" 2>&1)"
readme_rc=$?
set -e

[[ "$readme_rc" -ne 0 ]] || fail "expected parity guard to fail on README forbidden reference"
echo "$readme_out" | grep -Fq "FAIL: README.md contains forbidden reference" || fail "missing README failure banner"
echo "$readme_out" | grep -Eq 'README\.md:[0-9]+:.*\./verify\.sh quick' || fail "missing exact README offender line"

ci_fixture="$(make_fixture ci)"
perl -0pi -e 's#\./plans/verify\.sh full 2>&1 \| tee verify_output\.log#./plans/verify.sh quick\n          ./plans/verify.sh full 2>\&1 | tee verify_output.log#' \
  "$ci_fixture/.github/workflows/ci.yml"

set +e
ci_out="$(README_CI_PARITY_ROOT="$ci_fixture" "$SCRIPT" 2>&1)"
ci_rc=$?
set -e

[[ "$ci_rc" -ne 0 ]] || fail "expected parity guard to fail on CI forbidden reference"
echo "$ci_out" | grep -Fq "FAIL: .github/workflows/ci.yml verify job contains forbidden reference" || fail "missing CI failure banner"
echo "$ci_out" | grep -Eq '\.github/workflows/ci\.yml:[0-9]+:.*\./plans/verify\.sh quick' || fail "missing exact CI offender line"

parse_fixture="$(make_fixture parse)"
cat > "$parse_fixture/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  pull_request:
    types: [opened]

jobs:
  copilot-gate:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
  verify-other:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF

set +e
parse_out="$(README_CI_PARITY_ROOT="$parse_fixture" "$SCRIPT" 2>&1)"
parse_rc=$?
set -e

[[ "$parse_rc" -ne 0 ]] || fail "expected parity guard to fail when verify job is missing"
echo "$parse_out" | grep -Fq "FAIL: unable to parse verify job from .github/workflows/ci.yml" || fail "missing parse failure banner"
echo "$parse_out" | grep -Fq "discovered jobs: copilot-gate verify-other" || fail "missing discovered job ids"

echo "PASS: README/CI verify parity check"
