#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER_SRC="$ROOT/plans/check_contract_change_ledger.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_rc() {
  local expected_rc="$1"
  shift

  set +e
  "$@" >"$tmp_dir/out.txt" 2>"$tmp_dir/err.txt"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$tmp_dir/out.txt" >&2 || true
    echo "stderr:" >&2
    cat "$tmp_dir/err.txt" >&2 || true
    fail "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -f "$CHECKER_SRC" ]] || fail "missing checker: $CHECKER_SRC"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/specs" "$repo/plans"

cp "$CHECKER_SRC" "$repo/plans/check_contract_change_ledger.sh"
chmod +x "$repo/plans/check_contract_change_ledger.sh"

cat > "$repo/specs/CONTRACT.md" <<'EOF_CONTRACT'
# CONTRACT fixture

## Baseline
Baseline text.

## **Appendix CONTRACT_CHANGE_LEDGER (Normative, Mandatory)**

| date_utc | change_id | sections_touched | change_type | summary | rationale | AT/VR refs | story/pr |
|---|---|---|---|---|---|---|---|
| 2026-03-01 | CCL-0001 | §0.1 | clarify | baseline row | fixture seed | AT-001 | fixture/main |

## End
EOF_CONTRACT

(
  cd "$repo"
  git init -q
  git config core.hooksPath /dev/null
  git checkout -qb main
  git config user.email "test@example.com"
  git config user.name "Test User"
  git add specs/CONTRACT.md plans/check_contract_change_ledger.sh
  git commit -qm "fixture base"
  git checkout -qb feature/task
)

# Unchanged contract must pass.
expect_rc 0 bash -lc "cd '$repo' && ./plans/check_contract_change_ledger.sh --base-ref main --contract specs/CONTRACT.md"

# Missing base ref must fail closed (no HEAD~1 fallback).
expect_rc 2 bash -lc "cd '$repo' && ./plans/check_contract_change_ledger.sh --base-ref does-not-exist --contract specs/CONTRACT.md"
grep -Fq "unable to resolve merge-base from base ref 'does-not-exist'" "$tmp_dir/err.txt" \
  || fail "expected missing-base diagnostic"

# Changed contract without new ledger row must fail.
cat > "$repo/specs/CONTRACT.md" <<'EOF_CONTRACT_CHANGED'
# CONTRACT fixture

## Baseline
Baseline text changed without ledger row update.

## **Appendix CONTRACT_CHANGE_LEDGER (Normative, Mandatory)**

| date_utc | change_id | sections_touched | change_type | summary | rationale | AT/VR refs | story/pr |
|---|---|---|---|---|---|---|---|
| 2026-03-01 | CCL-0001 | §0.1 | clarify | baseline row | fixture seed | AT-001 | fixture/main |

## End
EOF_CONTRACT_CHANGED

expect_rc 1 bash -lc "cd '$repo' && ./plans/check_contract_change_ledger.sh --base-ref main --contract specs/CONTRACT.md"
grep -Fq "no new ledger row detected" "$tmp_dir/err.txt" || fail "expected missing-row diagnostic"

# Changed contract with a valid new ledger row must pass.
cat > "$repo/specs/CONTRACT.md" <<'EOF_CONTRACT_CHANGED_WITH_ROW'
# CONTRACT fixture

## Baseline
Baseline text changed with ledger row update.

## **Appendix CONTRACT_CHANGE_LEDGER (Normative, Mandatory)**

| date_utc | change_id | sections_touched | change_type | summary | rationale | AT/VR refs | story/pr |
|---|---|---|---|---|---|---|---|
| 2026-03-01 | CCL-0001 | §0.1 | clarify | baseline row | fixture seed | AT-001 | fixture/main |
| 2026-03-04 | CCL-0002 | §1.0 | clarify | fixture contract edit | prove row increment rule | AT-002 | fixture/feature |

## End
EOF_CONTRACT_CHANGED_WITH_ROW

expect_rc 0 bash -lc "cd '$repo' && ./plans/check_contract_change_ledger.sh --base-ref main --contract specs/CONTRACT.md"

echo "PASS: contract change ledger checker"
