#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONTRACT_FILE="specs/CONTRACT.md"
BASE_REF="${CONTRACT_LEDGER_BASE_REF:-${VERIFY_BASE_REF:-origin/main}}"
LEDGER_HEADING="## **Appendix CONTRACT_CHANGE_LEDGER (Normative, Mandatory)**"

usage() {
  cat <<'EOF'
Usage: plans/check_contract_change_ledger.sh [--contract PATH] [--base-ref REF]

Checks that when CONTRACT.md changes, the contract-change ledger table gains
at least one new row (fail-closed).
EOF
}

setup_fail() {
  echo "ERROR[contract_change_ledger]: $*" >&2
  exit 2
}

fail() {
  echo "FAIL[contract_change_ledger]: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract)
      [[ $# -ge 2 ]] || setup_fail "--contract requires a value"
      CONTRACT_FILE="$2"
      shift 2
      ;;
    --base-ref)
      [[ $# -ge 2 ]] || setup_fail "--base-ref requires a value"
      BASE_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      setup_fail "unknown argument: $1"
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  setup_fail "git is required"
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  setup_fail "must run inside a git worktree"
fi

if [[ "$CONTRACT_FILE" == /* ]]; then
  contract_abs="$CONTRACT_FILE"
else
  contract_abs="$ROOT/$CONTRACT_FILE"
fi
[[ -f "$contract_abs" ]] || setup_fail "contract file not found: $CONTRACT_FILE"

contract_rel="${contract_abs#$ROOT/}"
if [[ "$contract_rel" == "$contract_abs" ]]; then
  setup_fail "contract path must be inside repo root: $contract_abs"
fi

resolve_base_commit() {
  local base_ref="$1"
  local merge_base=""

  if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    merge_base="$(git merge-base "$base_ref" HEAD 2>/dev/null || true)"
    if [[ -n "$merge_base" ]]; then
      echo "$merge_base"
      return 0
    fi
  fi

  if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    echo "HEAD~1"
    return 0
  fi

  return 1
}

base_commit="$(resolve_base_commit "$BASE_REF")" || setup_fail "unable to resolve base commit from '$BASE_REF' or HEAD~1"
if ! git rev-parse --verify "$base_commit" >/dev/null 2>&1; then
  setup_fail "resolved base commit is invalid: $base_commit"
fi

changed_paths="$(
  {
    git diff --name-only "$base_commit"...HEAD 2>/dev/null || true
    git diff --name-only --cached 2>/dev/null || true
    git diff --name-only 2>/dev/null || true
  } | sed '/^$/d' | LC_ALL=C sort -u
)"

if ! printf '%s\n' "$changed_paths" | grep -Fxq "$contract_rel"; then
  echo "PASS[contract_change_ledger]: contract unchanged (base=$base_commit, ref=$BASE_REF)"
  exit 0
fi

row_count_lenient() {
  local file="$1"
  awk -v heading="$LEDGER_HEADING" '
    BEGIN {
      in_section = 0
      rows = 0
    }
    $0 == heading {
      in_section = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    !in_section {
      next
    }
    $0 ~ /^\|/ {
      compact = $0
      gsub(/[[:space:]]/, "", compact)
      lower = tolower($0)
      if (lower ~ /\|[[:space:]]*date_utc[[:space:]]*\|/) {
        next
      }
      if (compact ~ /^\|[-:|]+\|$/) {
        next
      }
      rows++
    }
    END {
      print rows
    }
  ' "$file"
}

validate_and_count_strict() {
  local file="$1"
  awk -v heading="$LEDGER_HEADING" '
    function trim(s) {
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      return s
    }
    BEGIN {
      in_section = 0
      saw_heading = 0
      saw_header = 0
      rows = 0
      invalid = 0
    }
    $0 == heading {
      in_section = 1
      saw_heading = 1
      next
    }
    in_section && /^## / {
      in_section = 0
    }
    !in_section {
      next
    }
    $0 ~ /^\|/ {
      lower = tolower($0)
      compact = $0
      gsub(/[[:space:]]/, "", compact)
      if (lower ~ /\|[[:space:]]*date_utc[[:space:]]*\|[[:space:]]*change_id[[:space:]]*\|[[:space:]]*sections_touched[[:space:]]*\|[[:space:]]*change_type[[:space:]]*\|[[:space:]]*summary[[:space:]]*\|[[:space:]]*rationale[[:space:]]*\|[[:space:]]*at\/vr refs[[:space:]]*\|[[:space:]]*story\/pr[[:space:]]*\|/) {
        saw_header = 1
        next
      }
      if (compact ~ /^\|[-:|]+\|$/) {
        next
      }
      rows++
      n = split($0, cols, "|")
      if (n != 10) {
        print "malformed ledger row (expected 8 columns): " $0 > "/dev/stderr"
        invalid = 1
        next
      }
      date_utc = ""
      for (i = 2; i <= 9; i++) {
        cell = trim(cols[i])
        if (i == 2) {
          date_utc = cell
        }
        if (cell == "") {
          print "empty ledger field in row: " $0 > "/dev/stderr"
          invalid = 1
        }
      }
      if (date_utc !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
        print "invalid date_utc (expected YYYY-MM-DD): " date_utc > "/dev/stderr"
        invalid = 1
      }
    }
    END {
      if (!saw_heading) {
        print "missing ledger appendix heading: " heading > "/dev/stderr"
        exit 41
      }
      if (!saw_header) {
        print "missing ledger table header row" > "/dev/stderr"
        exit 42
      }
      if (rows == 0) {
        print "missing ledger data rows" > "/dev/stderr"
        exit 43
      }
      if (invalid) {
        exit 44
      }
      print rows
    }
  ' "$file"
}

tmp_base="$(mktemp)"
trap 'rm -f "$tmp_base" "$tmp_base.err"' EXIT
if ! git show "${base_commit}:${contract_rel}" > "$tmp_base" 2>/dev/null; then
  : > "$tmp_base"
fi

base_rows="$(row_count_lenient "$tmp_base")"
[[ "$base_rows" =~ ^[0-9]+$ ]] || setup_fail "internal error: invalid base row count '$base_rows'"

set +e
current_rows="$(validate_and_count_strict "$contract_abs" 2> "$tmp_base.err")"
validate_rc=$?
set -e
if [[ "$validate_rc" -ne 0 ]]; then
  cat "$tmp_base.err" >&2 || true
  fail "contract changed but ledger section is invalid"
fi
[[ "$current_rows" =~ ^[0-9]+$ ]] || setup_fail "internal error: invalid current row count '$current_rows'"

if (( current_rows <= base_rows )); then
  fail "contract changed but no new ledger row detected (base_rows=$base_rows current_rows=$current_rows)"
fi

echo "PASS[contract_change_ledger]: new ledger row detected (base_rows=$base_rows current_rows=$current_rows base=$base_commit ref=$BASE_REF)"
