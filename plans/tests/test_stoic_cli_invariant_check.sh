#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/plans/stoic_cli_invariant_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$GUARD" ]] || fail "missing executable guard: $GUARD"

# Real file must pass.
STOIC_CLI_FILE="$ROOT/stoic-cli" "$GUARD" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Missing transfer guard token must fail.
missing_transfer="$tmp_dir/stoic_cli_missing_transfer.py"
grep -v 'transfer_enabled must be false' "$ROOT/stoic-cli" > "$missing_transfer"

set +e
out_missing="$(STOIC_CLI_FILE="$missing_transfer" "$GUARD" 2>&1)"
rc_missing=$?
set -e

[[ $rc_missing -ne 0 ]] || fail "expected guard to fail when transfer guard token is removed"
echo "$out_missing" | grep -Fq "missing required keys-check invariant" || fail "missing expected missing-transfer error"

# Wrong durability ordering must fail.
wrong_order="$tmp_dir/stoic_cli_wrong_order.py"
cat > "$wrong_order" <<'EOF'
def _fsync_directory(path: Path) -> None:
    dir_fd = os.open(path, os.O_RDONLY)
    os.fsync(dir_fd)

def _write_runtime_state(path: Path, state: Dict[str, Any]) -> None:
    _fsync_directory(path.parent)
    os.replace(tmp_path, path)

def _cmd_keys_check(args: argparse.Namespace) -> int:
    if entry.get("transfer_enabled") is not False:
        errors.append(f"{label}: transfer_enabled must be false")
    if "transfer" in scopes_lower:
        errors.append(f"{label}: scopes must not include transfer")
    if transfer_result in {"success", "accepted"}:
        errors.append(f"{label}: transfer probe must not show success for trade-capable keys")
        errors.append(f"{label}: non-trade scope must not show successful transfers")

def _build_parser() -> argparse.ArgumentParser:
    pass
EOF

set +e
out_order="$(STOIC_CLI_FILE="$wrong_order" "$GUARD" 2>&1)"
rc_order=$?
set -e

[[ $rc_order -ne 0 ]] || fail "expected guard to fail when fsync ordering is wrong"
echo "$out_order" | grep -Fq "must execute after os.replace" || fail "missing expected fsync-order error"

echo "PASS: stoic-cli invariant check fixtures"
