#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/legacy_layout_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

active_fixture="$tmp_dir/active"
mkdir -p "$active_fixture/plans" "$active_fixture/reviews/postmortems"
cat > "$active_fixture/plans/ralph.sh" <<'EOF'
#!/usr/bin/env bash
echo legacy
EOF

set +e
active_out="$(LEGACY_LAYOUT_GUARD_ROOT="$active_fixture" "$SCRIPT" 2>&1)"
active_rc=$?
set -e

[[ "$active_rc" -ne 0 ]] || fail "expected guard to fail on active legacy path"
echo "$active_out" | grep -Fq "FAIL: legacy files found in active paths:" || fail "missing active-path failure banner"
echo "$active_out" | grep -Fq "  - plans/ralph.sh" || fail "missing exact active-path offender"

postmortem_fixture="$tmp_dir/postmortem"
mkdir -p "$postmortem_fixture/plans" "$postmortem_fixture/reviews/postmortems"
cat > "$postmortem_fixture/reviews/postmortems/unlabeled.md" <<'EOF'
Historical note: the removed command was `plans/ralph.sh`.
EOF

set +e
postmortem_out="$(LEGACY_LAYOUT_GUARD_ROOT="$postmortem_fixture" "$SCRIPT" 2>&1)"
postmortem_rc=$?
set -e

[[ "$postmortem_rc" -ne 0 ]] || fail "expected guard to fail on unlabeled legacy postmortem"
echo "$postmortem_out" | grep -Fq "FAIL: postmortems with legacy references require archival label:" || fail "missing unlabeled-postmortem failure banner"
echo "$postmortem_out" | grep -Fq "  - reviews/postmortems/unlabeled.md" || fail "missing exact unlabeled-postmortem offender"

prose_fixture="$tmp_dir/prose"
mkdir -p "$prose_fixture/plans" "$prose_fixture/reviews/postmortems"
cat > "$prose_fixture/reviews/postmortems/prose.md" <<'EOF'
This postmortem discusses workflow acceptance criteria as historical prose only.
EOF

LEGACY_LAYOUT_GUARD_ROOT="$prose_fixture" "$SCRIPT" >/dev/null \
  || fail "expected prose-only workflow history to pass without archival label"

echo "PASS: legacy layout guard"
