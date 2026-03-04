#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_PREFLIGHT="$ROOT/plans/preflight.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SOURCE_PREFLIGHT" ]] || fail "missing source preflight script: $SOURCE_PREFLIGHT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/specs"

cp "$SOURCE_PREFLIGHT" "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

write_pass_script() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$path"
}

write_pass_script "$repo/plans/legacy_layout_guard.sh"
write_pass_script "$repo/plans/readme_ci_parity_check.sh"
write_pass_script "$repo/plans/slice_completion_review_guard.sh"
write_pass_script "$repo/plans/story_review_findings_guard.sh"
write_pass_script "$repo/plans/stoic_cli_invariant_check.sh"
write_pass_script "$repo/plans/toggle_policy_check.sh"
write_pass_script "$repo/plans/prd_schema_check.sh"
write_pass_script "$repo/plans/ok.sh"

cat > "$repo/plans/prd.json" <<'EOF'
{}
EOF
cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract
EOF

(
  cd "$repo"
  git init -q
  git config user.name "fixture"
  git config user.email "fixture@example.com"
)

mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
real_mktemp_path="$(command -v mktemp)"
cat > "$mock_bin/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${MOCK_MKTEMP_STATE:?}"
real_mktemp="${REAL_MKTEMP:?}"

count=0
if [[ -f "$state_file" ]]; then
  count="$(cat "$state_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$state_file"

# First mktemp call in preflight is for guard logs and should succeed.
# Second mktemp call is shell syntax aggregate temp-file setup and is fault-injected.
if [[ "$count" -eq 2 ]]; then
  echo "mock mktemp failure (shell syntax aggregate setup)" >&2
  exit 1
fi

exec "$real_mktemp" "$@"
EOF
chmod +x "$mock_bin/mktemp"

log_file="$tmp_dir/preflight_mktemp_fail.log"
set +e
(
  cd "$repo"
  PATH="$mock_bin:$PATH" \
  MOCK_MKTEMP_STATE="$tmp_dir/mktemp_state" \
  REAL_MKTEMP="$real_mktemp_path" \
  PREFLIGHT_FIXTURE_MODE=none \
  POSTMORTEM_GATE=0 \
  ./plans/preflight.sh >"$log_file" 2>&1
)
rc=$?
set -e

[[ "$rc" -eq 2 ]] || fail "expected rc=2 on shell syntax aggregate mktemp setup failure, got $rc"
grep -Fq "Shell syntax aggregate setup failed (mktemp)" "$log_file" \
  || fail "missing setup-fail diagnostic for aggregate mktemp failure"
grep -Fq "Shell syntax errors in:" "$log_file" \
  || fail "missing shell syntax failure contract message"
grep -Fq "preflight:" "$log_file" \
  || fail "missing deterministic summary line"

echo "test_preflight_shell_syntax_setup_failure.sh: ok"
