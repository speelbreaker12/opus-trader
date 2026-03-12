#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/premortem_ready.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
command -v jq >/dev/null 2>&1 || fail "jq is required for this test"
JQ_BIN="$(command -v jq)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/reviews/premortems" "$repo/specs" "$repo/touch"
git -C "$tmp_dir" init -q repo

cp "$SCRIPT" "$repo/plans/premortem_ready.sh"
chmod +x "$repo/plans/premortem_ready.sh"

# Keep this gate deterministic for the ownership-scope test.
cat > "$repo/plans/premortem_gate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$repo/plans/premortem_gate.sh"

cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract Stub
EOF

cat > "$repo/reviews/premortems/S1-001_premortem.md" <<'EOF'
**STOPLIGHT**: GREEN
## 0) What we're building
ok
## 1) Clause audit (contract → AT traceability)
ok
## 2) Assumptions (each must become a test or get killed)
ok
## 3) Top 5 failure modes
ok
## 4) Open decisions (resolve before coding)
ok
## 5) Wrong implementation gate
ok
## 6) Proof plan (AT → enforcement → tests)
ok
## 7) Economic risk (loss_mode)
ok
## 8) Conflict scan & hot zones
ok
## 9) Constraint I expect to hit
ok
## 10) STOPLIGHT + Exit criteria
ok
EOF

touch "$repo/touch/s1" "$repo/touch/s2"

cat > "$repo/plans/prd.json" <<'EOF'
{
  "items": [
    {
      "id": "S1-001",
      "slice": 1,
      "primary_owner_for": ["AT-999"],
      "scope": {"touch": ["touch/s1"]}
    },
    {
      "id": "S2-001",
      "slice": 2,
      "primary_owner_for": ["AT-999"],
      "scope": {"touch": ["touch/s2"]}
    }
  ]
}
EOF

set +e
conflict_out="$(
  cd "$repo" && bash plans/premortem_ready.sh S1-001 2>&1
)"
conflict_rc=$?
set -e
[[ "$conflict_rc" -eq 1 ]] || fail "expected cross-slice ownership conflict to fail"
echo "$conflict_out" | grep -Fq "AT ownership conflict(s) found" || fail "missing ownership conflict error"
echo "$conflict_out" | grep -Fq "AT-999 -> S1-001, S2-001" || fail "missing cross-slice claimant detail"

set +e
skip_json="$(
  cd "$repo" && RECON_SKIP_OWNERSHIP=1 bash plans/premortem_ready.sh S1-001 --json
)"
skip_rc=$?
set -e
[[ "$skip_rc" -eq 0 ]] || fail "expected skip mode to allow jq-path ownership conflicts"
echo "$skip_json" | "$JQ_BIN" -e '.ready == true' >/dev/null || fail "skip mode should report ready"
echo "$skip_json" | "$JQ_BIN" -e '.ownership_conflicts == 0' >/dev/null || fail "skip mode should zero ownership_conflicts"
echo "$skip_json" | "$JQ_BIN" -e '.ownership_conflict_details == []' >/dev/null || fail "skip mode should clear jq-path ownership_conflict_details"

# Remove the cross-slice conflict and verify the gate turns ready.
jq '
  .items |= map(
    if .id == "S2-001"
    then (.primary_owner_for = ["AT-888"])
    else .
    end
  )
' "$repo/plans/prd.json" > "$repo/plans/prd.json.tmp"
mv "$repo/plans/prd.json.tmp" "$repo/plans/prd.json"

set +e
ready_out="$(
  cd "$repo" && bash plans/premortem_ready.sh S1-001 2>&1
)"
ready_rc=$?
set -e
[[ "$ready_rc" -eq 0 ]] || fail "expected gate to pass once ownership conflict is removed"
echo "$ready_out" | grep -Fq "OK: premortem ready for S1-001" || fail "missing ready confirmation"

cat > "$repo/reviews/premortems/S1-010_premortem.md" <<'EOF'
**STOPLIGHT**: GREEN
## 0) What we're building
ok
## 1) Clause audit (contract → AT traceability)
| AT | Note |
| --- | --- |
| AT-777 | owned here |
## 2) Assumptions (each must become a test or get killed)
ok
## 3) Top 5 failure modes
ok
## 4) Open decisions (resolve before coding)
ok
## 5) Wrong implementation gate
ok
## 6) Proof plan (AT → enforcement → tests)
ok
## 7) Economic risk (loss_mode)
ok
## 8) Conflict scan & hot zones
ok
## 9) Constraint I expect to hit
ok
## 10) STOPLIGHT + Exit criteria
ok
EOF

cat > "$repo/reviews/premortems/S2-010_premortem.md" <<'EOF'
**STOPLIGHT**: GREEN
## 1) Clause audit (contract → AT traceability)
| AT | Note |
| --- | --- |
| AT-777 | conflicting owner |
EOF

cat > "$repo/plans/prd.json" <<'EOF'
{
  "items": [
    {
      "id": "S1-010",
      "scope": {"touch": ["touch/s1"]}
    },
    {
      "id": "S2-010",
      "scope": {"touch": ["touch/s2"]}
    }
  ]
}
EOF

no_jq_bin="$tmp_dir/no-jq-bin"
mkdir -p "$no_jq_bin"
for cmd in bash git grep sed head sort tr wc basename date; do
  ln -s "$(command -v "$cmd")" "$no_jq_bin/$cmd"
done

set +e
legacy_skip_json="$(
  cd "$repo" && PATH="$no_jq_bin" RECON_SKIP_OWNERSHIP=1 bash plans/premortem_ready.sh S1-010 --json
)"
legacy_skip_rc=$?
set -e
[[ "$legacy_skip_rc" -eq 0 ]] || fail "expected skip mode to allow legacy ownership conflicts"
echo "$legacy_skip_json" | "$JQ_BIN" -e '.ready == true' >/dev/null || fail "legacy skip mode should report ready"
echo "$legacy_skip_json" | "$JQ_BIN" -e '.ownership_conflicts == 0' >/dev/null || fail "legacy skip mode should zero ownership_conflicts"
echo "$legacy_skip_json" | "$JQ_BIN" -e '.ownership_conflict_details == []' >/dev/null || fail "legacy skip mode should clear ownership_conflict_details"

echo "test_premortem_ready_ownership_conflict.sh: ok"
