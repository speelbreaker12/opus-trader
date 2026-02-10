# Phase 0 — Launch Policy & Authority Baseline (AUTO/MANUAL, Ungameable)

**Purpose:** Phase 0 binds authority before code correctness is trusted.  
If this is paperwork only, the rest of the roadmap is gameable.

**Rule:** Phase 0 is DONE only if every item below is satisfied with required evidence.

Canonical narrative: `docs/phase0_acceptance.md`.

## Phase 0 Evidence Pack (required)

Create: `evidence/phase0/` with the following required files:

```text
evidence/phase0/
  README.md
  ci_links.md
  policy/
    launch_policy_snapshot.md
    policy_config_snapshot.json
  env/
    env_matrix_snapshot.md
  keys/
    key_scope_probe.json
  break_glass/
    runbook_snapshot.md
    drill.md
    log_excerpt.txt
  health/
    health_endpoint_snapshot.md
```

- `README.md`: 1-page owner summary (what was proven, what failed, remaining risks).
- `ci_links.md`: links to CI runs + build IDs used for proof; if CI is not wired yet, include recorded local output for AUTO gates.
- Snapshots are literal copies of sign-off docs (prevents silent edits after sign-off).

## P0-A — Launch Policy Baseline is Explicit (no hidden assumptions)

**MANUAL artifacts (docs must exist):**
- `docs/launch_policy.md` with:
  - allowed instruments / venues
  - allowed order types
  - max position / max daily loss (or equivalent capital stop)
  - max order rate / pacing rule (coarse)
  - environments: DEV / STAGING / PAPER / LIVE (names + purpose)

**MANUAL evidence:**
- `evidence/phase0/policy/launch_policy_snapshot.md` (literal snapshot at sign-off)

**Unblock condition:** MANUAL doc + snapshot exist.

## P0-B — Environment Isolation (keys/configs cannot leak across envs)

**MANUAL artifacts (docs must exist):**
- `docs/env_matrix.md` table with:
  - each environment (DEV/STAGING/PAPER/LIVE)
  - exchange account + API key used per env
  - key permissions/scope per env (read-only vs trade; withdraw disabled)
  - where secrets are stored (vault, env vars, etc.)

**MANUAL evidence:**
- `evidence/phase0/env/env_matrix_snapshot.md` (snapshot at sign-off)

**Unblock condition:** MANUAL doc + snapshot exist.

## P0-C — Keys & Secrets Baseline (least privilege, verifiable scope)

**MANUAL artifacts (docs must exist):**
- `docs/keys_and_secrets.md` including:
  - key creation rules (least privilege; withdrawals disabled)
  - rotation plan (who/when/how)
  - where secrets live (and what must never appear in repo)
  - how LIVE keys are protected from local/dev usage

**AUTO/MANUAL evidence (must exist):**
- `evidence/phase0/keys/key_scope_probe.json` with minimum fields:
  - `env`
  - `exchange`
  - `key_id` (redacted ok)
  - `scopes` (list)
  - `withdraw_enabled` (bool)
  - `timestamp_utc`
  - `operator`

**Unblock condition:** MANUAL doc exists and scope probe JSON exists + is valid (non-empty).

## P0-D — Break-Glass Runbook + Executed Drill (paperwork is not enough)

**MANUAL artifacts (docs must exist):**
- `docs/break_glass_runbook.md` includes:
  - exact STOP TRADING steps (kill switch)
  - how to verify no further OPEN risk
  - how to verify risk reduction is still possible if exposure exists
  - escalation + who to notify

**MANUAL evidence (recorded drill required):**
- `evidence/phase0/break_glass/runbook_snapshot.md` (snapshot at sign-off)
- `evidence/phase0/break_glass/drill.md` with trigger scenario, time to halt, observed behavior, and follow-ups
- `evidence/phase0/break_glass/log_excerpt.txt` proving drill occurred

**Unblock condition:** doc + snapshots + drill record + logs exist.

## P0-E — Minimal Health Command/Endpoint

**Goal:** A single health command/endpoint proves liveness/config basics.

**MANUAL artifacts (docs must exist):**
- `docs/health_endpoint.md` documenting:
  - exact health command/endpoint
  - expected output format
  - required fields: `ok`, `build_id`, `contract_version`

**MANUAL evidence (snapshot required):**
- `evidence/phase0/health/health_endpoint_snapshot.md` (literal snapshot at sign-off)

**AUTO gates:**
- `test_health_endpoint_returns_required_fields`
- `test_health_command_exits_zero_when_healthy`
- `test_health_command_behavior` (healthy and forced-unhealthy paths)

**Unblock condition:** health doc exists, health snapshot exists, and AUTO tests are green.

## P0-F — Machine-Readable Policy Path + Strict Loader

**Goal:** Policy must be machine-readable and actively loaded/validated so runtime checks are not documentation-only.

**MANUAL artifacts (must exist):**
- `config/policy.json` with explicit policy keys (envs/order types/limits/fail_closed)
- `tools/policy_loader.py` with strict validation (non-zero on invalid policy)

**MANUAL evidence (snapshot required):**
- `evidence/phase0/policy/policy_config_snapshot.json` (literal snapshot at sign-off)

**AUTO gates:**
- `test_machine_policy_loader_and_config`

**Unblock condition:** machine policy file + loader exist, snapshot exists, and strict loader test is green.

## Phase 0 Minimal Tests (must pass)

Phase 0 is complete only if the following tests are defined and evidenced:

1) `test_policy_is_required_and_bound`  
   Proves missing/malformed policy fails closed (no OPEN trading possible).
2) `test_machine_policy_loader_and_config`  
   Proves `config/policy.json` is present, valid, and loader-enforced.
3) `test_health_command_behavior`  
   Proves `./stoic-cli health` returns required fields when healthy and exits non-zero when forced unhealthy.
4) `test_api_keys_are_least_privilege`  
   Proves forbidden key actions fail explicitly (no implicit privilege).
5) `test_break_glass_kill_blocks_open_allows_reduce`  
   Proves forced Kill blocks OPEN while risk reduction remains possible.

Reference location: `tests/phase0/`.

## Phase 0 Owner Sign-Off (Binary)

Answer YES/NO with links into `evidence/phase0/`. If any answer is “I think so,” Phase 0 is NOT DONE.

1) Are launch boundaries written clearly enough that a non-coder can detect a violation?
2) Are environments isolated (DEV/STAGING/PAPER/LIVE) with separate keys/accounts?
3) Do we have proof of key scopes (not just claims) and withdrawals are disabled?
4) Was a break-glass drill executed and recorded, proving we can halt new risk immediately?
5) Does a single health command/endpoint show `ok` / `build_id` / `contract_version` and fail non-zero when policy load fails?

## Explicit Phase 0 Non-Goals (Do Not Backport)

- No `/status` endpoint
- No TradingMode/PolicyGuard logic
- No replay/evidence/certification loop
- No dashboards/UI
- No chaos suite beyond the single break-glass drill
