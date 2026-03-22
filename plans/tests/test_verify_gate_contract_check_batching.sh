#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_GATE_CHECK="$ROOT/plans/verify_gate_contract_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SOURCE_GATE_CHECK" ]] || fail "missing source script: $SOURCE_GATE_CHECK"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mkdir -p "$repo/plans/lib" "$repo/specs"

cp "$SOURCE_GATE_CHECK" "$repo/plans/verify_gate_contract_check.sh"
cp "$ROOT/specs/WORKFLOW_CONTRACT.md" "$repo/specs/WORKFLOW_CONTRACT.md"
cp "$ROOT/plans/verify_fork.sh" "$repo/plans/verify_fork.sh"
cp "$ROOT/plans/lib/rust_gates.sh" "$repo/plans/lib/rust_gates.sh"
cp "$ROOT/plans/lib/python_gates.sh" "$repo/plans/lib/python_gates.sh"
cp "$ROOT/plans/lib/node_gates.sh" "$repo/plans/lib/node_gates.sh"
cp "$ROOT/plans/lib/status_reason_codegen_gate.sh" "$repo/plans/lib/status_reason_codegen_gate.sh"
chmod +x "$repo/plans/verify_gate_contract_check.sh"

(
  cd "$repo"
  ./plans/verify_gate_contract_check.sh >/dev/null 2>&1
) || fail "baseline fixture run must pass before mutation"

verify_file="$repo/plans/verify_fork.sh"
verify_file_backup="$tmp_dir/verify_fork.original.sh"
cp "$verify_file" "$verify_file_backup"
rust_gates_file="$repo/plans/lib/rust_gates.sh"
rust_gates_file_backup="$tmp_dir/rust_gates.original.sh"
cp "$rust_gates_file" "$rust_gates_file_backup"
gate_check_file="$repo/plans/verify_gate_contract_check.sh"

mutate_verify_file() {
  local target="$1"
  local old_token="$2"
  local new_token="$3"

  command -v python3 >/dev/null 2>&1 \
    || fail "python3 is required for deterministic fixture mutation"

  python3 - "$target" "$old_token" "$new_token" <<'PY'
import sys

path, old_token, new_token = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    content = handle.read()
content = content.replace(old_token, new_token)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(content)
PY
}

run_expect_missing_token() {
  local expected_token="$1"
  local expected_file="$2"
  local output=""
  local rc=0
  local expected_line=""
  local first_line=""

  set +e
  output="$(
    cd "$repo"
    ./plans/verify_gate_contract_check.sh 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 1 ]] || fail "expected verify gate check to fail with rc=1, got $rc"

  expected_line="FAIL: missing code token '$expected_token' in $expected_file"
  first_line="$(printf '%s\n' "$output" | head -n1)"
  [[ "$first_line" == "$expected_line" ]] \
    || fail "unexpected failure line: '$first_line' (expected '$expected_line')"
}

# Regression guard: require non-pipeline literal token check to avoid pipefail/SIGPIPE false negatives.
if grep -Fq -- "printf '%s\\n' \"\$section_text\" | grep -Fq" "$gate_check_file"; then
  fail "require_doc_token must not use printf|grep pipeline"
fi
grep -Fq -- "grep -Fq -- \"\$token\" <<< \"\$section_text\"" "$gate_check_file" \
  || fail "require_doc_token literal non-pipeline grep check missing"

if grep -Fq -- "printf '%s\\n' \"\$file_content\" | grep -Fq" "$gate_check_file"; then
  fail "require_code_token must not use printf|grep pipeline"
fi
if grep -Fq -- "grep -Fq -- \"\$token\" <<< \"\$file_content\"" "$gate_check_file"; then
  fail "require_code_token must not spawn grep per token"
fi
grep -Fq -- "contains_literal_token() {" "$gate_check_file" \
  || fail "contains_literal_token helper missing"
grep -Fq -- "[[ \"\$haystack\" == *\"\$needle\"* ]]" "$gate_check_file" \
  || fail "contains_literal_token must use bash-native literal substring match"
grep -Fq -- "if ! contains_literal_token \"\$file_content\" \"\$token\"; then" "$gate_check_file" \
  || fail "require_code_token must use contains_literal_token helper"

# Case A: remove first and second ordered verify tokens.
# Must fail-first on the first token in the original deterministic order.
cp "$verify_file_backup" "$verify_file"
mutate_verify_file "$verify_file" \
  'run_logged_or_exit "contract_review_generate"' \
  'run_logged_or_exit "__removed_contract_review_generate"'
mutate_verify_file "$verify_file" \
  'run_logged_or_exit "contract_review_validate"' \
  'run_logged_or_exit "__removed_contract_review_validate"'

run_expect_missing_token 'run_logged_or_exit "contract_review_generate"' "plans/verify_fork.sh"

# Case B: remove only the second ordered verify token.
# Must keep exact failure message contract unchanged.
cp "$verify_file_backup" "$verify_file"
mutate_verify_file "$verify_file" \
  'run_logged_or_exit "contract_review_validate"' \
  'run_logged_or_exit "__removed_contract_review_validate"'

run_expect_missing_token 'run_logged_or_exit "contract_review_validate"' "plans/verify_fork.sh"

# Case C: remove the graybox telemetry lint Rust gate token.
# Must fail on the rust gate script so new workflow contract tokens stay self-proving.
cp "$verify_file_backup" "$verify_file"
cp "$rust_gates_file_backup" "$rust_gates_file"
mutate_verify_file "$rust_gates_file" \
  'run_logged_or_exit "graybox_telemetry_lint"' \
  'run_logged_or_exit "__removed_graybox_telemetry_lint"'

run_expect_missing_token 'run_logged_or_exit "graybox_telemetry_lint"' "plans/lib/rust_gates.sh"

echo "PASS: verify gate contract check batching"
