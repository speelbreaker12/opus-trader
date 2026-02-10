# Phase 0 Minimal Test Set

This directory defines the exact minimal Phase 0 test set.
These are acceptance definitions and evidence anchors, not strategy tests.

## Required Tests

- `test_policy_is_required_and_bound`
- `test_machine_policy_loader_and_config`
- `test_health_command_behavior`
- `test_api_keys_are_least_privilege`
- `test_break_glass_kill_blocks_open_allows_reduce`

## Contract Intent

- Policy must be bound and fail-closed.
- Machine policy path + loader must be executable and strict.
- Health command must be executable with deterministic healthy/unhealthy semantics.
- Credential scope must enforce least privilege.
- Break-glass Kill must stop new OPEN risk while preserving risk reduction.

## Evidence

Attach execution evidence under `evidence/phase0/` (or later phase folders for reruns), including timestamps and operator attribution.
