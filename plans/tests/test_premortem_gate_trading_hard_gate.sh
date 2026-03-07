#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/premortem_gate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/reviews/premortems"
git init -q "$repo"

cp "$SCRIPT" "$repo/plans/premortem_gate.sh"
chmod +x "$repo/plans/premortem_gate.sh"

cat > "$repo/reviews/premortems/S9-001_premortem.md" <<'MD'
# Story Premortem: S9-001

> Premortem Schema: v2

## 0) What we're building
- Story: Trading hard gate wiring test
- Contract clause(s): `specs/CONTRACT.md` §5.1
- Acceptance tests: AT-900
- Touch scope: plans/premortem_gate.sh

## Trading Risk Hard Gate

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | YES | Reject paths remain fail-closed under uncertainty. | CONTRACT §5.1; plans/premortem_gate.sh; test_premortem_gate_trading_hard_gate.sh | N/A |
| Profit preservation | YES | Valid reduce and compliant dispatch flows are not blocked. | CONTRACT §5.2; plans/premortem_gate.sh; golden-vector-01 | N/A |
| Best design choice | YES | Single gate table avoids hidden branching complexity. | CONTRACT §2.4; plans/premortem_gate.sh; design-note-01 | N/A |
| Better alternative check | YES | A simpler pass-through design was rejected as fail-open risk. | CONTRACT §2.4; reviews/premortems/STORY_PREMORTEM_TEMPLATE.md; review-01 | N/A |
| Failure-path correctness | YES | Retries, replay, stale state, and venue errors map to explicit deny behavior. | CONTRACT §6.3; plans/premortem_gate.sh; failure-matrix-01 | N/A |
| Fail-closed enforcement | YES | Missing or inconsistent state yields deterministic NO-GO behavior. | CONTRACT §3.2; plans/premortem_gate.sh; test-vector-closed-01 | N/A |
| Proof, not belief | YES | Every claim maps to contract plus executable gate evidence. | CONTRACT §1.1; plans/premortem_gate.sh; test artifact bundle | N/A |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)
| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-900 | §5.1 | Fail closed on uncertainty | MUST | Y |

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Inputs are parseable | malformed tables bypass checks | test-parse-01 | YES |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing row | row lookup fails | block | AT-900 |
| 2 | Invalid answer | enum check fails | block | AT-900 |
| 3 | Missing proof | non-empty proof check fails | block | AT-900 |

## 4) Open decisions (resolve before coding)
### Decision: keep gate local
- **What is ambiguous / missing**: where to enforce hard-gate schema
- **Evidence** (file + anchor or snippet): plans/premortem_gate.sh
- **Options**:
  1. Option A — enforce in premortem gate
  2. Option B — enforce only in docs review
- **Chosen**: A — deciding factor: deterministic enforcement
- **Why not others**: review-only path is non-deterministic
- **Scope control**:
  - What we're NOT doing yet (subordinate): migrate legacy premortems
  - What unblocks us if this choice is wrong (elevate): add migration tool

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-900 | Allow UNKNOWN without gap id | Y | hides untracked risk | add gap-id requirement |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-900 | plans/premortem_gate.sh | test_premortem_gate_trading_hard_gate.sh | Y | Y | reject_reason | Y |

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: unsafe implementation reaches dispatch.
- **Fail-closed cap on loss** (what restricts exposure): block implementation start.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: premortem gate.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: enforce explicit NO-GO reasoning

## 10) STOPLIGHT + Exit criteria
**STOPLIGHT**: GREEN
- [ ] done 1
- [ ] done 2
- [ ] done 3
- [ ] done 4
- [ ] done 5
MD

(
  cd "$repo"
  bash plans/premortem_gate.sh S9-001 >/dev/null
) || fail "expected v2 premortem with filled Trading Risk Hard Gate to pass"

cat > "$repo/reviews/premortems/S9-002_premortem.md" <<'MD'
# Story Premortem: S9-002

> Premortem Schema: v2

## 0) What we're building
- Story: Trading hard gate invalid gap-id case
- Contract clause(s): `specs/CONTRACT.md` §5.1
- Acceptance tests: AT-901
- Touch scope: plans/premortem_gate.sh

## Trading Risk Hard Gate

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | YES | Reject path is fail-closed. | CONTRACT §5.1; plans/premortem_gate.sh; test | N/A |
| Profit preservation | YES | Valid reduce behavior stays unblocked. | CONTRACT §5.2; plans/premortem_gate.sh; test | N/A |
| Best design choice | YES | Single gate is smallest safe scope. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Better alternative check | YES | Simpler alternatives were evaluated and rejected. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Failure-path correctness | UNKNOWN | Retry and replay coverage needs follow-up. | CONTRACT §6.3; plans/premortem_gate.sh; test | |
| Fail-closed enforcement | YES | Unknown states deny by default. | CONTRACT §3.2; plans/premortem_gate.sh; test | N/A |
| Proof, not belief | YES | Claims map to contract and test artifacts. | CONTRACT §1.1; plans/premortem_gate.sh; test | N/A |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)
| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-901 | §5.1 | Fail closed on uncertainty | MUST | Y |

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Inputs are parseable | malformed tables bypass checks | test-parse-01 | YES |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing row | row lookup fails | block | AT-901 |
| 2 | Invalid answer | enum check fails | block | AT-901 |
| 3 | Missing proof | non-empty proof check fails | block | AT-901 |

## 4) Open decisions (resolve before coding)
### Decision: keep gate local
- **What is ambiguous / missing**: where to enforce hard-gate schema
- **Evidence** (file + anchor or snippet): plans/premortem_gate.sh
- **Options**:
  1. Option A — enforce in premortem gate
  2. Option B — enforce only in docs review
- **Chosen**: A — deciding factor: deterministic enforcement
- **Why not others**: review-only path is non-deterministic
- **Scope control**:
  - What we're NOT doing yet (subordinate): migrate legacy premortems
  - What unblocks us if this choice is wrong (elevate): add migration tool

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-901 | Allow UNKNOWN without gap id | Y | hides untracked risk | add gap-id requirement |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-901 | plans/premortem_gate.sh | test_premortem_gate_trading_hard_gate.sh | Y | Y | reject_reason | Y |

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: unsafe implementation reaches dispatch.
- **Fail-closed cap on loss** (what restricts exposure): block implementation start.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: premortem gate.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: enforce explicit NO-GO reasoning

## 10) STOPLIGHT + Exit criteria
**STOPLIGHT**: GREEN
- [ ] done 1
- [ ] done 2
- [ ] done 3
- [ ] done 4
- [ ] done 5
MD

set +e
invalid_out="$(cd "$repo" && bash plans/premortem_gate.sh S9-002 2>&1)"
invalid_rc=$?
set -e

[[ "$invalid_rc" -ne 0 ]] || fail "expected UNKNOWN row without Gap ID to fail"
printf '%s\n' "$invalid_out" | grep -Fq "requires Gap ID for answer UNKNOWN" || fail "missing Gap ID failure diagnostic"

cat > "$repo/reviews/premortems/S9-002A_premortem.md" <<'MD'
# Story Premortem: S9-002A

> Premortem Schema: v2

## 0) What we're building
- Story: Trading hard gate YELLOW unknown case
- Contract clause(s): `specs/CONTRACT.md` §5.1
- Acceptance tests: AT-901A
- Touch scope: plans/premortem_gate.sh

## Trading Risk Hard Gate

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | YES | Reject path is fail-closed. | CONTRACT §5.1; plans/premortem_gate.sh; test | N/A |
| Profit preservation | YES | Valid reduce behavior stays unblocked. | CONTRACT §5.2; plans/premortem_gate.sh; test | N/A |
| Best design choice | YES | Single gate is smallest safe scope. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Better alternative check | YES | Simpler alternatives were evaluated and rejected. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Failure-path correctness | UNKNOWN | Retry and replay coverage needs follow-up. | CONTRACT §6.3; plans/premortem_gate.sh; test | GAP-S9-002A-1 |
| Fail-closed enforcement | YES | Unknown states deny by default. | CONTRACT §3.2; plans/premortem_gate.sh; test | N/A |
| Proof, not belief | YES | Claims map to contract and test artifacts. | CONTRACT §1.1; plans/premortem_gate.sh; test | N/A |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)
| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-901A | §5.1 | YELLOW unknowns require tracked debt | MUST | Y |

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Inputs are parseable | malformed tables bypass checks | test-parse-01 | YES |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing row | row lookup fails | block | AT-901A |
| 2 | Invalid answer | enum check fails | block | AT-901A |
| 3 | Missing proof | non-empty proof check fails | block | AT-901A |

## 4) Open decisions (resolve before coding)
### Decision: keep gate local
- **What is ambiguous / missing**: where to enforce hard-gate schema
- **Evidence** (file + anchor or snippet): plans/premortem_gate.sh
- **Options**:
  1. Option A — enforce in premortem gate
  2. Option B — enforce only in docs review
- **Chosen**: A — deciding factor: deterministic enforcement
- **Why not others**: review-only path is non-deterministic
- **Scope control**:
  - What we're NOT doing yet (subordinate): migrate legacy premortems
  - What unblocks us if this choice is wrong (elevate): add migration tool

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-901A | Block all UNKNOWN answers | Y | makes YELLOW design review impossible | allow tracked UNKNOWN under YELLOW |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-901A | plans/premortem_gate.sh | test_premortem_gate_trading_hard_gate.sh | Y | Y | reject_reason | Y |

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: safe design-reviewable work is blocked despite tracked containment.
- **Fail-closed cap on loss** (what restricts exposure): YELLOW debt register and owner review.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: premortem gate.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: enforce explicit YELLOW debt accounting

## 10) STOPLIGHT + Exit criteria
**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW):

| gap_id | Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|--------|------|----------|-------------|-------|-------------|-----------------|
| GAP-S9-002A-1 | retry and replay coverage | P1 | Need a follow-up review cycle to add replay-path proof without blocking current design review. | owner | S9-002A follow-up | AT-901A |

- [ ] done 1
- [ ] done 2
- [ ] done 3
- [ ] done 4
- [ ] done 5
MD

(
  cd "$repo"
  bash plans/premortem_gate.sh S9-002A >/dev/null
) || fail "expected YELLOW premortem with tracked UNKNOWN debt to pass"

cat > "$repo/reviews/premortems/S9-003_premortem.md" <<'MD'
# Story Premortem: S9-003

> Premortem Schema: v2

## 0) What we're building
- Story: Trading hard gate explicit no-go case
- Contract clause(s): `specs/CONTRACT.md` §5.1
- Acceptance tests: AT-902
- Touch scope: plans/premortem_gate.sh

## Trading Risk Hard Gate

| Question | Answer (YES/NO/UNKNOWN) | Why (one sentence) | Proof (contract clause(s); enforcement file(s); test/vector/artifact) | Gap ID (required when NO/UNKNOWN) |
|----------|--------------------------|--------------------|------------------------------------------------------------------------|-----------------------------------|
| Loss prevention | NO | The change can still widen loss on stale state. | CONTRACT §5.1; plans/premortem_gate.sh; stale-state-audit | GAP-S9-003-1 |
| Profit preservation | YES | Valid reduce behavior stays unblocked. | CONTRACT §5.2; plans/premortem_gate.sh; test | N/A |
| Best design choice | YES | Single gate is still the smallest safe scope. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Better alternative check | YES | Simpler alternatives were evaluated and rejected. | CONTRACT §2.4; plans/premortem_gate.sh; test | N/A |
| Failure-path correctness | YES | Failure paths still map to explicit deny behavior. | CONTRACT §6.3; plans/premortem_gate.sh; test | N/A |
| Fail-closed enforcement | YES | Unknown states deny by default. | CONTRACT §3.2; plans/premortem_gate.sh; test | N/A |
| Proof, not belief | YES | Claims map to contract and test artifacts. | CONTRACT §1.1; plans/premortem_gate.sh; test | N/A |

Hard Gate Decision Rule:

- GO only if all 7 answers are YES with concrete proof.
- YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment.
- NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim.

## 1) Clause audit (contract → AT traceability)
| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-902 | §5.1 | Fail closed on uncertainty | MUST | Y |

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Inputs are parseable | malformed tables bypass checks | test-parse-01 | YES |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing row | row lookup fails | block | AT-902 |
| 2 | Invalid answer | enum check fails | block | AT-902 |
| 3 | Missing proof | non-empty proof check fails | block | AT-902 |

## 4) Open decisions (resolve before coding)
### Decision: keep gate local
- **What is ambiguous / missing**: where to enforce hard-gate schema
- **Evidence** (file + anchor or snippet): plans/premortem_gate.sh
- **Options**:
  1. Option A — enforce in premortem gate
  2. Option B — enforce only in docs review
- **Chosen**: A — deciding factor: deterministic enforcement
- **Why not others**: review-only path is non-deterministic
- **Scope control**:
  - What we're NOT doing yet (subordinate): migrate legacy premortems
  - What unblocks us if this choice is wrong (elevate): add migration tool

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Easier than correct? (Y/N) | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|-----------------------------|----------------|---------------------------------------------------|
| AT-902 | Allow explicit NO to pass under RED | Y | permits implementation despite a hard block | fail on any NO answer |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-902 | plans/premortem_gate.sh | test_premortem_gate_trading_hard_gate.sh | Y | Y | reject_reason | Y |

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: unsafe implementation reaches dispatch.
- **Fail-closed cap on loss** (what restricts exposure): block implementation start.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: premortem gate.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: enforce explicit NO-GO reasoning

## 10) STOPLIGHT + Exit criteria
**STOPLIGHT**: RED

**Debt Register** (required if YELLOW):

| gap_id | Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|--------|------|----------|-------------|-------|-------------|-----------------|
| GAP-S9-003-1 | stale-state loss path | P0 | explicit hard block captured for owner review | owner | S9-003 follow-up | AT-902 |

- [ ] done 1
- [ ] done 2
- [ ] done 3
- [ ] done 4
- [ ] done 5
MD

set +e
no_out="$(cd "$repo" && bash plans/premortem_gate.sh S9-003 2>&1)"
no_rc=$?
set -e

[[ "$no_rc" -ne 0 ]] || fail "expected NO answer to fail even with RED stoplight and tracked gap"
printf '%s\n' "$no_out" | grep -Fq "Trading Risk Hard Gate has NO answers; premortem is NO-GO" || fail "missing NO-GO failure diagnostic"

echo "PASS: premortem gate trading hard gate"
