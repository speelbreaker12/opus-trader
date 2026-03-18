# R7c — Production Wiring Audit (FIX_DIFF + AT_REGRESSION)

Story scope: `S0`

Review basis: `FIX_DIFF + AT_REGRESSION (Cycle 2)`

Phase equivalent: `R7c`

## Method

- Traced modified call paths from changed enforcement points.
- Verified entry-point reachability from `main`/command dispatch in `stoic-cli`.
- Confirmed test invocations target the same command behavior in `crates/soldier_infra/tests/test_phase0_runtime.rs`.

## AT wiring status

- `AT-023` (privilege / probe validation): `PROVEN-INTEGRATED`
  - Reachability evidence:
    - `main()` dispatches `_cmd_dispatch_check` / `_cmd_keys_check` paths under normal CLI operation.
    - CLI failure/kill mode and status output paths consume the same `_runtime_state` file and marker helper set.
    - Runtime tests exercise both `dispatch-check` and `status` paths with malformed/missing-state cases.
- `AT-022` (status/health transport proof): `DEFERRED`
  - Existing transport gap already recorded as debt in slice artifacts; no new wiring introduced in this fix batch.

## Classification completeness

- All safety-relevant ATs in this fix batch are classified.
