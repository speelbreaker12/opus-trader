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
echo "### F-1 - P1 - Priority 2: late finding"
echo "crates/soldier_core/src/execution/quantize.rs:13"
exit 0
MOCK_CLAUDE

cat > "$mock_bin/timeout" <<'MOCK_TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail
secs="${1:?missing seconds}"
shift
[[ "$secs" =~ ^[0-9]+$ ]] || exit 125
[[ "$#" -gt 0 ]] || exit 125

# Deterministic fixture behavior:
# - For probe calls used by timeout_bin() (e.g., `timeout 1 bash -c 'exit 0'`), pass through.
# - For 1-second invocations, simulate timeout expiry.
# - For all other invocations, pass through.
if [[ "$secs" == "1" ]]; then
  if [[ "${1:-}" == "bash" && "${2:-}" == "-c" ]]; then
    "$@"
    exit $?
  fi
  exit 124
fi
"$@"
exit $?
MOCK_TIMEOUT

cat > "$mock_bin/gemini" <<'MOCK_GEMINI'
#!/usr/bin/env bash
echo "### Finding 1"
echo "- **Severity:** P1-High"
echo "- **Evidence citation:** crates/soldier_core/src/idempotency/hash.rs:43"
echo
echo "2. **P2 - Canonical hash drift risk**"
echo "- **Evidence citation:** crates/soldier_core/tests/test_idempotency.rs:24"
exit 0
MOCK_GEMINI

chmod +x "$mock_bin/codex" "$mock_bin/kimi" "$mock_bin/claude" "$mock_bin/gemini" "$mock_bin/timeout"

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

# 5) Gemini run should parse "Severity:" labels and numbered bold severities
PATH="$mock_bin:$PATH" "$SCRIPT" S2-003 --tool gemini --uncommitted --prompt enriched --out-root "$out_root" >/dev/null
gemini_md="$out_root/S2-003/gemini/gemini.enriched.md"
[[ -f "$gemini_md" ]] || fail "gemini artifact missing"
grep -Fxq "FINDINGS_SUMMARY: P0=0 P1=1 P2=1" "$gemini_md" || fail "gemini findings summary mismatch"
pass "gemini run parses Severity labels and numbered bold severity findings"

# 6) Opus run should parse heading form "### F1 - P1 - ..."
PATH="$mock_bin:$PATH" "$SCRIPT" S2-004 --tool opus --uncommitted --prompt enriched --timeout-seconds 0 --out-root "$out_root" >/dev/null
opus_findings_md="$out_root/S2-004/opus/opus.enriched.md"
[[ -f "$opus_findings_md" ]] || fail "opus findings artifact missing"
grep -Fxq "FINDINGS_SUMMARY: P0=0 P1=1 P2=0" "$opus_findings_md" || fail "opus F-heading findings summary mismatch"
pass "opus run parses F-heading severity format"

# 7) Opus timeout should fail-closed with deterministic exit, clear stale sidecar, and mark timeout
opus_sidecar="$out_root/S2-002/opus/opus.enriched.sidecar.json"
mkdir -p "$(dirname "$opus_sidecar")"
printf '{"stale":true}\n' > "$opus_sidecar"

set +e
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=1 PATH="$mock_bin:$PATH" \
  "$SCRIPT" S2-002 --tool opus --uncommitted --prompt enriched --timeout-seconds 1 --out-root "$out_root" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 7 ]] || fail "opus timeout expected exit 7, got $rc"
opus_md="$out_root/S2-002/opus/opus.enriched.md"
[[ -f "$opus_md" ]] || fail "opus artifact missing after timeout"
grep -Fxq -- "- Timed Out: true" "$opus_md" || fail "timeout marker missing in artifact"
grep -Fxq -- "HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)" "$opus_md" || fail "timeout hard-gate marker missing"
[[ ! -f "$opus_sidecar" ]] || fail "stale sidecar should be removed on failed run"
pass "opus timeout fails closed with deterministic exit 7 and clears stale sidecar"

echo "PASS: review_logged regression fixtures"
