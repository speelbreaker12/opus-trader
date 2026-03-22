#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SCAN_ROOTS="$(printf '%s\n%s\n' \
  "$ROOT/crates/soldier_core/src/execution" \
  "$ROOT/crates/soldier_core/src/risk")"
SCAN_ROOTS_RAW="${LINT_GRAYBOX_TELEMETRY_ROOTS:-$DEFAULT_SCAN_ROOTS}"

python3 - "$SCAN_ROOTS_RAW" <<'PY'
import pathlib
import re
import sys


def sanitize(text: str) -> str:
    out = []
    i = 0
    n = len(text)
    state = "code"
    block_depth = 0
    raw_hashes = 0
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if state == "code":
            if ch == "/" and nxt == "/":
                out.extend("  ")
                i += 2
                state = "line_comment"
                continue
            if ch == "/" and nxt == "*":
                out.extend("  ")
                i += 2
                state = "block_comment"
                block_depth = 1
                continue
            if ch == '"':
                out.append(" ")
                i += 1
                state = "string"
                continue
            if ch == "'":
                j = i + 1
                while j < n and (text[j].isalnum() or text[j] == "_"):
                    j += 1
                if j > i + 1 and (j >= n or text[j] != "'"):
                    out.append(ch)
                    i += 1
                    continue
                out.append(" ")
                i += 1
                state = "char"
                continue
            if ch == "r":
                j = i + 1
                while j < n and text[j] == "#":
                    j += 1
                if j < n and text[j] == '"':
                    raw_hashes = j - (i + 1)
                    out.extend(" " * (j - i + 1))
                    i = j + 1
                    state = "raw_string"
                    continue
            out.append(ch)
            i += 1
            continue

        if state == "line_comment":
            out.append("\n" if ch == "\n" else " ")
            i += 1
            if ch == "\n":
                state = "code"
            continue

        if state == "block_comment":
            if ch == "/" and nxt == "*":
                out.extend("  ")
                i += 2
                block_depth += 1
                continue
            if ch == "*" and nxt == "/":
                out.extend("  ")
                i += 2
                block_depth -= 1
                if block_depth == 0:
                    state = "code"
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue

        if state == "string":
            if ch == "\\" and i + 1 < n:
                out.extend("  ")
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            if ch == '"':
                state = "code"
            continue

        if state == "char":
            if ch == "\\" and i + 1 < n:
                out.extend("  ")
                i += 2
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            if ch == "'":
                state = "code"
            continue

        if state == "raw_string":
            closing = '"' + ('#' * raw_hashes)
            if text.startswith(closing, i):
                out.extend(" " * len(closing))
                i += len(closing)
                state = "code"
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue

    return "".join(out)


def find_matching_brace(code: str, open_index: int) -> int:
    depth = 0
    for idx in range(open_index, len(code)):
        ch = code[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return idx
    raise ValueError("unbalanced braces")


FUNCTION_RE = re.compile(r"\bfn\s+([A-Za-z_][A-Za-z0-9_]*_with_events)\b")
FORBIDDEN = {
    r"\bemit_execution_metric_line\s*\(": "metric-line emission",
    r"\bfetch_add\s*\(": "global counter mutation",
    r"\bwith_intent_trace_ids\s*\(": "trace-id dependency",
    r"\btake_execution_metric_lines\s*\(": "metric-buffer inspection",
    r"\bMETRICS_TEST_LOCK\b": "shared metrics lock dependency",
    r"\btracing::(?:trace|debug|info|warn|error)!\s*[\(\{\[]": "direct tracing macro",
    r"(?<!\.)\bbump_[A-Za-z0-9_]*\s*\(": "wrapper-only bump helper call",
    r"(?<!\.)\brecord_(?:[A-Za-z0-9_]*metric[A-Za-z0-9_]*|expected_slippage_sample|gate_sequence_result|wal_nonblocking_allowed)\s*\(": "wrapper-only record helper call",
}

raw_roots = sys.argv[1]
root_parts = []
if "\n" in raw_roots:
    root_parts = [part.strip() for part in raw_roots.splitlines() if part.strip()]
elif raw_roots.strip():
    exact_path = pathlib.Path(raw_roots)
    if exact_path.exists():
        root_parts = [raw_roots]
    else:
        # Backward compatibility for the original space-delimited override.
        root_parts = [part.strip() for part in raw_roots.split() if part.strip()]

roots = [pathlib.Path(part) for part in root_parts]
if not roots:
    print("FAIL: no scan roots provided", file=sys.stderr)
    sys.exit(1)

violations = []
for root in roots:
    if not root.exists():
        print(f"FAIL: missing scan root: {root}", file=sys.stderr)
        sys.exit(1)
    for path in sorted(root.rglob("*.rs")):
        text = path.read_text(encoding="utf-8")
        code = sanitize(text)
        for match in FUNCTION_RE.finditer(code):
            name = match.group(1)
            search_start = match.end()
            next_brace = code.find("{", search_start)
            next_semi = code.find(";", search_start)
            if next_semi != -1 and (next_brace == -1 or next_semi < next_brace):
                continue
            brace_index = next_brace
            if brace_index == -1:
                violations.append(f"{path}: unable to find body for {name}")
                continue
            close_index = find_matching_brace(code, brace_index)
            body = code[brace_index + 1:close_index]
            for pattern, description in FORBIDDEN.items():
                hit = re.search(pattern, body)
                if hit:
                    line = text[: brace_index + 1 + hit.start()].count("\n") + 1
                    violations.append(
                        f"{path}:{line}: {name} contains forbidden {description}"
                    )

if violations:
    print("FAIL: graybox telemetry seams must stay free of direct telemetry calls")
    for violation in violations:
        print(violation)
    sys.exit(1)

print("PASS: graybox telemetry seams are free of direct telemetry calls")
PY
