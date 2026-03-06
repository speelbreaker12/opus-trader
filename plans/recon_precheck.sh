#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: plans/recon_precheck.sh STORY_ID [--json]

Hard gate for reconciliation workflow entry.

Checks:
  1) Premortem file exists at reviews/premortems/<STORY_ID>_premortem.md
  2) No global AT ownership conflicts for STORY_ID in plans/prd.json

Options:
  --json    Emit machine-readable result JSON
  -h|--help Show this help

Exit codes:
  0 = precheck passed
  1 = precheck failed (blockers found)
  2 = usage/setup error
USAGE
}

story_id="${1:-}"
if [[ -z "$story_id" ]]; then
  usage >&2
  exit 2
fi
shift

json_mode=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) json_mode=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ ! "$story_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "ERROR: invalid STORY_ID '$story_id'" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repository" >&2
  exit 2
}
cd "$repo_root"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for ownership conflict checks" >&2
  exit 2
fi

prd_file="plans/prd.json"
if [[ ! -f "$prd_file" ]]; then
  echo "ERROR: missing PRD file: $prd_file" >&2
  exit 2
fi

head_commit="$(git rev-parse --short=12 HEAD 2>/dev/null || echo "UNKNOWN")"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
premortem_path="reviews/premortems/${story_id}_premortem.md"
premortem_exists=false
reasons=()

if [[ -f "$premortem_path" ]]; then
  premortem_exists=true
else
  reasons+=("premortem file not found: $premortem_path")
fi

conflict_payload="$(
  jq -c --arg sid "$story_id" '
    def owner_claims($obj):
      if (($obj | has("primary_owner_for")) and (($obj.primary_owner_for // null) != null)) then
        ($obj.primary_owner_for // [])
      else
        ($obj.enforcing_contract_ats // [])
      end;

    [ .items[]? | {id: (.id | tostring), claims: (owner_claims(.) | map(tostring))} ] as $items
    | [ (.stories // {}) | to_entries[]? | {id: (.key | tostring), claims: (owner_claims(.value) | map(tostring))} ] as $legacy
    | ($legacy + $items) as $all
    | (reduce $all[] as $story ({}; .[$story.id] = $story.claims)
       | to_entries
       | map({id: .key, claims: .value})) as $stories
    | ($stories | map(select(.id == $sid)) | first) as $target
    | if $target == null then
        {story_found: false, conflicts: []}
      else
        {story_found: true, conflicts: [
          $target.claims[]? as $at
          | {at_id: $at, claiming_stories: [$stories[] | select((.claims // []) | index($at)) | .id]}
          | select((.claiming_stories | length) > 1)
        ]}
      end
  ' "$prd_file"
)" || {
  echo "ERROR: failed to parse ownership conflict data from $prd_file" >&2
  exit 2
}

if ! echo "$conflict_payload" | jq -e '.story_found != null and (.conflicts | type == "array")' >/dev/null 2>&1; then
  echo "ERROR: failed to interpret ownership conflict data from $prd_file" >&2
  exit 2
fi

story_found="$(echo "$conflict_payload" | jq -r '.story_found')"
conflict_json="$(echo "$conflict_payload" | jq -c '.conflicts')"
ownership_conflicts="$(echo "$conflict_payload" | jq -r '.conflicts | length')"
if [[ "$story_found" != "true" ]]; then
  reasons+=("story not found in $prd_file: $story_id")
fi
if [[ "$ownership_conflicts" -gt 0 ]]; then
  if [[ "${RECON_SKIP_OWNERSHIP:-0}" == "1" ]]; then
    echo "WARN: $ownership_conflicts AT ownership conflict(s) found but RECON_SKIP_OWNERSHIP=1 — skipping" >&2
    echo "$conflict_json" | jq -r '.[] | "  - \(.at_id): \(.claiming_stories | join(", "))"' >&2
    ownership_conflicts=0
  else
    reasons+=("$ownership_conflicts AT ownership conflict(s) found")
  fi
fi

# ==== Stale-docs check (warning only, does not block) ====
stale_docs=()
for doc in \
  "plans/step_prompts/recon/INDEX.md" \
  "plans/prompts/slice_reconcile_r1_audit.md" \
  "reviews/reconciliations/PROTOCOL.md" \
  "reviews/reconciliations/REFERENCE.md" \
  "reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md" \
  "plans/wf_step.sh"; do
  if [[ -f "$doc" ]] && git cat-file -e "main:$doc" 2>/dev/null; then
    main_hash="$(git rev-parse "main:$doc" 2>/dev/null || true)"
    local_hash="$(git rev-parse "HEAD:$doc" 2>/dev/null || true)"
    if [[ -n "$main_hash" && -n "$local_hash" && "$main_hash" != "$local_hash" ]]; then
      stale_docs+=("$doc")
    fi
  fi
done

if [[ ${#stale_docs[@]} -gt 0 && "$json_mode" -ne 1 ]]; then
  echo "WARN: ${#stale_docs[@]} process doc(s) differ from main — consider \`git merge main\` before proceeding" >&2
  for sd in "${stale_docs[@]}"; do
    echo "  - $sd" >&2
  done
fi

ready=false
if [[ "$premortem_exists" == "true" && "$story_found" == "true" && "$ownership_conflicts" -eq 0 ]]; then
  ready=true
fi

if [[ "$json_mode" -eq 1 ]]; then
  jq -n \
    --arg schema_version "recon_precheck.v1" \
    --arg head_commit "$head_commit" \
    --arg created_at "$created_at" \
    --arg story_id "$story_id" \
    --arg premortem_path "$premortem_path" \
    --argjson premortem_exists "$premortem_exists" \
    --argjson ownership_conflicts "$ownership_conflicts" \
    --argjson ownership_conflict_details "$conflict_json" \
    --argjson reasons "$(printf '%s\n' "${reasons[@]:-}" | jq -R -s 'split("\n") | map(select(length>0))')" \
    --argjson ready "$ready" \
    --argjson stale_docs "$(printf '%s\n' "${stale_docs[@]:-}" | jq -R -s 'split("\n") | map(select(length>0))')" \
    '{
      schema_version: $schema_version,
      head_commit: $head_commit,
      created_at: $created_at,
      story_id: $story_id,
      ready: $ready,
      premortem_path: $premortem_path,
      premortem_exists: $premortem_exists,
      ownership_conflicts: $ownership_conflicts,
      ownership_conflict_details: $ownership_conflict_details,
      reasons: $reasons,
      stale_docs: $stale_docs
    }'
fi

if [[ "$ready" == "true" ]]; then
  if [[ "$json_mode" -ne 1 ]]; then
    echo "PASS: recon precheck ready for $story_id"
  fi
  exit 0
fi

echo "FAIL: recon precheck blocked for $story_id" >&2
for reason in "${reasons[@]:-}"; do
  [[ -n "$reason" ]] && echo "  - $reason" >&2
done
if [[ "$ownership_conflicts" -gt 0 ]]; then
  echo "$conflict_json" | jq -r '.[] | "  - \(.at_id): \(.claiming_stories | join(", "))"' >&2
fi
exit 1
