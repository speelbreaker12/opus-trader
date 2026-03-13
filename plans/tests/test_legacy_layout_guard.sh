#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_SOURCE="$ROOT/plans/legacy_layout_guard.sh"

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
mkdir -p "$repo/plans" "$repo/reviews/postmortems"

cp "$GUARD_SOURCE" "$repo/plans/legacy_layout_guard.sh"
chmod +x "$repo/plans/legacy_layout_guard.sh"

write_postmortem() {
  local content="$1"
  cat > "$repo/reviews/postmortems/sample.md" <<EOF
$content
EOF
}

guard_cmd() {
  (
    cd "$repo"
    ./plans/legacy_layout_guard.sh
  )
}

# Forbidden active-path legacy file must fail.
printf '# legacy\n' > "$repo/plans/ralph.sh"
expect_fail "forbidden legacy path" "legacy files found in active paths" guard_cmd
rm -f "$repo/plans/ralph.sh"

# Unlabeled legacy reference in a postmortem must fail.
write_postmortem $'# Postmortem\nThis references plans/ralph.sh as prior workflow context.\n'
expect_fail "unlabeled legacy postmortem" "postmortems with legacy references require archival label" guard_cmd

# Archival label makes the same legacy reference acceptable.
write_postmortem $'# Postmortem\nARCHIVAL NOTE (Legacy Workflow): historical Ralph context only.\nThis references plans/ralph.sh as prior workflow context.\n'
guard_cmd >/dev/null

# Prose-only workflow history should not be treated as legacy reference.
write_postmortem $'# Postmortem\nThis discusses workflow acceptance criteria as historical prose only.\n'
guard_cmd >/dev/null

# Missing postmortem directory should pass (no legacy references found).
rm -rf "$repo/reviews/postmortems"
guard_cmd >/dev/null

echo "PASS: legacy_layout_guard"
