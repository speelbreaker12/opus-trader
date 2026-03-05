#!/usr/bin/env bash
set -euo pipefail

REPO="speelbreaker12/opus-trader"
BRANCH="main"
OWNER_HANDLE="speelbreaker"
DRY_RUN=0

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
    --owner-handle)
      OWNER_HANDLE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

echo "[preflight] gh auth status"
gh auth status >/dev/null

echo "[preflight] admin permission check"
IS_ADMIN=$(gh api "repos/${REPO}" --jq '.permissions.admin')
[[ "$IS_ADMIN" == "true" ]] || { echo "ABORT: caller is not repo admin for ${REPO}" >&2; exit 1; }

echo "[preflight] branch existence check"
BR_NAME=$(gh api "repos/${REPO}/branches/${BRANCH}" --jq '.name')
[[ "$BR_NAME" == "$BRANCH" ]] || { echo "ABORT: branch ${BRANCH} not found" >&2; exit 1; }

echo "[preflight] collaborator handle check"
HANDLE=$(gh api "repos/${REPO}/collaborators/${OWNER_HANDLE}/permission" --jq '.user.login')
[[ "$HANDLE" == "$OWNER_HANDLE" ]] || { echo "ABORT: expected collaborator ${OWNER_HANDLE}, got ${HANDLE}" >&2; exit 1; }

echo "[preflight] ruleset compatibility guard"
RULESET_COUNT=$(gh api "repos/${REPO}/rulesets" --jq 'length')
if [[ "$RULESET_COUNT" -gt 0 ]]; then
  echo "ABORT: ${RULESET_COUNT} rulesets found; branch-protection assumptions may be overridden" >&2
  gh api "repos/${REPO}/rulesets" --jq '.[] | {id, name, target, enforcement}'
  if [[ "${ALLOW_RULESET_COMPAT:-0}" != "1" ]]; then
    echo "Set ALLOW_RULESET_COMPAT=1 only after explicit compatibility review." >&2
    exit 1
  fi
  echo "OVERRIDE: ALLOW_RULESET_COMPAT=1 accepted"
fi

echo "[preflight] local crossref-gate job naming check"
[[ -f .github/workflows/ci.yml ]] || { echo "ABORT: .github/workflows/ci.yml missing" >&2; exit 1; }
grep -q '^  crossref-gate:' .github/workflows/ci.yml || { echo "ABORT: crossref-gate job name not found in ci.yml" >&2; exit 1; }

echo "[preflight] crossref-gate burn-in evidence check"
RUN_IDS=$(gh run list --repo "$REPO" --workflow=ci.yml --limit 10 --json databaseId --jq '.[].databaseId')
FAILURES=0
SUCCESSES=0
OBSERVED=0
PENDING=0
while IFS= read -r RID; do
  [[ -z "$RID" ]] && continue
  RESULT=$(gh run view --repo "$REPO" "$RID" --json jobs --jq '[.jobs[] | select(.name == "crossref-gate") | (.conclusion // "pending")] | .[0] // ""' 2>/dev/null || true)
  [[ -z "$RESULT" ]] && continue
  case "$RESULT" in
    success)
      SUCCESSES=$((SUCCESSES + 1))
      OBSERVED=$((OBSERVED + 1))
      ;;
    skipped|neutral)
      OBSERVED=$((OBSERVED + 1))
      ;;
    pending|"")
      PENDING=$((PENDING + 1))
      ;;
    *)
      OBSERVED=$((OBSERVED + 1))
      echo "FAIL: crossref-gate run ${RID} concluded: ${RESULT}" >&2
      FAILURES=$((FAILURES + 1))
      ;;
  esac
done <<< "$RUN_IDS"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "ABORT: ${FAILURES} crossref-gate failures in last 10 runs" >&2
  exit 1
fi
if [[ "$SUCCESSES" -lt 3 ]]; then
  echo "ABORT: insufficient burn-in evidence (successes=${SUCCESSES}, observed=${OBSERVED}, required>=3)" >&2
  exit 1
fi

echo "[preflight] burn-in OK: successes=${SUCCESSES} observed=${OBSERVED} pending=${PENDING} failures=${FAILURES}"

mkdir -p artifacts/ci_enforcement_backups
RAW_FILE="artifacts/ci_enforcement_backups/protection-raw-$(date -u +%Y%m%dT%H%M%SZ).json"
REVIEWS_FILE="artifacts/ci_enforcement_backups/reviews-raw.json"
REVIEWS_ERR="artifacts/ci_enforcement_backups/reviews-fetch.err"
RESTORE_FILE="artifacts/ci_enforcement_backups/protection-restore.json"

echo "[snapshot] fetching branch protection"
gh api "repos/${REPO}/branches/${BRANCH}/protection" > "$RAW_FILE"

echo "[snapshot] fetching PR review settings"
HAS_REVIEWS=true
if ! gh api "repos/${REPO}/branches/${BRANCH}/protection/required_pull_request_reviews" > "$REVIEWS_FILE" 2>"$REVIEWS_ERR"; then
  if grep -Eq '404|Not Found' "$REVIEWS_ERR"; then
    HAS_REVIEWS=false
  else
    echo "ABORT: failed fetching required_pull_request_reviews endpoint" >&2
    cat "$REVIEWS_ERR" >&2
    exit 1
  fi
fi

if [[ "$HAS_REVIEWS" == "true" ]]; then
  REVIEWS_BLOCK=$(jq '{
    dismiss_stale_reviews: .dismiss_stale_reviews,
    require_code_owner_reviews: .require_code_owner_reviews,
    require_last_push_approval: .require_last_push_approval,
    required_approving_review_count: .required_approving_review_count
  }' "$REVIEWS_FILE")
else
  REVIEWS_BLOCK='null'
fi

jq --argjson reviews "$REVIEWS_BLOCK" '{
  required_status_checks: (
    if .required_status_checks == null then null
    else {
      strict: (.required_status_checks.strict // false),
      checks: (.required_status_checks.checks // [])
    }
    end
  ),
  required_pull_request_reviews: $reviews,
  restrictions: .restrictions,
  enforce_admins: .enforce_admins.enabled,
  allow_force_pushes: .allow_force_pushes.enabled,
  allow_deletions: .allow_deletions.enabled,
  required_linear_history: .required_linear_history.enabled,
  required_conversation_resolution: .required_conversation_resolution.enabled,
  block_creations: .block_creations.enabled,
  lock_branch: .lock_branch.enabled,
  allow_fork_syncing: .allow_fork_syncing.enabled
}' "$RAW_FILE" > "$RESTORE_FILE"

BAD_NULLS=$(jq -r '
  [paths(type == "null")] |
  map(select(. != ["restrictions"] and . != ["required_pull_request_reviews"] and . != ["required_status_checks"])) |
  map(join("."))[]?
' "$RESTORE_FILE")

if [[ -n "$BAD_NULLS" ]]; then
  echo "ABORT: unexpected null values in restore payload at: $BAD_NULLS" >&2
  exit 1
fi

echo "[snapshot] restore payload ready: ${RESTORE_FILE}"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[done] dry-run snapshot complete (remote state read, local artifacts written, no branch-protection writes)"
else
  echo "[done] preflight + snapshot complete"
fi
