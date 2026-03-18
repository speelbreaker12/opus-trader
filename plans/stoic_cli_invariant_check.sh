#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLI_FILE="${STOIC_CLI_FILE:-stoic-cli}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$CLI_FILE" ]] || fail "missing stoic-cli file: $CLI_FILE"

require_in_keys_check() {
  local token="$1"
  if ! awk '/^def _cmd_keys_check\(/,/^def _build_parser\(/ {print}' "$CLI_FILE" | grep -Fq "$token"; then
    fail "missing required keys-check invariant: $token"
  fi
}

line_of() {
  local token="$1"
  local line
  line="$(grep -nF "$token" "$CLI_FILE" | head -n1 | cut -d: -f1 || true)"
  [[ -n "$line" ]] || fail "missing required runtime-state durability anchor: $token"
  echo "$line"
}

# Keys-check least-privilege anchors.
require_in_keys_check 'if entry.get("transfer_enabled") is not False:'
require_in_keys_check 'errors.append(f"{label}: transfer_enabled must be false")'
require_in_keys_check 'if "transfer" in scopes_lower:'
require_in_keys_check 'errors.append(f"{label}: scopes must not include transfer")'
require_in_keys_check 'errors.append(f"{label}: transfer probe must not show success for trade-capable keys")'
require_in_keys_check 'errors.append(f"{label}: non-trade scope must not show successful transfers")'

# Runtime-state durability anchors.
line_of 'def _fsync_directory(path: Path) -> None:' >/dev/null
line_of 'os.fsync(dir_fd)' >/dev/null
replace_line="$(line_of 'os.replace(tmp_path, path)')"
call_line="$(line_of '_fsync_directory(path.parent)')"

if (( call_line <= replace_line )); then
  fail "runtime-state durability regression: _fsync_directory(path.parent) must execute after os.replace(tmp_path, path)"
fi

echo "PASS: stoic-cli invariant check"
