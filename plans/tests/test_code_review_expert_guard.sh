#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_SRC="$ROOT/plans/code_review_expert_guard.sh"
ATTEST_SRC="$ROOT/plans/code_review_expert_attest.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$GUARD_SRC" ]] || fail "missing executable guard script: $GUARD_SRC"
[[ -x "$ATTEST_SRC" ]] || fail "missing executable attest script: $ATTEST_SRC"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"

mkdir -p "$repo/plans"
cp "$GUARD_SRC" "$repo/plans/code_review_expert_guard.sh"
cp "$ATTEST_SRC" "$repo/plans/code_review_expert_attest.sh"

cd "$repo"
git init -q
git config user.name "Test User"
git config user.email "test@example.com"
git config core.hooksPath /dev/null

echo "base" > README.md
git add README.md
git commit -q -m "init"

./plans/code_review_expert_guard.sh

mkdir -p python
echo 'print("x")' > python/app.py
git add python/app.py

set +e
no_attest_output="$(./plans/code_review_expert_guard.sh 2>&1)"
no_attest_rc=$?
set -e
[[ "$no_attest_rc" -ne 0 ]] || fail "guard should fail without attestation for significant changes"
printf '%s\n' "$no_attest_output" | grep -Fq "code-review-expert" \
  || fail "missing code-review-expert diagnostic"

SKIP_CODE_REVIEW_EXPERT_HOOK=1 ./plans/code_review_expert_guard.sh

./plans/code_review_expert_attest.sh
./plans/code_review_expert_guard.sh

echo 'print("y")' >> python/app.py
git add python/app.py

set +e
stale_output="$(./plans/code_review_expert_guard.sh 2>&1)"
stale_rc=$?
set -e
[[ "$stale_rc" -ne 0 ]] || fail "guard should fail when attestation is stale"
printf '%s\n' "$stale_output" | grep -Fq "stale" \
  || fail "missing stale attestation diagnostic"

./plans/code_review_expert_attest.sh
./plans/code_review_expert_guard.sh

git reset --hard -q HEAD
echo "docs-only update" > NOTES.md
git add NOTES.md
./plans/code_review_expert_guard.sh

echo "PASS: code_review_expert_guard"
