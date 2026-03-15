#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="${LINT_RISK_FACADE_MOD:-$ROOT/crates/soldier_core/src/risk/mod.rs}"
API="${LINT_RISK_FACADE_API:-$ROOT/crates/soldier_core/src/risk/api.rs}"
ALLOWLIST="${LINT_RISK_FACADE_ALLOWLIST:-$ROOT/plans/risk_facade_symbols.txt}"
SCAN_ROOT="${LINT_RISK_FACADE_SCAN_ROOT:-$ROOT/crates}"

cleanup_tmp() {
  [[ -n "${tmp_expected:-}" && -f "${tmp_expected:-}" ]] && rm -f "$tmp_expected"
  [[ -n "${tmp_actual:-}" && -f "${tmp_actual:-}" ]] && rm -f "$tmp_actual"
}
trap cleanup_tmp EXIT

[[ -f "$MOD" ]] || { echo "FAIL: missing risk mod file: $MOD"; exit 1; }
[[ -f "$API" ]] || { echo "FAIL: missing risk api file: $API"; exit 1; }
[[ -f "$ALLOWLIST" ]] || { echo "FAIL: missing risk facade allowlist: $ALLOWLIST"; exit 1; }

if rg -q '^\s*pub(\s*\([^)]*\))?\s+mod\s+api\s*;' "$MOD"; then
  echo "FAIL: risk/mod.rs must not expose 'pub mod api;'"
  exit 1
fi

api_private_mod_count="$(rg -c '^\s*mod\s+api\s*;' "$MOD" || true)"
if [[ "$api_private_mod_count" -ne 1 ]]; then
  echo "FAIL: risk/mod.rs must contain exactly one private 'mod api;' line, found $api_private_mod_count"
  exit 1
fi

if ! rg -q '^\s*pub\s+use\s+api::\*\s*;' "$MOD"; then
  echo "FAIL: missing facade re-export line in risk/mod.rs: pub use api::*;"
  exit 1
fi

pub_use_count="$(rg -c '^\s*pub\s+use\s+' "$MOD" || true)"
if [[ "$pub_use_count" -ne 1 ]]; then
  echo "FAIL: risk/mod.rs must contain exactly one public re-export line, found $pub_use_count"
  exit 1
fi

extract_allowlist_symbols() {
  grep -Ev '^[[:space:]]*(#|$)' "$ALLOWLIST" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | LC_ALL=C sort -u
}

extract_api_export_symbols() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to parse risk/api.rs exports" >&2
    exit 1
  fi

  python3 - "$API" <<'PY'
import collections
import pathlib
import re
import sys

api_path = pathlib.Path(sys.argv[1])
text = api_path.read_text(encoding="utf-8")
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"//.*", "", text)
id_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
token_re = re.compile(r"::|[{}*,]|[A-Za-z_][A-Za-z0-9_]*")
symbols = []

class ParseError(Exception):
    pass


def build_brace_depth_prefix(src):
    depth_prefix = [0] * (len(src) + 1)
    depth = 0
    for idx, ch in enumerate(src):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                raise ParseError("unbalanced closing brace in risk/api.rs")
        depth_prefix[idx + 1] = depth
    if depth != 0:
        raise ParseError("unbalanced braces in risk/api.rs")
    return depth_prefix


def find_pub_use_rhses(src, depth_prefix):
    start_re = re.compile(r"\bpub\s+use\b")
    pos = 0
    while True:
        match = start_re.search(src, pos)
        if match is None:
            break
        if depth_prefix[match.start()] != 0:
            raise ParseError("non-top-level pub use is not allowed in risk/api.rs")
        idx = match.end()
        depth = 0
        while idx < len(src):
            ch = src[idx]
            if ch == "{":
                depth += 1
            elif ch == "}":
                if depth == 0:
                    raise ParseError("unbalanced closing brace in pub use statement")
                depth -= 1
            elif ch == ";" and depth == 0:
                rhs = src[match.end():idx].strip()
                if not rhs:
                    raise ParseError("empty pub use statement")
                yield rhs
                pos = idx + 1
                break
            idx += 1
        else:
            raise ParseError("unterminated pub use statement (missing ';')")


def tokenize(rhs):
    tokens = []
    idx = 0
    while idx < len(rhs):
        if rhs[idx].isspace():
            idx += 1
            continue
        match = token_re.match(rhs, idx)
        if match is None:
            snippet = rhs[idx:idx + 20]
            raise ParseError(f"unsupported syntax near {snippet!r}")
        tokens.append(match.group(0))
        idx = match.end()
    return tokens


class UseTreeParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.idx = 0
        self.out = []

    def peek(self, offset=0):
        pos = self.idx + offset
        if pos >= len(self.tokens):
            return None
        return self.tokens[pos]

    def pop(self, expected=None):
        token = self.peek()
        if token is None:
            raise ParseError("unexpected end of use tree")
        if expected is not None and token != expected:
            raise ParseError(f"expected '{expected}', found '{token}'")
        self.idx += 1
        return token

    def is_ident(self, token):
        return token is not None and bool(id_re.match(token)) and token != "as"

    def pop_ident(self, context):
        token = self.peek()
        if not self.is_ident(token):
            raise ParseError(f"expected identifier for {context}, found '{token}'")
        self.idx += 1
        return token

    def parse(self):
        self.parse_use_list(prefix=[])
        if self.peek() is not None:
            raise ParseError(f"unexpected trailing token '{self.peek()}'")
        return self.out

    def parse_use_list(self, prefix):
        self.parse_use_tree(prefix)
        while self.peek() == ",":
            self.pop(",")
            if self.peek() in (None, "}"):
                break
            self.parse_use_tree(prefix)

    def parse_path_segments(self):
        segments = []
        if not self.is_ident(self.peek()):
            return segments
        segments.append(self.pop_ident("path segment"))
        while self.peek() == "::" and self.is_ident(self.peek(1)):
            self.pop("::")
            segments.append(self.pop_ident("path segment"))
        return segments

    def parse_use_tree(self, prefix):
        segments = self.parse_path_segments()
        current = prefix + segments
        token = self.peek()

        if token == "::":
            self.pop("::")
            token = self.peek()
            if token == "{":
                self.pop("{")
                if self.peek() != "}":
                    self.parse_use_list(prefix=current)
                self.pop("}")
                return
            if token == "*":
                raise ParseError("wildcard re-export is not allowed in risk/api.rs")
            raise ParseError(f"unsupported token '{token}' after '::'")

        if token == "as":
            if not current:
                raise ParseError("alias without path")
            self.pop("as")
            alias = self.pop_ident("alias")
            self.out.append(alias)
            return

        if token == "{":
            if segments:
                raise ParseError("grouped re-export requires '::' before '{'")
            self.pop("{")
            if self.peek() != "}":
                self.parse_use_list(prefix=prefix)
            self.pop("}")
            return

        if token == "*":
            raise ParseError("wildcard re-export is not allowed in risk/api.rs")

        if not current:
            raise ParseError("empty re-export item")
        leaf = current[-1]
        if leaf in {"self", "super", "crate"}:
            raise ParseError(f"unsupported keyword re-export leaf '{leaf}'")
        self.out.append(leaf)


try:
    depth_prefix = build_brace_depth_prefix(text)
    rhses = list(find_pub_use_rhses(text, depth_prefix))
except ParseError as exc:
    print(f"FAIL: {exc}", file=sys.stderr)
    sys.exit(2)

for rhs in rhses:
    try:
        parser = UseTreeParser(tokenize(rhs))
        symbols.extend(parser.parse())
    except ParseError as exc:
        print(f"FAIL: invalid re-export in risk/api.rs: {rhs}: {exc}", file=sys.stderr)
        sys.exit(2)

if not symbols:
    print("FAIL: no pub use re-export symbols found in risk/api.rs", file=sys.stderr)
    sys.exit(2)

dupes = sorted(sym for sym, count in collections.Counter(symbols).items() if count > 1)
if dupes:
    print("FAIL: duplicate re-export symbols in risk/api.rs:", file=sys.stderr)
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
  echo "FAIL: duplicate symbols found in risk facade allowlist: $ALLOWLIST"
  exit 1
fi

missing_symbols="$(comm -23 "$tmp_expected" "$tmp_actual" || true)"
extra_symbols="$(comm -13 "$tmp_expected" "$tmp_actual" || true)"

if [[ -n "$missing_symbols" ]]; then
  echo "FAIL: allowlisted exports missing from risk/api.rs:"
  echo "$missing_symbols"
  exit 1
fi
if [[ -n "$extra_symbols" ]]; then
  echo "FAIL: non-allowlisted exports present in risk/api.rs:"
  echo "$extra_symbols"
  exit 1
fi

if rg -q '^\s*(pub(\s*\([^)]*\))?\s+)?fn\s+[A-Za-z_][A-Za-z0-9_]*' "$API"; then
  echo "FAIL: risk/api.rs contains function definitions; facade file must be re-exports only."
  exit 1
fi

if [[ -d "$SCAN_ROOT" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to lint deep risk imports"
    exit 1
  fi

  deep_import_violations="$(python3 - "$SCAN_ROOT" <<'PY'
import pathlib
import re
import sys

scan_root = pathlib.Path(sys.argv[1]).resolve()
stmt_re = re.compile(r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?use\b.*?;', re.M | re.S)
deep_re = re.compile(r'\brisk::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*')
deep_grouped_re = re.compile(r'\brisk::\{[^;]*\b[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*')

for path in sorted(scan_root.rglob("*.rs")):
    rel = path.relative_to(scan_root).as_posix()
    if rel.startswith("soldier_core/src/risk/"):
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
    echo "FAIL: deep risk imports are forbidden outside soldier_core/src/risk."
    echo "$deep_import_violations"
    exit 1
  fi
fi

echo "✓ risk facade lint passed"
