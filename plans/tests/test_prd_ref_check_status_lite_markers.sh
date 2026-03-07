#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/plans/prd_ref_check.sh"

die() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_rc() {
  local expected_rc="$1"
  shift

  set +e
  "$@" >"$tmp_dir/out.txt" 2>"$tmp_dir/err.txt"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$tmp_dir/out.txt" >&2 || true
    echo "stderr:" >&2
    cat "$tmp_dir/err.txt" >&2 || true
    die "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -x "$CHECKER" ]] || die "checker is not executable: $CHECKER"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_prd="$tmp_dir/valid_status_lite.json"
cat > "$valid_prd" <<'JSON'
{
  "items": [
    { "id": "S0-100", "story_ref": "P0-A prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-101", "story_ref": "P0-B prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-102", "story_ref": "P0-C prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-103", "story_ref": "P0-D prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-104", "story_ref": "P0-E prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-105", "story_ref": "P0-F prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    {
      "id": "S0-900",
      "story_ref": "Foundation status-lite marker guard",
      "contract_refs": [],
      "plan_refs": [],
      "acceptance": [
        "GIVEN status_mode=foundation_status_lite and phase == foundation WHEN /status is queried THEN payload includes service_up, build_id, contract_version, dispatch_enabled=false, and phase=foundation.",
        "GIVEN phase == foundation WHEN /status is emitted THEN dispatch_enabled=false remains hard-blocked.",
        "GIVEN foundation bootstrap mode WHEN /status is returned THEN status-lite scope remains active."
      ],
      "verify": [],
      "enforcing_contract_ats": []
    },
    {
      "id": "S0-920",
      "story_ref": "Compact CSP marker guard",
      "contract_refs": [],
      "plan_refs": [],
      "acceptance": [
        "GIVEN /status coverage WHEN the compact csp minimum key set required by at-023/at-405/at-419/at-907/at-927/at-1117 is documented THEN schema/profile/mode/risk fields remain listed.",
        "GIVEN /status coverage WHEN policy freshness fields and certification fields are documented THEN 5m rate-limit counters remain included.",
        "GIVEN /status coverage WHEN durability-queue counters and open-permission fields are documented THEN compact CSP coverage stays explicit."
      ],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 0 "$CHECKER" "$valid_prd"
if grep -Fq "malformed foundation status-lite markers" "$tmp_dir/err.txt"; then
  cat "$tmp_dir/err.txt" >&2
  die "valid status-lite markers were flagged as malformed"
fi
if grep -Fq 'S0-920 references /status but acceptance missing required CSP key' "$tmp_dir/err.txt"; then
  cat "$tmp_dir/err.txt" >&2
  die "compact CSP marker story was still treated as missing literal CSP keys"
fi

invalid_prd="$tmp_dir/invalid_status_lite.json"
cat > "$invalid_prd" <<'JSON'
{
  "items": [
    { "id": "S0-100", "story_ref": "P0-A prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-101", "story_ref": "P0-B prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-102", "story_ref": "P0-C prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-103", "story_ref": "P0-D prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-104", "story_ref": "P0-E prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-105", "story_ref": "P0-F prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    {
      "id": "S0-901",
      "story_ref": "Malformed foundation status-lite marker guard",
      "contract_refs": [],
      "plan_refs": [],
      "acceptance": [
        "GIVEN status_mode=foundation_status_lite and phase == foundation WHEN /status is queried THEN payload includes service_up and build_id.",
        "GIVEN phase == foundation WHEN /status is emitted THEN status-lite scope is preserved.",
        "GIVEN foundation bootstrap mode WHEN /status is returned THEN canonical authority fields remain absent."
      ],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 1 "$CHECKER" "$invalid_prd"
if ! grep -Fq "S0-901 malformed foundation status-lite markers" "$tmp_dir/err.txt"; then
  echo "stderr:" >&2
  cat "$tmp_dir/err.txt" >&2 || true
  die "missing malformed status-lite marker diagnostic"
fi

invalid_phase_prd="$tmp_dir/invalid_status_lite_missing_phase.json"
cat > "$invalid_phase_prd" <<'JSON'
{
  "items": [
    { "id": "S0-100", "story_ref": "P0-A prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-101", "story_ref": "P0-B prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-102", "story_ref": "P0-C prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-103", "story_ref": "P0-D prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-104", "story_ref": "P0-E prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    { "id": "S0-105", "story_ref": "P0-F prereq stub", "contract_refs": [], "plan_refs": [], "acceptance": [], "verify": [], "enforcing_contract_ats": [] },
    {
      "id": "S0-902",
      "story_ref": "Malformed foundation status-lite marker guard (missing phase marker)",
      "contract_refs": [],
      "plan_refs": [],
      "acceptance": [
        "GIVEN status_mode=foundation_status_lite WHEN /status is queried THEN payload includes service_up, build_id, dispatch_enabled=false, and bootstrap semantics.",
        "GIVEN dispatch_enabled=false WHEN owner status is emitted THEN status-lite scope remains active.",
        "GIVEN bootstrap mode is active WHEN owner status is returned THEN canonical authority fields remain absent."
      ],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 1 "$CHECKER" "$invalid_phase_prd"
if ! grep -Fq "S0-902 malformed foundation status-lite markers" "$tmp_dir/err.txt"; then
  echo "stderr:" >&2
  cat "$tmp_dir/err.txt" >&2 || true
  die "missing malformed status-lite missing-phase diagnostic"
fi

echo "PASS: prd_ref_check foundation status-lite marker guard"
