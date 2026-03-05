#!/usr/bin/env bash
set -euo pipefail

REPO="speelbreaker12/opus-trader"
BRANCH="main"
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

command -v gh >/dev/null || { echo "ABORT: gh CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "ABORT: jq not found" >&2; exit 1; }

[[ -f artifacts/ci_enforcement_backups/protection-restore.json ]] || {
  echo "ABORT: missing artifacts/ci_enforcement_backups/protection-restore.json; run preflight first" >&2
  exit 1
}

EXISTING=$(gh api "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks" --jq '.checks')
[[ -n "$EXISTING" && "$EXISTING" != "null" ]] || { echo "ABORT: failed to read existing status checks" >&2; exit 1; }

BODY=$(jq -n --argjson existing "$EXISTING" '{
  strict: true,
  checks: (
    (
      [ $existing[] | select(.context != "verify" and .context != "crossref-gate") ]
      + [
        {"context":"verify"},
        {"context":"crossref-gate","app_id":15368}
      ]
    )
    | unique_by(.context)
  )
}')

if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "[check-only] status-check patch body:" 
  echo "$BODY" | jq '.'
  exit 0
fi

# Gate: CODEOWNERS must exist on main before enabling code-owner reviews.
gh api "repos/${REPO}/contents/.github/CODEOWNERS?ref=${BRANCH}" --jq '.name' | grep -qx 'CODEOWNERS' || {
  echo "ABORT: CODEOWNERS missing on ${BRANCH}" >&2
  exit 1
}

echo "[apply] required status checks"
echo "$BODY" | gh api "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks" --method PATCH --input - >/dev/null

echo "[apply] required pull request reviews"
RPR_FILE=$(mktemp)
RPR_ERR=$(mktemp)
cleanup_tmp() {
  rm -f "$RPR_FILE" "$RPR_ERR"
}
trap cleanup_tmp EXIT

if gh api "repos/${REPO}/branches/${BRANCH}/protection/required_pull_request_reviews" > "$RPR_FILE" 2>"$RPR_ERR"; then
  RPR_BODY=$(jq '{
    dismiss_stale_reviews: (.dismiss_stale_reviews // false),
    require_code_owner_reviews: true,
    require_last_push_approval: (.require_last_push_approval // false),
    required_approving_review_count: ((.required_approving_review_count // 1) | if . < 1 then 1 else . end)
  }' "$RPR_FILE")
else
  if grep -Eq '404|Not Found' "$RPR_ERR"; then
    RPR_BODY='{"dismiss_stale_reviews":false,"require_code_owner_reviews":true,"require_last_push_approval":false,"required_approving_review_count":1}'
  else
    echo "ABORT: unable to read required_pull_request_reviews" >&2
    cat "$RPR_ERR" >&2
    exit 1
  fi
fi
printf '%s' "$RPR_BODY" | gh api "repos/${REPO}/branches/${BRANCH}/protection/required_pull_request_reviews" --method PATCH --input - >/dev/null

trap - EXIT
cleanup_tmp

echo "[apply] enforce admins"
gh api "repos/${REPO}/branches/${BRANCH}/protection/enforce_admins" --method POST >/dev/null

echo "[done] branch protection updates applied"
