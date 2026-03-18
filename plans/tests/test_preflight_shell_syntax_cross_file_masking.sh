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

# Complementary invalid files: each file fails alone, but concatenation can parse.
cat > "$repo/plans/z0_mask_open.sh" <<'EOF'
#!/usr/bin/env bash
if true; then
  echo "open"
EOF

cat > "$repo/plans/z1_mask_close.sh" <<'EOF'
#!/usr/bin/env bash
fi
EOF

chmod +x "$repo/plans/z0_mask_open.sh" "$repo/plans/z1_mask_close.sh"

if bash -n "$repo/plans/z0_mask_open.sh" >/dev/null 2>&1; then
  fail "expected z0_mask_open.sh to fail per-file syntax parse"
fi
if bash -n "$repo/plans/z1_mask_close.sh" >/dev/null 2>&1; then
  fail "expected z1_mask_close.sh to fail per-file syntax parse"
fi

aggregate_file="$tmp_dir/aggregate_plans.sh"
for f in "$repo"/plans/*.sh; do
  cat "$f" >> "$aggregate_file"
  printf '\n' >> "$aggregate_file"
done
if ! bash -n "$aggregate_file" >/dev/null 2>&1; then
  fail "expected concatenated aggregate parse to pass masking fixture"
fi

log_file="$tmp_dir/preflight_cross_file_masking.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE=none \
  POSTMORTEM_GATE=0 \
  ./plans/preflight.sh >"$log_file" 2>&1
)
rc=$?
set -e

[[ "$rc" -eq 1 ]] || fail "expected preflight rc=1 for per-file shell syntax failure, got $rc"
grep -Fq "Shell syntax errors in:" "$log_file" \
  || fail "missing shell syntax failure message"
grep -Fq "plans/z0_mask_open.sh" "$log_file" \
  || fail "missing z0_mask_open.sh in shell syntax failure output"
grep -Fq "plans/z1_mask_close.sh" "$log_file" \
  || fail "missing z1_mask_close.sh in shell syntax failure output"

echo "test_preflight_shell_syntax_cross_file_masking.sh: ok"
