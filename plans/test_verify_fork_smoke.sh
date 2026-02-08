#!/usr/bin/env bash
# =============================================================================
# Smoke test for the verify fork migration
# Validates structural invariants without running the full verify chain.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

check_not() {
  local label="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== verify fork smoke test ==="
echo ""

# 1) Syntax checks
echo "1) Syntax checks"
check "plans/verify.sh parses"        bash -n plans/verify.sh
check "plans/verify_fork.sh parses"   bash -n plans/verify_fork.sh
check "plans/prd_set_pass.sh parses"  bash -n plans/prd_set_pass.sh
check "plans/workflow_verify.sh parses" bash -n plans/workflow_verify.sh
echo ""

# 2) Wrapper chain: verify.sh must exec verify_fork.sh
echo "2) Wrapper chain"
check "verify.sh references verify_fork.sh" grep -q 'verify_fork\.sh' plans/verify.sh
check "verify.sh uses exec" grep -q 'exec.*verify_fork\.sh' plans/verify.sh
echo ""

# 3) verify_fork.sh sources verify_utils.sh (not standalone)
echo "3) Library sourcing"
check "verify_fork.sh sources verify_utils.sh" grep -q 'source.*verify_utils\.sh' plans/verify_fork.sh
check_not "verify_fork.sh does not source verify_checkpoint.sh" grep -q 'source.*verify_checkpoint\.sh' plans/verify_fork.sh
check_not "verify_fork.sh does not source change_detection.sh" grep -q 'source.*change_detection\.sh' plans/verify_fork.sh
echo ""

# 4) Fork contract: no workflow_acceptance in runtime gates
echo "4) Fork contract (no workflow_acceptance in runtime path)"
check_not "verify_fork.sh does not call workflow_acceptance.sh" \
  grep -E '(bash|exec|source|\./plans/).*workflow_acceptance' plans/verify_fork.sh
check_not "verify_fork.sh has no checkpoint skip entrypoint" grep -q '^[[:space:]]*decide_skip_gate\(\)' plans/verify_fork.sh
check "verify_fork.sh usage is quick/full only" grep -q 'Usage: ./plans/verify.sh \[quick|full\]' plans/verify_fork.sh
check "verify_fork.sh writes verify.meta.json" grep -q 'verify.meta.json' plans/verify_fork.sh
check "verify_fork.sh includes contract_kernel gate" grep -q 'run_logged_or_exit \"contract_kernel\"' plans/verify_fork.sh
echo ""

# 5) Root wrapper chain (if root verify.sh exists)
echo "5) Root wrapper"
if [[ -f verify.sh ]]; then
  check "root verify.sh delegates to plans/" grep -q 'plans/verify\.sh' verify.sh
else
  echo "  SKIP: no root verify.sh"
fi
echo ""

# Summary
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
