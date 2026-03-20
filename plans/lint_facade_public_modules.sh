#!/usr/bin/env bash
set -euo pipefail

ROOT="${LINT_FACADE_PUBLIC_MODULES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE_LIB="$ROOT/crates/soldier_core/src/lib.rs"
INFRA_LIB="$ROOT/crates/soldier_infra/src/lib.rs"

required_core_facades=(
  execution
  idempotency
  recovery
  risk
  status_codes
  venue
)

[[ -f "$CORE_LIB" ]] || {
  echo "FAIL: missing soldier_core lib file: $CORE_LIB"
  exit 1
}

[[ -f "$INFRA_LIB" ]] || {
  echo "FAIL: missing soldier_infra lib file: $INFRA_LIB"
  exit 1
}

cd "$ROOT"

collect_pub_mods() {
  python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
targets = [
    root / "crates" / "soldier_core" / "src",
    root / "crates" / "soldier_infra" / "src",
]
pattern = re.compile(
    r'(?m)^(?P<indent>\s*)(?P<attrs>(?:#\[[^\n]*\]\s*)*)pub\s+mod\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<term>;|\{)'
)

for target in targets:
    for path in sorted(target.rglob("*.rs")):
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            snippet = " ".join(match.group(0).split())
            name = match.group("name")
            print(f"{rel}\t{line}\t{name}\t{snippet}")
PY
}

pub_mod_rows="$(collect_pub_mods)"

missing_required=""
duplicate_required=""
for facade in "${required_core_facades[@]}"; do
  count="$(printf '%s\n' "$pub_mod_rows" | awk -F '\t' -v name="$facade" '$1 == "crates/soldier_core/src/lib.rs" && $3 == name && $4 == ("pub mod " name ";") { count++ } END { print count + 0 }')"
  if [[ "$count" -eq 0 ]]; then
    missing_required+="crates/soldier_core/src/lib.rs: pub mod ${facade};\n"
  elif [[ "$count" -gt 1 ]]; then
    duplicate_required+="crates/soldier_core/src/lib.rs: pub mod ${facade}; (count=$count)\n"
  fi
done

if [[ -n "$missing_required" ]]; then
  echo "Missing required public facade modules:"
  printf '%b' "$missing_required"
  exit 1
fi

if [[ -n "$duplicate_required" ]]; then
  echo "Duplicate required public facade modules found:"
  printf '%b' "$duplicate_required"
  exit 1
fi

unexpected_pub_mods="$(printf '%s\n' "$pub_mod_rows" | awk -F '\t' '
  $1 == "crates/soldier_core/src/lib.rs" && $4 == ("pub mod " $3 ";") &&
  ($3 == "execution" || $3 == "idempotency" || $3 == "recovery" || $3 == "risk" || $3 == "status_codes" || $3 == "venue") {
    next
  }
  NF >= 4 {
    printf "%s:%s:%s\n", $1, $2, $4
  }
')"

if [[ -n "$unexpected_pub_mods" ]]; then
  echo "Unexpected public submodules found:"
  echo "$unexpected_pub_mods"
  exit 1
fi

echo "✓ facade public-module lint passed"
