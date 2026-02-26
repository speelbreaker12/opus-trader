#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEMA_VERSION="recon_bundle.v1"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  plans/recon_bundle.sh export --slice <S#> [--verify-run <run_id>] [--bundle-id <id>] [--out-root <path>]
  plans/recon_bundle.sh import --bundle <bundle_dir> [--allow-head-mismatch] [--dry-run]

Commands:
  export   Build deterministic recon evidence bundle (directory + manifest)
  import   Validate and import bundle payload into current repo

Options (export):
  --slice <S#>              Required slice id (example: S14)
  --verify-run <run_id>     Optional verify run id to include from artifacts/verify/<run_id>/
  --bundle-id <id>          Optional deterministic bundle id (default: recon_<slice>_<utcstamp>)
  --out-root <path>         Optional output root (default: artifacts/recon_bundles)

Options (import):
  --bundle <bundle_dir>     Required bundle directory path
  --allow-head-mismatch     Allow import when source_head_sha != current HEAD
  --dry-run                 Validate only; do not write files
USAGE
}

need_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: $cmd"
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "sha256 tool not found (need sha256sum or shasum)"
  fi
}

normalize_rel_path() {
  local rel="$1"
  rel="${rel#./}"
  printf '%s\n' "$rel"
}

assert_safe_rel_path() {
  local rel="$1"
  [[ -n "$rel" ]] || fail "unsafe empty manifest path"
  [[ "$rel" != /* ]] || fail "unsafe manifest path (absolute): $rel"
  [[ "$rel" != *$'\n'* ]] || fail "unsafe manifest path (newline): $rel"
  [[ "$rel" != */ ]] || fail "unsafe manifest path (trailing slash): $rel"
  if printf '%s\n' "$rel" | grep -Eq '(^|/)\.\.(/|$)'; then
    fail "unsafe manifest path (dotdot): $rel"
  fi
  if printf '%s\n' "$rel" | grep -Eq '(^|/)\.(/|$)'; then
    fail "unsafe manifest path (dot component): $rel"
  fi
}

is_allowed_scope_path() {
  local rel="$1"
  local slice="$2"
  local verify_run="${3:-}"

  if [[ "$rel" == "reviews/reconciliations/$slice/"* ]]; then
    return 0
  fi

  if [[ "$rel" == ".wf/receipts/${slice}-"*/* ]]; then
    return 0
  fi

  if [[ "$rel" == ".wf/recon_scope_lock/${slice}-"*.scope_lock.json ]]; then
    return 0
  fi

  if [[ "$rel" == "artifacts/story/${slice}-"*/* ]]; then
    return 0
  fi

  if [[ -n "$verify_run" && "$rel" == "artifacts/verify/$verify_run/"* ]]; then
    return 0
  fi

  return 1
}

append_scope_files() {
  local list_file="$1"
  local find_expr="$2"
  local scope_desc="$3"
  local found=0
  local rel=""

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rel="$(normalize_rel_path "$rel")"
    [[ -n "$rel" ]] || continue
    printf '%s\n' "$rel" >> "$list_file"
    found=1
  done < <(eval "$find_expr" | LC_ALL=C sort)

  [[ "$found" -eq 1 ]] || fail "missing required export scope: $scope_desc"
}

build_export_bundle() {
  local slice="$1"
  local verify_run="$2"
  local bundle_id="$3"
  local out_root="$4"

  local files_list=""
  local bundle_dir=""
  local payload_dir=""
  local manifest_tmp=""
  local file_rows=""
  local rel=""
  local src=""
  local dst=""
  local sha=""
  local size=""
  local files_json=""
  local created_at_utc=""
  local source_head_sha=""

  files_list="$(mktemp)"
  file_rows="$(mktemp)"

  append_scope_files "$files_list" "find reviews/reconciliations/$slice -type f 2>/dev/null || true" "reviews/reconciliations/$slice/**"
  append_scope_files "$files_list" "find .wf/receipts -type f -path '.wf/receipts/${slice}-*/*' 2>/dev/null || true" ".wf/receipts/${slice}-*/**"
  append_scope_files "$files_list" "find .wf/recon_scope_lock -type f -name '${slice}-*.scope_lock.json' 2>/dev/null || true" ".wf/recon_scope_lock/${slice}-*.scope_lock.json"
  append_scope_files "$files_list" "find artifacts/story -type f -path 'artifacts/story/${slice}-*/*' 2>/dev/null || true" "artifacts/story/${slice}-*/**"

  if [[ -n "$verify_run" ]]; then
    append_scope_files "$files_list" "find artifacts/verify/$verify_run -type f 2>/dev/null || true" "artifacts/verify/$verify_run/**"
  fi

  sort -u "$files_list" -o "$files_list"
  [[ -s "$files_list" ]] || fail "no files selected for bundle export"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    assert_safe_rel_path "$rel"
    is_allowed_scope_path "$rel" "$slice" "$verify_run" || fail "selected file outside allowed scope: $rel"
    [[ -f "$ROOT/$rel" ]] || fail "selected file does not exist: $rel"
  done < "$files_list"

  mkdir -p "$out_root"
  bundle_dir="$out_root/$bundle_id"
  payload_dir="$bundle_dir/payload"
  [[ ! -e "$bundle_dir" ]] || fail "bundle output already exists: $bundle_dir"
  mkdir -p "$payload_dir"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$ROOT/$rel"
    dst="$payload_dir/$rel"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"

    sha="$(sha256_file "$dst")"
    size="$(wc -c < "$dst" | tr -d '[:space:]')"
    jq -cn \
      --arg path "$rel" \
      --arg sha256 "$sha" \
      --argjson size_bytes "$size" \
      '{path:$path,sha256:$sha256,size_bytes:$size_bytes}' >> "$file_rows"
  done < "$files_list"

  files_json="$(jq -s 'sort_by(.path)' "$file_rows")"
  created_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  source_head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$source_head_sha" ]] || fail "unable to determine source head sha"

  manifest_tmp="$(mktemp)"
  if [[ -n "$verify_run" ]]; then
    jq -n \
      --arg schema_version "$SCHEMA_VERSION" \
      --arg bundle_id "$bundle_id" \
      --arg slice_id "$slice" \
      --arg source_head_sha "$source_head_sha" \
      --arg created_at_utc "$created_at_utc" \
      --arg verify_run_id "$verify_run" \
      --argjson files "$files_json" \
      '{
        schema_version: $schema_version,
        bundle_id: $bundle_id,
        slice_id: $slice_id,
        source_head_sha: $source_head_sha,
        created_at_utc: $created_at_utc,
        verify_run_id: $verify_run_id,
        files: $files
      }' > "$manifest_tmp"
  else
    jq -n \
      --arg schema_version "$SCHEMA_VERSION" \
      --arg bundle_id "$bundle_id" \
      --arg slice_id "$slice" \
      --arg source_head_sha "$source_head_sha" \
      --arg created_at_utc "$created_at_utc" \
      --argjson files "$files_json" \
      '{
        schema_version: $schema_version,
        bundle_id: $bundle_id,
        slice_id: $slice_id,
        source_head_sha: $source_head_sha,
        created_at_utc: $created_at_utc,
        files: $files
      }' > "$manifest_tmp"
  fi

  jq empty "$manifest_tmp" >/dev/null 2>&1 || fail "failed to build manifest json"
  mv "$manifest_tmp" "$bundle_dir/bundle.manifest.json"
  rm -f "$files_list" "$file_rows"
  echo "OK: recon bundle exported ($bundle_dir)"
}

validate_manifest_structure() {
  local manifest="$1"
  jq -e '
    (.schema_version | type == "string" and length > 0) and
    (.bundle_id | type == "string" and length > 0) and
    (.slice_id | type == "string" and length > 0) and
    (.source_head_sha | type == "string" and length > 0) and
    (.created_at_utc | type == "string" and length > 0) and
    (.files | type == "array" and length > 0) and
    ([.files[] |
      (.path | type == "string" and length > 0) and
      (.sha256 | type == "string" and length > 0) and
      (.size_bytes | type == "number" and . >= 0)
    ] | all)
  ' "$manifest" >/dev/null 2>&1 || fail "invalid manifest structure: $manifest"
}

import_bundle_payload() {
  local bundle_dir="$1"
  local allow_head_mismatch="$2"
  local dry_run="$3"
  local manifest="$bundle_dir/bundle.manifest.json"
  local payload_root="$bundle_dir/payload"
  local schema_version=""
  local slice_id=""
  local source_head_sha=""
  local verify_run_id=""
  local current_head_sha=""
  local paths=""
  local sorted_paths=""
  local rel=""
  local payload_file=""
  local expected_sha=""
  local expected_size=""
  local actual_sha=""
  local actual_size=""

  [[ -d "$bundle_dir" ]] || fail "bundle directory not found: $bundle_dir"
  [[ -f "$manifest" ]] || fail "bundle manifest not found: $manifest"
  [[ -d "$payload_root" ]] || fail "bundle payload directory not found: $payload_root"
  jq empty "$manifest" >/dev/null 2>&1 || fail "bundle manifest is not valid json: $manifest"
  validate_manifest_structure "$manifest"

  schema_version="$(jq -r '.schema_version' "$manifest")"
  [[ "$schema_version" == "$SCHEMA_VERSION" ]] || fail "unsupported schema_version '$schema_version' (expected $SCHEMA_VERSION)"

  slice_id="$(jq -r '.slice_id' "$manifest")"
  source_head_sha="$(jq -r '.source_head_sha' "$manifest")"
  verify_run_id="$(jq -r '.verify_run_id // empty' "$manifest")"
  current_head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$current_head_sha" ]] || fail "unable to determine current HEAD"

  if [[ "$allow_head_mismatch" -ne 1 && "$current_head_sha" != "$source_head_sha" ]]; then
    fail "source_head_sha mismatch (source=$source_head_sha current=$current_head_sha)"
  fi

  paths="$(jq -r '.files[].path' "$manifest")"
  [[ -n "$paths" ]] || fail "manifest files[] empty"
  sorted_paths="$(printf '%s\n' "$paths" | LC_ALL=C sort)"
  [[ "$paths" == "$sorted_paths" ]] || fail "manifest files[] must be sorted by path"
  dupes="$(printf '%s\n' "$paths" | LC_ALL=C sort | uniq -d || true)"
  [[ -z "$dupes" ]] || fail "manifest files[] contains duplicate path(s): $dupes"

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    assert_safe_rel_path "$rel"
    is_allowed_scope_path "$rel" "$slice_id" "$verify_run_id" || fail "unsafe manifest path outside allowed scope: $rel"

    payload_file="$payload_root/$rel"
    [[ -e "$payload_file" ]] || fail "missing payload file: $rel"
    [[ -f "$payload_file" ]] || fail "payload entry is not a regular file: $rel"
    [[ ! -L "$payload_file" ]] || fail "payload entry must not be symlink: $rel"

    expected_sha="$(jq -r --arg path "$rel" '.files[] | select(.path == $path) | .sha256' "$manifest")"
    expected_size="$(jq -r --arg path "$rel" '.files[] | select(.path == $path) | .size_bytes' "$manifest")"

    actual_sha="$(sha256_file "$payload_file")"
    actual_size="$(wc -c < "$payload_file" | tr -d '[:space:]')"

    [[ "$actual_sha" == "$expected_sha" ]] || fail "checksum mismatch for $rel"
    [[ "$actual_size" == "$expected_size" ]] || fail "size mismatch for $rel"
  done <<< "$paths"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "OK: recon bundle validated (dry-run bundle=$bundle_dir)"
    return 0
  fi

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    payload_file="$payload_root/$rel"
    mkdir -p "$(dirname "$ROOT/$rel")"
    if [[ -L "$ROOT/$rel" ]]; then
      fail "destination path is symlink: $rel"
    fi
    cp "$payload_file" "$ROOT/$rel"
  done <<< "$paths"

  echo "OK: recon bundle imported ($bundle_dir)"
}

run_export() {
  local slice=""
  local verify_run=""
  local bundle_id=""
  local out_root="$ROOT/artifacts/recon_bundles"
  local utc_stamp=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slice)
        [[ $# -ge 2 ]] || fail "--slice requires value"
        slice="$2"
        shift 2
        ;;
      --slice=*)
        slice="${1#*=}"
        shift
        ;;
      --verify-run)
        [[ $# -ge 2 ]] || fail "--verify-run requires value"
        verify_run="$2"
        shift 2
        ;;
      --verify-run=*)
        verify_run="${1#*=}"
        shift
        ;;
      --bundle-id)
        [[ $# -ge 2 ]] || fail "--bundle-id requires value"
        bundle_id="$2"
        shift 2
        ;;
      --bundle-id=*)
        bundle_id="${1#*=}"
        shift
        ;;
      --out-root)
        [[ $# -ge 2 ]] || fail "--out-root requires value"
        out_root="$2"
        shift 2
        ;;
      --out-root=*)
        out_root="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown export option: $1"
        ;;
    esac
  done

  [[ -n "$slice" ]] || fail "missing required --slice <S#>"
  [[ "$slice" =~ ^S[0-9]+$ ]] || fail "invalid --slice '$slice' (expected S<digits>)"

  if [[ -z "$bundle_id" ]]; then
    utc_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    bundle_id="recon_${slice}_${utc_stamp}"
  fi
  [[ "$bundle_id" != */* ]] || fail "bundle_id must not contain '/'"

  build_export_bundle "$slice" "$verify_run" "$bundle_id" "$out_root"
}

run_import() {
  local bundle_dir=""
  local allow_head_mismatch=0
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        [[ $# -ge 2 ]] || fail "--bundle requires value"
        bundle_dir="$2"
        shift 2
        ;;
      --bundle=*)
        bundle_dir="${1#*=}"
        shift
        ;;
      --allow-head-mismatch)
        allow_head_mismatch=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown import option: $1"
        ;;
    esac
  done

  [[ -n "$bundle_dir" ]] || fail "missing required --bundle <bundle_dir>"
  import_bundle_payload "$bundle_dir" "$allow_head_mismatch" "$dry_run"
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || {
    usage
    exit 2
  }
  shift || true

  need_cmd jq
  need_cmd git

  case "$cmd" in
    export) run_export "$@" ;;
    import) run_import "$@" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown command: $cmd"
      ;;
  esac
}

main "$@"
