#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/codex_review_digest.sh <raw_review_file> [--out <path>]

Reads a raw Codex review artifact and writes a concise digest that includes:
  - Story / HEAD metadata (if present)
  - Severity findings lines matching - [P0]/[P1]/[P2]
  - Final Codex message (last non-empty block)

Default output path:
  <raw_review_file with _review.md replaced by _digest.md>
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

raw_file="${1:-}"
[[ -n "$raw_file" ]] || { usage >&2; exit 2; }
shift

out_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out_file="${2:?missing path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [[ "$raw_file" != /* ]]; then
  raw_file="$repo_root/$raw_file"
fi
[[ -f "$raw_file" ]] || die "raw review file not found: $raw_file"

if [[ -z "$out_file" ]]; then
  if [[ "$raw_file" == *_review.md ]]; then
    out_file="${raw_file%_review.md}_digest.md"
  else
    out_file="${raw_file}.digest.md"
  fi
elif [[ "$out_file" != /* ]]; then
  out_file="$repo_root/$out_file"
fi

mkdir -p "$(dirname "$out_file")"

story="$(sed -n 's/^- Story:[[:space:]]*//p' "$raw_file" | head -n 1 || true)"
head_sha="$(sed -n 's/^- HEAD:[[:space:]]*//p' "$raw_file" | head -n 1 || true)"
timestamp="$(sed -n 's/^- Timestamp (UTC):[[:space:]]*//p' "$raw_file" | head -n 1 || true)"

body="$(
  awk '
    /^---[[:space:]]*$/ {seen_sep=1; next}
    {if (seen_sep) print}
  ' "$raw_file"
)"
if [[ -z "$body" ]]; then
  body="$(cat "$raw_file")"
fi

severity_lines="$(printf '%s\n' "$body" | grep -E '^[[:space:]]*-[[:space:]]*\[P[0-2]\]' || true)"

final_block="$(
  printf '%s\n' "$body" | awk '
    NF {
      if (buf == "") {
        buf = $0
      } else {
        buf = buf ORS $0
      }
      next
    }
    {
      if (buf != "") {
        last = buf
        buf = ""
      }
    }
    END {
      if (buf != "") {
        last = buf
      }
      print last
    }
  '
)"

digest_ts="$(date -u +%Y%m%dT%H%M%SZ)"

{
  echo "# Codex Review Digest"
  echo
  echo "- Source review file: $raw_file"
  echo "- Story: ${story:-<unknown>}"
  echo "- HEAD: ${head_sha:-<unknown>}"
  echo "- Source timestamp (UTC): ${timestamp:-<unknown>}"
  echo "- Digest generated (UTC): $digest_ts"
  echo
  echo "## Severity Findings (P0/P1/P2)"
  if [[ -n "$severity_lines" ]]; then
    printf '%s\n' "$severity_lines"
  else
    echo "- none"
  fi
  echo
  echo "## Final Codex Message"
  if [[ -n "$final_block" ]]; then
    echo "$final_block"
  else
    echo "- none extracted"
  fi
} > "$out_file"

echo "Saved Codex review digest: $out_file"
