Invoke the `review-stack` skill to run the full review stack and collect a single gate artifact.

## Steps

1. Use the Skill tool with skill name "review-stack" and follow it fully.

2. After the review stack completes with `PASS` or `CONDITIONAL_PASS`, write the PR gate marker:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/artifacts/pr-review-gate"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//_}"
HEAD=$(git rev-parse HEAD)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$REPO_ROOT/artifacts/pr-review-gate/${SAFE_BRANCH}.json" <<EOF
{
  "branch": "${BRANCH}",
  "head_commit": "${HEAD}",
  "head": "${HEAD}",
  "verdict": "${DECISION}",
  "timestamp_utc": "${TS}"
}
EOF
```

This marker is checked by the PR review gate before `gh pr create`.
