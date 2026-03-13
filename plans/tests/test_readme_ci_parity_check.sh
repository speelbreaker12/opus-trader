#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_SOURCE="$ROOT/plans/readme_ci_parity_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local out=""
  set +e
  out="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$out" | grep -Fq "$pattern" || fail "$label missing expected error '$pattern'"
}

[[ -x "$GUARD_SOURCE" ]] || fail "missing executable guard: $GUARD_SOURCE"

# Real repo should satisfy the guard.
"$GUARD_SOURCE" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/.github/workflows"

cp "$GUARD_SOURCE" "$repo/plans/readme_ci_parity_check.sh"
chmod +x "$repo/plans/readme_ci_parity_check.sh"

write_valid_readme() {
  cat > "$repo/README.md" <<'EOF'
# opus-trader

Run `./plans/verify.sh quick` during iteration.
Run `./plans/verify.sh full` before handoff.
Use `./plans/codex_review_let_pass.sh` for the review step.
EOF
}

write_valid_ci() {
  cat > "$repo/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
  pull_request_review:
  pull_request_review_comment:
  issue_comment:

jobs:
  verify:
    name: Verify (single source of truth)
    runs-on: ubuntu-latest
    steps:
      - run: ./plans/verify.sh full > verify_output.log
      - name: Upload verify log
        uses: actions/upload-artifact@v4
        with:
          name: verify_output.log
          path: verify_output.log

  prd-story-gate:
    if: |
      github.event_name == 'pull_request_review' ||
      github.event_name == 'pull_request_review_comment' ||
      github.event_name == 'issue_comment' && github.event.issue.pull_request
    env:
      PR_NUMBER: ${{ github.event.pull_request.number || github.event.issue.number }}
    steps:
      - run: |
          story_id=S1-001
          aftercare_ack_mode=require
          ./plans/pr_gate.sh --pr "${PR_NUMBER}" --story "${story_id}" --bot-comments-mode block --require-copilot-review --aftercare-ack-mode "${aftercare_ack_mode}"
EOF
}

guard_cmd() {
  (
    cd "$repo"
    ./plans/readme_ci_parity_check.sh
  )
}

write_valid_readme
write_valid_ci
guard_cmd >/dev/null

# README advertising non-canonical verify must fail.
cat > "$repo/README.md" <<'EOF'
# opus-trader

Run ./verify.sh for everything.
Run `./plans/verify.sh quick` during iteration.
Run `./plans/verify.sh full` before handoff.
Use `./plans/codex_review_let_pass.sh` for the review step.
EOF
expect_fail "non-canonical README entrypoint" "README.md contains forbidden reference (non-canonical verify entrypoint)" guard_cmd

write_valid_readme
write_valid_ci

# CI verify job missing full verify must fail.
ci_tmp="$repo/.github/workflows/ci.yml.tmp"
awk '
  !done {
    changed = sub("\\./plans/verify\\.sh full", "./plans/verify.sh quick")
    if (changed) {
      done = 1
    }
  }
  { print }
' "$repo/.github/workflows/ci.yml" > "$ci_tmp"
mv "$ci_tmp" "$repo/.github/workflows/ci.yml"
expect_fail "verify job missing full verify" ".github/workflows/ci.yml verify job missing required token: ./plans/verify.sh full" guard_cmd

echo "PASS: readme_ci_parity_check"
