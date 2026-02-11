#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/pr_gate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$GATE" ]] || fail "missing executable gate: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/fake_bin"
repo_dir="$tmp_dir/repo"
mkdir -p "$fake_bin" "$repo_dir/plans"

cp "$GATE" "$repo_dir/plans/pr_gate.sh"
chmod +x "$repo_dir/plans/pr_gate.sh"

cat > "$fake_bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

mode="${GH_MODE:-clean}"
cmd="${1:-}"
sub="${2:-}"

if [[ "$cmd" == "pr" && "$sub" == "view" ]]; then
  if [[ "${3:-}" == "--json" && "${4:-}" == "number" ]]; then
    echo "17"
    exit 0
  fi

  if [[ "$mode" == "changes_requested" ]]; then
    echo "CHANGES_REQUESTED"
  else
    echo "APPROVED"
  fi
  exit 0
fi

if [[ "$cmd" != "api" ]]; then
  echo "unsupported gh invocation: $*" >&2
  exit 2
fi

endpoint="${2:-}"
case "$endpoint" in
  repos/acme/demo/pulls/17)
    if [[ "$mode" == "dirty_merge" ]]; then
      cat <<'EOF_JSON'
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"abc123"},"base":{"ref":"main"},"mergeable":false,"mergeable_state":"dirty"}
EOF_JSON
    else
      cat <<'EOF_JSON'
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"abc123"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"clean"}
EOF_JSON
    fi
    ;;
  repos/acme/demo/commits/abc123)
    cat <<'EOF_JSON'
{"commit":{"committer":{"date":"2026-02-11T00:00:00Z"}}}
EOF_JSON
    ;;
  repos/acme/demo/commits/abc123/check-runs)
    case "$mode" in
      pending_checks)
        cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"in_progress","conclusion":null,"html_url":"https://example.invalid/check/1"}]}
EOF_JSON
        ;;
      failing_checks)
        cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"completed","conclusion":"failure","html_url":"https://example.invalid/check/1"}]}
EOF_JSON
        ;;
      *)
        cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"completed","conclusion":"success","html_url":"https://example.invalid/check/1"}]}
EOF_JSON
        ;;
    esac
    ;;
  repos/acme/demo/commits/abc123/status)
    cat <<'EOF_JSON'
{"statuses":[{"state":"success"}]}
EOF_JSON
    ;;
  repos/acme/demo/pulls/17/comments?per_page=100)
    if [[ "$mode" == "bot_comment" ]]; then
      cat <<'EOF_JSON'
[{"created_at":"2026-02-11T00:05:00Z","html_url":"https://example.invalid/pr-comment/1","body":"Automated finding","user":{"login":"copilot-swe-agent","type":"Bot"}}]
EOF_JSON
    else
      echo '[]'
    fi
    ;;
  repos/acme/demo/issues/17/comments?per_page=100)
    echo '[]'
    ;;
  *)
    echo "unsupported gh api endpoint: $endpoint" >&2
    exit 2
    ;;
esac
EOF_GH
chmod +x "$fake_bin/gh"

git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "ci@example.com"
git -C "$repo_dir" config user.name "CI"
echo "fixture" > "$repo_dir/README.md"
git -C "$repo_dir" add README.md
git -C "$repo_dir" commit -q -m "init fixture repo"
git -C "$repo_dir" remote add origin "https://github.com/acme/demo.git"

# Case 1: auto-detected PR passes; bot comments are warnings in default mode.
set +e
out_case1="$(
  cd "$repo_dir" && GH_MODE=bot_comment PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --story S1 --artifacts-root "$tmp_dir/artifacts" 2>&1
)"
rc_case1=$?
set -e
[[ $rc_case1 -eq 0 ]] || fail "expected case1 to pass"
printf '%s\n' "$out_case1" | grep -Fq "OK: PR gate passed" || fail "case1 missing pass output"
printf '%s\n' "$out_case1" | grep -Fq "WARN: detected new bot/copilot comments since head commit" || fail "case1 missing warn-mode bot comment warning"

report_count="$(find "$tmp_dir/artifacts/S1/pr_gate" -type f -name '*_pr_gate.md' | wc -l | tr -d '[:space:]')"
[[ "$report_count" -eq 1 ]] || fail "expected one report artifact for case1"

# Case 2: merge conflicts/blocked state fail closed.
expect_fail "mergeable state dirty" "merge_conflict_or_blocked: mergeable_state=dirty" \
  bash -lc "cd '$repo_dir' && GH_MODE=dirty_merge PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 3: pending checks fail.
expect_fail "checks pending" "checks_pending" \
  bash -lc "cd '$repo_dir' && GH_MODE=pending_checks PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 4: bot comments can be elevated to blocking mode.
expect_fail "bot comment blocking mode" "new_bot_comments_since_last_push" \
  bash -lc "cd '$repo_dir' && GH_MODE=bot_comment PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --bot-comments-mode block"

echo "PASS: pr_gate fixtures"
