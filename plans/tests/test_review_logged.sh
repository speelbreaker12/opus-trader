#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
echo "- [P1] first finding"
echo "- [P2] second finding"
echo "crates/soldier_core/src/execution/quantize.rs:42"
exit 0
MOCK_CODEX

cat > "$mock_bin/kimi" <<'MOCK_KIMI'
#!/usr/bin/env bash
cat >/dev/null
echo "### P1-High: heading finding"
echo "### P2-Medium: heading finding"
echo "crates/soldier_core/src/execution/quantize.rs:99"
exit 0
MOCK_KIMI

cat > "$mock_bin/claude" <<'MOCK_CLAUDE'
#!/usr/bin/env bash
cat >/dev/null
sleep 5
echo "### P1-High: late finding"
echo "crates/soldier_core/src/execution/quantize.rs:13"
exit 0
MOCK_CLAUDE

cat > "$mock_bin/timeout" <<'MOCK_TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail

_seconds="${1:?missing timeout seconds}"
shift

if [[ "${1:-}" == "bash" && "${2:-}" == "-c" ]]; then
  "$@"
  exit $?
fi

if [[ "${1:-}" == *"/claude" || "${1:-}" == "claude" ]]; then
  exit 124
fi

"$@"
exit $?
MOCK_TIMEOUT

chmod +x "$mock_bin/codex" "$mock_bin/kimi" "$mock_bin/claude" "$mock_bin/timeout"

out_root="$tmp_dir/out"

# 1) Codex run should succeed (self-copy normalized path must not fail)
PATH="$mock_bin:$PATH" "$SCRIPT" S2-000 --tool codex --uncommitted --prompt enriched --out-root "$out_root" >/dev/null
codex_md="$out_root/S2-000/codex/codex.enriched.md"
[[ -f "$codex_md" ]] || fail "codex artifact missing"
grep -Fxq "FINDINGS_SUMMARY: P0=0 P1=1 P2=1" "$codex_md" || fail "codex findings summary mismatch"
pass "codex run succeeds and findings summary parses [P1]/[P2] bullets"

# 2) Codex --files mode should use nonzero default timeout
PATH="$mock_bin:$PATH" "$SCRIPT" S2-010 --tool codex --files "plans/review_logged.sh" --prompt enriched --out-root "$out_root" >/dev/null
codex_files_md="$out_root/S2-010/codex/codex.enriched.md"
[[ -f "$codex_files_md" ]] || fail "codex --files artifact missing"
grep -Fxq -- "- Timeout Seconds: 600" "$codex_files_md" || fail "codex --files default timeout mismatch"
pass "codex --files mode applies elevated default timeout"

# 3) Kimi run should parse heading severity format
PATH="$mock_bin:$PATH" "$SCRIPT" S2-001 --tool kimi --uncommitted --prompt enriched --out-root "$out_root" >/dev/null
kimi_md="$out_root/S2-001/kimi/kimi.enriched.md"
[[ -f "$kimi_md" ]] || fail "kimi artifact missing"
grep -Fxq "FINDINGS_SUMMARY: P0=0 P1=1 P2=1" "$kimi_md" || fail "kimi findings summary mismatch"
pass "kimi run succeeds and findings summary parses heading severities"

# 4) Prompt contract should explicitly require file:line citations
grep -Fq 'Every finding must contain at least one' "$SCRIPT" \
  || fail "citation hard-requirement text missing from prompt contract"
grep -Fq 'path/to/file.ext:line' "$SCRIPT" \
  || fail "citation hard-requirement text missing from prompt contract"
pass "prompt contract requires explicit file:line citations"

# 5) Sonnet timeout should fail-closed with deterministic exit, clear stale sidecar, and mark timeout
sonnet_sidecar="$out_root/S2-002/sonnet/sonnet.enriched.sidecar.json"
mkdir -p "$(dirname "$sonnet_sidecar")"
printf '{"stale":true}\n' > "$sonnet_sidecar"

set +e
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=1 PATH="$mock_bin:$PATH" "$SCRIPT" S2-002 --tool sonnet --uncommitted --prompt enriched --timeout-seconds 1 --out-root "$out_root" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 7 ]] || fail "sonnet timeout expected exit 7, got $rc"
sonnet_md="$out_root/S2-002/sonnet/sonnet.enriched.md"
[[ -f "$sonnet_md" ]] || fail "sonnet artifact missing after timeout"
grep -Fxq -- "- Timed Out: true" "$sonnet_md" || fail "timeout marker missing in artifact"
grep -Fxq -- "HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)" "$sonnet_md" || fail "timeout hard-gate marker missing"
[[ ! -f "$sonnet_sidecar" ]] || fail "stale sidecar should be removed on failed run"
pass "sonnet timeout fails closed with deterministic exit 7 and clears stale sidecar"

echo "PASS: review_logged regression fixtures"
