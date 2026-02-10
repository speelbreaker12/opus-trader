# test_status_command_behavior

## Purpose

Prove the owner status command is executable and reports minimum authority fields in Phase 0.

## Procedure

1. Run healthy status path:
   - `./stoic-cli status --format json`
2. Validate output fields:
   - `ok`
   - `build_id`
   - `contract_version`
   - `trading_mode`
   - `is_trading_allowed`
   - `runtime_state_path`
   - `external_runtime_state`
3. Run forced-unhealthy status path with missing policy:
   - `STOIC_POLICY_PATH=./config/missing_policy.json ./stoic-cli status --format json`

## Pass Criteria

- Healthy path exits `0` and returns JSON with required fields and `ok=true`.
- Forced-unhealthy path exits `1` with `ok=false`.
- Unhealthy payload forces `trading_mode=KILL` and `is_trading_allowed=false`.
- Unhealthy payload includes explicit policy-load error.
