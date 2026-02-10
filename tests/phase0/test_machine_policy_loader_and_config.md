# test_machine_policy_loader_and_config

## Purpose

Prove Phase-0 policy is machine-readable and validated by an executable strict loader.

## Procedure

1. Validate `config/policy.json` exists and is valid JSON.
2. Run strict loader validation:
   - `python tools/policy_loader.py --policy config/policy.json --strict`
3. Compare `config/policy.json` with `evidence/phase0/policy/policy_config_snapshot.json`.

## Pass Criteria

- Strict loader exits `0` on current policy file.
- Policy includes required keys (envs/order types/risk limits/fail_closed).
- PAPER is non-trade-capable in machine policy.
- Snapshot is a literal copy of the sign-off policy config.
