# Key Rotation Exercise Record (Phase 0)

- date_utc: 2026-02-11T21:29:13Z
- envs_tested: STAGING, LIVE
- operator: phase0_operator
- witness: safety_witness
- scope: Post-rotation validation rehearsal (no production key replacement in this run)

## Objective

Exercise and record the Phase-0 key-rotation validation path so operators have repeatable proof commands for STAGING and LIVE key checks.

## Inputs

- Probe source: `evidence/phase0/keys/key_scope_probe.json`
- Command surface: `./stoic-cli keys-check`

## Commands Executed

```bash
./stoic-cli keys-check --probe evidence/phase0/keys/key_scope_probe.json --format json
./stoic-cli keys-check --probe evidence/phase0/keys/key_scope_probe.json --env LIVE --format json
./stoic-cli keys-check --probe evidence/phase0/keys/key_scope_probe.json --env STAGING --format json
```

## Recorded Outputs

- `evidence/phase0/keys/rotation_check_all.json`
  - `ok: true`
  - `checked_entries: 3`
- `evidence/phase0/keys/rotation_check_live.json`
  - `ok: true`
  - `checked_entries: 1`
  - `env_filter: "LIVE"`
- `evidence/phase0/keys/rotation_check_staging.json`
  - `ok: true`
  - `checked_entries: 1`
  - `env_filter: "STAGING"`

## Outcome

- Exercise status: PASSED
- Validation command path is executable and deterministic for all keys, LIVE-only, and STAGING-only filters.
- Probe data remains consistent with least-privilege expectations.

## Known Limits

- This run is a validation rehearsal and does not perform a full LIVE key cutover (create new key -> deploy new secret -> revoke old key).
- Full cutover must still be executed in a controlled maintenance window and logged as an incident-grade evidence record.
