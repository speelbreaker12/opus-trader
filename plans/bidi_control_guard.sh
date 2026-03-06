#!/usr/bin/env bash
set -euo pipefail

# Fail if any bidirectional control characters exist in repository text files.
# This mitigates Trojan Source class risks in reviews and diffs.

ROOT_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${BIDI_CONTROL_GUARD_ROOT:-$ROOT_DEFAULT}"
cd "$ROOT"

BIDI_REGEX='[\x{061C}\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]'

# Fast path: ripgrep with PCRE2 handles UTF-8 safely and skips binaries.
if command -v rg >/dev/null 2>&1; then
  set +e
  rg_hits="$(
    rg -n --no-heading --color=never -P "$BIDI_REGEX" \
      --hidden \
      --glob '!.git/**' \
      --glob '!target/**' \
      . 2>/dev/null
  )"
  rg_rc=$?
  set -e

  case "$rg_rc" in
    0)
      echo "FAIL: bidirectional control characters detected" >&2
      echo "  Forbidden code points: U+061C U+200E U+200F U+202A..U+202E U+2066..U+2069" >&2
      printf '%s\n' "$rg_hits" \
        | awk -F: 'NF >= 2 { print "  " $1 ":" $2 }' \
        | LC_ALL=C sort -u >&2
      exit 1
      ;;
    1)
      echo "bidi_control_guard: PASS"
      exit 0
      ;;
    *)
      echo "WARN: rg -P scanner unavailable (rc=$rg_rc); falling back to perl scanner" >&2
      ;;
  esac
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "FAIL: perl is required when rg -P is unavailable" >&2
  exit 1
fi

tmp_files="$(mktemp)"
tmp_hits="$(mktemp)"
trap 'rm -f "$tmp_files" "$tmp_hits"' EXIT

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -z --cached --others --exclude-standard > "$tmp_files"
else
  find . -type f \
    -not -path './.git/*' \
    -not -path './target/*' \
    -print0 > "$tmp_files"
fi

if [[ ! -s "$tmp_files" ]]; then
  echo "bidi_control_guard: no files to scan — PASS"
  exit 0
fi

match_count=0
while IFS= read -r -d '' relpath; do
  relpath="${relpath#./}"
  [[ -f "$relpath" ]] || continue

  # Skip binary files (NUL-byte heuristic).
  if perl -ne 'if (index($_, "\0") >= 0) { exit 0 } END { exit 1 }' \
    "$relpath" >/dev/null 2>&1; then
    continue
  fi

  # Skip non-text files that grep cannot classify as text.
  if ! LC_ALL=C grep -Iq . "$relpath" 2>/dev/null; then
    continue
  fi

  set +e
  line_hits="$(
    perl -CSDA -ne '
      if (/'"$BIDI_REGEX"'/) {
        print "$.\n";
        $found = 1;
      }
      END { exit($found ? 0 : 1); }
    ' "$relpath" 2>/dev/null
  )"
  perl_rc=$?
  set -e

  case "$perl_rc" in
    0)
      while IFS= read -r line_no; do
        [[ -n "$line_no" ]] || continue
        printf '%s:%s\n' "$relpath" "$line_no" >> "$tmp_hits"
        match_count=$((match_count + 1))
      done <<< "$line_hits"
      ;;
    1)
      ;;
    *)
      echo "FAIL: scanner error while reading $relpath (perl rc=$perl_rc)" >&2
      exit 1
      ;;
  esac
done < "$tmp_files"

if [[ "$match_count" -gt 0 ]]; then
  echo "FAIL: bidirectional control characters detected ($match_count occurrence(s))" >&2
  echo "  Forbidden code points: U+061C U+200E U+200F U+202A..U+202E U+2066..U+2069" >&2
  sed 's/^/  /' "$tmp_hits" >&2
  exit 1
fi

echo "bidi_control_guard: PASS"
