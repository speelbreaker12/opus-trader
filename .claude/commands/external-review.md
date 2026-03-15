Invoke the external-review-generic skill to run codex, opus, kimi, and gemini reviewers in parallel.

## Steps

1. Use the Skill tool with skill name "external-review-generic" and follow it fully.

2. After the external review completes successfully, write the external gate marker:

```bash
mkdir -p artifacts/pr-review-gate
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SAFE_BRANCH="${BRANCH//\//_}"
HEAD=$(git rev-parse --short HEAD)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "artifacts/pr-review-gate/${SAFE_BRANCH}.external.json" <<EOF
{
  "branch": "${BRANCH}",
  "head": "${HEAD}",
  "timestamp_utc": "${TS}"
}
EOF
```

This marker is checked (as a warning, not a block) by the PR gate hook before `gh pr create`.
