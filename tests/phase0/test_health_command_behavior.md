# test_health_command_behavior

## Purpose

Prove the owner health command is executable and has deterministic healthy/unhealthy behavior.

## Procedure

1. Run healthy path:
   - `./stoic-cli health --format json`
2. Validate output fields:
   - `ok`
   - `build_id`
   - `contract_version`
3. Run forced-unhealthy path with missing policy:
   - `STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli health --format json`

## Pass Criteria

- Healthy path exits `0` and returns JSON with required fields and `ok=true`.
- Forced-unhealthy path exits `1` with `ok=false`.
- Unhealthy payload includes explicit policy-load error.
