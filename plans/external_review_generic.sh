#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  plans/external_review_generic.sh [PR_NUMBER|PR123|#123]
  plans/external_review_generic.sh --commit <sha|ref>
  plans/external_review_generic.sh --base <ref>
  plans/external_review_generic.sh --files "<paths>"
  plans/external_review_generic.sh

Behavior:
  PR token        Review the fetched PR head against the resolved PR base.
  --commit REF    Review one commit.
  --base REF      Review current branch diff vs base.
  --files LIST    Review selected files only.
  no args         Review the current tracked working-tree diff only.

Notes:
  - Runs codex, opus, kimi, and gemini generic reviews in parallel.
  - Writes dispatch_status.json and summary.md under:
      artifacts/story/<RUN_ID>/external_review_generic/
  - Exits 0 only when all four reviewers succeed and summary generation succeeds.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

find_python() {
  local candidate=""
  for candidate in python3 python; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi
    if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

sanitize_component() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_')"
  raw="$(printf '%s' "$raw" | sed -E 's/_+/_/g; s/^_+//; s/_+$//')"
  if [[ -z "$raw" ]]; then
    raw="value"
  fi
  printf '%s' "$raw"
}

generate_unique_suffix() {
  local temp_dir=""
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/external-review.XXXXXX")" || return 1
  basename "$temp_dir"
  rmdir "$temp_dir" >/dev/null 2>&1 || true
}

extract_json_field() {
  local json_path="$1"
  local field_name="$2"
  "$PYTHON_BIN" - "$json_path" "$field_name" <<'PY'
import json
import sys

path = sys.argv[1]
field = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(field, "")
if value is None:
    value = ""
print(value)
PY
}

ROOT="${EXTERNAL_REVIEW_ROOT:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not in a git repo"
fi

PARALLEL_SCRIPT="${EXTERNAL_REVIEW_PARALLEL_SCRIPT:-$ROOT/plans/parallel_review.sh}"
[[ -x "$PARALLEL_SCRIPT" ]] || fail "parallel review script not found: $PARALLEL_SCRIPT"

PYTHON_BIN="$(find_python)" || fail "python3 (or python 3) is required"

requested_target=""
mode=""
mode_value=""
positional_target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --commit)
      [[ -z "$mode" && -z "$positional_target" ]] || fail "only one target mode is allowed"
      mode="commit"
      mode_value="${2:?missing commit ref}"
      requested_target="--commit $mode_value"
      shift 2
      ;;
    --base)
      [[ -z "$mode" && -z "$positional_target" ]] || fail "only one target mode is allowed"
      mode="base"
      mode_value="${2:?missing base ref}"
      requested_target="--base $mode_value"
      shift 2
      ;;
    --files)
      [[ -z "$mode" && -z "$positional_target" ]] || fail "only one target mode is allowed"
      mode="files"
      mode_value="${2:?missing files list}"
      requested_target="--files $mode_value"
      shift 2
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      [[ -z "$mode" && -z "$positional_target" ]] || fail "only one target mode is allowed"
      positional_target="$1"
      requested_target="$1"
      shift
      ;;
  esac
done

pr_number=""
normalized_target=""
run_id_suffix=""
parallel_mode_args=()
parallel_cwd="$ROOT"
resolved_base_ref=""
resolved_head_oid=""
fetched_head_oid=""
pr_metadata_json=""
temp_ref=""
temp_worktree=""
dispatch_log=""
status_tsv=""
dispatch_status_json=""
summary_md=""
parallel_review_log=""
temp_worktree_created=false

cleanup() {
  if [[ "$temp_worktree_created" == "true" && -n "$temp_worktree" ]]; then
    git -C "$ROOT" worktree remove --force "$temp_worktree" >/dev/null 2>&1 || true
  fi
  if [[ -n "$temp_ref" ]]; then
    git -C "$ROOT" update-ref -d "$temp_ref" >/dev/null 2>&1 || true
  fi
  rm -f "${dispatch_log:-}" "${status_tsv:-}" "${pr_metadata_json:-}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ -n "$positional_target" ]]; then
  case "$positional_target" in
    PR[0-9]*)
      pr_number="${positional_target#PR}"
      ;;
    \#[0-9]*)
      pr_number="${positional_target#\#}"
      ;;
    [0-9]*)
      pr_number="$positional_target"
      ;;
    *)
      fail "unsupported target: $positional_target"
      ;;
  esac
  mode="pr"
fi

if [[ -z "$mode" ]]; then
  mode="uncommitted"
  requested_target="tracked working-tree diff"
fi

case "$mode" in
  pr)
    [[ -n "$pr_number" ]] || fail "missing PR number"
    normalized_target="PR #$pr_number"
    run_id_suffix="pr_$pr_number"

    pr_metadata_json="$(mktemp)"
    gh pr view "$pr_number" --json number,baseRefName,headRefOid > "$pr_metadata_json"
    resolved_base_ref="$(extract_json_field "$pr_metadata_json" "baseRefName")"
    resolved_head_oid="$(extract_json_field "$pr_metadata_json" "headRefOid")"
    [[ -n "$resolved_base_ref" ]] || fail "failed to resolve baseRefName for PR #$pr_number"
    [[ -n "$resolved_head_oid" ]] || fail "failed to resolve headRefOid for PR #$pr_number"

    unique_suffix="$(generate_unique_suffix)" || fail "failed to generate unique temp suffix"
    temp_ref="refs/tmp/external-review/pr-$pr_number-$unique_suffix"
    temp_worktree="$ROOT/.tmp/external-review/pr-$pr_number-$unique_suffix"
    mkdir -p "$(dirname "$temp_worktree")"

    git -C "$ROOT" fetch origin "$resolved_base_ref" "pull/$pr_number/head:$temp_ref"
    git -C "$ROOT" worktree add --detach "$temp_worktree" "$temp_ref"
    temp_worktree_created=true
    fetched_head_oid="$(git -C "$temp_worktree" rev-parse HEAD)"
    [[ "$fetched_head_oid" == "$resolved_head_oid" ]] || fail "fetched PR head OID does not match GitHub metadata"

    parallel_cwd="$temp_worktree"
    parallel_mode_args=(--base "origin/$resolved_base_ref")
    ;;
  commit)
    normalized_target="commit $mode_value"
    run_id_suffix="commit_$(sanitize_component "$mode_value")"
    parallel_mode_args=(--commit "$mode_value")
    ;;
  base)
    normalized_target="base $mode_value"
    run_id_suffix="base_$(sanitize_component "$mode_value")"
    parallel_mode_args=(--base "$mode_value")
    ;;
  files)
    normalized_target="files $mode_value"
    run_id_suffix="files_selected"
    parallel_mode_args=(--files "$mode_value")
    ;;
  uncommitted)
    normalized_target="tracked uncommitted diff"
    run_id_suffix="tracked_uncommitted"
    parallel_mode_args=(--uncommitted)
    ;;
  *)
    fail "unsupported mode: $mode"
    ;;
esac

timestamp_utc="${EXTERNAL_REVIEW_NOW_UTC:-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ -n "$timestamp_utc" ]] || fail "timestamp generation failed"

RUN_ID="external_review_generic_${timestamp_utc}_${run_id_suffix}"
RUN_ID="$(sanitize_component "$RUN_ID")"

review_dir="$ROOT/artifacts/story/$RUN_ID/external_review_generic"
mkdir -p "$review_dir"

dispatch_log="$(mktemp)"
status_tsv="$(mktemp)"
dispatch_status_json="$review_dir/dispatch_status.json"
summary_md="$review_dir/summary.md"
parallel_review_log="$review_dir/parallel_review.log"

parallel_cmd=("$PARALLEL_SCRIPT" "$RUN_ID" --tools codex,opus,kimi,gemini --prompt generic)
parallel_cmd+=("${parallel_mode_args[@]}")

set +e
(
  cd "$parallel_cwd"
  PARALLEL_REVIEW_REVIEW_SCRIPT="$ROOT/plans/review_logged.sh" \
  STORY_ARTIFACTS_ROOT="$ROOT/artifacts/story" \
  "${parallel_cmd[@]}"
) 2>&1 | tee "$dispatch_log"
parallel_rc="${PIPESTATUS[0]}"
set -e

cp "$dispatch_log" "$parallel_review_log"

if [[ "$parallel_cwd" != "$ROOT" ]]; then
  source_story_dir="$parallel_cwd/artifacts/story/$RUN_ID"
  dest_story_dir="$ROOT/artifacts/story/$RUN_ID"
  if [[ -d "$source_story_dir" ]]; then
    for artifact_dir in codex opus kimi gemini review_logs; do
      if [[ -e "$source_story_dir/$artifact_dir" ]]; then
        rm -rf "$dest_story_dir/$artifact_dir"
        cp -R "$source_story_dir/$artifact_dir" "$dest_story_dir/"
      fi
    done
  fi
fi

capture_error=0
for tool in codex opus kimi gemini; do
  line="$(grep -E "^\[(done|FAIL)\][[:space:]]+$tool[[:space:]]+exit=[0-9]+" "$dispatch_log" | tail -1 || true)"
  if [[ -z "$line" ]]; then
    printf '%s\tFAIL\t98\tmissing authoritative dispatch line\n' "$tool" >> "$status_tsv"
    capture_error=1
    continue
  fi

  if [[ "$line" == \[done\]* ]]; then
    status="OK"
  else
    status="FAIL"
  fi
  exit_code="$(printf '%s\n' "$line" | sed -E 's/.*exit=([0-9]+).*/\1/')"
  printf '%s\t%s\t%s\t\n' "$tool" "$status" "$exit_code" >> "$status_tsv"
done

set +e
"$PYTHON_BIN" - "$ROOT" "$RUN_ID" "$requested_target" "$normalized_target" "$mode" "$timestamp_utc" "$parallel_rc" "$status_tsv" "$dispatch_status_json" "$summary_md" "$resolved_base_ref" "$resolved_head_oid" "$capture_error" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
run_id = sys.argv[2]
requested_target = sys.argv[3]
normalized_target = sys.argv[4]
mode = sys.argv[5]
timestamp_utc = sys.argv[6]
parallel_rc = int(sys.argv[7])
status_tsv = Path(sys.argv[8])
dispatch_status_json = Path(sys.argv[9])
summary_md = Path(sys.argv[10])
resolved_base_ref = sys.argv[11]
resolved_head_oid = sys.argv[12]
capture_error = int(sys.argv[13])

story_dir = root / "artifacts" / "story" / run_id
review_dir = story_dir / "external_review_generic"
review_dir.mkdir(parents=True, exist_ok=True)

severity_rank = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}

def parse_counts(text: str):
    match = re.search(r"FINDINGS_SUMMARY:\s*P0=(\d+)\s+P1=(\d+)\s+P2=(\d+)", text)
    if not match:
        return None
    return {
        "P0": int(match.group(1)),
        "P1": int(match.group(2)),
        "P2": int(match.group(3)),
    }

def extract_findings(tool: str, text: str):
    findings = []
    lines = text.splitlines()
    for idx, line in enumerate(lines):
      severity = None
      stripped = line.strip()
      bullet = re.search(r"\[(P[0-3])\]", stripped)
      heading = re.search(r"\b(P[0-3])(?:[-: ]|$)", stripped) if stripped.startswith("#") else None
      plain = re.match(r"^(P[0-3])[-: ]", stripped)
      if bullet:
          severity = bullet.group(1)
      elif heading:
          severity = heading.group(1)
      elif plain:
          severity = plain.group(1)
      if not severity:
          continue

      citation = ""
      for look_ahead in range(idx, min(idx + 4, len(lines))):
          citation_match = re.search(r"([A-Za-z0-9_./:-]+\.[A-Za-z0-9_]+:\d+)", lines[look_ahead])
          if citation_match:
              citation = citation_match.group(1)
              break

      findings.append({
          "severity": severity,
          "tool": tool,
          "text": stripped,
          "citation": citation,
      })
    findings.sort(key=lambda item: (severity_rank.get(item["severity"], 9), item["tool"], item["text"]))
    return findings[:3]

entries = []
with status_tsv.open("r", encoding="utf-8") as handle:
    for raw in handle:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        parts = raw.split("\t")
        while len(parts) < 4:
            parts.append("")
        tool, dispatch_status, exit_code_text, note = parts[:4]
        try:
            exit_code = int(exit_code_text)
        except ValueError:
            exit_code = 98
        entries.append({
            "tool": tool,
            "dispatch_status": dispatch_status,
            "exit_code": exit_code,
            "note": note,
        })

summary_entries = []
merged_findings = []
failure_lines = []
blocking_total = 0
inconsistent = False

for entry in entries:
    tool = entry["tool"]
    exit_code = entry["exit_code"]
    artifact = story_dir / tool / f"{tool}.generic.md"
    review_log = story_dir / "review_logs" / f"{tool}.log"

    display_status = "OK"
    counts_text = "unavailable"
    note = entry["note"]
    counts = None

    if exit_code != 0:
        display_status = "FAIL"
        if review_log.exists():
            note = str(review_log.relative_to(root))
        elif not note:
            note = "review failed"
    else:
        if not artifact.exists():
            display_status = "FAIL"
            note = "missing canonical artifact"
            inconsistent = True
        else:
            text = artifact.read_text(encoding="utf-8")
            counts = parse_counts(text)
            if counts is None:
                display_status = "FAIL"
                note = "missing FINDINGS_SUMMARY"
                inconsistent = True
            else:
                counts_text = f'P0={counts["P0"]} P1={counts["P1"]} P2={counts["P2"]}'
                blocking_total += counts["P0"] + counts["P1"]
                merged_findings.extend(extract_findings(tool, text))

    if display_status == "FAIL":
        if not note:
            note = "unknown failure"
        failure_lines.append(f"- {tool}: {note}")

    summary_entries.append({
        "tool": tool,
        "dispatch_status": entry["dispatch_status"],
        "display_status": display_status,
        "exit_code": exit_code,
        "counts_text": counts_text,
        "note": note,
        "artifact": str(artifact.relative_to(root)),
    })

dispatch_payload = {
    "schema_version": 1,
    "tool": "external_review_generic.sh",
    "run_id": run_id,
    "requested_target": requested_target,
    "normalized_target": normalized_target,
    "mode": mode,
    "timestamp_utc": timestamp_utc,
    "parallel_review_exit": parallel_rc,
    "resolved_base_ref": resolved_base_ref,
    "resolved_head_oid": resolved_head_oid,
    "capture_error": bool(capture_error),
    "tools": [
        {
            "tool": item["tool"],
            "dispatch_status": item["dispatch_status"],
            "exit_code": item["exit_code"],
            "note": item["note"],
        }
        for item in entries
    ],
}
dispatch_status_json.write_text(json.dumps(dispatch_payload, indent=2) + "\n", encoding="utf-8")

merged_findings.sort(key=lambda item: (severity_rank.get(item["severity"], 9), item["tool"], item["text"]))

summary_lines = [
    "# External Review Generic Summary",
    "",
    "## Target reviewed",
    f"- Requested: {requested_target}",
    f"- Normalized: {normalized_target}",
    f"- Run ID: {run_id}",
]
if resolved_base_ref:
    summary_lines.append(f"- Resolved base ref: origin/{resolved_base_ref}")
if resolved_head_oid:
    summary_lines.append(f"- Resolved PR head OID: {resolved_head_oid}")

summary_lines.extend([
    "",
    "## Per-tool status",
])
for item in summary_entries:
    summary_lines.append(f'- {item["tool"]} | {item["display_status"]} | exit={item["exit_code"]}')

summary_lines.extend([
    "",
    "## Per-tool findings",
])
for item in summary_entries:
    summary_lines.append(f'- {item["tool"]} | {item["counts_text"]}')

summary_lines.extend([
    "",
    "## Short merged findings",
])
if merged_findings:
    for finding in merged_findings[:8]:
        suffix = f' | {finding["citation"]}' if finding["citation"] else ""
        summary_lines.append(f'- {finding["severity"]} | {finding["tool"]} | {finding["text"]}{suffix}')
else:
    summary_lines.append("- none")

summary_lines.extend([
    "",
    "## Failures and inconsistencies",
])
if failure_lines:
    summary_lines.extend(failure_lines)
else:
    summary_lines.append("- none")

summary_lines.extend([
    "",
    "## Totals",
    f"- Blocking findings from successful reviewers only: {blocking_total}",
])

summary_md.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

if capture_error or inconsistent:
    raise SystemExit(11)
PY
summary_rc=$?
set -e

tool_status_pairs=()
blocking_total=0
for tool in codex opus kimi gemini; do
  line="$(grep -F -- "- $tool | " "$summary_md" | head -1 || true)"
  if [[ -n "$line" ]]; then
    tool_status_pairs+=("${line#- }")
  fi
done
blocking_line="$(grep -F "Blocking findings from successful reviewers only:" "$summary_md" || true)"
if [[ -n "$blocking_line" ]]; then
  blocking_total="${blocking_line##*: }"
fi

echo "requested target: $requested_target"
echo "normalized run id: $RUN_ID"
for pair in "${tool_status_pairs[@]}"; do
  echo "tool status: $pair"
done
echo "blocking findings (P0 + P1 from successful reviewers only): $blocking_total"
echo "summary artifact: ${summary_md#$ROOT/}"

if [[ "$parallel_rc" -ne 0 || "$capture_error" -ne 0 || "$summary_rc" -ne 0 ]]; then
  exit 1
fi

exit 0
