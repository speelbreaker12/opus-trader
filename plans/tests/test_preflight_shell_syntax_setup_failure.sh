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
mkdir -p "$repo/plans" "$repo/scripts" "$repo/specs"

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
write_pass_script "$repo/plans/premortem_path_guard.sh"
write_pass_script "$repo/plans/readme_ci_parity_check.sh"
write_pass_script "$repo/plans/slice_completion_review_guard.sh"
write_pass_script "$repo/plans/story_review_findings_guard.sh"
write_pass_script "$repo/plans/stoic_cli_invariant_check.sh"
write_pass_script "$repo/plans/toggle_policy_check.sh"
write_pass_script "$repo/plans/prd_schema_check.sh"
write_pass_script "$repo/plans/ok.sh"

cat > "$repo/scripts/check_skills_index.py" <<'EOF'
#!/usr/bin/env python3
raise SystemExit(0)
EOF
chmod +x "$repo/scripts/check_skills_index.py"

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
real_bash_path="$(command -v bash)"
cat > "$mock_bin/bash" <<'EOF'
#!/bin/sh
set -eu

real_bash="${REAL_BASH:?}"

# Guard scripts should still run; only shell syntax checks are fault-injected.
if [ "${1:-}" = "-n" ]; then
  echo "mock bash failure (shell syntax checker setup)" >&2
  exit 127
fi

exec "$real_bash" "$@"
EOF
chmod +x "$mock_bin/bash"

log_file="$tmp_dir/preflight_mktemp_fail.log"
set +e
(
  cd "$repo"
  PATH="$mock_bin:$PATH" \
  REAL_BASH="$real_bash_path" \
  PREFLIGHT_FIXTURE_MODE=none \
  POSTMORTEM_GATE=0 \
  "$real_bash_path" ./plans/preflight.sh >"$log_file" 2>&1
)
rc=$?
set -e

[[ "$rc" -eq 2 ]] || fail "expected rc=2 on shell syntax checker setup failure, got $rc"
grep -Fq "Shell syntax setup failed while checking" "$log_file" \
  || fail "missing setup-fail diagnostic for shell syntax checker setup failure"
grep -Fq "Shell syntax errors in:" "$log_file" \
  || fail "missing shell syntax failure contract message"
grep -Fq "preflight:" "$log_file" \
  || fail "missing deterministic summary line"

echo "test_preflight_shell_syntax_setup_failure.sh: ok"
