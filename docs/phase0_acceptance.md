# Phase 0 Acceptance — Launch Policy & Authority Baseline

Canonical checklist source: `docs/PHASE0_CHECKLIST_BLOCK.md`.
If this document and the canonical checklist differ, the canonical checklist wins.

## Purpose (Read This First)

Phase 0 exists to bind authority before code correctness is trusted.

If Phase 0 is weak, every later phase is gameable.
If Phase 0 is strong, later enforcement becomes mechanical.

Phase 0 does NOT validate strategy, execution, or performance.
It validates that:
- the rules of the game are defined,
- the system is bound to those rules,
- and there is a proven way to stop trading under failure.

---

## What Phase 0 Proves (Non-Negotiable)

By the end of Phase 0, it must be mechanically impossible for the system to:
- trade without loading an explicit policy,
- exceed defined limits by accident,
- or continue opening risk after a forced stop.

This phase answers:
> "Who is allowed to trade, under what limits, and who can stop it, and are those rules enforced?"

---

## Required Artifacts

All artifacts below mark Phase 0 complete.

### 1. Trading Policy (Human + Machine)

**Files**
- `docs/launch_policy.md` (human-readable)
- `config/policy.json` (machine-readable)
- `tools/policy_loader.py` (strict loader/validator)

**Requirements**
- Explicit limits:
  - instruments / venues
  - max leverage
  - max position size
  - max daily loss
  - micro-live caps (even if micro-live is later)
- No implied defaults.
- Missing values must fail-closed.
- Loader must fail non-zero on malformed/missing policy.

---

### 2. Trading Modes & Authority

**Defined Modes**
- `Active`
- `ReduceOnly`
- `Kill`
- `Paper`

**Requirements**
- Who/what can transition modes is explicitly documented.
- Mode transitions are derived, not manually toggled.
- No component may override mode authority.

---

### 3. Key & Secrets Policy (Bound, Not Just Written)

**File**
- `docs/keys_and_secrets.md`

**Requirements**
- Separate keys per environment.
- Least privilege:
  - trading key cannot withdraw
  - read-only key cannot trade
- Rotation and revocation plan documented.

---

### 4. Break-Glass Capability (Proven)

Phase 0 is not complete without a recorded break-glass drill.

**Requirements**
- Simulate a runaway order attempt.
- Force `Kill`.
- Verify:
  - no new OPEN risk is created
  - REDUCE_ONLY actions remain possible
- Artifact recorded (log, video, or transcript).

---

### 5. Minimal Health Output

Before `/status` exists, there must be some owner-readable health output.

**Requirements**
- Single command or endpoint.
- Shows:
  - `ok` (boolean)
  - `build_id` (string)
  - `contract_version` (string)
- Readable by a non-coder.
- Includes deterministic unhealthy behavior (non-zero exit) when policy load fails.

---

## Phase-0 Tests (Must Pass)

Phase 0 is considered complete only if all tests below pass.

- Policy binding test (fail-closed on missing/invalid policy)
- Machine policy loader test (strict validation against `config/policy.json`)
- Health command behavior test (healthy and forced-unhealthy paths)
- Key scope probe test (prove least privilege)
- Break-glass drill test (forced Kill blocks OPENs)

See `tests/phase0/`, `tools/phase0_meta_test.py`, and `evidence/phase0/` for Phase-0 acceptance evidence in this repository.

---

## Owner Sign-Off (Required)

The owner must be able to answer YES to all of the following:

- Are risk limits defined in a file the system actually reads?
- Can trading be forcibly stopped even if the strategy misbehaves?
- Are keys provably scoped and tested?
- Has a break-glass drill been executed and recorded?
- Is there any way to trade without passing through these controls?

If any answer is "I think so," Phase 0 is not complete.

---

## Explicit Non-Goals (Do Not Add These Here)

Phase 0 must NOT include:
- `/status` schema
- dashboards
- chaos drills beyond break-glass
- replay, evidence, or certification
- strategy logic

Those belong to later phases.

---

## Final Rule

If Phase 0 is skipped or weakened, later safety guarantees are invalid.

Phase 0 is the foundation.
Do not treat it as paperwork.

---

## Exact Minimal Phase-0 Tests

These are the only tests Phase 0 needs.
Anything more belongs to Phase 1+.

### Test 1 — Policy Binding (Fail-Closed)

**Name**
- `test_policy_is_required_and_bound`

**Purpose**
- Proves the system cannot trade without a loaded policy.

**Procedure**
- Start system with no policy file.
- Expect startup failure or trading disabled (Kill or equivalent).
- Start system with malformed policy.
- Expect same behavior.

**Pass Criteria**
- No OPEN trading possible.
- Clear error or refusal.
- No implicit defaults.

**Why this matters**
- Closes: "policy exists but code never read it".

### Test 2 — Key Scope Probe (Least Privilege)

**Name**
- `test_api_keys_are_least_privilege`

**Purpose**
- Proves credentials cannot exceed intended authority.

**Procedure**
- Attempt trade with read-only key.
- Attempt withdrawal with trading key.
- Attempt trade with revoked key.

**Pass Criteria**
- Each forbidden action fails.
- Failures are explicit, not silent.
- No fallback or implicit privilege.

**Why this matters**
- Closes: "keys were accidentally over-privileged".

### Test 3 — Break-Glass Drill (Authority Override)

**Name**
- `test_break_glass_kill_blocks_open_allows_reduce`

**Purpose**
- Proves there is a reliable way to stop trading under failure.

**Procedure**
- Simulate runaway order generation.
- Trigger break-glass Kill.
- Attempt:
  - OPEN order -> must fail
  - REDUCE_ONLY action -> must succeed

**Pass Criteria**
- OPEN is blocked immediately.
- Exposure reduction remains possible.
- Evidence of the drill is recorded.

**Why this matters**
- Closes: "we can stop it in theory".

### Test Count Summary (Phase 0)

| Test Count | Purpose |
|------------|---------|
| 1 | Policy binding |
| 1 | Key scope enforcement |
| 1 | Break-glass authority |

Total: 3 tests.

No fixtures.
No schemas.
No dashboards.

Exactly as minimal as Phase 0 should be.

---

## Final Owner Perspective

After Phase 0:
- You do not trust the system yet, and that is fine.
- But you know:
  - the rules are bound,
  - authority is enforced,
  - and there is a proven stop button.

That is the only promise Phase 0 needs to keep.
