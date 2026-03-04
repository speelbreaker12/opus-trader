#!/usr/bin/env bash
set -euo pipefail

REPO="speelbreaker12/opus-trader"
BRANCH="main"

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
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

command -v gh >/dev/null || { echo "ABORT: gh CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "ABORT: jq not found" >&2; exit 1; }

# Status checks: verify + crossref-gate(app_id 15368)
CHECKS_JSON=$(gh api "repos/${REPO}/branches/${BRANCH}/protection/required_status_checks")
echo "$CHECKS_JSON" | jq -e '.checks | any(.[]; .context == "verify")' >/dev/null || {
  echo "ABORT: required check 'verify' missing" >&2
  exit 1
}
echo "$CHECKS_JSON" | jq -e '.checks | any(.[]; .context == "crossref-gate" and .app_id == 15368)' >/dev/null || {
  echo "ABORT: required check 'crossref-gate' with app_id 15368 missing" >&2
  exit 1
}

# PR reviews: code-owner reviews enabled and at least 1 approval
REVIEWS_JSON=$(gh api "repos/${REPO}/branches/${BRANCH}/protection/required_pull_request_reviews")
echo "$REVIEWS_JSON" | jq -e '.require_code_owner_reviews == true' >/dev/null || {
  echo "ABORT: require_code_owner_reviews is not true" >&2
  exit 1
}
echo "$REVIEWS_JSON" | jq -e '(.required_approving_review_count // 0) >= 1' >/dev/null || {
  echo "ABORT: required_approving_review_count < 1" >&2
  exit 1
}

# Admin enforcement enabled
ADMINS_JSON=$(gh api "repos/${REPO}/branches/${BRANCH}/protection/enforce_admins")
echo "$ADMINS_JSON" | jq -e '.enabled == true' >/dev/null || {
  echo "ABORT: enforce_admins not enabled" >&2
  exit 1
}

echo "VERIFICATION PASSED: branch protection matches expected CI enforcement policy"
