#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER_SRC="$ROOT/plans/prd_ref_check.sh"

failures=0
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

record_failure() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

dump_run() {
  local label="$1"
  echo "--- $label stdout ---" >&2
  cat "$RUN_STDOUT" >&2 || true
  echo "--- $label stderr ---" >&2
  cat "$RUN_STDERR" >&2 || true
  echo "--- end $label output ---" >&2
}

make_repo() {
  local name="$1"
  local repo="$tmp_dir/$name"
  mkdir -p "$repo/plans" "$repo/specs" "$repo/docs"
  cp "$CHECKER_SRC" "$repo/plans/prd_ref_check.sh"
  chmod +x "$repo/plans/prd_ref_check.sh"
  printf '{}\n' > "$repo/docs/contract_kernel.json"
  printf '%s\n' "$repo"
}

run_checker() {
  local repo="$1"
  RUN_STDOUT="$repo/run.stdout"
  RUN_STDERR="$repo/run.stderr"
  set +e
  (
    cd "$repo"
    bash plans/prd_ref_check.sh plans/prd.json
  ) >"$RUN_STDOUT" 2>"$RUN_STDERR"
  RUN_RC=$?
  set -e
}

stderr_contains() {
  local needle="$1"
  grep -Fq "$needle" "$RUN_STDERR"
}

assert_no_bootstrap_crash() {
  local label="$1"
  if stderr_contains 'EXTRA_CONTRACT_FILES[@]: unbound variable'; then
    record_failure "$label crashed before reaching ref-resolution checks"
    dump_run "$label"
    return 1
  fi
  return 0
}

run_roadmap_prefixed_case() {
  local repo
  repo="$(make_repo roadmap_prefixed)"

  cat > "$repo/plans/prd.json" <<'JSON'
{
  "items": [
    {
      "id": "S0-100",
      "story_ref": "Roadmap ref resolution case",
      "category": "infra",
      "contract_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "plan_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "acceptance": ["a", "b", "c"],
      "verify": ["./plans/verify.sh"],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

  cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract

AT-001 baseline
EOF

  cat > "$repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

Infra story only.
EOF

  cat > "$repo/docs/ROADMAP.md" <<'EOF'
# Roadmap

## P0-A Launch Policy Baseline
EOF

  run_checker "$repo"
  assert_no_bootstrap_crash "roadmap-prefixed ref case" || return

  if [[ "$RUN_RC" -eq 0 ]]; then
    echo "PASS: roadmap-prefixed ROADMAP.md refs resolve from docs/ROADMAP.md"
    return
  fi

  if ! stderr_contains '[prd_ref_check] ERROR: unresolved contract_ref for S0-100: ROADMAP.md P0-A Launch Policy Baseline'; then
    record_failure "roadmap-prefixed ref case failed without the expected contract_ref diagnostic"
    dump_run "roadmap-prefixed ref case"
    return
  fi
  if ! stderr_contains '[prd_ref_check] ERROR: unresolved plan_ref for S0-100: ROADMAP.md P0-A Launch Policy Baseline'; then
    record_failure "roadmap-prefixed ref case failed without the expected plan_ref diagnostic"
    dump_run "roadmap-prefixed ref case"
    return
  fi

  record_failure "roadmap-prefixed ROADMAP.md refs still fail even though docs/ROADMAP.md exists"
  dump_run "roadmap-prefixed ref case"
}

run_bare_roadmap_anchor_case() {
  local repo
  repo="$(make_repo roadmap_bare_anchor)"

  cat > "$repo/plans/prd.json" <<'JSON'
{
  "items": [
    {
      "id": "S0-101",
      "story_ref": "Infra story bare roadmap anchor case",
      "category": "infra",
      "contract_refs": [],
      "plan_refs": ["P0-A Launch Policy Baseline"],
      "acceptance": ["a", "b", "c"],
      "verify": ["./plans/verify.sh"],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

  cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract

AT-001 baseline
EOF

  cat > "$repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

Infra story only.
EOF

  cat > "$repo/docs/ROADMAP.md" <<'EOF'
# Roadmap

## P0-A Launch Policy Baseline
EOF

  run_checker "$repo"
  assert_no_bootstrap_crash "bare roadmap anchor case" || return

  if [[ "$RUN_RC" -eq 0 ]]; then
    echo "PASS: bare roadmap anchor resolves from docs/ROADMAP.md"
    return
  fi

  if ! stderr_contains '[prd_ref_check] ERROR: unresolved plan_ref for S0-101: P0-A Launch Policy Baseline'; then
    record_failure "bare roadmap anchor case failed without the expected unresolved plan_ref diagnostic"
    dump_run "bare roadmap anchor case"
    return
  fi

  record_failure 'bare roadmap anchor still fails when docs/ROADMAP.md contains "P0-A Launch Policy Baseline"'
  dump_run "bare roadmap anchor case"
}

run_numeric_boundary_case() {
  local repo
  repo="$(make_repo numeric_boundary)"

  cat > "$repo/plans/prd.json" <<'JSON'
{
  "items": [
    {
      "id": "S0-102",
      "story_ref": "Numeric boundary ref case",
      "contract_refs": ["CONTRACT.md 2.2 Missing Section"],
      "plan_refs": [],
      "acceptance": ["a", "b", "c"],
      "verify": ["./plans/verify.sh"],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

  cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract

## 12.2 Missing Section

## 2.21 Missing Section

## 2.2.1 Missing Section

AT-001 baseline
EOF

  cat > "$repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

Infra story only.
EOF

  run_checker "$repo"
  assert_no_bootstrap_crash "numeric boundary case" || return

  if [[ "$RUN_RC" -ne 0 ]]; then
    if stderr_contains '[prd_ref_check] ERROR: unresolved contract_ref for S0-102: CONTRACT.md 2.2 Missing Section'; then
      echo "PASS: numeric boundary no longer resolves against nearby numbered sections"
      return
    fi
    record_failure "numeric boundary case failed without the expected unresolved contract_ref diagnostic"
    dump_run "numeric boundary case"
    return
  fi

  record_failure "numeric boundary case incorrectly resolved missing 2.2 against nearby numbered sections"
  dump_run "numeric boundary case"
}

[[ -x "$CHECKER_SRC" ]] || fail "checker is not executable: $CHECKER_SRC"

run_roadmap_prefixed_case
run_bare_roadmap_anchor_case
run_numeric_boundary_case

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "PASS: prd_ref_check roadmap and numeric ref resolution regressions"
