# test_policy_is_required_and_bound

## Purpose

Prove the system cannot trade without a loaded and valid policy.

## Procedure

1. Start the system with no policy file.
2. Attempt to initialize trading.
3. Start the system with a malformed policy file.
4. Attempt to initialize trading again.

## Pass Criteria

- Startup fails closed OR trading starts in a non-OPEN mode that blocks OPEN dispatch.
- OPEN order attempts are rejected in both missing-policy and malformed-policy cases.
- Failure is explicit in logs/errors (no silent fallback).
- No implicit default policy is applied.
