#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

START_DIR="$(pwd)"
ROOT=""
CONTRACT_FILE="specs/CONTRACT.md"
PRD_FILE="plans/prd.json"
BASE_REF="${VERIFY_BASE_REF:-origin/main}"

usage() {
  cat <<'EOF'
Usage: plans/check_contract_at_wording_drift.sh [--contract PATH] [--prd PATH] [--base-ref REF]

Fail closed when CONTRACT.md changes the wording of an AT block that is still
quoted in plans/prd.json contract_must_evidence entries anchored to that AT.
EOF
}

setup_fail() {
  echo "ERROR[contract_at_wording_drift]: $*" >&2
  exit 2
}

fail() {
  echo "FAIL[contract_at_wording_drift]: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract)
      [[ $# -ge 2 ]] || setup_fail "--contract requires a value"
      CONTRACT_FILE="$2"
      shift 2
      ;;
    --prd)
      [[ $# -ge 2 ]] || setup_fail "--prd requires a value"
      PRD_FILE="$2"
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
if ! git -C "$START_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  setup_fail "must run inside a git worktree"
fi
if ! command -v python3 >/dev/null 2>&1; then
  setup_fail "python3 is required"
fi

ROOT="$(git -C "$START_DIR" rev-parse --show-toplevel)"
cd "$ROOT"

if [[ "$CONTRACT_FILE" == /* ]]; then
  contract_abs="$CONTRACT_FILE"
else
  contract_abs="$ROOT/$CONTRACT_FILE"
fi
[[ -f "$contract_abs" ]] || setup_fail "contract file not found: $CONTRACT_FILE"

if [[ "$PRD_FILE" == /* ]]; then
  prd_abs="$PRD_FILE"
else
  prd_abs="$ROOT/$PRD_FILE"
fi
[[ -f "$prd_abs" ]] || setup_fail "PRD file not found: $PRD_FILE"

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

  return 1
}

base_commit="$(resolve_base_commit "$BASE_REF")" || setup_fail "unable to resolve merge-base from base ref '$BASE_REF'"
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
  echo "PASS[contract_at_wording_drift]: contract unchanged (base=$base_commit, ref=$BASE_REF)"
  exit 0
fi

tmp_base_contract="$(mktemp)"
trap 'rm -f "$tmp_base_contract"' EXIT
if ! git show "${base_commit}:${contract_rel}" > "$tmp_base_contract" 2>/dev/null; then
  : > "$tmp_base_contract"
fi

python3 - "$contract_abs" "$tmp_base_contract" "$prd_abs" "$base_commit" "$BASE_REF" <<'PY'
import json
import re
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
base_contract_path = Path(sys.argv[2])
prd_path = Path(sys.argv[3])
base_commit = sys.argv[4]
base_ref = sys.argv[5]

AT_RE = re.compile(r"^(AT-\d+)\b")
HEADING_RE = re.compile(r"^#{1,6}\s+")


def normalize(text: str) -> str:
    s = text.strip()
    if not s:
        return ""
    s = s.replace("§", "")
    s = s.replace("\\", "")
    s = s.replace("`", "")
    s = s.replace("*", "")
    s = s.replace("_", "")
    s = re.sub(r"[–—]", "-", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip().lower()


def parse_at_blocks(text: str):
    blocks = {}
    current_at = None
    current_lines = []

    def flush() -> None:
        nonlocal current_at, current_lines
        if current_at is not None:
            blocks[current_at] = "\n".join(current_lines).strip()
        current_at = None
        current_lines = []

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        at_match = AT_RE.match(stripped)
        if at_match:
            flush()
            current_at = at_match.group(1)
            current_lines = [raw_line]
            continue

        if current_at is not None and HEADING_RE.match(stripped):
            flush()
            continue

        if current_at is not None:
            current_lines.append(raw_line)

    flush()
    return blocks


current_contract = contract_path.read_text(encoding="utf-8")
base_contract = base_contract_path.read_text(encoding="utf-8")
prd = json.loads(prd_path.read_text(encoding="utf-8"))

items = prd.get("items", [])
if not isinstance(items, list):
    print("ERROR[contract_at_wording_drift]: PRD items must be an array", file=sys.stderr)
    raise SystemExit(2)

current_blocks = parse_at_blocks(current_contract)
base_blocks = parse_at_blocks(base_contract)

changed_ats = sorted(
    at
    for at in set(current_blocks) | set(base_blocks)
    if normalize(current_blocks.get(at, "")) != normalize(base_blocks.get(at, ""))
)

if not changed_ats:
    print(
        f"PASS[contract_at_wording_drift]: contract changed but no AT block wording drift detected (base={base_commit}, ref={base_ref})"
    )
    raise SystemExit(0)

issues = []
checked = 0

for item in items:
    item_id = str(item.get("id", "unknown"))
    entries = item.get("contract_must_evidence", []) or []
    if not isinstance(entries, list):
        print(
            f"ERROR[contract_at_wording_drift]: contract_must_evidence must be an array for {item_id}",
            file=sys.stderr,
        )
        raise SystemExit(2)

    for entry in entries:
        if not isinstance(entry, dict):
            print(
                f"ERROR[contract_at_wording_drift]: contract_must_evidence entries must be objects for {item_id}",
                file=sys.stderr,
            )
            raise SystemExit(2)
        anchor = str(entry.get("anchor", "")).strip()
        quote = str(entry.get("quote", "")).strip()
        if not anchor or not quote:
            continue
        if not AT_RE.match(anchor):
            continue
        if anchor not in changed_ats:
            continue
        checked += 1
        current_block = current_blocks.get(anchor, "")
        if not current_block:
            issues.append((item_id, anchor, "anchor missing from current CONTRACT.md", quote))
            continue
        if normalize(quote) not in normalize(current_block):
            issues.append((item_id, anchor, "quote no longer matches current CONTRACT.md wording", quote))

if issues:
    for item_id, anchor, reason, quote in issues:
        print(
            f"FAIL[contract_at_wording_drift]: {item_id} quote for {anchor} {reason}: {quote}",
            file=sys.stderr,
        )
    raise SystemExit(1)

if checked == 0:
    changed_label = ", ".join(changed_ats)
    print(
        f"PASS[contract_at_wording_drift]: changed AT blocks ({changed_label}) have no quote-backed PRD anchors to validate"
    )
    raise SystemExit(0)

changed_label = ", ".join(changed_ats)
print(
    f"PASS[contract_at_wording_drift]: validated {checked} quote-backed PRD AT reference(s) across changed blocks ({changed_label})"
)
PY
