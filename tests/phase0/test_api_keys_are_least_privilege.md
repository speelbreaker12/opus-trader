# test_api_keys_are_least_privilege

## Purpose

Prove API credentials cannot exceed intended authority.

## Procedure

1. Attempt a trade action using a read-only key.
2. Attempt a withdrawal action using a trading key.
3. Attempt a trade action using a revoked key.

## Pass Criteria

- Each forbidden action fails.
- Failure reason is explicit and attributable.
- No fallback path grants extra privilege.
- No implicit key substitution occurs.
