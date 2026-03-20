#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SRC="$ROOT/.githooks/pre-push"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$HOOK_SRC" ]] || fail "missing executable hook: $HOOK_SRC"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans"
git -C "$tmp_dir" init -q repo
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" checkout -qb "feature/pre-push-env"

echo "seed" > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm "seed"

cp "$HOOK_SRC" "$repo/.git/hooks/pre-push"
chmod +x "$repo/.git/hooks/pre-push"

cat > "$repo/plans/project_scope_guard.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$repo/plans/project_scope_guard.sh"

cat > "$repo/plans/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for name in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_PREFIX; do
  value="${!name-}"
  printf '%s=%s\n' "$name" "$value"
done > .verify_env
EOF
chmod +x "$repo/plans/verify.sh"

local_sha="$(git -C "$repo" rev-parse HEAD)"
remote_ref="refs/heads/feature/pre-push-env"

set +e
output="$(
  cd "$repo"
  GIT_DIR="$repo/.git" \
  GIT_WORK_TREE="$repo" \
  GIT_INDEX_FILE="$repo/.git/index" \
  GIT_OBJECT_DIRECTORY="$repo/.git/objects" \
  GIT_PREFIX="nested/" \
  bash .git/hooks/pre-push origin https://example.invalid/repo.git <<EOF
refs/heads/feature/pre-push-env $local_sha $remote_ref 0000000000000000000000000000000000000000
EOF
)"
rc=$?
set -e

[[ "$rc" -eq 0 ]] || fail "pre-push hook should succeed with isolated env, got rc=$rc output=$output"

[[ -f "$repo/.verify_env" ]] || fail "verify shim did not run"

while IFS='=' read -r name value; do
  [[ -z "$value" ]] || fail "expected $name to be unset for verify invocation, got '$value'"
done < "$repo/.verify_env"

echo "test_pre_push_hook_env_isolation.sh: ok"
