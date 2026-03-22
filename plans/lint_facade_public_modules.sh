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

pattern = re.compile(
    r'(?m)^(?P<indent>\s*)(?P<attrs>(?:#\[[^\n]*\]\s*)*)pub\s+mod\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<term>;|\{)'
)

def strip_strings_and_comments(text: str) -> str:
    """Replace string literals and comments with whitespace-preserving placeholders.

    This prevents `pub mod` inside strings/comments from tripping the lint.
    Handles: line comments (//), block comments (/* */), raw strings (r#"..."#),
    byte strings (b"..."), and regular strings ("...").
    Newlines inside replaced regions are preserved so line numbers stay correct.
    """
    result = []
    i = 0
    n = len(text)
    while i < n:
        # Line comment
        if text[i:i+2] == '//':
            end = text.find('\n', i)
            if end == -1:
                end = n
            result.append(' ' * (end - i))
            i = end
        # Block comment
        elif text[i:i+2] == '/*':
            end = text.find('*/', i + 2)
            if end == -1:
                end = n
            else:
                end += 2
            segment = text[i:end]
            result.append(''.join('\n' if c == '\n' else ' ' for c in segment))
            i = end
        # Raw string: r#"..."# (with variable number of #)
        elif text[i] == 'r' and i + 1 < n and text[i+1] in ('"', '#'):
            j = i + 1
            hashes = 0
            while j < n and text[j] == '#':
                hashes += 1
                j += 1
            if j < n and text[j] == '"':
                j += 1  # skip opening quote
                closing = '"' + '#' * hashes
                end = text.find(closing, j)
                if end == -1:
                    end = n
                else:
                    end += len(closing)
                segment = text[i:end]
                result.append(''.join('\n' if c == '\n' else ' ' for c in segment))
                i = end
            else:
                result.append(text[i])
                i += 1
        # Byte string b"..." or regular string "..."
        elif text[i] == '"' or (text[i] == 'b' and i + 1 < n and text[i+1] == '"'):
            start = i
            if text[i] == 'b':
                i += 1
            i += 1  # skip opening quote
            while i < n:
                if text[i] == '\\' and i + 1 < n:
                    i += 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            segment = text[start:i]
            result.append(''.join('\n' if c == '\n' else ' ' for c in segment))
        else:
            result.append(text[i])
            i += 1
    return ''.join(result)

for target in targets:
    for path in sorted(target.rglob("*.rs")):
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        cleaned = strip_strings_and_comments(text)
        for match in pattern.finditer(cleaned):
            # Use the module name position for line numbering — avoids
            # off-by-one when the regex ^ anchor captures a preceding newline.
            line = cleaned.count("\n", 0, match.start("name")) + 1
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
