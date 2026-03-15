#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${LINT_SOLDIER_INFRA_FACADE_LIB:-$ROOT/crates/soldier_infra/src/lib.rs}"
API="${LINT_SOLDIER_INFRA_FACADE_API:-$ROOT/crates/soldier_infra/src/api.rs}"
ALLOWLIST="${LINT_SOLDIER_INFRA_FACADE_ALLOWLIST:-$ROOT/plans/soldier_infra_facade_symbols.txt}"
SCAN_ROOT="${LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT:-$ROOT}"

cleanup_tmp() {
  [[ -n "${tmp_expected:-}" && -f "${tmp_expected:-}" ]] && rm -f "$tmp_expected"
  [[ -n "${tmp_actual:-}" && -f "${tmp_actual:-}" ]] && rm -f "$tmp_actual"
}
trap cleanup_tmp EXIT

[[ -f "$LIB" ]] || { echo "FAIL: missing soldier_infra lib file: $LIB"; exit 1; }
[[ -f "$API" ]] || { echo "FAIL: missing soldier_infra api file: $API"; exit 1; }
[[ -f "$ALLOWLIST" ]] || { echo "FAIL: missing soldier_infra facade allowlist: $ALLOWLIST"; exit 1; }

if rg -q '^\s*pub(\s*\([^)]*\))?\s+mod\s+api\s*;' "$LIB"; then
  echo "FAIL: soldier_infra/lib.rs must not expose 'pub mod api;'"
  exit 1
fi

api_private_mod_count="$(rg -c '^\s*mod\s+api\s*;' "$LIB" || true)"
if [[ "$api_private_mod_count" -ne 1 ]]; then
  echo "FAIL: soldier_infra/lib.rs must contain exactly one private 'mod api;' line, found $api_private_mod_count"
  exit 1
fi

if ! rg -q '^\s*pub\s+use\s+api::\*\s*;' "$LIB"; then
  echo "FAIL: missing facade re-export line in soldier_infra/lib.rs: pub use api::*;"
  exit 1
fi

pub_use_count="$(rg -c '^\s*pub\s+use\s+' "$LIB" || true)"
if [[ "$pub_use_count" -ne 1 ]]; then
  echo "FAIL: soldier_infra/lib.rs must contain exactly one public re-export line, found $pub_use_count"
  exit 1
fi

extract_allowlist_symbols() {
  grep -Ev '^[[:space:]]*(#|$)' "$ALLOWLIST" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | LC_ALL=C sort -u
}

extract_api_export_symbols() {
  python3 - "$API" <<'PY'
import collections
import pathlib
import re
import sys

api_path = pathlib.Path(sys.argv[1])
text = api_path.read_text(encoding="utf-8")
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"//.*", "", text)
stmt_re = re.compile(r'^\s*pub\s+use\b.*?;', re.M | re.S)
symbols = []

for match in stmt_re.finditer(text):
    rhs = match.group(0)
    rhs = re.sub(r'^\s*pub\s+use\s+', '', rhs).rstrip(';').strip()
    if '{' in rhs:
        inside = rhs.split('{', 1)[1].rsplit('}', 1)[0]
        items = [item.strip() for item in inside.split(',') if item.strip()]
        for item in items:
            if ' as ' in item:
                symbols.append(item.split(' as ', 1)[1].strip())
            else:
                symbols.append(item.rsplit('::', 1)[-1])
    else:
        leaf = rhs.rsplit('::', 1)[-1]
        if ' as ' in leaf:
            leaf = leaf.split(' as ', 1)[1].strip()
        symbols.append(leaf)

dupes = sorted(sym for sym, count in collections.Counter(symbols).items() if count > 1)
if dupes:
    print("FAIL: duplicate re-export symbols in soldier_infra/api.rs:", file=sys.stderr)
    for sym in dupes:
        print(f"  {sym}", file=sys.stderr)
    sys.exit(2)

for sym in sorted(set(symbols)):
    print(sym)
PY
}

tmp_expected="$(mktemp)"
tmp_actual="$(mktemp)"
extract_allowlist_symbols > "$tmp_expected"
extract_api_export_symbols > "$tmp_actual"

allowlist_total="$(grep -cEv '^[[:space:]]*(#|$)' "$ALLOWLIST" || true)"
allowlist_unique="$(wc -l < "$tmp_expected" | tr -d '[:space:]')"
if [[ "$allowlist_total" -ne "$allowlist_unique" ]]; then
  echo "FAIL: duplicate symbols found in soldier_infra facade allowlist: $ALLOWLIST"
  exit 1
fi

missing_symbols="$(comm -23 "$tmp_expected" "$tmp_actual" || true)"
extra_symbols="$(comm -13 "$tmp_expected" "$tmp_actual" || true)"

if [[ -n "$missing_symbols" ]]; then
  echo "FAIL: allowlisted exports missing from soldier_infra/api.rs:"
  echo "$missing_symbols"
  exit 1
fi
if [[ -n "$extra_symbols" ]]; then
  echo "FAIL: non-allowlisted exports present in soldier_infra/api.rs:"
  echo "$extra_symbols"
  exit 1
fi

if rg -q '^\s*(pub(\s*\([^)]*\))?\s+)?fn\s+[A-Za-z_][A-Za-z0-9_]*' "$API"; then
  echo "FAIL: soldier_infra/api.rs contains function definitions; facade file must be re-exports only."
  exit 1
fi

if [[ -d "$SCAN_ROOT" ]]; then
  deep_import_violations="$(python3 - "$SCAN_ROOT" <<'PY'
import pathlib
import re
import sys

scan_root = pathlib.Path(sys.argv[1]).resolve()
stmt_re = re.compile(r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?use\b.*?;', re.M | re.S)
deep_re = re.compile(r'\bsoldier_infra::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*')
deep_grouped_re = re.compile(r'\bsoldier_infra::\{[^;]*\b[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*')

for path in sorted(scan_root.rglob("*.rs")):
    rel = path.relative_to(scan_root).as_posix()
    if rel.startswith("crates/soldier_infra/src/"):
        continue
    text = path.read_text(encoding="utf-8")
    for match in stmt_re.finditer(text):
        statement = " ".join(match.group(0).split())
        if deep_re.search(statement) or deep_grouped_re.search(statement):
            line = text.count("\n", 0, match.start()) + 1
            print(f"{rel}:{line}: {statement}")
PY
    )"
  if [[ -n "$deep_import_violations" ]]; then
    echo "FAIL: deep soldier_infra imports are forbidden outside crates/soldier_infra/src."
    echo "$deep_import_violations"
    exit 1
  fi
fi

echo "✓ soldier_infra facade lint passed"
