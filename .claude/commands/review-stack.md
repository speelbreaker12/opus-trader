Invoke the review-stack skill to run the full 7-skill review stack and emit the PR review gate marker.

## Steps

1. Use the Skill tool with skill name "review-stack" and follow it fully.

2. Capture the reviewed head:

```bash
git rev-parse HEAD
```

3. After the review completes successfully, write the gate marker under `artifacts/pr-review-gate`:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/artifacts/pr-review-gate"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//_}"
HEAD=$(git rev-parse HEAD)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$REPO_ROOT/artifacts/pr-review-gate/${SAFE_BRANCH}.review-stack.json" <<EOF
{
  "branch": "${BRANCH}",
  "head_commit": "${HEAD}",
  "head": "${HEAD}",
  "timestamp_utc": "${TS}"
}
EOF
```

This marker is checked by workflow review gates before PR publication and merge.
