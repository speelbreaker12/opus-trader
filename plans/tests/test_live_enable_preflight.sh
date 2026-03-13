#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_WRAPPER="$ROOT/plans/live_enable_preflight.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SOURCE_WRAPPER" ]] || fail "missing source wrapper: $SOURCE_WRAPPER"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mock_bin="$tmp_dir/mock_bin"
log_file="$tmp_dir/python_invocations.log"
BASH_BIN="$(command -v bash)"

mkdir -p "$repo/plans" "$repo/tools" "$mock_bin"
cp "$SOURCE_WRAPPER" "$repo/plans/live_enable_preflight.sh"
chmod +x "$repo/plans/live_enable_preflight.sh"

cat > "$repo/tools/phase0_meta_test.py" <<'EOF'
print("placeholder")
EOF

cat > "$mock_bin/dirname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

input="${1:-}"
input="${input%/}"
case "$input" in
  */*) printf '%s\n' "${input%/*}" ;;
  *) printf '.\n' ;;
esac
EOF
chmod +x "$mock_bin/dirname"

write_mock_python() {
  local path="$1"
  local label="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$label" "\$*" >> "$log_file"
EOF
  chmod +x "$path"
}

write_mock_python "$mock_bin/python" "python"
write_mock_python "$mock_bin/python3" "python3"

(
  cd "$repo"
  PATH="$mock_bin:/bin" "$BASH_BIN" ./plans/live_enable_preflight.sh
)

expected_default="python3|tools/phase0_meta_test.py --root $repo"
grep -Fxq "$expected_default" "$log_file" \
  || fail "expected wrapper to prefer python3 when both interpreters exist"

rm -f "$log_file"
rm -f "$mock_bin/python3"
(
  cd "$repo"
  PATH="$mock_bin:/bin" "$BASH_BIN" ./plans/live_enable_preflight.sh
)

expected_fallback="python|tools/phase0_meta_test.py --root $repo"
grep -Fxq "$expected_fallback" "$log_file" \
  || fail "expected wrapper to fall back to python when python3 is unavailable"

rm -f "$log_file"
write_mock_python "$mock_bin/custom-python" "custom-python"
(
  cd "$repo"
  PATH="$mock_bin:/bin" PYTHON_BIN=custom-python "$BASH_BIN" ./plans/live_enable_preflight.sh
)

expected_override="custom-python|tools/phase0_meta_test.py --root $repo"
grep -Fxq "$expected_override" "$log_file" \
  || fail "expected wrapper to honor PYTHON_BIN override"

echo "test_live_enable_preflight.sh: ok"
