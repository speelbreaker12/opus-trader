#!/usr/bin/env bash
set -euo pipefail

# Adversarial contract testing gate — coverage accounting and semantic validation.
# Tests themselves run via rust_tests_full; this gate validates coverage completeness.

if [[ -z "${ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Self-initialize VERIFY_ARTIFACTS_DIR for standalone runs (outside verify_fork.sh)
if [[ -z "${VERIFY_ARTIFACTS_DIR:-}" ]]; then
  RUN_ID="standalone-$(date +%s)"
  VERIFY_ARTIFACTS_DIR="${ROOT}/artifacts/verify/${RUN_ID}"
  mkdir -p "$VERIFY_ARTIFACTS_DIR"
  echo "INFO: Standalone run, using VERIFY_ARTIFACTS_DIR=$VERIFY_ARTIFACTS_DIR" >&2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed. Install: apt-get install jq / brew install jq" >&2
  exit 1
fi

# Gate utilities
write_rc() {
  local rc=$1
  local gate_name=$2
  if [[ -z "$VERIFY_ARTIFACTS_DIR" || ! -d "$VERIFY_ARTIFACTS_DIR" ]]; then
    echo "ERROR: VERIFY_ARTIFACTS_DIR not set or not a directory" >&2
    return 1
  fi
  echo "$rc" > "$VERIFY_ARTIFACTS_DIR/${gate_name}.rc"
}

write_warn() {
  local gate_name=$1
  local message=$2
  if [[ -z "$VERIFY_ARTIFACTS_DIR" || ! -d "$VERIFY_ARTIFACTS_DIR" ]]; then
    echo "ERROR: VERIFY_ARTIFACTS_DIR not set or not a directory" >&2
    return 1
  fi
  echo "$message" > "$VERIFY_ARTIFACTS_DIR/${gate_name}.warn"
}

adversarial_errors=0

GI_SPEC_FILE="$ROOT/specs/invariants/GLOBAL_INVARIANTS.md"
if [[ ! -r "$GI_SPEC_FILE" ]]; then
  echo "ERROR: GLOBAL_INVARIANTS.md not found or not readable: $GI_SPEC_FILE" >&2
  write_rc 1 adversarial_invariant_tests
  exit 1
fi

# ─── Preflight: YAML frontmatter presence ────────────────────────────────

expected_gi_count=$(grep -cE '^### GI-[0-9]+ ' "$GI_SPEC_FILE" || echo 0)
frontmatter_count=$(grep -c "reject_reason_code:" "$GI_SPEC_FILE" || echo 0)
if [[ "$frontmatter_count" -ne "$expected_gi_count" ]]; then
  echo "ERROR: Expected $expected_gi_count GI entries with reject_reason_code frontmatter, found $frontmatter_count" >&2
  echo "       All GIs in GLOBAL_INVARIANTS.md must have YAML frontmatter with reject_reason_code field" >&2
  write_rc 1 adversarial_invariant_tests
  exit 1
fi

# Count testable GIs (pipeline + module level, excludes deferred)
testable_gi_count=$(awk '
  /^### GI-[0-9]+/ { in_gi=1; next }
  in_gi && /^### / { in_gi=0 }
  in_gi && /test_level:/ && !/deferred/ { count++ }
  END { print count+0 }
' "$GI_SPEC_FILE")
deferred_gi_count=$((expected_gi_count - testable_gi_count))
echo "INFO: $expected_gi_count total GIs, $testable_gi_count testable, $deferred_gi_count deferred" >&2

# ─── Extract GI ID sets ──────────────────────────────────────────────────

export LC_ALL=C

# IDs present in spec (restricted to section headers to avoid cross-reference noise)
spec_ids=$(grep -E '^### GI-[0-9]+ ' "$GI_SPEC_FILE" | grep -oE 'GI-[0-9]+' | sort -u)

# IDs marked as deferred
deferred_ids=$(awk '
  /^### GI-[0-9]+/ { gi=$2; in_gi=1; next }
  in_gi && /^### / { in_gi=0 }
  in_gi && /test_level:.*deferred/ { print gi }
' "$GI_SPEC_FILE" | sort -u)

# Testable IDs = spec_ids minus deferred_ids
if [[ -n "$deferred_ids" ]]; then
  testable_ids=$(comm -23 <(printf '%s\n' $spec_ids) <(printf '%s\n' $deferred_ids))
else
  testable_ids="$spec_ids"
fi

# IDs targeted by adversarial tests
shopt -s nullglob
test_files=("$ROOT/crates/soldier_core/tests/adversarial_"*.rs)
shopt -u nullglob

if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "WARN: no adversarial test files found — skipping coverage checks" >&2
  targeted_ids=""
  targeted_sms=""
else
  targeted_ids=$(grep -E '^// TARGET: GI-[0-9]+' "${test_files[@]}" 2>/dev/null \
    | grep -oE 'GI-[0-9]+' | sort -u || true)

  targeted_sms=$(grep -E '^// TARGET: SM-[a-z_]+' "${test_files[@]}" 2>/dev/null \
    | grep -oE 'SM-[a-z_]+' | sort -u || true)

  # Validate: every adversarial file MUST have at least one // TARGET: header
  for f in "${test_files[@]}"; do
    if ! grep -qE '^// TARGET: (GI-[0-9]+|SM-[a-z_]+)' "$f" 2>/dev/null; then
      echo "ERROR: $(basename "$f") has no // TARGET: GI-NNN or SM-xxx header" >&2
      adversarial_errors=$((adversarial_errors + 1))
    fi
  done
fi

accounted_ids="$targeted_ids"

# ─── Bidirectional drift check ───────────────────────────────────────────

missing_ids=""
unexpected_ids=""
if [[ -n "$testable_ids" || -n "$accounted_ids" ]]; then
  missing_ids=$(comm -23 <(printf '%s\n' $testable_ids) <(printf '%s\n' $accounted_ids) 2>/dev/null) || true
  unexpected_ids=$(comm -13 <(printf '%s\n' $spec_ids) <(printf '%s\n' $targeted_ids) 2>/dev/null) || true
fi

if [[ -n "$deferred_ids" ]]; then
  deferred_count=$(printf '%s\n' $deferred_ids | wc -l | tr -d ' ')
  echo "INFO: $deferred_count GIs deferred (enforcement not yet in soldier_core)" >&2
fi

# ─── Semantic test validation ────────────────────────────────────────────

for gi in $targeted_ids; do
  test_file=$(grep -l "^// TARGET: $gi" "${test_files[@]}" 2>/dev/null | head -1)
  if [[ -z "$test_file" ]]; then continue; fi

  expected_reason=$(awk -v target="$gi" '
    /^### / {
      if ($0 ~ "^### " target " ") { in_section=1; next }
      if (in_section) exit
    }
    in_section && /<!--/ { in_comment=1 }
    in_section && in_comment && /reject_reason_code:/ {
      sub(/.*reject_reason_code: */, "")
      print
      exit
    }
    in_section && /-->/ { in_comment=0 }
  ' "$GI_SPEC_FILE")

  if [[ "$expected_reason" == "N/A" ]]; then
    echo "INFO: $gi has reject_reason_code=N/A (module/deferred level) — skipping semantic validation" >&2
  elif [[ -n "$expected_reason" ]]; then
    if ! grep -E "(assert_eq!|assert!|matches!|ChokeRejectReason|RejectReasonCode).*$expected_reason" "$test_file" >/dev/null; then
      echo "ERROR: $gi test in $(basename "$test_file") does not assert expected reason: $expected_reason" >&2
      adversarial_errors=$((adversarial_errors + 1))
    fi
  else
    echo "WARN: $gi has no reject_reason_code in GLOBAL_INVARIANTS.md YAML frontmatter" >&2
  fi
done

# ─── Build report ────────────────────────────────────────────────────────

attack_vectors=0
attacks_blocked=0
# Note: attacks_succeeded is always 0 here because violations manifest as
# `cargo test` failures (assert!/panic), not as a runtime counter.
# The rust_tests_full gate catches actual violations; this gate validates coverage.
attacks_succeeded=0

# Count attack tests (functions named gi_NNN_blocks_* or gi_NNN_*)
if [[ ${#test_files[@]} -gt 0 ]]; then
  attack_vectors=$(grep -chE '#\[test\]' "${test_files[@]}" 2>/dev/null | awk '{s+=$0} END {print s+0}')
  attacks_blocked=$attack_vectors
fi

# Build JSON arrays (empty-guarded to avoid [""] from empty printf)
if [[ -n "$spec_ids" ]]; then
  spec_ids_json=$(printf '%s\n' $spec_ids | jq -R . | jq -s .)
else
  spec_ids_json='[]'
fi
testable_ids_json=$(printf '%s\n' $testable_ids | jq -R . | jq -s . 2>/dev/null || echo '[]')
deferred_ids_json=$(printf '%s\n' $deferred_ids | jq -R . | jq -s . 2>/dev/null || echo '[]')
targeted_ids_json=$(printf '%s\n' $targeted_ids | jq -R . | jq -s . 2>/dev/null || echo '[]')
if [[ -n "$targeted_sms" ]]; then
  targeted_sms_json=$(printf '%s\n' $targeted_sms | jq -R . | jq -s .)
else
  targeted_sms_json='[]'
fi

# Handle empty missing/unexpected
if [[ -n "$missing_ids" ]]; then
  missing_ids_json=$(printf '%s\n' $missing_ids | jq -R . | jq -s .)
else
  missing_ids_json='[]'
fi
if [[ -n "$unexpected_ids" ]]; then
  unexpected_ids_json=$(printf '%s\n' $unexpected_ids | jq -R . | jq -s .)
else
  unexpected_ids_json='[]'
fi

report_file="$VERIFY_ARTIFACTS_DIR/adversarial_report.json"
jq -n \
  --argjson spec "$spec_ids_json" \
  --argjson testable "$testable_ids_json" \
  --argjson deferred "$deferred_ids_json" \
  --argjson targeted "$targeted_ids_json" \
  --argjson missing "$missing_ids_json" \
  --argjson unexpected "$unexpected_ids_json" \
  --argjson sms "$targeted_sms_json" \
  --argjson vectors "$attack_vectors" \
  --argjson blocked "$attacks_blocked" \
  --argjson succeeded "$attacks_succeeded" \
  '{
    invariants_in_spec: $spec,
    invariants_testable: $testable,
    invariants_deferred: $deferred,
    invariants_targeted: $targeted,
    missing_ids: $missing,
    unexpected_ids: $unexpected,
    state_machines_targeted: $sms,
    attack_vectors_tried: $vectors,
    attacks_blocked: $blocked,
    attacks_succeeded: $succeeded
  }' > "$report_file"

# Validate JSON
if ! jq empty "$report_file" 2>/dev/null; then
  echo "ERROR: adversarial_report.json is not valid JSON" >&2
  write_rc 1 adversarial_invariant_tests
  exit 1
fi

echo "INFO: Adversarial report written to $report_file" >&2

# ─── Sunset enforcement ─────────────────────────────────────────────────

SUNSET_CONFIG="${ROOT}/plans/config/gate_sunsets.sh"
if [[ -f "$SUNSET_CONFIG" ]]; then
  # shellcheck source=../config/gate_sunsets.sh
  source "$SUNSET_CONFIG"
fi
ADVERSARIAL_SUNSET_DATE="${ADVERSARIAL_SUNSET_DATE:-2026-04-15}"

sunset_passed=0
if command -v date >/dev/null 2>&1; then
  now_epoch=$(date +%s)
  sunset_epoch=$(date -d "$ADVERSARIAL_SUNSET_DATE" +%s 2>/dev/null || \
                 date -j -f "%Y-%m-%d" "$ADVERSARIAL_SUNSET_DATE" +%s 2>/dev/null || echo "PARSE_FAILED")

  if [[ "$sunset_epoch" == "PARSE_FAILED" ]]; then
    echo "ERROR: date command failed to parse sunset date '$ADVERSARIAL_SUNSET_DATE'" >&2
    echo "       FAIL-CLOSED: Treating as sunset already passed (conservative)." >&2
    sunset_passed=1
  elif [[ "$now_epoch" -gt "$sunset_epoch" ]]; then
    sunset_passed=1
  fi
else
  echo "ERROR: date command not found — FAIL-CLOSED: treating as sunset passed." >&2
  sunset_passed=1
fi

# ─── Final determination ─────────────────────────────────────────────────

has_findings=0
if [[ -n "$missing_ids" || -n "$unexpected_ids" || "$attacks_succeeded" -gt 0 || "$adversarial_errors" -gt 0 ]]; then
  has_findings=1
fi

if [[ "$has_findings" -eq 1 ]]; then
  findings_summary="missing_ids=$(echo "$missing_ids" | tr '\n' ',' | sed 's/,$//') unexpected_ids=$(echo "$unexpected_ids" | tr '\n' ',' | sed 's/,$//') errors=$adversarial_errors"
  if [[ "$sunset_passed" -eq 1 ]]; then
    echo "ERROR: adversarial gate sunset ($ADVERSARIAL_SUNSET_DATE) reached — findings are now blocking" >&2
    echo "  $findings_summary" >&2
    write_rc 1 adversarial_invariant_tests
    exit 1
  else
    echo "WARN: adversarial gate findings (WARN-only until $ADVERSARIAL_SUNSET_DATE):" >&2
    echo "  $findings_summary" >&2
    write_warn adversarial_invariant_tests "$findings_summary"
    write_rc 0 adversarial_invariant_tests
  fi
else
  write_rc 0 adversarial_invariant_tests
fi

echo "✓ adversarial gate passed (${#test_files[@]} test files, $attack_vectors attack vectors)" >&2
