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

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required but not found"; exit 1; }

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
# Known limitation: this regex may match `pub mod` inside string literals
# (e.g., r#"pub mod foo;"#). This is a known false-positive risk; in practice
# crate lib.rs files rarely contain such strings.
pattern = re.compile(
    r'(?m)^(?P<indent>\s*)(?P<attrs>(?:#\[[^\n]*\]\s*)*)pub\s+mod\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<term>;|\{)'
)
# Filter out lines that look like string literals (mitigate false positives)
string_prefix = re.compile(r'^\s*(r#)?"')

for target in targets:
    for path in sorted(target.rglob("*.rs")):
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in pattern.finditer(text):
            # Skip matches inside string literals (false-positive mitigation)
            line_start = text.rfind("\n", 0, match.start()) + 1
            line_text = text[line_start:match.end()]
            if string_prefix.match(line_text):
                continue
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

# Build awk allowlist from the single-source-of-truth required_core_facades array
_awk_allowlist="$(printf '%s\n' "${required_core_facades[@]}" | paste -sd'|' -)"

unexpected_pub_mods="$(printf '%s\n' "$pub_mod_rows" | awk -F '\t' -v allowlist="$_awk_allowlist" '
  BEGIN { split(allowlist, a, "|"); for (i in a) allowed[a[i]] = 1 }
  $1 == "crates/soldier_core/src/lib.rs" && $4 == ("pub mod " $3 ";") && ($3 in allowed) {
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

echo "[OK] facade public-module lint passed"
